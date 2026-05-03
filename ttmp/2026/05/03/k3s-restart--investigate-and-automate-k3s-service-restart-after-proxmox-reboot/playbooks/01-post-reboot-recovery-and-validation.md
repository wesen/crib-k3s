---
Title: Post-Reboot Recovery and Validation Playbook
Ticket: k3s-restart
Status: active
Topics:
  - k3s
  - proxmox
  - recovery
  - traefik
  - tailscale
DocType: playbook
Intent: long-term
Owners:
  - manuel
RelatedFiles:
  - /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/scripts/01-post-reboot-validate.sh
  - /home/manuel/code/wesen/crib-k3s/cloud-init.yaml
  - /home/manuel/code/wesen/crib-k3s/README.md
Summary: "Operator playbook for validating and recovering crib-k3s after a VM or Proxmox reboot."
LastUpdated: 2026-05-03
---

# Post-Reboot Recovery and Validation Playbook

## Purpose

Use this playbook after rebooting the crib k3s VM or the Proxmox host that runs it. The goal is to verify that the recovered architecture comes back cleanly: k3s starts, the embedded cloud-controller-manager stays enabled, Traefik binds host ports 80/443, the old DNAT proxy remains disabled, ArgoCD applications are synced, and the public tailnet-facing crib URLs respond.

This playbook matches the final recovery model from the May 3 incident:

- `*.crib.scapegoat.dev` resolves to the VM's Tailscale IP, `100.67.90.12`.
- k3s packaged Traefik is enabled.
- Traefik is configured by `HelmChartConfig` with `hostNetwork: true` and `hostPort: 80/443`.
- `k3s-tailscale-proxy.service` is disabled and inactive.
- ArgoCD owns app routes through Traefik `IngressRoute` resources.

## Quick command

From the crib-k3s repo:

```bash
ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/scripts/01-post-reboot-validate.sh --wait
```

Use `--wait` immediately after a reboot. The script waits for SSH, then runs all remote and URL checks.

## Manual validation sequence

### 1. Confirm the VM is reachable

```bash
ssh ubuntu@100.67.90.12 'hostname; uptime'
```

Expected hostname:

```text
k3s-server
```

### 2. Confirm k3s is stable

```bash
ssh ubuntu@100.67.90.12 'sudo systemctl is-active k3s.service'
ssh ubuntu@100.67.90.12 'sudo kubectl get nodes -o wide'
```

Expected:

```text
active
k3s-server Ready control-plane
```

### 3. Confirm the final k3s config

```bash
ssh ubuntu@100.67.90.12 'sudo cat /etc/rancher/k3s/config.yaml'
```

Expected:

```yaml
write-kubeconfig-mode: "0644"
tls-san:
  - k3s-server
  - k3s-server.tail879302.ts.net
  - k3s-proxmox
  - k3s-proxmox.tail879302.ts.net
```

There should be no `disable: - traefik` and no `disable-cloud-controller: true`.

### 4. Confirm CCM RBAC

```bash
ssh ubuntu@100.67.90.12 \
  'sudo kubectl auth can-i get configmap/extension-apiserver-authentication --as=k3s-cloud-controller-manager -n kube-system'
```

Expected:

```text
yes
```

If this says `no` and k3s is crash-looping, temporarily add `disable-cloud-controller: true`, restart k3s, wait for `ccm.yaml` to apply, verify `yes`, then remove `disable-cloud-controller: true` and restart again.

### 5. Confirm Traefik and routes

```bash
ssh ubuntu@100.67.90.12 'sudo kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o wide'
ssh ubuntu@100.67.90.12 'sudo kubectl get ingressroute -A'
```

Expected routes:

```text
jellyfin/jellyfin
jellyfin/jellyfin-http
jellyfin/jellyfin-tv
monitoring/grafana
poll-modem/poll-modem
```

### 6. Confirm the legacy DNAT proxy is disabled

```bash
ssh ubuntu@100.67.90.12 'sudo systemctl is-enabled k3s-tailscale-proxy.service; sudo systemctl is-active k3s-tailscale-proxy.service'
ssh ubuntu@100.67.90.12 "sudo iptables -t nat -L PREROUTING -n --line-numbers | grep -E '100.67.90.12|32277|32241' || true"
```

Expected:

```text
disabled
inactive
```

The grep command should print nothing.

### 7. Confirm ArgoCD sync

```bash
ssh ubuntu@100.67.90.12 'sudo kubectl get application -n argocd -o wide'
```

Expected:

- `jellyfin` is `Synced` and `Healthy`
- `grafana-crib` is `Synced` and `Healthy`
- `poll-modem` is `Synced` and `Healthy`
- `platform-cert-issuer` is `Synced` and `Healthy`
- `monitoring` is `Synced` and `Healthy`
- `argocd-crib` may show `Progressing` while still serving correctly; investigate if it remains Progressing long-term

If apps are OutOfSync because IngressRoute CRDs were missing during an earlier sync, trigger manual retries:

```bash
for app in jellyfin grafana-crib poll-modem; do
  ssh ubuntu@100.67.90.12 "sudo kubectl patch application $app -n argocd --type merge -p '{\"operation\":{\"initiatedBy\":{\"username\":\"operator\"},\"sync\":{\"prune\":true}}}'"
done
```

### 8. Confirm external URLs

```bash
curl -skI https://argocd.crib.scapegoat.dev/
curl -skI https://watch.crib.scapegoat.dev/
curl -skI https://grafana.crib.scapegoat.dev/
curl -skI https://modem.crib.scapegoat.dev/
```

Expected:

```text
argocd  -> HTTP/2 200
watch   -> HTTP/2 302 location: web/
grafana -> HTTP/2 302 location: /login
modem   -> HTTP/2 200
```

## Recovery decision tree

```text
Cannot SSH
  -> Check Tailscale admin and Proxmox VM state
  -> Start VM 301 if needed

SSH works, k3s inactive/crash-looping
  -> journalctl -u k3s.service
  -> If CCM RBAC error:
       temporarily set disable-cloud-controller: true
       restart k3s
       wait for ccm.yaml RBAC
       remove disable-cloud-controller
       restart k3s

k3s active, URLs fail connection/refused
  -> Check Traefik pod
  -> Check k3s-tailscale-proxy disabled
  -> Check no stale DNAT rules

Traefik running, URL returns 404
  -> Check IngressRoutes
  -> Check ArgoCD apps for stale failed sync
  -> Trigger manual ArgoCD sync

Apps synced, URL still fails TLS or route
  -> Check wildcard TLS secret in target namespace
  -> Check IngressRoute host match and service port
```

## Working rule

Do not mix the old DNAT-to-NodePort model with the final Traefik hostPort model. If Traefik has hostPorts 80/443, the DNAT proxy must remain disabled.
