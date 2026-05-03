---
Title: Diary - Takeover Crashloop Investigation
Ticket: k3s-restart
Status: active
Topics:
  - k3s
  - proxmox
  - recovery
  - systemd
  - tailscale
DocType: reference
Intent: long-term
Owners:
  - manuel
RelatedFiles:
  - /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/reference/01-diary-k3s-restart-investigation.md
  - /home/manuel/code/wesen/crib-k3s/cloud-init.yaml
ExternalSources:
  - https://github.com/k3s-io/k3s/issues/7328
  - https://docs.k3s.io/add-ons/helm
Summary: "Takeover diary for independent investigation of the k3s crashloop after Traefik re-enable attempt."
LastUpdated: 2026-05-03
---

# Diary - Takeover Crashloop Investigation

## Goal

Continue the `k3s-restart` investigation from a clean operator perspective. The immediate goal is to understand why k3s is crash-looping after the previous Traefik recovery attempt, identify what went wrong in that attempt, and find the safest path back to a stable cluster.

## Step 1: Take over and establish a baseline

I am treating the previous investigation as evidence, not as ground truth. The prior notes identify a likely root cause for the original ingress outage, but the current operational problem is now different: k3s itself may be unstable. Before making changes, I need to inspect the live service state, the k3s config, the packaged Traefik manifest state, and the systemd logs.

### Prompt Context

**User prompt (verbatim):** "Ok, we're taking over for your little brother who seems to be struggling with figuring out the crashloop for k3s. Take over and investigate, keep your own diary, go over their steps and see what went wrong"

**Assistant interpretation:** Start an independent crashloop investigation, keep a separate diary, and audit the previous recovery steps.

**Inferred user intent:** Recover the k3s server safely and understand whether the prior fix attempt made incorrect assumptions.

### What I did

- Created this separate takeover diary as `reference/02-diary-takeover-crashloop-investigation.md`.
- Next I will inspect the live VM and prior artifacts before changing anything.

### Why

The previous attempt changed the k3s config and applied a HelmChartConfig. If k3s is now crash-looping, additional writes may make recovery harder. A fresh baseline reduces the risk of chasing stale assumptions.

### What worked

- The new diary exists in the same docmgr ticket and can record an independent investigation path.

### What didn't work

- N/A for this step.

### What I learned

- The ticket already contains useful sources and a previous diary, but the live system must be inspected again.

### What was tricky to build

- N/A.

### What warrants a second pair of eyes

- Whether to recover by restoring the previous stable config first or by continuing to push through the Traefik packaged component path.

### What should be done in the future

- Record every live command and every config mutation in this diary before proceeding to the next action.

### Code review instructions

- Start with this diary and compare against `reference/01-diary-k3s-restart-investigation.md`.
- Validate using `systemctl status k3s`, `journalctl -u k3s`, and `kubectl get nodes` on the VM.

### Technical details

Relevant live host: `ubuntu@100.67.90.12` (`k3s-proxmox` Tailscale identity, VM hostname `k3s-server`).

---

## Step 2: Baseline live crashloop state

The live VM is reachable, but `k3s.service` is not stable. systemd reports it as `activating (auto-restart)`, and the service repeatedly exits with code 0 after the embedded cloud-controller-manager fails. The crash repeats roughly every 10–15 seconds.

### Prompt Context

**User prompt (verbatim):** (see Step 1)

**Assistant interpretation:** Audit the live crashloop and compare it to the previous recovery attempt.

**Inferred user intent:** Find the real operational blocker instead of continuing to apply unvalidated fixes.

### What I did

- Checked host, uptime, and `systemctl status k3s.service` on `ubuntu@100.67.90.12`.
- Read `/etc/rancher/k3s/config.yaml`.
- Listed `/var/lib/rancher/k3s/server/manifests/`.
- Read recent `journalctl -u k3s.service` errors.
- Read `ccm.yaml` and `rolebindings.yaml` from the packaged manifests directory.

### Why

The previous attempt changed k3s config and then diagnosed a repeated RBAC race. Before trying to repair it, I wanted to know whether the missing RoleBinding was absent from disk, absent from the API, or merely not being applied before the embedded CCM starts.

### What worked

