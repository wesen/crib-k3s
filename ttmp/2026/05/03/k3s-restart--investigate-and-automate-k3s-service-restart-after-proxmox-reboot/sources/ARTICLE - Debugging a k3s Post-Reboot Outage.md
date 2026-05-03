---
title: "ARTICLE - Debugging a k3s Post-Reboot Outage — Traefik, HelmCharts, and Crash Loops"
aliases:
  - k3s post-reboot debugging
  - crib k3s outage may 2026
tags:
  - article
  - k3s
  - proxmox
  - traefik
  - kubernetes
  - homelab
  - debugging
  - tailscale
status: active
type: article
created: 2026-05-03
repo: /home/manuel/code/wesen/crib-k3s
last_updated: 2026-05-03
---

# Debugging a k3s Post-Reboot Outage — Traefik, HelmCharts, and Crash Loops

This article documents a multi-hour investigation into why a single-node k3s cluster on Proxmox lost all external connectivity after a host reboot. The root cause turned out to be a layered chain of decisions made weeks earlier: a cloud-init template that disabled Traefik, a HelmChartConfig that was removed from git, and an iptables forwarding service that appeared healthy while forwarding to ports with no listener. The first fix attempt exposed a second problem — a known k3s race condition in the embedded cloud-controller-manager. The takeover recovery resolved both layers: k3s was stabilized long enough for its CCM RBAC manifests to apply, the cloud controller was re-enabled, Traefik was restored with hostPorts, stale DNAT forwarding was disabled, and ArgoCD was forced to retry applications whose previous syncs failed while Traefik CRDs were absent.

The article is written for someone who needs to understand not just what happened, but why each layer behaved the way it did, how the recovery worked, and what the final operating model is.

