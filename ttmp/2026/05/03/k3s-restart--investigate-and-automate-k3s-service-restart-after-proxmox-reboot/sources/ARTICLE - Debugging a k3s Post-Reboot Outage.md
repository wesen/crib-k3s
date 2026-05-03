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
---

# Debugging a k3s Post-Reboot Outage — Traefik, HelmCharts, and Crash Loops

This article documents a multi-hour investigation into why a single-node k3s cluster on Proxmox lost all external connectivity after a host reboot. The root cause turned out to be a layered chain of decisions made weeks earlier: a cloud-init template that disabled Traefik, a HelmChartConfig that was removed from git, and an iptables forwarding service that appeared healthy while forwarding to ports with no listener. The fix itself introduced a second problem — a known k3s race condition in the cloud-controller-manager that caused the entire cluster to crash-loop.

The article is written for someone who needs to understand not just what happened, but why each layer behaved the way it did, and what the debugging process looked like in practice.

> [!summary]
> 1. **Traefik was never re-deployed after reboot** because k3s config disabled it and the HelmChartConfig that previously overrode that was removed from git
> 2. **The iptables proxy masked the problem** — it reported healthy while forwarding to dead ports
> 3. **Re-enabling Traefik triggered a k3s crash loop** — a known RBAC race condition in the cloud-controller-manager ([k3s#7328](https://github.com/k3s-io/k3s/issues/7328))
> 4. **Two independent oversights compounded** — the cloud-init was never updated to reflect a manual fix, and the HelmChartConfig removal was based on a misunderstanding of the networking architecture

## Why this note exists

On May 3, 2026, the Proxmox host running the crib k3s cluster was rebooted. After the reboot, `watch.crib.scapegoat.dev` and `argocd.crib.scapegoat.dev` were unreachable. All Kubernetes pods were running, k3s was healthy, DNS resolved correctly — but no HTTP traffic reached any service. This article traces the full investigation from initial symptom to root cause to attempted fix, documenting every dead end and every lesson along the way.

The article also serves as a reference for the crib cluster's networking architecture, which spans four layers (physical, iptables DNAT, Tailscale overlay, and DNS) and is not documented in any single place outside the ticket workspace.

## The crib cluster architecture

The crib cluster is a single-node k3s installation running as a QEMU VM (ID 301) on a Proxmox 8.1.4 host at home, behind a Cox cable modem. The VM runs Ubuntu Noble 24.04 with 4 cores and 8GB RAM. It was bootstrapped from a cloud image using cloud-init.

The networking stack has four layers:

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
                       │ DNAT via iptables
┌──────────────────────▼───────────────────────────────────────┐
│  Layer 2: iptables DNAT (k3s-tailscale-proxy.service)         │
│  :80  →  127.0.0.1:32277   (Traefik HTTP NodePort)           │
│  :443 →  127.0.0.1:32241   (Traefik HTTPS NodePort)          │
└──────────────────────┬───────────────────────────────────────┘
                       │ forwarded to
┌──────────────────────▼───────────────────────────────────────┐
│  Layer 1: Physical / LAN                                      │
│  192.168.0.212 (VM) ← vmbr0 → 192.168.0.227 (Proxmox)       │
└──────────────────────────────────────────────────────────────┘
```

Traffic flow for `https://watch.crib.scapegoat.dev`:

1. Browser resolves `watch.crib.scapegoat.dev` → `100.67.90.12` (Tailscale IP)
2. Browser connects to `100.67.90.12:443` over the Tailscale WireGuard tunnel
3. VM receives the connection on the `tailscale0` interface
4. iptables DNAT rule rewrites destination to `127.0.0.1:32241` (Traefik HTTPS NodePort)
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

k3s would briefly start (the node became Ready for a few seconds), then crash when the CCM exited. The cycle repeated every 30-60 seconds. The API server was only briefly available between crashes, making it impossible to apply manual fixes via `kubectl`.

## Lessons learned

### Oneshot systemd services need health checks

The `k3s-tailscale-proxy.service` is a `Type=oneshot` service with `RemainAfterExit=yes`. It runs once at boot, adds iptables rules, and exits. Systemd considers it permanently active after that. There is no mechanism to verify that the backend (Traefik NodePorts) is actually listening.

A better design would include a verification step:

```bash
#!/bin/bash
# /usr/local/bin/check-traefik-ports.sh
for port in 32277 32241; do
  timeout=0
  while ! ss -tlnp | grep -q ":$port " && [ $timeout -lt 60 ]; do
    sleep 2
    timeout=$((timeout + 2))
  done
  if ! ss -tlnp | grep -q ":$port "; then
    echo "WARNING: Port $port not listening after 60s"
  fi
done
```

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

The fix in the issue is simply to restart k3s again — on the second start, the RoleBinding should already exist. But when the race persists across multiple restarts (as in our case), the situation is more complex and may require manually creating the RoleBinding during a brief window when the API server is up, or stopping k3s entirely, cleaning stale state, and starting fresh.

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

**Fix:** Re-enable Traefik in k3s config and restart.

### Failure mode 2: k3s crash loop after config change

**Symptom:** k3s starts, node becomes Ready briefly, then crashes within 30 seconds. Repeats indefinitely.

**Cause:** Cloud-controller-manager RBAC race condition (k3s#7328).

**Diagnosis:**
```bash
journalctl -u k3s.service | grep 'cloud-controller-manager exited'
```

**Fix:** Restart k3s again. If the race persists, manually create the RoleBinding during a brief API server window, or restore the previous config to stabilize.

### Failure mode 3: Tailscale hostname confusion

**Symptom:** `tailscale ping k3s-server` times out, but SSH works to `k3s-proxmox`.

**Cause:** Stale Tailscale registrations from previous VM instances. The VM is registered under a different hostname than expected.

**Fix:** Remove stale registrations from the Tailscale admin console. Use a single consistent hostname.

## Working rules

1. **Never edit k3s config on the VM without updating cloud-init.** Any manual change to `/etc/rancher/k3s/config.yaml` must be propagated to `cloud-init.yaml` in the git repo, or the change will be lost on VM rebuild.

2. **The iptables proxy does not replace Traefik.** The `k3s-tailscale-proxy.service` handles DNAT forwarding only. Traefik (or another ingress controller) must be running for services to be reachable.

3. **Add health checks to oneshot services.** A systemd oneshot that sets up network rules should verify that its backend is listening before reporting success.

4. **Write accurate commit messages for infrastructure changes.** "using systemd iptables instead" obscured the fact that Traefik was still needed. Infrastructure commits should name the specific component being changed and what replaces what.

5. **Test recovery procedures before you need them.** The post-reboot recovery was not tested when the iptables proxy was set up. A single test — reboot the VM and verify services come back — would have caught the Traefik gap immediately.

6. **Consolidate Tailscale identities.** Use a single hostname for each VM. Clean up stale registrations promptly.

7. **After any k3s config change, verify the node is stable for 5+ minutes.** The CCM race condition can take up to 30 seconds to manifest. A quick `kubectl get nodes` is not sufficient.

## Related resources

- [[ARTICLE - Deploying k3s on Proxmox - A Technical Deep Dive]] — original setup documentation
- [[PROJ - Jellyfin Media Server]] — Jellyfin deployment details on the cluster
- k3s Helm controller docs: [docs.k3s.io/add-ons/helm](https://docs.k3s.io/add-ons/helm)
- k3s CCM race condition: [github.com/k3s-io/k3s/issues/7328](https://github.com/k3s-io/k3s/issues/7328)
- k3s re-enable Traefik after disable: [github.com/k3s-io/k3s/issues/5114](https://github.com/k3s-io/k3s/issues/5114)
- Ticket workspace: `ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/`
- Session transcript: `/home/manuel/.pi/agent/sessions/--home-manuel-code-wesen-crib-k3s--/2026-05-03T11-37-51-600Z_019deda1-68ef-7233-a49b-487d09b04b5d.jsonl`

## Open questions

- How to resolve the persistent CCM crash loop — is it necessary to wipe k3s state and re-bootstrap, or can the RBAC resources be manually injected?
- Should Traefik be deployed via k3s packaged component (remove from disable list) or independently via Helm?
- Is the Funnel-to-tailnet pivot the right long-term model, or should Funnel be re-enabled for services that need public access?

## Near-term next steps

1. Restore k3s to a stable state (re-add `disable: - traefik` if needed to stop the crash loop)
2. Deploy Traefik independently via Helm (bypasses k3s packaged component mechanism entirely)
3. Update `cloud-init.yaml` to match the intended running state
4. Add a health check to `k3s-tailscale-proxy.service`
5. Create a post-reboot validation script
6. Test the full recovery procedure end-to-end