- The VM is reachable and not hung.
- The k3s config currently has Traefik re-enabled (no `disable: - traefik`), and k3s has written `/var/lib/rancher/k3s/server/manifests/traefik.yaml`.
- There are no `.skip` files in the manifests directory.
- `/var/lib/rancher/k3s/server/manifests/ccm.yaml` already contains the missing RoleBinding:
  - `RoleBinding/k3s-cloud-controller-manager-authentication-reader`
  - namespace `kube-system`
  - role `extension-apiserver-authentication-reader`
  - subject user `k3s-cloud-controller-manager`

### What didn't work

- k3s repeatedly exits after this error:
  ```text
  unable to load configmap based request-header-client-ca-file: configmaps "extension-apiserver-authentication" is forbidden: User "k3s-cloud-controller-manager" cannot get resource "configmaps" in API group "" in the namespace "kube-system"
  ```
- Because k3s exits so quickly, the add-on manifest controller does not appear to get far enough to apply `ccm.yaml` before the CCM starts and fails.

### What I learned

The earlier framing, "the RoleBinding may not persist," is not the strongest explanation. The stronger explanation is ordering: the needed RBAC exists on disk, but the embedded CCM starts before k3s applies the add-on file that grants its permission. Repeated restarts repeat the same race because the add-on apply step never wins.

### What was tricky to build

The logs are misleading because they point to a missing permission, but the permission manifest is present on disk. The failure is not primarily about authoring the RoleBinding; it is about boot order and whether the API server stays up long enough for add-on reconciliation.

### What warrants a second pair of eyes

Whether to break the boot-order cycle by temporarily disabling the embedded cloud controller (`disable-cloud-controller: true`) or by racing `kubectl apply` during the brief API availability window.

### What should be done in the future

Add an explicit crashloop recovery note: when embedded CCM RBAC races block k3s startup, temporarily disabling the embedded CCM may be safer than repeatedly restarting and hoping the race resolves.

### Code review instructions

- Inspect `/var/lib/rancher/k3s/server/manifests/ccm.yaml` on the VM.
- Compare that manifest with the journal error and confirm it grants exactly the missing access.

### Technical details

Current config:
```yaml
write-kubeconfig-mode: "0644"
tls-san:
  - k3s-server
  - k3s-server.tail879302.ts.net
  - k3s-proxmox
  - k3s-proxmox.tail879302.ts.net
```

Current manifests include:
```text
ccm.yaml
coredns.yaml
local-storage.yaml
metrics-server/
rolebindings.yaml
runtimes.yaml
traefik.yaml
```

---

## Step 3: Break the CCM race by temporarily disabling embedded cloud controller

I added `disable-cloud-controller: true` to `/etc/rancher/k3s/config.yaml` and restarted k3s. This prevented the embedded cloud-controller-manager from starting early and crashing the server. With the server stable, the add-on manifest controller was able to apply the packaged manifests, including Traefik and the CCM RBAC resources.

### Prompt Context

**User prompt (verbatim):** (see Step 1)

**Assistant interpretation:** Continue live recovery, but make a reversible change that stabilizes k3s before trying to repair ingress.

**Inferred user intent:** Recover the cluster safely while understanding what the prior attempt missed.

### What I did

- Backed up `/etc/rancher/k3s/config.yaml` on the VM.
- Appended `disable-cloud-controller: true`.
- Restarted `k3s.service`.
- Waited for k3s to stabilize.
- Verified `kubectl get nodes` and `kubectl get pods -A`.
- Verified that Traefik was installed by k3s Helm controller.
- Verified that the missing CCM RoleBinding now exists and `kubectl auth can-i` returns `yes` for the previously forbidden access.

### Why

The embedded CCM was crashing before the add-on controller could apply `ccm.yaml`. Disabling the embedded CCM gave k3s enough time to start the API server and reconcile add-on manifests. This turned the race into an ordered recovery step.

### What worked

- `k3s.service` became `active (running)`.
- The node is `Ready`.
- Core pods are running.
- k3s created Helm install jobs for Traefik and Traefik CRDs.
- `traefik-54dbf8bb75-4qhrw` is running in `kube-system`.
- `RoleBinding/k3s-cloud-controller-manager-authentication-reader` now exists.
- `kubectl auth can-i get configmap/extension-apiserver-authentication --as=k3s-cloud-controller-manager -n kube-system` returns `yes`.

### What didn't work

- Services were still not reachable after Traefik came up.
- The next blocker is stale iptables DNAT from `k3s-tailscale-proxy.service`.

### What I learned

The previous recovery got close but missed the boot-order escape hatch. The CCM crash loop can be broken by temporarily disabling the embedded CCM, letting k3s apply the RBAC manifests, and then deciding later whether to re-enable CCM.