> [!summary]
> 1. **Traefik was never re-deployed after reboot** because k3s config disabled it and the HelmChartConfig that previously overrode that was removed from git
> 2. **The iptables proxy masked the problem** — it reported healthy while forwarding to dead NodePorts
> 3. **Re-enabling Traefik triggered a k3s crash loop** — a known RBAC race condition in the cloud-controller-manager ([k3s#7328](https://github.com/k3s-io/k3s/issues/7328))
> 4. **The successful recovery used ordering, not force** — temporarily disable embedded CCM, let RBAC apply, re-enable CCM, then restore Traefik routes
> 5. **The final ingress model is Traefik hostPorts** — `*.crib.scapegoat.dev` resolves to the VM's Tailscale IP and Traefik binds host ports 80/443 directly; the old DNAT proxy is disabled

## Why this note exists

On May 3, 2026, the Proxmox host running the crib k3s cluster was rebooted. After the reboot, `watch.crib.scapegoat.dev` and `argocd.crib.scapegoat.dev` were unreachable. All Kubernetes pods were running, k3s was healthy, DNS resolved correctly — but no HTTP traffic reached any service. This article traces the full investigation from initial symptom to root cause to attempted fix, documenting every dead end and every lesson along the way.

The article also serves as a reference for the crib cluster's networking architecture, which spans four layers (physical, iptables DNAT, Tailscale overlay, and DNS) and is not documented in any single place outside the ticket workspace.

## The crib cluster architecture

The crib cluster is a single-node k3s installation running as a QEMU VM (ID 301) on a Proxmox 8.1.4 host at home, behind a Cox cable modem. The VM runs Ubuntu Noble 24.04 with 4 cores and 8GB RAM. It was bootstrapped from a cloud image using cloud-init.

The final networking stack has four layers. The important change from the failed state is that Traefik now binds host ports 80 and 443 directly. The old `k3s-tailscale-proxy.service` DNAT-to-NodePort layer is disabled.

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 4: DNS                                                │
│  *.crib.scapegoat.dev  →  100.67.90.12  (DigitalOcean A)    │
└──────────────────────┬───────────────────────────────────────┘
                       │ resolves to
┌──────────────────────▼───────────────────────────────────────┐
│  Layer 3: Tailscale Overlay                                   │
│  100.67.90.12 (k3s-proxmox)  — WireGuard mesh network        │
└──────────────────────┬───────────────────────────────────────┘
                       │ TCP 80/443 delivered to host
┌──────────────────────▼───────────────────────────────────────┐
│  Layer 2: Traefik hostPorts                                   │
│  host :80  →  traefik container :8000                         │
│  host :443 →  traefik container :8443                         │
└──────────────────────┬───────────────────────────────────────┘
                       │ routes by Host() rule
┌──────────────────────▼───────────────────────────────────────┐
│  Layer 1: Kubernetes services and pods                        │
│  Jellyfin, ArgoCD, Grafana, poll-modem                        │
└──────────────────────────────────────────────────────────────┘
```

Traffic flow for `https://watch.crib.scapegoat.dev`:

1. Browser resolves `watch.crib.scapegoat.dev` → `100.67.90.12` (Tailscale IP)
2. Browser connects to `100.67.90.12:443` over the Tailscale WireGuard tunnel
3. VM receives the connection on the `tailscale0` interface
4. Traefik receives the connection through its `hostPort: 443` binding and container port `8443`
5. Traefik terminates TLS and routes the request to the `jellyfin` service based on the `Host()` match in its `IngressRoute` resource

The cable modem at `192.168.0.1` does not reliably bridge traffic between physical and virtual MAC addresses, which is why Tailscale is essential. Without the overlay network, the VM is unreachable from any device other than the Proxmox host itself.

## The initial symptom

The first observation was that `tailscale status` showed the VM as `k3s-proxmox` at `100.67.90.12` in `idle` state — it was connected to the tailnet. The Proxmox host itself (`pve` at `100.81.254.116`) was `active` and reachable. But `tailscale ping k3s-server` (a stale registration at `100.97.160.12`) timed out. The correct Tailscale identity was `k3s-proxmox`, not `k3s-server`.

After SSHing into the VM at `100.67.90.12`, the picture became clearer:

- **k3s service**: `active (running)`, uptime 7 minutes — it had auto-started correctly
- **Node**: `k3s-server` in `Ready` state
- **All pods**: Running, including ArgoCD, Jellyfin, cert-manager, monitoring
- **DNS**: `dig watch.crib.scapegoat.dev` resolved to `100.67.90.12` — correct

Everything looked healthy inside the cluster. The problem was between the Tailscale IP and the pods.

## Finding the missing piece: Traefik

The next diagnostic step was to check the ingress layer. The command `kubectl get pods -A | grep traefik` returned nothing. There were no Traefik pods running anywhere in the cluster.

Further checks confirmed:

- `kubectl get ingressclass` — no ingress classes
- `kubectl get crd | grep traefik` — no Traefik CRDs
- `kubectl get daemonset -A` — no Traefik DaemonSet
- `kubectl get deploy -A` — no Traefik Deployment

Traefik was completely absent. But the `k3s-tailscale-proxy.service` — a systemd oneshot that adds iptables DNAT rules — was running and reporting `active (exited)`:

```
● k3s-tailscale-proxy.service - Forward Tailscale IP to k3s Traefik NodePorts
     Active: active (exited) since Sun 2026-05-03 11:34:43 UTC; 9min ago
```

The service had set up these rules:

```
DNAT  tcp  --  *  *  0.0.0.0/0  100.67.90.12  tcp dpt:80  to:127.0.0.1:32277
DNAT  tcp  --  *  *  0.0.0.0/0  100.67.90.12  tcp dpt:443 to:127.0.0.1:32241
```

But `ss -tlnp` showed nothing listening on ports 32277 or 32241. The iptables rules were forwarding traffic to ports with no listener. The `k3s-tailscale-proxy.service` is a `oneshot` type with `RemainAfterExit=yes` — it runs once at boot, sets up rules, and then systemd considers it permanently "active" regardless of whether the backend is actually running.

This is a design flaw in the proxy service: it has no health check mechanism. It reports healthy by default.

## Why Traefik was missing

The k3s configuration file at `/etc/rancher/k3s/config.yaml` contained:

```yaml
write-kubeconfig-mode: "0644"
disable:
  - traefik
tls-san:
  - k3s-server
  - k3s-server.tail879302.ts.net
  - k3s-proxmox
  - k3s-proxmox.tail879302.ts.net
```

The `disable: - traefik` directive tells k3s not to deploy its bundled Traefik ingress controller. This was set by the cloud-init template during initial VM bootstrap.

But Traefik *was* running before the reboot. How?

The answer required digging into the git history and past diary entries.

## Historical reconstruction

All events trace back to **April 15, 2026**, the day the cluster was first set up. The diary file at `fbd83ba:diary.md` (stored in the crib-k3s repo) documents the session.

### Phase 1: Funnel-based public access (original design)

The original networking model used **Tailscale Funnel** to expose services publicly. Funnel received traffic on port 443 and forwarded it via raw TCP passthrough to Traefik:

```
Browser → *.crib.scapegoat.dev DNS (CNAME → k3s-proxmox.tail879302.ts.net)
  → Tailscale Funnel (TCP passthrough 443)
  → Traefik on the VM
  → Kubernetes services
```

DNS was a CNAME record pointing to the Tailscale hostname. Services were publicly accessible through Tailscale's edge network.

### Phase 2: Manually re-enabling Traefik

The diary records that cloud-init disables Traefik by default, and the developer manually re-enabled it:

```bash
# From the diary, Step 2: "Re-enable Traefik"
sudo sed -i '/disable:/,/traefik/d' /etc/rancher/k3s/config.yaml
sudo systemctl restart k3s
```

This was a manual edit on the running VM. The cloud-init template in the git repo was **never updated** — `cloud-init.yaml` still contained `disable: - traefik`.

### Phase 3: Making Traefik reachable on the Tailscale IP

Traefik was listening on the LAN IP (`192.168.0.212`) but not on the Tailscale IP (`100.67.90.12`). Traffic arriving over Tailscale couldn't reach Traefik. This triggered a rapid debugging session visible in git history — **four commits in 12 minutes**:

| Time | Commit | What was tried |
|------|--------|---------------|
| 19:23 | `b8314b1` | Added `HelmChartConfig` with `hostPort: 80/443` |
| 19:25 | `86b7d47` | Added `hostNetwork: true` |
| 19:28 | `005f353` | Added `runAsUser: 0` + `NET_BIND_SERVICE` capability |
| 19:35 | `ec66802` | **Removed the entire traefik-config kustomize** |

The progression shows someone troubleshooting port binding: first trying hostPort alone, then adding hostNetwork, then fixing the root/non-root issue, and then — instead of proceeding with the working configuration — removing the entire `traefik-config` kustomize with the commit message **"using systemd iptables instead."**

This commit message reveals a misunderstanding. The iptables DNAT rules (`k3s-tailscale-proxy.service`) handle traffic forwarding from the Tailscale IP to Traefik's NodePorts. They do not replace Traefik itself. The developer likely conflated the iptables forwarding (which replaced Tailscale Funnel's TCP passthrough role) with Traefik's ingress routing role.

### Phase 4: The Funnel-to-tailnet pivot

At some point after April 15, the networking model changed from Funnel-based public access to tailnet-only access. The DNS record changed from a CNAME pointing to the Tailscale hostname to a direct A record pointing to the Tailscale IP. The README was updated in commit `b3198e0` to reflect this, but the reason for the pivot was not recorded.

### Phase 5: The outage

On May 3, the Proxmox host rebooted. The VM restarted, and k3s read its config file — which still had `disable: - traefik` from the original cloud-init. The `HelmChartConfig` that previously overrode this had been removed from git in commit `ec66802`, and ArgoCD had pruned the corresponding Kubernetes resource. Traefik pods that survived from the initial deployment were gone after the reboot. The iptables proxy dutifully added its DNAT rules and reported healthy, forwarding to ports where nothing listened.

### Root cause chain

The outage resulted from two independent oversights that compounded:

1. The cloud-init template was never updated after Traefik was manually re-enabled on the VM. Any fresh boot reads the original config and disables Traefik.
2. The HelmChartConfig was removed from git without a replacement mechanism for deploying Traefik. The commit message suggests the developer believed iptables rules were sufficient, but they only handle traffic forwarding — not ingress routing.
3. No health check existed on the iptables proxy service, so the broken state was not visible until someone tried to access a service.

## The fix attempt and the crash loop

The fix seemed straightforward: remove `traefik` from the `disable` list in `/etc/rancher/k3s/config.yaml`, apply the `HelmChartConfig` with the hostNetwork/hostPort settings from git history, and restart k3s.

The first complication was that `sed` removed the `traefik` line but left an empty `disable:` block. k3s interpreted this as `--disable ""`, visible in the node annotations:

```
"k3s.io/node-args": "[\"server\",\"--write-kubeconfig-mode\",\"0644\",\"--disable\",\"\",\"--tls-san\",...]"
```

After cleaning up the config to remove the empty `disable:` block entirely and restarting k3s, the Traefik manifest was written to `/var/lib/rancher/k3s/server/manifests/traefik.yaml` — k3s recognized that Traefik was no longer disabled. But k3s immediately entered a crash loop.

### The crash loop

The crash was caused by the cloud-controller-manager (CCM) failing with an RBAC error:

```
Error: unable to load configmap based request-header-client-ca-file: configmaps
"extension-apiserver-authentication" is forbidden: User "k3s-cloud-controller-manager"
cannot get resource "configmaps" in API group "" in the namespace "kube-system"
```

This is a **known k3s race condition** documented in [k3s issue #7328](https://github.com/k3s-io/k3s/issues/7328). The CCM starts before the RBAC RoleBinding `k3s-cloud-controller-manager-authentication-reader` is created. The CCM fails with a permission error, and k3s treats this as fatal — it shuts down entirely.

The issue report says "Restarting the k3s service resolves the issue" because on the second start, the RoleBinding already exists from the first attempt. But in our case, k3s kept hitting the same race on every restart. The likely reason is that k3s uses kine (a SQLite-backed etcd replacement) for state storage, and the crash may prevent the RoleBinding from being persisted.

k3s would briefly start (the node became Ready for a few seconds), then crash when the CCM exited. The cycle repeated every 30-60 seconds. The API server was only briefly available between crashes, making it difficult to apply manual fixes via `kubectl`.

## The takeover recovery

The successful recovery did not try to race `kubectl` against the crash loop. It changed the startup order so k3s could apply its own packaged manifests.

The key observation was that the missing RoleBinding was already present on disk in:

```text
/var/lib/rancher/k3s/server/manifests/ccm.yaml
```

The manifest contained exactly the RoleBinding needed by the error:

```yaml
kind: RoleBinding
metadata:
  name: k3s-cloud-controller-manager-authentication-reader
  namespace: kube-system
roleRef:
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
- kind: User
  name: k3s-cloud-controller-manager
```

The failure was not that we did not know what RBAC to create. The failure was that the embedded cloud-controller-manager started before k3s had time to apply that manifest. The recovery sequence was therefore:

```text
1. Add disable-cloud-controller: true to k3s config.
2. Restart k3s.
3. Let k3s start without launching embedded CCM.
4. Let the add-on controller apply ccm.yaml and other packaged manifests.
5. Verify the RoleBinding exists.
6. Verify the previously forbidden access now works.
7. Remove disable-cloud-controller: true.
8. Restart k3s.
9. Confirm embedded CCM starts without crashing.
```

The validation command was:

```bash
kubectl auth can-i get configmap/extension-apiserver-authentication \
  --as=k3s-cloud-controller-manager \
  -n kube-system
```

It returned:

```text
yes
```

After that, removing `disable-cloud-controller: true` and restarting k3s succeeded. The cloud-controller-manager started normally, the node stayed `Ready`, and `k3s.service` remained `active (running)`.

## Restoring ingress

Once k3s was stable and Traefik was running, a second networking bug remained. The old systemd proxy service still had DNAT rules that rewrote Tailscale traffic from ports 80/443 to old NodePorts `32277/32241`. But the restored Traefik service was now using a hostPort model, and its current NodePorts were different (`31310/31810`). The stale DNAT rules intercepted traffic before Traefik's hostPorts could receive it.

The fix was to stop and disable the proxy:

```bash
sudo systemctl stop k3s-tailscale-proxy.service
sudo systemctl disable k3s-tailscale-proxy.service
```

Stopping the service also ran its `ExecStop` commands, removing the stale DNAT rules. From that point on, traffic could reach Traefik directly on host ports 80 and 443.

The final live Traefik configuration uses the k3s packaged Helm chart and a `HelmChartConfig` equivalent to:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      type: NodePort
    deployment:
      hostNetwork: true
    securityContext:
      capabilities:
        drop: []
        add:
          - NET_BIND_SERVICE
      runAsNonRoot: false
      runAsUser: 0
    ports:
      web:
        hostPort: 80
      websecure:
        hostPort: 443
```

## Restoring ArgoCD application routes

After Traefik CRDs existed again, the app-specific `IngressRoute` resources were still missing. ArgoCD had tried to sync `jellyfin`, `grafana-crib`, and `poll-modem` while the CRDs were absent. Those sync attempts failed. Later, after Traefik installed the CRDs, ArgoCD still refused to retry the same git revision automatically:

```text
Skipping auto-sync: failed previous sync attempt to [revision] and will not retry for [revision]
```

The recovery was to trigger explicit ArgoCD sync operations by patching the `Application.operation` field:

```bash
for app in jellyfin grafana-crib poll-modem; do
  kubectl patch application "$app" -n argocd --type merge -p '{
    "operation": {
      "initiatedBy": {"username": "pi-takeover"},
      "sync": {
        "revision": "b3198e0de27f82b6f4007ce221904fc956b2176b",
        "prune": true
      }
    }
  }'
done
```

After that, the IngressRoutes were created:

```text
jellyfin/jellyfin
jellyfin/jellyfin-http
jellyfin/jellyfin-tv
monitoring/grafana
poll-modem/poll-modem
```

The final URL validation was:

```text
https://argocd.crib.scapegoat.dev/  -> HTTP/2 200
https://watch.crib.scapegoat.dev/   -> HTTP/2 302 location: web/
https://grafana.crib.scapegoat.dev/ -> HTTP/2 302 location: /login
https://modem.crib.scapegoat.dev/   -> HTTP/2 200
```

## Persisting the recovered model

The live system was not enough. The repo needed to be updated so the next VM rebuild or reboot would not recreate the same failure.

The persistent changes were:

- `cloud-init.yaml` no longer writes `disable: - traefik` into `/etc/rancher/k3s/config.yaml`.
- `cloud-init.yaml` now writes `/var/lib/rancher/k3s/server/manifests/traefik-config.yaml` with the hostPort Traefik `HelmChartConfig`.
- The Traefik `HelmChartConfig` uses `hostNetwork`, hostPorts 80/443, explicit Ingress status IP `100.67.90.12`, and `updateStrategy.type: Recreate`.
- `README.md` documents the final model: k3s packaged Traefik, hostNetwork + hostPort 80/443, explicit Ingress status IP, and the legacy DNAT proxy disabled.

This was committed in the crib-k3s repo as:

```text
21e90a8 Recover crib k3s ingress and persist Traefik hostPort model
```

## Proving the fix with a real reboot

A live repair is not complete until it survives a reboot. After the recovery model was persisted, we wrote an operator validation script and playbook in the docmgr ticket workspace:

```text
ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/scripts/01-post-reboot-validate.sh
ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/playbooks/01-post-reboot-recovery-and-validation.md
```

The validation script checks the full stack:

- SSH reachability over Tailscale
- `k3s.service` active state
- node readiness
- pod health
- embedded cloud-controller-manager RBAC
- Traefik HelmCharts, HelmChartConfig, pod, CRDs, and IngressRoutes
- ArgoCD Application sync and health status
- disabled/inactive legacy `k3s-tailscale-proxy.service`
- absence of stale DNAT rules
- external HTTP status codes for ArgoCD, Jellyfin, Grafana, and poll-modem

The first baseline validation passed before reboot. Then the VM was rebooted:

```bash
ssh ubuntu@100.67.90.12 'sudo reboot'
```

The validation script was run in wait mode:

```bash
ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/scripts/01-post-reboot-validate.sh --wait
```

This real test found two useful script bugs. First, `systemctl status | head` under `set -o pipefail` caused exit 141 because `head` closed the pipe early. That was replaced with `sed -n`. Second, the initial `--wait` implementation waited for SSH but did not retry the full Kubernetes validation; it could report success after URL checks even when the remote validation had just failed. The script was changed so `--wait` retries the entire validation until success or timeout.

After those fixes, the post-reboot validation passed at `2026-05-03T09:09:58-04:00`:

```text
POST-REBOOT VALIDATION OK
```

The final reboot validation confirmed:

```text
k3s.service                         -> active
node/k3s-server                     -> Ready
Traefik                             -> Running
IngressRoutes                       -> present
k3s-tailscale-proxy.service         -> disabled / inactive
stale DNAT rules                    -> absent
argocd.crib.scapegoat.dev           -> HTTP 200
watch.crib.scapegoat.dev            -> HTTP 302
grafana.crib.scapegoat.dev          -> HTTP 302
modem.crib.scapegoat.dev            -> HTTP 200
```

The script and playbook were committed as:

```text
26ccbcc Add post-reboot validation script and playbook
```

This validation step is important because it exercised the exact failure mode that caused the incident: k3s startup after reboot. The recovered model no longer depends on manual post-boot edits, stale live state, or an already-running Traefik deployment.

## Resolving `argocd-crib` Progressing health

One post-validation anomaly remained: `argocd-crib` reported `Synced` but `Progressing`, while `https://argocd.crib.scapegoat.dev/` returned HTTP 200. The service worked, but ArgoCD still considered the Application not fully healthy.

The Application owned two resources:

```text
ConfigMap argocd-cmd-params-cm
Ingress   argocd-server-crib
```

The Ingress was the important resource. Its status was empty:

```yaml
status:
  loadBalancer: {}
```

ArgoCD's built-in health check for a standard Kubernetes `Ingress` expects the ingress controller to publish an address into `.status.loadBalancer`. In this cluster, Traefik was serving traffic through `hostNetwork` and hostPorts 80/443, not through a cloud `LoadBalancer` Service. The default Traefik chart configuration published Ingress status from the Traefik Service:

```text
--providers.kubernetesingress.ingressendpoint.publishedservice=kube-system/traefik
```

That Service had no load balancer address to copy, so `argocd-server-crib` served correctly but never became healthy from ArgoCD's perspective.

The fix was to make Traefik publish the Tailscale ingress IP explicitly:

```yaml
providers:
  kubernetesIngress:
    publishedService:
      enabled: false
additionalArguments:
  - "--providers.kubernetesingress.ingressendpoint.ip=100.67.90.12"
```

Applying that change exposed one more hostPort-specific deployment detail. Traefik's chart defaults to a rolling update strategy. With `hostNetwork` and hostPorts 80/443, a second Traefik pod cannot bind the same host ports while the old pod is still running. The safe rollout strategy for this single-node hostPort deployment is therefore `Recreate`:

```yaml
updateStrategy:
  type: Recreate
```

After applying the change, the Ingress status became explicit:

```text
NAME                 CLASS     HOSTS                                                     ADDRESS        PORTS
argocd-server-crib   traefik   argocd.crib.scapegoat.dev,k3s-proxmox.tail879302.ts.net   100.67.90.12   80, 443
```

`argocd-crib` then became `Healthy`. The validation script was tightened so it now requires every ArgoCD Application to be `Healthy` and explicitly checks that `argocd-server-crib` publishes `100.67.90.12` as its Ingress status address.

This fix was applied live, written back to `/var/lib/rancher/k3s/server/manifests/traefik-config.yaml`, and persisted in `cloud-init.yaml` so the k3s packaged component manifest cannot revert after a restart or rebuild.

## Final reboot validation after the ArgoCD health fix

The final validation was a second controlled VM reboot after the Traefik Ingress status fix had been applied and persisted.

```bash
ssh ubuntu@100.67.90.12 'sudo reboot'
./ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/scripts/01-post-reboot-validate.sh --wait
```

This reboot validated the final form of the system, not just the initial recovery. It specifically proved that:

- k3s starts with the embedded cloud-controller-manager enabled.
- Traefik comes back with hostPort 80/443.
- Traefik keeps publishing `100.67.90.12` into standard Ingress status.
- `argocd-crib` returns to `Synced` and `Healthy` after boot.
- The legacy DNAT proxy remains disabled and inactive.
- The external crib URLs return their expected HTTP statuses.

The first post-reboot validation pass occurred while the cluster was still settling. It saw transient `monitoring` Progressing health and a brief HTTP 503 from ArgoCD. That was a useful final test of the validation script itself: URL checks also need to be retryable in `--wait` mode. The script was adjusted so transient URL mismatches return failure to the wait loop instead of exiting immediately.

The next validation attempt passed at `2026-05-03T09:25:56-04:00`:

```text
POST-REBOOT VALIDATION OK
```

The final verified state was:

```text
argocd-crib            Synced   Healthy
monitoring             Synced   Healthy
k3s-tailscale-proxy    disabled / inactive
argocd URL             HTTP 200
watch URL              HTTP 302
grafana URL            HTTP 302
modem URL              HTTP 200
```

At this point the recovered ingress model had survived two controlled VM reboots. The remaining untested scenario is a full VM rebuild from `cloud-init.yaml`; that is a stronger test than rebooting the already-repaired VM.

## Lessons learned

### Do not mix ingress exposure models

The failure combined two incompatible models. The old model used `k3s-tailscale-proxy.service` to DNAT traffic from the Tailscale IP to fixed Traefik NodePorts. The recovered model uses Traefik hostPorts 80/443 directly. Either model can work if designed carefully, but combining them creates a black hole: PREROUTING rewrites traffic before Traefik's hostPort path can receive it.

The current rule is simple:

- Use k3s packaged Traefik with hostNetwork + hostPort 80/443.
- Keep `k3s-tailscale-proxy.service` disabled.
- Do not add DNAT rules for ports 80/443 unless Traefik is intentionally configured without hostPorts and with known fixed NodePorts.

### Cloud-init state diverges from running state silently

Cloud-init runs once on first boot and writes configuration files. If those files are later edited manually on the running VM, the cloud-init template in the git repo becomes stale. On a VM rebuild or fresh boot, the stale template is applied.

This is a general problem with cloud-init: it has no mechanism to reconcile its template with the current running state. The only defense is to either:

1. Never edit cloud-init-managed files manually — instead, update the template and rebuild the VM
2. Or document every manual edit and propagate it back to the template

### k3s packaged components are not obvious

k3s deploys Traefik, CoreDNS, metrics-server, and a local-path provisioner as "packaged components" via a built-in Helm controller. These components are controlled by:

1. The `disable:` list in `/etc/rancher/k3s/config.yaml` — prevents k3s from writing the manifest
2. Static manifest files in `/var/lib/rancher/k3s/server/manifests/` — k3s auto-deploys these as HelmCharts
3. `HelmChartConfig` resources — customize values for packaged HelmCharts

When Traefik is disabled, k3s does not write the manifest file. When the manifest file exists, k3s creates a `HelmChart` resource, which the helm controller processes into a Deployment, Service, and related resources.

The interaction between `disable`, the manifest file, `HelmChart`, and `HelmChartConfig` is not immediately obvious. The k3s documentation on this is at [docs.k3s.io/add-ons/helm](https://docs.k3s.io/add-ons/helm).

### Commit messages matter for infrastructure

The commit message "using systemd iptables instead" in `ec66802` is actively misleading. It suggests that iptables replaces Traefik, when in fact iptables replaces Tailscale Funnel's TCP forwarding role. A more accurate message would have been "Replace Funnel TCP forwarding with iptables DNAT" — which would have made it clear that Traefik is still needed.

### The k3s CCM race condition

k3s issue [#7328](https://github.com/k3s-io/k3s/issues/7328) describes a race condition where the cloud-controller-manager starts before the RBAC RoleBinding that grants it access to the `extension-apiserver-authentication` ConfigMap is created. The CCM exits with a permission error, and k3s treats this as fatal, shutting down the entire server.

The fix in the issue is simply to restart k3s again — on the second start, the RoleBinding should already exist. In this incident the race persisted until we changed the startup ordering. Temporarily setting `disable-cloud-controller: true` let the API server and add-on controller stay up long enough to apply `ccm.yaml`. Once the RoleBinding existed, the embedded cloud controller could be re-enabled and k3s stayed stable.

## Common failure modes

### Failure mode 1: Services down after reboot, pods healthy

**Symptom:** All Kubernetes pods are Running, but `*.crib.scapegoat.dev` services return connection refused.

**Cause:** The ingress controller (Traefik) is not running. The iptables proxy forwards traffic to NodePorts with no listener.

**Diagnosis:**
```bash
kubectl get pods -A | grep traefik     # nothing
ss -tlnp | grep -E '32277|32241'       # nothing
iptables -t nat -L PREROUTING -n -v     # DNAT rules present
```

**Fix:** Re-enable Traefik in k3s config, ensure the hostPort `HelmChartConfig` exists, stop/disable the legacy DNAT proxy if using hostPorts, and restart k3s.

### Failure mode 2: k3s crash loop after config change

**Symptom:** k3s starts, node becomes Ready briefly, then crashes within 30 seconds. Repeats indefinitely.

**Cause:** Cloud-controller-manager RBAC race condition (k3s#7328).

**Diagnosis:**
```bash
journalctl -u k3s.service | grep 'cloud-controller-manager exited'
```

**Fix:** Restart k3s again. If the race persists, temporarily set `disable-cloud-controller: true`, restart k3s, wait for `ccm.yaml` to apply, verify `kubectl auth can-i ... --as=k3s-cloud-controller-manager` returns `yes`, then remove `disable-cloud-controller: true` and restart k3s again.

### Failure mode 3: Tailscale hostname confusion

**Symptom:** `tailscale ping k3s-server` times out, but SSH works to `k3s-proxmox`.

**Cause:** Stale Tailscale registrations from previous VM instances. The VM is registered under a different hostname than expected.

**Fix:** Remove stale registrations from the Tailscale admin console. Use a single consistent hostname.

## Working rules

1. **Never edit k3s config on the VM without updating cloud-init.** Any manual change to `/etc/rancher/k3s/config.yaml` must be propagated to `cloud-init.yaml` in the git repo, or the change will be lost on VM rebuild.

2. **The current ingress model is Traefik hostPort, not DNAT-to-NodePort.** The `k3s-tailscale-proxy.service` is legacy and disabled. Do not re-enable it while Traefik binds host ports 80/443.

3. **Use temporary CCM disable as a recovery lever, not as the final state.** If the embedded cloud-controller-manager crashes before its RBAC applies, temporarily set `disable-cloud-controller: true`, let `ccm.yaml` reconcile, verify RBAC, then remove the flag.

4. **ArgoCD may not retry the same failed revision automatically.** If CRDs were missing during a failed sync, manually trigger a sync operation after the CRDs are restored.

5. **Write accurate commit messages for infrastructure changes.** "using systemd iptables instead" obscured the fact that Traefik was still needed. Infrastructure commits should name the specific component being changed and what replaces what.

6. **Test recovery procedures before you need them.** The post-reboot recovery was not tested when the iptables proxy was set up. A single test — reboot the VM and verify services come back — would have caught the Traefik gap immediately. The new validation script now performs this check end to end.

7. **Validation scripts must wait for the cluster, not just SSH.** SSH can return while Kubernetes pods are still restarting and ArgoCD is still reconciling. A reboot validator should retry the full validation until the cluster settles.

8. **Ingress health is not the same as HTTP reachability.** A standard Kubernetes `Ingress` can serve traffic and still be `Progressing` in ArgoCD if `.status.loadBalancer` is empty. In a hostPort Traefik model, publish the known ingress IP explicitly.

9. **Use Recreate updates for single-node hostPort Traefik.** Rolling updates can strand a new Traefik pod in Pending because the old pod still owns host ports 80/443.

10. **Consolidate Tailscale identities.** Use a single hostname for each VM. Clean up stale registrations promptly.

11. **After any k3s config change, verify the node is stable for 5+ minutes.** The CCM race condition can take up to 30 seconds to manifest. A quick `kubectl get nodes` is not sufficient.

## Related resources

- [[ARTICLE - Deploying k3s on Proxmox - A Technical Deep Dive]] — original setup documentation
- [[PROJ - Jellyfin Media Server]] — Jellyfin deployment details on the cluster
- k3s Helm controller docs: [docs.k3s.io/add-ons/helm](https://docs.k3s.io/add-ons/helm)
- k3s CCM race condition: [github.com/k3s-io/k3s/issues/7328](https://github.com/k3s-io/k3s/issues/7328)
- k3s re-enable Traefik after disable: [github.com/k3s-io/k3s/issues/5114](https://github.com/k3s-io/k3s/issues/5114)
- Ticket workspace: `ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/`
- Session transcript: `/home/manuel/.pi/agent/sessions/--home-manuel-code-wesen-crib-k3s--/2026-05-03T11-37-51-600Z_019deda1-68ef-7233-a49b-487d09b04b5d.jsonl`

## Resolved questions

- **How do we resolve the persistent CCM crash loop?** Temporarily disable the embedded cloud controller, let `ccm.yaml` apply the missing RBAC, verify access, then re-enable the cloud controller.
- **Should Traefik be deployed through k3s packaged components or independently via Helm?** The recovered and persisted model uses k3s packaged Traefik plus a `HelmChartConfig` written by cloud-init.
- **Should the DNAT proxy remain enabled?** No. It conflicts with the hostPort model and is disabled.
- **Was this related to a Tailscale exit node?** No local evidence supports that. The evidence points to inbound Funnel/tailnet ingress experiments, not exit-node routing.

## Near-term next steps

1. Promote the post-reboot validation script to a top-level repo script or Makefile target if it becomes a regular operator tool.
2. Test the updated `cloud-init.yaml` through a full VM rebuild, not just a reboot of the repaired VM.
3. Decide whether to delete the disabled `k3s-tailscale-proxy.service` from the VM or leave it as an explicit rollback artifact.
4. If the Tailscale IP changes, update DNS and Traefik's explicit `ingressendpoint.ip` together.

## Final status

The incident is resolved. The cluster, ingress controller, ArgoCD routes, and public crib service URLs recovered and survived two controlled VM reboots. The final validated ingress model is k3s packaged Traefik with hostNetwork, hostPorts 80/443, explicit Ingress status IP `100.67.90.12`, and the legacy DNAT proxy disabled.