### What was tricky to build

The fix is counterintuitive: disabling a core component temporarily lets the add-on system create the permissions that component needs. The key is that `disable-cloud-controller: true` changes startup ordering without deleting the RBAC manifests already present on disk.

### What warrants a second pair of eyes

Whether to re-enable the embedded CCM after confirming the RoleBinding exists, or leave it disabled if the single-node cluster remains healthy. Re-enabling should be tested in a controlled restart.

### What should be done in the future

Document `disable-cloud-controller: true` as a temporary recovery lever, not as the intended final state unless explicitly chosen.

### Code review instructions

- Verify `k3s.service` is stable.
- Verify the CCM RoleBinding exists.
- Verify no recent `cloud-controller-manager exited` errors occur after the timestamp where `disable-cloud-controller: true` was applied.

### Technical details

Recovery config now includes:
```yaml
disable-cloud-controller: true
```

The RBAC check now succeeds:
```bash
sudo kubectl auth can-i get configmap/extension-apiserver-authentication \
  --as=k3s-cloud-controller-manager \
  -n kube-system
# yes
```

---

## Step 4: Traefik is running, but stale DNAT rules intercept traffic

With k3s stable, Traefik is now running. The service is NodePort, but the HelmChartConfig also configured Traefik with hostPorts 80 and 443. That means traffic can be handled by Traefik directly on host ports. However, the old `k3s-tailscale-proxy.service` is still adding DNAT rules that redirect traffic for `100.67.90.12:80/443` to stale NodePorts `32277/32241`.

### Prompt Context

**User prompt (verbatim):** (see Step 1)

**Assistant interpretation:** Continue from k3s stabilization into ingress-path debugging.

**Inferred user intent:** Identify what still prevents `watch.crib.scapegoat.dev` and `argocd.crib.scapegoat.dev` from responding.

### What I did

- Checked Traefik HelmCharts and HelmChartConfig.
- Checked Traefik service NodePorts.
- Inspected Traefik Deployment for `hostPort` configuration.
- Checked current iptables PREROUTING rules.
- Tested external curl to `argocd.crib.scapegoat.dev` and `watch.crib.scapegoat.dev`.

### What worked

- Traefik CRDs now exist.
- Traefik pod is running.
- The Traefik Deployment has:
  - `containerPort: 8000`, `hostPort: 80`
  - `containerPort: 8443`, `hostPort: 443`
  - `NET_BIND_SERVICE`
  - `runAsUser: 0` at container securityContext level

### What didn't work

- The old DNAT rules are still present:
  ```text
  100.67.90.12 tcp dpt:80  -> 127.0.0.1:32277
  100.67.90.12 tcp dpt:443 -> 127.0.0.1:32241
  ```
- The current Traefik service NodePorts are different:
  ```text
  80:31310/TCP,443:31810/TCP
  ```
- Therefore the proxy forwards to dead ports and bypasses the working hostPort model.

### What I learned

There are two mutually exclusive ingress exposure models:

1. **Traefik hostPort model:** Traefik binds 80/443 on the host. No DNAT proxy is needed.
2. **DNAT-to-NodePort model:** Traefik exposes fixed NodePorts, and iptables forwards Tailscale 80/443 to those NodePorts.

The previous recovery accidentally combined both models: it restored the old hostPort HelmChartConfig while leaving the DNAT proxy enabled. This creates a traffic black hole.

### What was tricky to build

The stale DNAT rules are earlier in PREROUTING than CNI hostPort rules, so traffic to the Tailscale IP is rewritten before it can reach Traefik's hostPort path. Traefik can be healthy while all external traffic still fails.

### What warrants a second pair of eyes

Whether the final architecture should use hostPort (simpler now that it works) or DNAT-to-fixed-NodePort (closer to the `k3s-tailscale-proxy.service` design). Mixing them is wrong.

### What should be done in the future

Pick one exposure model and encode it in both cloud-init and documentation. The immediate recovery should probably stop/disable `k3s-tailscale-proxy.service` and remove its stale DNAT rules so Traefik hostPorts can receive traffic.

---

## Step 5: Disabled stale `k3s-tailscale-proxy.service`

I stopped and disabled `k3s-tailscale-proxy.service`. Its `ExecStop` rules removed the old DNAT entries from `nat/PREROUTING`, leaving no stale forwarding from `100.67.90.12:80/443` to `127.0.0.1:32277/32241`.

### Prompt Context

**User prompt (verbatim):** (see Step 1)

**Assistant interpretation:** Remove the stale proxy that conflicts with the restored Traefik hostPort model.

**Inferred user intent:** Continue safe recovery toward making ingress reachable again.

### What I did

- Checked `systemctl status k3s-tailscale-proxy.service`.
- Ran `sudo systemctl stop k3s-tailscale-proxy.service`.
- Ran `sudo systemctl disable k3s-tailscale-proxy.service`.
- Verified it is now `disabled` and `inactive`.
- Verified the old DNAT rules no longer appear in `iptables -t nat -L PREROUTING`.

### Why

Traefik is currently configured with hostPorts 80 and 443. The old DNAT-to-NodePort proxy conflicts with that model because it rewrites traffic away from hostPort handling and toward stale NodePorts.

### What worked

- The systemd service stopped cleanly.
- The symlink from `multi-user.target.wants` was removed.
- The stale DNAT rules disappeared.

### What didn't work

- End-to-end service validation still needs to be run after this change.

### What I learned

The immediate live network state now matches the Traefik hostPort model better than the old DNAT proxy model.

### What was tricky to build

Stopping the proxy is safe only because Traefik is now configured with hostPorts. If Traefik were only a NodePort service without hostPorts, disabling the proxy would remove the only Tailscale ingress path.

### What warrants a second pair of eyes

Whether to delete the service file entirely or keep it disabled as a rollback option.

### What should be done in the future

Update docs and cloud-init to avoid enabling both hostPort and DNAT proxy models at the same time.

---

## Step 6: Re-enabled embedded cloud controller after RBAC existed

After stabilizing k3s with `disable-cloud-controller: true`, I verified that the missing CCM RoleBinding existed and that `kubectl auth can-i` returned `yes` for the exact permission that previously failed. I then removed `disable-cloud-controller: true` and restarted k3s. This time the embedded cloud-controller-manager started without crashing k3s.

### Prompt Context

**User prompt (verbatim):** "so how do we go back to enabling the cloud controller? is it enough now that the secrets were restored? I also think the whole traefik thing was disabled so that we could have tailscale exit node."

**Assistant interpretation:** Explain whether disabling CCM is temporary, whether the cluster can safely re-enable it now, and investigate the exit-node hypothesis.

**Inferred user intent:** Return the cluster to a normal k3s configuration if safe, and understand whether Traefik was intentionally disabled for a Tailscale feature.

### What I did

- Searched repo/docs/vault notes for `exit node`, `exit-node`, `disable-cloud-controller`, and related Tailscale terms.
- Verified k3s was stable with `disable-cloud-controller: true`.
- Verified the RoleBinding existed and RBAC check returned `yes`.
- Backed up `/etc/rancher/k3s/config.yaml` again.
- Removed `disable-cloud-controller: true`.
- Restarted k3s.
- Waited 75 seconds and checked service status, node readiness, RBAC, logs, and core pods.
- Tested external ingress after removing stale DNAT proxy.

### What worked

- k3s stayed `active (running)` after re-enabling the embedded cloud controller.
- Node stayed `Ready`.
- Logs show `Running cloud-controller-manager ...` and no `cloud-controller-manager exited` after restart.
- RBAC check still returns `yes`.
- Traefik remains running.
- `https://argocd.crib.scapegoat.dev/` now returns HTTP 200.

### What didn't work

- `https://watch.crib.scapegoat.dev/` returns HTTP 404 from Traefik.
- `kubectl get ingressroute -A` shows no IngressRoute resources.
- ArgoCD shows `jellyfin`, `grafana-crib`, and `poll-modem` as `OutOfSync`, likely because those IngressRoute resources failed to apply while the CRDs were absent and now need resync.

### What I learned

It was enough to re-enable CCM after the RoleBinding existed, but the thing that was restored was RBAC, not secrets. The earlier phrase "secrets restored" is not accurate for this failure mode. The failure was authorization on a ConfigMap, fixed by the RoleBinding from `ccm.yaml`.

I found no evidence that Traefik was disabled for Tailscale exit-node functionality. The local evidence points to Tailscale Funnel/TCP passthrough and later tailnet-facing DNS, not exit-node routing. An exit node is an outbound routing feature (`tailscale up --advertise-exit-node`) and does not require disabling Traefik. Traefik may conflict with Tailscale Funnel/Serve if both want host ports 80/443, but that is different from an exit node.

### What was tricky to build

The safe order was important: do not simply remove `disable-cloud-controller` while the RoleBinding might be missing. First stabilize k3s, let add-ons reconcile, verify RBAC, then re-enable CCM.

### What warrants a second pair of eyes

Whether to encode a permanent recovery guard for this known k3s CCM race or accept that it is only a rare boot-order problem after packaged component changes.

### What should be done in the future

- Resync ArgoCD apps that own IngressRoute resources now that Traefik CRDs exist.
- Update docs: this was not an exit-node issue; it was an ingress exposure model issue.
- Keep the final config without `disable-cloud-controller: true` if it remains stable over a longer observation window.

### Technical details

After re-enable, the config is:
```yaml
write-kubeconfig-mode: "0644"
tls-san:
  - k3s-server
  - k3s-server.tail879302.ts.net
  - k3s-proxmox
  - k3s-proxmox.tail879302.ts.net
```

Validation:
```text
systemctl is-active k3s.service -> active
kubectl get nodes -> Ready
kubectl auth can-i ... --as=k3s-cloud-controller-manager -> yes
curl -skI https://argocd.crib.scapegoat.dev/ -> HTTP/2 200
curl -skI https://watch.crib.scapegoat.dev/ -> HTTP/2 404
```

---

## Step 7: Forced ArgoCD retries and validated external services

After Traefik CRDs existed, ArgoCD still did not recreate the missing IngressRoute resources because the previous automated sync attempts had already failed for the same git revision. ArgoCD logged `Skipping auto-sync: failed previous sync attempt ... and will not retry for [revision]`. I triggered manual sync operations for the affected Applications through the `Application.operation` field.

### Prompt Context

**User prompt (verbatim):** "continue"

**Assistant interpretation:** Continue from stable k3s/Traefik state to restore app ingress and validate service URLs.

**Inferred user intent:** Finish the recovery and confirm that the user-facing services are back.

### What I did

- Inspected ArgoCD Application status for `jellyfin`, `grafana-crib`, and `poll-modem`.
- Confirmed their failed sync operation messages were stale `IngressRoute CRD missing` errors from before Traefik was restored.
- Confirmed ArgoCD was explicitly skipping automated retry for the same revision.
- Patched each Application with an explicit sync operation:
  ```bash
  kubectl patch application "$app" -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"pi-takeover"},"sync":{"revision":"b3198e0de27f82b6f4007ce221904fc956b2176b","prune":true}}}'
  ```
- Verified `kubectl get ingressroute -A` now shows routes in `jellyfin`, `monitoring`, and `poll-modem`.
- Tested external URLs.

### What worked

All affected apps are now `Synced` and `Healthy`:

```text
grafana-crib  Synced  Healthy
jellyfin      Synced  Healthy
poll-modem    Synced  Healthy
```

IngressRoutes now exist:

```text
jellyfin/jellyfin
jellyfin/jellyfin-http
jellyfin/jellyfin-tv
monitoring/grafana
poll-modem/poll-modem
```

External validation:

```text
https://argocd.crib.scapegoat.dev/  -> HTTP/2 200
https://watch.crib.scapegoat.dev/   -> HTTP/2 302 location: web/
https://grafana.crib.scapegoat.dev/ -> HTTP/2 302 location: /login
https://modem.crib.scapegoat.dev/   -> HTTP/2 200
```

### What didn't work

- ArgoCD did not automatically retry the failed revision after the CRDs appeared; manual sync operations were required.
- `argocd-crib` remains `Synced` but `Progressing`; it serves HTTP 200, so this appears to be an ArgoCD health classification issue rather than a reachability problem.

### What I learned

ArgoCD automated sync has a retry memory per revision. If a sync fails because a CRD is missing, then the CRD later appears, ArgoCD may still refuse to retry the same revision automatically. A manual operation clears that operational dead-end.

### What was tricky to build

The cluster was healthy and Traefik was healthy, but the app routes were absent because of ArgoCD sync history rather than Kubernetes state. This is a third layer of recovery state distinct from systemd and k3s.

### What warrants a second pair of eyes

Why `argocd-crib` is `Progressing` despite serving correctly.

### What should be done in the future

A post-reboot recovery script should include an ArgoCD retry step for apps with stale failed sync attempts after CRDs/controllers return.

---

## Step 8: Persist final ingress model in repo docs and cloud-init

After the live recovery succeeded, I updated the repository source of truth so a future VM rebuild does not recreate the original Traefik-disabled state. The intended model is now explicit: k3s packaged Traefik remains enabled, cloud-init writes a `HelmChartConfig` that binds Traefik hostPorts 80/443, and the legacy `k3s-tailscale-proxy.service` DNAT model stays disabled.

### Prompt Context

**User prompt (verbatim):** (see Step 7)

**Assistant interpretation:** Continue by making the recovered live architecture durable in the repo.

**Inferred user intent:** Avoid another reboot/rebuild outage caused by docs or cloud-init drifting from the live state.

### What I did

- Edited `cloud-init.yaml`:
  - removed `disable: - traefik` from `/etc/rancher/k3s/config.yaml` content
  - added `/var/lib/rancher/k3s/server/manifests/traefik-config.yaml` as a cloud-init managed `HelmChartConfig`
  - added comments warning not to combine the hostPort model with the old DNAT proxy service
- Edited `README.md`:
  - described Traefik as k3s packaged Traefik configured by HelmChartConfig with hostNetwork + hostPort 80/443
  - documented that `k3s-tailscale-proxy.service` DNAT-to-NodePort is disabled and should not be used with hostPort

### Why

The live VM was repaired, but the repository still encoded the old broken state. If the VM were rebuilt with the old `cloud-init.yaml`, Traefik would again be disabled and ingress would fail.

### What worked

- The repo now matches the recovered live architecture at a high level.

### What didn't work

- This has not yet been tested through a full VM rebuild.

### What I learned

The correct durable fix is not just a live k3s edit. It is a consistency update across cloud-init, README, operational playbooks, and recovery scripts.

### What was tricky to build

`cloud-init.yaml` needs to provide a k3s packaged component config before or during k3s installation. The chosen approach writes the `HelmChartConfig` into k3s's manifests directory so the k3s add-on controller can apply it with the packaged Traefik chart.

### What warrants a second pair of eyes

Whether cloud-init `write_files` should create `/var/lib/rancher/k3s/server/manifests/traefik-config.yaml` directly, or whether the bootstrap script should write it after `mkdir -p` for maximum bootstrapping reliability.

### What should be done in the future

- Add a recovery/playbook doc that names the final hostPort model.
- Consider deleting or archiving the legacy systemd proxy service from the VM once the hostPort model is fully validated after reboot.

---

## Step 9: Wrote validation script, playbook, rebooted VM, and validated recovery

I wrote the post-reboot validation automation and an operator playbook, then rebooted the k3s VM and validated that the cluster came back cleanly. The first validation attempt after reboot ran too early and correctly found pods still settling; I fixed the script so `--wait` retries full validation instead of only waiting for SSH. The final post-reboot validation passed.

### Prompt Context

**User prompt (verbatim):** "write post-reboot validation script and operator playbook, then actually reboot the machine and make sure it comes back up properly"

**Assistant interpretation:** Produce reusable operator artifacts, then perform a real reboot test of the recovered architecture.

**Inferred user intent:** Prove that the final k3s/Traefik/cloud-init model survives reboot, not just live manual repair.

### What I did

- Wrote `scripts/01-post-reboot-validate.sh` in the ticket workspace.
- Wrote `playbooks/01-post-reboot-recovery-and-validation.md` in the ticket workspace.
- Ran the validation script before reboot as a baseline.
- Rebooted the k3s VM via `ssh ubuntu@100.67.90.12 'sudo reboot'`.
- Ran the validation script with `--wait` after reboot.
- Fixed two script bugs found during real use:
  - `systemctl status | head` under `pipefail` caused exit 141; replaced with `sed -n`.
  - `--wait` initially retried only SSH and let a failed remote validation fall through to URL checks; changed `run_once` to return immediately on remote validation failure and made `--wait` retry full validation.

### What worked

- The VM rebooted and returned on Tailscale.
- k3s came back `active` and node `Ready`.
- Embedded cloud-controller-manager remained enabled and did not crash-loop.
- Traefik came back Running.
- ArgoCD Applications remained Synced/Healthy after the cluster settled.
- The legacy DNAT proxy stayed `disabled` and `inactive`.
- Stale DNAT rules did not return.
- External URL checks passed:
  ```text
  https://argocd.crib.scapegoat.dev/  -> HTTP 200
  https://watch.crib.scapegoat.dev/   -> HTTP 302
  https://grafana.crib.scapegoat.dev/ -> HTTP 302
  https://modem.crib.scapegoat.dev/   -> HTTP 200
  ```

### What didn't work

- The first post-reboot validation attempt failed because pods were still settling. This was expected operationally but exposed that `--wait` needed to retry the entire validation, not just SSH.
- Immediately after reboot, some pods reported `Unknown` or partial readiness for a short period; the second `--wait` run passed once the cluster settled.

### What I learned

A useful reboot validation script must treat SSH readiness as only the first gate. Kubernetes needs additional settling time after SSH returns, especially for ArgoCD, monitoring, and pods with persistent volumes. The script must retry cluster-level checks until they pass or a real timeout expires.

### What was tricky to build

The script had to distinguish transient reboot settling from real failure. The chosen approach is simple: in `--wait` mode, rerun all checks until success or timeout. This avoids embedding complex per-resource backoff logic.

### What warrants a second pair of eyes

- Whether `argocd-crib` being `Progressing` should be allowed indefinitely. It served HTTP 200, and the script currently permits `argocd-crib` Progressing while requiring other apps Healthy.
- Whether to add log checks for `cloud-controller-manager exited` after reboot as a hard failure.

### What should be done in the future

- Optionally install the validation script as a top-level repo script or Makefile target.
- Consider deleting the disabled legacy proxy service from the VM after one more reboot validation.

### Technical details

Final successful post-reboot validation completed at `2026-05-03T09:09:58-04:00` with:

```text
POST-REBOOT VALIDATION OK
```

---

## Step 10: Investigated and fixed `argocd-crib` Progressing health

After the reboot validation, the user asked me to investigate why `argocd-crib` stayed `Progressing` even though `https://argocd.crib.scapegoat.dev/` returned HTTP 200. The root cause was not an application serving problem. It was the interaction between ArgoCD's built-in health check for standard Kubernetes `Ingress` resources and the hostPort Traefik ingress model.

### Prompt Context

**User prompt (verbatim):** "Ok, figure out the argocd progressing thing"

**Follow-up constraint (verbatim):** "continue keeping a diary btw"

**Assistant interpretation:** Identify the actual health signal causing `argocd-crib` to report `Progressing`, fix it if appropriate, persist the fix, and record the work in the diary.

### What I inspected

I inspected the `argocd-crib` Application status:

```bash
kubectl get application argocd-crib -n argocd -o wide
kubectl describe application argocd-crib -n argocd
kubectl get application argocd-crib -n argocd -o json | jq '.status'
```

The Application was `Synced` but `Progressing`. It owned two resources:

```text
ConfigMap argocd-cmd-params-cm
Ingress   argocd-server-crib
```

The relevant Ingress had an empty load balancer status:

```yaml
status:
  loadBalancer: {}
```

The Ingress worked at the HTTP level, but Kubernetes had no published ingress address. ArgoCD's standard Ingress health check treats that as not fully healthy, so the Application stayed `Progressing`.

### Root cause

The recovered ingress model uses k3s packaged Traefik with `hostNetwork: true` and hostPorts 80/443. The Traefik chart defaults to publishing Ingress status from the Traefik Kubernetes Service:

```text
--providers.kubernetesingress.ingressendpoint.publishedservice=kube-system/traefik
```

In this cluster, that Service is not a cloud `LoadBalancer`; it does not have an external load balancer address. Therefore Traefik had no address to copy into standard `Ingress.status.loadBalancer`, even though the hostPort listener was reachable through Tailscale at `100.67.90.12`.

### Fix applied live

I updated the Traefik `HelmChartConfig` so the Kubernetes Ingress provider does not use the Service as its published status source and instead publishes the Tailscale ingress IP explicitly:

```yaml
providers:
  kubernetesIngress:
    publishedService:
      enabled: false
additionalArguments:
  - "--providers.kubernetesingress.ingressendpoint.ip=100.67.90.12"
```

The first attempt exposed another important hostPort deployment detail. Traefik's chart uses a rolling Deployment strategy by default. With `hostNetwork` and hostPorts 80/443, a new Traefik pod cannot schedule while the old pod still owns those host ports. The fix is to use a Recreate update strategy for Traefik:

```yaml
updateStrategy:
  type: Recreate
```

After applying those values, the Traefik Deployment rolled out successfully and its args included:

```text
--providers.kubernetesingress.ingressendpoint.ip=100.67.90.12
```

I also wrote the same manifest back to the live VM file at:

```text
/var/lib/rancher/k3s/server/manifests/traefik-config.yaml
```

That matters because k3s packaged component config is reconciled from the server manifests directory. Updating only the Kubernetes API object would leave a stale manifest file that could reassert the old values later.

### Result

The `argocd-server-crib` Ingress status now has the expected address:

```text
NAME                 CLASS     HOSTS                                                     ADDRESS        PORTS
argocd-server-crib   traefik   argocd.crib.scapegoat.dev,k3s-proxmox.tail879302.ts.net   100.67.90.12   80, 443
```

`argocd-crib` became healthy:

```text
NAME          SYNC STATUS   HEALTH STATUS
argocd-crib   Synced        Healthy
```

Then the tightened validation script passed with all ArgoCD apps requiring `Healthy`:

```text
POST-REBOOT VALIDATION OK
```

### Repository changes made

- Updated `cloud-init.yaml` Traefik `HelmChartConfig` with:
  - `updateStrategy.type: Recreate`
  - disabled `publishedService`
  - explicit ingress endpoint IP `100.67.90.12`
- Updated `README.md` to explain why Traefik publishes the Tailscale IP into standard Ingress status.
- Updated `scripts/01-post-reboot-validate.sh` to:
  - assert `argocd-server-crib` Ingress status IP is `100.67.90.12`
  - require every ArgoCD Application to be `Healthy`; the old `argocd-crib Progressing` exception is no longer needed.

### What was tricky

The externally visible service was healthy, so a simple HTTP check hid the problem. The failing signal was Kubernetes object health, not network health. The fix had to target the status publisher in Traefik's Kubernetes Ingress provider, not the ArgoCD server or the cert-manager certificate.

### Future note

If the Tailscale IP ever changes, update the DNS record and the Traefik `ingressendpoint.ip` value together. Otherwise the Ingress status address will be inaccurate even if routing still works through some other path.

---

## Step 11: Reboot-validated the final Traefik Ingress status fix

After fixing `argocd-crib` health, the user asked me to perform one more controlled reboot and update the final project report. This reboot specifically validated the new Traefik settings:

- explicit Kubernetes Ingress status IP `100.67.90.12`
- `updateStrategy.type: Recreate` for hostPort Traefik
- no validation-script exception for `argocd-crib Progressing`

### Prompt Context

**User prompt (verbatim):** "do it, and do a final project report update (and copy to vault)"

**Assistant interpretation:** Reboot the k3s VM again, prove the final ArgoCD health fix survives startup, then update the diary and project report copies.

### What happened

I rebooted the VM:

```bash
ssh ubuntu@100.67.90.12 'sudo reboot'
```

Then I ran the validation script:

```bash
./ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/scripts/01-post-reboot-validate.sh --wait
```

The first validation pass reached SSH very quickly, while k3s and application pods were still settling. It found transient conditions:

- `monitoring` was still `Progressing`
- ArgoCD returned HTTP 503 briefly

This exposed one final script issue: URL checks still called the top-level `fail`, which bypassed the wait-mode retry loop. I changed URL mismatches to `return 1` from `check_urls`, so `--wait` can retry transient HTTP failures the same way it retries transient Kubernetes health failures.

### Final result

The second validation attempt passed at `2026-05-03T09:25:56-04:00`:

```text
POST-REBOOT VALIDATION OK
```

The important final checks were:

```text
argocd-crib            Synced   Healthy
monitoring             Synced   Healthy
k3s-tailscale-proxy    disabled / inactive
argocd URL             HTTP 200
watch URL              HTTP 302
grafana URL            HTTP 302
modem URL              HTTP 200
```

This confirmed that the Traefik explicit Ingress status configuration survives reboot and that the validation script now handles the real boot sequence correctly: SSH first, Kubernetes health second, HTTP readiness last.

### What was updated because of this step

- `scripts/01-post-reboot-validate.sh` now returns retryable failure for transient URL mismatches in `--wait` mode.
- The project report was updated with this final reboot validation.
- The project report was copied between the ticket source and the Obsidian vault copy so both contain the final state.

### Final operational conclusion

The recovered model has now survived two controlled VM reboots. The final validated model is:

- k3s starts with embedded CCM enabled.
- k3s packaged Traefik is enabled.
- Traefik binds host ports 80/443 via hostNetwork/hostPort.
- Traefik publishes `100.67.90.12` into standard Ingress status.
- ArgoCD sees `argocd-crib` as Healthy.
- The old DNAT proxy remains disabled and inactive.
- All public crib service URLs return expected responses after the cluster settles.
