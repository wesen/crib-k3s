---
Title: System Architecture and Recovery Guide - crib k3s Cluster
Ticket: k3s-restart
Status: active
Topics:
    - k3s
    - proxmox
    - recovery
    - systemd
    - tailscale
DocType: design
Intent: long-term
Owners:
    - manuel
RelatedFiles:
    - /home/manuel/code/wesen/crib-k3s/cloud-init.yaml
    - /home/manuel/code/wesen/crib-k3s/scripts/create-k3s-vm.sh
    - /home/manuel/code/wesen/crib-k3s/README.md
    - /home/manuel/code/wesen/crib-k3s/kubeconfig.yaml
    - /home/manuel/code/wesen/crib-k3s/gitops/kustomize/jellyfin/ingress.yaml
    - /home/manuel/code/wesen/crib-k3s/gitops/kustomize/argocd-crib/argocd-ingress.yaml
ExternalSources: []
Summary: >
    Comprehensive guide explaining every layer of the crib k3s cluster on Proxmox,
    written for someone new to the system. Covers hardware, virtualization, networking,
    k3s internals, Traefik ingress, DNS, TLS, ArgoCD GitOps, and post-reboot recovery.
LastUpdated: 2026-05-03
WhatFor: "Onboarding guide and recovery reference for the crib k3s cluster"
WhenToUse: "When onboarding to the crib cluster, debugging post-reboot issues, or planning infrastructure changes"
---

# System Architecture and Recovery Guide — crib k3s Cluster

## Purpose

This document is a comprehensive technical guide to the **crib k3s cluster**: a single-node Kubernetes cluster running on a Proxmox VM at home, behind a cable modem, reachable exclusively over Tailscale.

It is written for someone who has never seen this system before. After reading this document, you will understand:

- What hardware and software make up the cluster
- How networking works across four layers (physical, virtual, overlay, DNS)
- How applications get deployed and exposed
- What happens when the server reboots and why services might not come back
- How to diagnose and fix a post-reboot outage

---

## 1. Physical Infrastructure

The crib cluster runs on a single physical server at home, sitting behind a cable modem provided by the ISP (Cox Communications). The physical server runs Proxmox VE, a hypervisor based on Debian.

### Key physical components

| Component | Details |
|-----------|---------|
| **Proxmox host** | Physical server, Proxmox 8.1.4 on Debian |
| **Proxmox IP** | `192.168.0.227` on interface `eno1`, bridged as `vmbr0` |
| **Cable modem** | Technicolor CGM4331COM at `192.168.0.1` — gateway and DHCP server |
| **TrueNAS SCALE** | Separate VM (ID 106) at `192.168.0.25` — NFS/SMB storage for media |
| **Network** | Single flat `/24` LAN, all devices get DHCP from the cable modem |

### The cable modem problem

The cable modem's DHCP server sees virtual MAC addresses from Proxmox VMs and does not always treat them the same as physical devices. Specifically:

- VMs on `vmbr0` get DHCP leases and can reach the internet
- VMs on `vmbr0` **cannot always be reached from other LAN devices** — the cable modem apparently does not bridge traffic between physical and virtual MACs at layer 3
- This means you cannot simply SSH from your laptop to a VM on the same LAN

This is why **Tailscale** is essential — it creates an overlay network that bypasses the cable modem entirely.

### Relevant files

- Proxmox article: `/home/manuel/code/wesen/obsidian-vault/Projects/2026/04/15/ARTICLE - Deploying k3s on Proxmox - A Technical Deep Dive.md`
- VM creation script: `scripts/create-k3s-vm.sh`

---

## 2. Virtual Machine Layer

The k3s cluster runs inside a QEMU/KVM virtual machine on Proxmox. The VM was created from an Ubuntu Noble (24.04) cloud image using Proxmox's cloud-init integration.

### VM specifications

| Property | Value |
|----------|-------|
| **VM ID** | 301 |
| **Name** | k3s-server |
| **OS** | Ubuntu Noble 24.04 (cloud image) |
| **Memory** | 8 GB |
| **CPU** | 4 cores, `host` passthrough |
| **Disk** | 30 GB on `local-lvm` |
| **Firmware** | OVMF (UEFI) with Q35 chipset |
| **Network** | `virtio` NIC on `vmbr0` (bridged to physical) |
| **Guest agent** | `qemu-guest-agent` enabled |

### Why a VM and not LXC?

k3s expects a real Linux kernel. LXC containers share the host kernel but with restricted access. Running k3s inside LXC requires a pile of hacks:

- `modprobe overlay` fails (can't load kernel modules)
- `/dev/kmsg` missing (needs manual `mknod` on every boot)
- `/proc/sys` read-only (kubelet can't write kernel parameters)
- AppArmor confinement blocks capabilities k3s needs

After enabling unconfined AppArmor, writable proc/sys, and device access, the container is barely contained — it's a VM with extra steps. A proper QEMU VM avoids all of this.

### Cloud-init bootstrap

The VM boots from a cloud image and is configured by cloud-init. The cloud-init user-data is stored in `/var/lib/vz/snippets/cloud-init-k3s.yaml` on the Proxmox host and referenced via `--cicustom user=local:snippets/cloud-init-k3s.yaml`.

The cloud-init process does the following, in order:

1. **Inject SSH keys** — both ed25519 (for dev machine) and RSA (for Proxmox host)
2. **Update packages** — `apt-get update && apt-get upgrade`
3. **Write k3s config** to `/etc/rancher/k3s/config.yaml`
4. **Write Tailscale apt source** for later installation
5. **Write bootstrap script** to `/usr/local/bin/bootstrap-k3s.sh`
6. **Run the bootstrap script**, which:
   - Installs Tailscale (but does NOT join the tailnet — that's manual)
   - Installs k3s via `curl -sfL https://get.k3s.io | sh -`
   - Waits for the node to become `Ready`
   - Installs cert-manager from upstream YAML
   - Installs ArgoCD from upstream YAML
   - Writes the ArgoCD admin password to `/root/argocd-password` and `/etc/motd`

### ⚠️ Critical cloud-init detail

The k3s config written by cloud-init **disables Traefik**:

```yaml
# /etc/rancher/k3s/config.yaml (written by cloud-init)
write-kubeconfig-mode: "0644"
disable:
  - traefik
```

This means k3s will NOT deploy its bundled Traefik ingress controller. Traefik must be configured separately after bootstrap (see Section 6).

### Relevant files

- Cloud-init template: `cloud-init.yaml`
- VM creation script: `scripts/create-k3s-vm.sh`
- Kubeconfig fetcher: `scripts/setup-access.sh`

---

## 3. Networking — The Four Layers

Networking is the most complex part of this system because it spans four distinct layers. Understanding each layer is essential for debugging connectivity issues.

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
│  192.168.0.1   (Cable modem / Gateway)                       │
└──────────────────────────────────────────────────────────────┘
```

### Layer 1: Physical / LAN

The Proxmox host sits on the home LAN at `192.168.0.227`. Its physical NIC (`eno1`) is bridged as `vmbr0`. VMs attached to `vmbr0` get virtual MAC addresses and DHCP leases from the cable modem at `192.168.0.1`.

- **VM LAN IP:** `192.168.0.212` (via DHCP from cable modem)
- **Proxmox IP:** `192.168.0.227`
- **Gateway:** `192.168.0.1` (cable modem)
- **Subnet:** `192.168.0.0/24`

The VM's LAN IP is used only for local access (e.g., the Samsung TV connecting to Jellyfin at `192.168.0.212:32277`). For everything else, we use Tailscale.

### Layer 2: iptables DNAT

A systemd service called `k3s-tailscale-proxy.service` adds iptables DNAT rules at boot. These rules forward traffic arriving at the Tailscale IP to the Traefik NodePorts.

```
# /etc/systemd/system/k3s-tailscale-proxy.service
[Unit]
Description=Forward Tailscale IP to k3s Traefik NodePorts
After=network.target k3s.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/iptables -t nat -A PREROUTING -d 100.67.90.12 -p tcp --dport 80  -j DNAT --to-destination 127.0.0.1:32277
ExecStart=/sbin/iptables -t nat -A PREROUTING -d 100.67.90.12 -p tcp --dport 443 -j DNAT --to-destination 127.0.0.1:32241
ExecStop=/sbin/iptables -t nat -D PREROUTING -d 100.67.90.12 -p tcp --dport 80  -j DNAT --to-destination 127.0.0.1:32277
ExecStop=/sbin/iptables -t nat -D PREROUTING -d 100.67.90.12 -p tcp --dport 443 -j DNAT --to-destination 127.0.0.1:32241

[Install]
WantedBy=multi-user.target
```

**Why is this needed?** Traefik runs as a Kubernetes NodePort service. By default, NodePorts are only accessible on the node's primary IP. The Tailscale IP (`100.67.90.12`) is a separate virtual interface, so traffic arriving there won't hit the NodePort. The DNAT rules bridge this gap.

**Key detail:** This service is a `oneshot` — it runs once, sets up the rules, and exits. The `RemainAfterExit=yes` flag keeps the service in "active" state so systemd considers it running.

**⚠️ Vulnerability:** The service reports "active (exited)" even when the backend (Traefik) is not running. There is no health check.

### Layer 3: Tailscale Overlay

Tailscale creates a WireGuard-based mesh VPN over the internet. Every device on the tailnet gets a stable IP in the `100.64.0.0/10` range (CGNAT space, not routable on the public internet).

| Tailscale hostname | IP | Purpose |
|-------------------|-----|----------|
| `k3s-proxmox` | `100.67.90.12` | The k3s VM (the one that matters) |
| `pve` | `100.81.254.116` | Proxmox host |
| `f` | `100.72.131.20` | Dev machine |
| `mimimi` | `100.113.140.75` | MacBook |
| `iphone-15-pro` | `100.93.226.49` | iPhone |

**Tailnet domain:** `tail879302.ts.net`

SSH access uses the Tailscale IP or hostname:

```bash
ssh ubuntu@k3s-proxmox       # via MagicDNS
ssh ubuntu@100.67.90.12      # via Tailscale IP
```

**Note:** ICMP ping is filtered by Tailscale on some configurations, so `tailscale ping` may time out even when SSH works fine.

### Layer 4: DNS

Wildcard DNS for `*.crib.scapegoat.dev` is managed via Terraform in DigitalOcean's DNS:

```hcl
# ~/code/wesen/terraform/dns/zones/scapegoat-dev/envs/prod/
wildcard_crib_a = {
  type  = "A"
  name  = "*.crib"
  value = "100.67.90.12"   # Tailscale IP of k3s-proxmox
  ttl   = 3600
}
```

This means:
- `watch.crib.scapegoat.dev` → `100.67.90.12`
- `argocd.crib.scapegoat.dev` → `100.67.90.12`
- `grafana.crib.scapegoat.dev` → `100.67.90.12`
- `modem.crib.scapegoat.dev` → `100.67.90.12`
- `anything.crib.scapegoat.dev` → `100.67.90.12`

**Clients must be on the tailnet** to reach this IP. These names resolve from anywhere (public DNS), but the IP is only reachable from within the tailnet.

### How a request flows

When you open `https://watch.crib.scapegoat.dev` in a browser:

```
Browser resolves watch.crib.scapegoat.dev
  → DNS: 100.67.90.12 (Tailscale IP)
  → Browser connects to 100.67.90.12:443
  → Tailscale encrypts + routes via WireGuard
  → VM receives on tailscale0 interface
  → iptables DNAT: 100.67.90.12:443 → 127.0.0.1:32241
  → Traefik NodePort 32241 receives
  → Traefik routes via IngressRoute to jellyfin:80
  → Jellyfin pod responds
```

---

## 4. k3s and Kubernetes Internals

k3s is a lightweight Kubernetes distribution packaged as a single binary. It bundles the API server, controller manager, scheduler, kubelet, and containerd into one process.

### k3s service

k3s runs as a systemd service:

```
# Check status
systemctl status k3s.service

# Restart (if needed)
sudo systemctl restart k3s.service

# Logs
journalctl -u k3s.service -f
```

The service is **enabled** by default, meaning it auto-starts on boot. After a Proxmox reboot, the VM boots, systemd starts k3s, and k3s recovers all previously deployed workloads from its datastore.

### k3s configuration

The k3s config file controls what k3s enables or disables:

```yaml
# /etc/rancher/k3s/config.yaml
write-kubeconfig-mode: "0644"
disable:
  - traefik
tls-san:
  - k3s-server
  - k3s-server.tail879302.ts.net
  - k3s-proxmox
  - k3s-proxmox.tail879302.ts.net
```

Key fields:

- **`disable: - traefik`** — prevents k3s from deploying its bundled Traefik ingress controller. This is the source of our current problem.
- **`tls-san`** — Subject Alternative Names for the k3s API server TLS certificate. These must include all hostnames used to reach the API (including Tailscale names), or kubectl will fail with TLS verification errors.
- **`write-kubeconfig-mode: "0644"`** — makes the kubeconfig readable by non-root users.

### k3s packaged components

Even with Traefik disabled, k3s deploys several core components as static manifests in `/var/lib/rancher/k3s/server/manifests/`:

| Manifest | Purpose |
|----------|----------|
| `ccm.yaml` | Cloud Controller Manager |
| `coredns.yaml` | CoreDNS for cluster-internal DNS |
| `local-storage.yaml` | Local path provisioner for PVCs |
| `metrics-server.yaml` | Resource metrics (CPU/memory) |
| `rolebindings.yaml` | Default RBAC bindings |

### k3s Helm controller

k3s includes a built-in Helm controller that watches for two custom resource types:

- **`HelmChart`** — tells k3s to install a Helm chart (k3s bundles charts for Traefik and others)
- **`HelmChartConfig`** — overrides values for a `HelmChart`

When k3s starts and Traefik is NOT disabled, it automatically creates a `HelmChart` for Traefik in the `kube-system` namespace. A `HelmChartConfig` can then customize Traefik's values (NodePort settings, security context, etc.).

The CRDs for these resources exist on the cluster even when not in use:

```bash
kubectl get crd | grep helm
# helmchartconfigs.helm.cattle.io
# helmcharts.helm.cattle.io
```

### Pods currently running

After a fresh reboot with all ArgoCD apps synced, the cluster runs these pods:

| Namespace | Pod | Purpose |
|-----------|-----|----------|
| `argocd` | `argocd-application-controller-0` | ArgoCD reconciliation engine |
| `argocd` | `argocd-server-*` | ArgoCD web UI and API |
| `argocd` | `argocd-repo-server-*` | Git repository cache |
| `argocd` | `argocd-redis-*` | ArgoCD cache |
| `argocd` | `argocd-dex-server-*` | SSO/OIDC provider |
| `argocd` | `argocd-applicationset-controller-*` | ApplicationSet controller |
| `argocd` | `argocd-notifications-controller-*` | Notification dispatcher |
| `cert-manager` | `cert-manager-*` | TLS certificate automation |
| `jellyfin` | `jellyfin-*` | Media server |
| `kube-system` | `coredns-*` | Cluster DNS |
| `kube-system` | `local-path-provisioner-*` | Dynamic PV provisioning |
| `kube-system` | `metrics-server-*` | Resource metrics API |
| `monitoring` | `monitoring-grafana-*` | Grafana dashboards |
| `monitoring` | `prometheus-*` | Metrics collection |
| `poll-modem` | `poll-modem-*` | Cable modem monitoring |

### Relevant files

- Kubeconfig: `kubeconfig.yaml` (local copy, synced from VM)
- k3s config on VM: `/etc/rancher/k3s/config.yaml`
- k3s static manifests on VM: `/var/lib/rancher/k3s/server/manifests/`

---

## 5. Traefik Ingress — The Missing Piece

Traefik is the ingress controller that routes external HTTP/HTTPS traffic to the correct Kubernetes service based on hostname. Without Traefik, no web service is reachable from outside the cluster.

### How Traefik normally works with k3s

When k3s deploys Traefik (when `traefik` is NOT in the `disable` list), it:

1. Creates a `HelmChart` resource in `kube-system` referencing the bundled Traefik Helm chart
2. The k3s Helm controller renders the chart and creates:
   - A `Deployment` running the Traefik binary
   - A `Service` of type `NodePort` (ports 80 and 443 mapped to high ports like 32277/32241)
   - `IngressRoute` CRDs (Traefik's custom routing resources)
   - An `IngressClass` resource named `traefik`

### Traefik configuration for crib

The crib cluster needs Traefik to bind on host ports 80 and 443 so the iptables DNAT rules can reach it. This is configured via a `HelmChartConfig`:

```yaml
# HelmChartConfig for Traefik (needs to be applied)
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik          # must match the HelmChart name k3s creates
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      type: NodePort
    deployment:
      hostNetwork: true     # bind directly on host network
    securityContext:
      capabilities:
        drop: []
        add:
          - NET_BIND_SERVICE   # allow binding ports < 1024
      runAsNonRoot: false
      runAsUser: 0
    ports:
      web:
        hostPort: 80           # bind port 80 on all interfaces
      websecure:
        hostPort: 443          # bind port 443 on all interfaces
```

Key settings explained:

- **`hostNetwork: true`** — Traefik pods bind directly to the host's network namespace, bypassing Kubernetes' port allocation
- **`hostPort: 80/443`** — Traefik listens on the host's ports 80 and 443 on ALL interfaces (including `tailscale0`)
- **`NET_BIND_SERVICE`** — Linux capability needed to bind privileged ports (< 1024)
- **`runAsUser: 0`** — Traefik runs as root to bind these ports

### Why Traefik was running before but not after reboot

Here is the sequence of events that led to the current outage:

1. **Initial bootstrap:** cloud-init disables Traefik in k3s config
2. **Post-bootstrap:** A `HelmChartConfig` was applied manually or via ArgoCD to re-enable and configure Traefik
3. **Git history:** The `traefik-config` kustomize was committed (commits `b8314b1` through `005f353`)
4. **Config removal:** The kustomize was removed in commit `ec66802` ("using systemd iptables instead")
5. **Before reboot:** Traefik pods were still running (already deployed, not cleaned up)
6. **After reboot:** k3s starts, sees `disable: - traefik`, no `HelmChartConfig` exists → Traefik is never deployed → ports 32277/32241 have no listener → all `*.crib.scapegoat.dev` services are down

The commit message "using systemd iptables instead" is misleading — the iptables rules only FORWARD traffic, they don't REPLACE Traefik. The person who made that change may have thought the iptables rules were sufficient, but they only handle the DNAT step; Traefik still needs to be running to receive the forwarded traffic.

### How routing works with IngressRoute

Traefik uses `IngressRoute` (a custom resource, not the standard Kubernetes `Ingress`) to define routing rules. Each service defines its own IngressRoute:

```yaml
# Example: gitops/kustomize/jellyfin/ingress.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: jellyfin
  namespace: jellyfin
spec:
  entryPoints:
    - websecure            # listen on port 443
  routes:
    - match: Host(`watch.crib.scapegoat.dev`)  # route by hostname
      kind: Rule
      services:
        - name: jellyfin     # forward to this Kubernetes service
          port: 80
  tls:
    secretName: crib-scapegoat-dev-tls   # TLS certificate
```

Traefik routing logic:

```
Incoming request on port 443
  → TLS termination using crib-scapegoat-dev-tls
  → Check SNI hostname against all IngressRoute rules
  → Match Host() condition
  → Forward to matching Kubernetes service
```

### Current IngressRoute resources

| Namespace | Name | Host | Service |
|-----------|------|------|----------|
| `jellyfin` | `jellyfin` | `watch.crib.scapegoat.dev` | `jellyfin:80` |
| `jellyfin` | `jellyfin-http` | `watch.crib.scapegoat.dev` | `jellyfin:80` |
| `jellyfin` | `jellyfin-tv` | `192.168.0.212` | `jellyfin:80` |
| `monitoring` | `grafana` | `grafana.crib.scapegoat.dev` | `monitoring-grafana:80` |
| `poll-modem` | `poll-modem` | `modem.crib.scapegoat.dev` | `poll-modem:80` |
| `argocd` | `argocd-server-crib` | `argocd.crib.scapegoat.dev` | (standard `Ingress`, not `IngressRoute`) |

**Note:** The ArgoCD ingress uses the standard Kubernetes `Ingress` resource (not `IngressRoute`) with `ingressClassName: traefik`. This still requires Traefik to be running, as Traefik watches both `IngressRoute` and standard `Ingress` resources.

---

## 6. TLS — Certificate Management

TLS certificates for `*.crib.scapegoat.dev` are managed by cert-manager using DNS-01 validation against DigitalOcean's DNS API.

### Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  cert-manager    │────▶│  DigitalOcean    │────▶│  DNS TXT record  │
│  ClusterIssuer   │     │  DNS API         │     │  _acme-challenge │
│  letsencrypt-prod│     │                  │     │  *.crib.scapegoat│
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                                                  │
        │  verifies TXT record                              │
        ▼                                                  │
┌─────────────────┐                                        │
│  Let's Encrypt   │◀──────────────────────────────────────┘
│  ACME server     │
└─────────────────┘
        │
        │ issues certificate
        ▼
┌─────────────────────────────────────────┐
│  Secret: crib-scapegoat-dev-tls           │
│  Namespace: cert-manager                  │
│  Type: kubernetes.io/tls                  │
│  Contains: tls.crt + tls.key              │
└─────────────────────────────────────────┘
        │
        │ copied to each namespace that needs it
        ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  monitoring ns   │ │  jellyfin ns     │ │  poll-modem ns   │
│  (Grafana)       │ │  (Jellyfin)      │ │  (poll-modem)    │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

### How it works

1. A `ClusterIssuer` named `letsencrypt-prod` is configured with the DigitalOcean API token
2. A `Certificate` resource requests a wildcard cert for `*.crib.scapegoat.dev`
3. cert-manager creates a DNS TXT record at `_acme-challenge.crib.scapegoat.dev` via the DigitalOcean API
4. Let's Encrypt verifies the TXT record and issues the certificate
5. The certificate is stored as a Kubernetes Secret `crib-scapegoat-dev-tls` in the `cert-manager` namespace
6. The secret must be **manually copied** to each namespace that needs it (cert-manager doesn't sync across namespaces)

### Copying the wildcard secret

```bash
# Copy wildcard cert to a namespace that needs it
kubectl get secret crib-scapegoat-dev-tls -n cert-manager -o yaml \
  | sed 's/namespace: cert-manager/namespace: TARGET_NAMESPACE/' \
  | kubectl apply -f -
```

### Known issue: DigitalOcean API rate limiting

The DigitalOcean DNS API has rate limits. If cert-manager retries too aggressively (e.g., during debugging), it can hit 429 errors. This is documented in playbook `06-recover-from-cert-manager-digitalocean-429s.md`.

### Relevant files

- Platform cert issuer app: `gitops/applications/platform-cert-issuer.yaml`
- ClusterIssuer manifest: `gitops/kustomize/platform-cert-issuer/clusterissuer.yaml`
- Wildcard cert manifest: `gitops/kustomize/platform-cert-issuer/wildcard-certificate.yaml`

---

## 7. ArgoCD GitOps

ArgoCD is the GitOps engine that keeps the cluster state synchronized with the git repository. Every application deployed to the cluster is defined as code in the `crib-k3s` repository.

### How ArgoCD works

```
┌──────────────────────────────────────────────────────┐
│  Git Repository: github.com/wesen/crib-k3s           │
│                                                      │
│  gitops/                                             │
│  ├── applications/        ← ArgoCD Application CRs   │
│  │   ├── jellyfin.yaml                                 │
│  │   ├── argocd-crib.yaml                              │
│  │   ├── platform-cert-issuer.yaml                     │
│  │   ├── grafana-crib.yaml                             │
│  │   ├── monitoring.yaml                               │
│  │   └── poll-modem.yaml                               │
│  └── kustomize/           ← Kubernetes manifests       │
│      ├── jellyfin/                                     │
│      ├── argocd-crib/                                  │
│      ├── platform-cert-issuer/                         │
│      ├── grafana-crib/                                 │
│      └── poll-modem/                                   │
└──────────────────────┬───────────────────────────────┘
                       │ polls every 3 minutes
                       ▼
┌──────────────────────────────────────────────────────┐
│  ArgoCD (running in cluster, namespace: argocd)       │
│                                                      │
│  For each Application:                                │
│    1. Fetch latest manifests from git                 │
│    2. Compare with live cluster state                 │
│    3. If drift detected → Sync (apply changes)        │
│    4. Report health status                            │
└──────────────────────┬───────────────────────────────┘
                       │ applies manifests
                       ▼
┌──────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                   │
│                                                      │
│  Deployments, Services, IngressRoutes, PVCs, etc.    │
└──────────────────────────────────────────────────────┘
```

### Application manifests

Each ArgoCD Application defines:

- **Source:** Which git repo + path to watch
- **Destination:** Which cluster + namespace to deploy to
- **Sync policy:** `automated: { prune: true, selfHeal: true }` means ArgoCD automatically applies changes and removes orphaned resources

```yaml
# Example: gitops/applications/jellyfin.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: jellyfin
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/wesen/crib-k3s.git
    targetRevision: main
    path: gitops/kustomize/jellyfin
  destination:
    server: https://kubernetes.default.svc
    namespace: jellyfin
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Current ArgoCD applications

| Application | Status (post-reboot) | Purpose |
|-------------|---------------------|----------|
| `argocd-crib` | Synced, Healthy | ArgoCD own ingress config |
| `platform-cert-issuer` | Synced, Healthy | cert-manager + wildcard cert |
| `monitoring` | Synced, Healthy | Prometheus + Grafana stack |
| `jellyfin` | OutOfSync, Healthy | Media server |
| `grafana-crib` | OutOfSync, Healthy | Grafana ingress |
| `poll-modem` | OutOfSync, Healthy | Cable modem monitor |

The "OutOfSync" status on some apps is expected — these use Traefik `IngressRoute` CRDs that don't exist yet (because Traefik isn't running). Once Traefik is restored, ArgoCD will sync them automatically.

### Relevant files

- All applications: `gitops/applications/*.yaml`
- All kustomize overlays: `gitops/kustomize/*/`
- ArgoCD access: `https://argocd.crib.scapegoat.dev` (admin password on VM at `/root/argocd-password`)

---

## 8. Post-Reboot Recovery Procedure

This is the procedure for bringing the crib cluster back to full health after a Proxmox host reboot.

### What auto-recovers (no intervention needed)

These components restart automatically via systemd:

- ✅ **Tailscale** — `tailscaled.service` is enabled, auto-connects to tailnet
- ✅ **k3s** — `k3s.service` is enabled, starts the Kubernetes control plane
- ✅ **All pods** — k3s reconciles pod state from its datastore
- ✅ **ArgoCD** — auto-syncs applications from git
- ✅ **iptables DNAT** — `k3s-tailscale-proxy.service` is enabled, adds forwarding rules
- ✅ **cert-manager** — renews certificates as needed

### What does NOT auto-recover

- ❌ **Traefik** — if k3s config has `disable: - traefik` and no `HelmChartConfig` exists, Traefik will not be deployed
- ❌ **Wildcard TLS secret copies** — if namespaces lost their copy of `crib-scapegoat-dev-tls`, they need to be re-copied

### Step-by-step recovery

#### Step 1: Verify the VM is running and reachable

```bash
# From the dev machine
ssh ubuntu@100.67.90.12 "hostname && uptime"
# Expected: k3s-server, uptime shows recent boot
```

If unreachable:
1. Log into Proxmox at `https://192.168.0.227:8006`
2. Check VM 301 is running: `qm status 301`
3. Start if stopped: `qm start 301`
4. Wait 2-3 minutes for cloud-init and k3s to bootstrap

#### Step 2: Verify k3s and pods

```bash
ssh ubuntu@100.67.90.12

# Check k3s service
sudo systemctl status k3s.service

# Check node is Ready
sudo kubectl get nodes

# Check all pods are Running
sudo kubectl get pods -A
```

All pods should be `Running` within 5 minutes of boot. ArgoCD pods may take longer to fully sync.

#### Step 3: Check if Traefik is running

```bash
# Check for Traefik pods
sudo kubectl get pods -A | grep traefik

# Check for HelmChart resources
sudo kubectl get helmchart -A
sudo kubectl get helmchartconfig -A

# Check if NodePorts are listening
sudo ss -tlnp | grep -E '32277|32241|:80 |:443 '
```

If no Traefik pods exist, proceed to Step 4.

#### Step 4: Re-enable Traefik

**Option A: Edit k3s config on the VM (quick fix, not persistent across VM rebuilds)**

```bash
ssh ubuntu@100.67.90.12

# 1. Remove traefik from the disable list
sudo sed -i '/^disable:/,/^tls-san:/ s/^  - traefik$//' /etc/rancher/k3s/config.yaml

# 2. Create HelmChartConfig for Traefik
sudo kubectl apply -f - <<'EOF'
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
EOF

# 3. Restart k3s to pick up config change
sudo systemctl restart k3s.service

# 4. Wait for k3s to be ready
sudo kubectl wait --for=condition=Ready node/k3s-server --timeout=120s

# 5. Wait for Traefik pods
sudo kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=traefik -n kube-system --timeout=120s
```

**Option B: Update cloud-init.yaml (persistent fix)**

1. Edit `cloud-init.yaml` in the repo to remove `traefik` from the disable list
2. Add the HelmChartConfig as a `write_files` entry
3. Upload the updated cloud-init to Proxmox:
   ```bash
   scp cloud-init.yaml root@pve:/var/lib/vz/snippets/cloud-init-k3s.yaml
   ```
4. This takes effect on the next VM rebuild; for immediate fix, use Option A

#### Step 5: Verify services are reachable

```bash
# Check Traefik is listening on host ports
sudo ss -tlnp | grep -E ':80 |:443 '

# Test from dev machine (on tailnet)
curl -skI https://watch.crib.scapegoat.dev/
curl -skI https://argocd.crib.scapegoat.dev/
curl -skI https://grafana.crib.scapegoat.dev/
curl -skI https://modem.crib.scapegoat.dev/
```

All should return HTTP 200 or 301/302 responses.

#### Step 6: Verify TLS certificates

```bash
ssh ubuntu@100.67.90.12

# Check wildcard cert exists and is valid
sudo kubectl get certificate -A

# Copy to namespaces that need it (if missing)
for ns in monitoring jellyfin poll-modem; do
  sudo kubectl get secret crib-scapegoat-dev-tls -n $ns 2>/dev/null \
    || (sudo kubectl get secret crib-scapegoat-dev-tls -n cert-manager -o yaml \
        | sed "s/namespace: cert-manager/namespace: $ns/" \
        | sudo kubectl apply -f -)
done
```

---

## 9. Systemd Services on the VM

The VM runs several systemd services that are critical for the cluster. Understanding their boot order and dependencies is essential.

### Boot sequence

```
VM powers on
  │
  ▼
cloud-init runs (first boot only)
  │
  ▼
systemd starts default targets
  │
  ├── tailscaled.service (enabled)
  │     └── Connects to tailnet, gets IP 100.67.90.12
  │
  ├── k3s.service (enabled)
  │     └── Starts k3s-server process
  │           ├── Loads config from /etc/rancher/k3s/config.yaml
  │           ├── Starts containerd
  │           ├── Deploys static manifests (coredns, metrics-server, etc.)
  │           ├── If NOT disabled: deploys Traefik via HelmChart
  │           └── Reconciles all existing workloads from datastore
  │
  └── k3s-tailscale-proxy.service (enabled)
        └── After=network.target k3s.service
              └── Adds iptables DNAT rules
              └── Exits (RemainAfterExit=yes)
```

### Service details

| Service | Type | Auto-start | Purpose |
|---------|------|------------|----------|
| `k3s.service` | forking | ✅ enabled | k3s server + containerd + kubelet |
| `tailscaled.service` | notify | ✅ enabled | Tailscale daemon |
| `k3s-tailscale-proxy.service` | oneshot | ✅ enabled | iptables DNAT rules |
| `qemu-guest-agent.service` | notify | ✅ enabled | Proxmox guest agent |

### Checking all services

```bash
# Quick health check
systemctl is-active k3s tailscaled k3s-tailscale-proxy qemu-guest-agent

# Full status overview
systemctl list-units --type=service --state=running | grep -E 'k3s|tailscale|qemu'
```

---

## 10. Diagnostic Commands Cheat Sheet

A quick reference for debugging common issues.

### Connectivity

```bash
# From dev machine
tailscale status                            # Check tailnet membership
tailscale ping k3s-proxmox                  # Test reachability
ssh ubuntu@100.67.90.12 "uptime"            # SSH connectivity test
dig watch.crib.scapegoat.dev +short         # DNS resolution
curl -skI https://watch.crib.scapegoat.dev/ # End-to-end test
```

### On the VM

```bash
# k3s
sudo systemctl status k3s
sudo kubectl get nodes
sudo kubectl get pods -A
sudo kubectl get pods -A -w   # watch for crashes

# Traefik
sudo kubectl get pods -A | grep traefik
sudo kubectl get helmchart -A
sudo kubectl get helmchartconfig -A
sudo ss -tlnp | grep -E ':80|:443|32277|32241'

# Networking
sudo iptables -t nat -L PREROUTING -n -v
ip addr show tailscale0
tailscale ip

# TLS
sudo kubectl get certificate -A
sudo kubectl get secret -A | grep tls

# ArgoCD
sudo kubectl get application -n argocd -o wide
sudo kubectl get ingress -A
```

### Proxmox host

```bash
# From dev machine or Proxmox host
ssh root@pve 'qm status 301'              # VM status
ssh root@pve 'qm start 301'              # Start VM if stopped
ssh root@pve 'qm terminal 301'           # Serial console
ssh root@pve 'ip neigh flush 192.168.0.212'  # Clear stale ARP
```

---

## 11. Known Issues and Future Improvements

### Known issues

1. **Traefik not persisted** — The `HelmChartConfig` for Traefik was removed from git, and the k3s config still disables it. This means Traefik won't come back after a reboot unless manually re-enabled.

2. **No health check on iptables proxy** — `k3s-tailscale-proxy.service` reports healthy even when backend ports have no listener.

3. **Tailscale hostname confusion** — The VM is registered as `k3s-proxmox` but the hostname is `k3s-server`. The old `k3s-server` Tailscale registration was stale.

4. **TLS secret not auto-synced** — The wildcard certificate is manually copied to namespaces. If cert-manager renews the cert, the copies become stale.

5. **Documentation drift** — README says "Ingress: Traefik (k3s default)" but the config disables it.

### Recommended improvements

1. **Re-add `traefik-config` to gitops** — Either restore the `HelmChartConfig` as an ArgoCD-managed application, or remove `traefik` from the k3s `disable` list in cloud-init.

2. **Add a health check script** — Create a script that runs after `k3s-tailscale-proxy.service` and verifies that ports 32277 and 32241 are listening:
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

3. **Consolidate Tailscale identity** — Use a single hostname (recommend `k3s-server` since that's the VM hostname) and clean up the old `k3s-proxmox` registration.

4. **Automate TLS secret sync** — Use cert-manager's `replicate` feature or a CronJob to copy the wildcard cert to all namespaces.

5. **Create a post-reboot validation script** — A single script that checks all services and reports status.

---

## Appendix A: History — Why Traefik Was Disabled

This section traces the full history of Traefik in the crib cluster, reconstructed from
git history and diary entries. Understanding this history is essential because it explains
why the cluster is in its current broken state.

### Timeline

All events below occurred on **April 15, 2026**.

#### Phase 1: Initial Setup — Funnel + Traefik (19:00–19:23)

The original design used **Tailscale Funnel** to expose services publicly.
The networking model was:

```
Browser → *.crib.scapegoat.dev DNS (CNAME → k3s-proxmox.tail879302.ts.net)
  → Tailscale Funnel (TCP passthrough 443)
  → Traefik on the VM
  → Kubernetes services
```

In this model:
- DNS was a **CNAME** record pointing to `k3s-proxmox.tail879302.ts.net`
- Tailscale Funnel received all traffic on port 443 and forwarded it via raw TCP
- Traefik terminated TLS with Let's Encrypt certificates
- Services were **publicly accessible** through Tailscale's edge network

The diary (Step 2) explicitly records re-enabling Traefik:

```bash
# From the diary, Step 2: "Re-enable Traefik"
# k3s had Traefik disabled in the cloud-init (disable: [traefik]).
# Removed that line and restarted k3s:
sudo sed -i '/disable:/,/traefik/d' /etc/rancher/k3s/config.yaml
sudo systemctl restart k3s
```

Note that this was a **manual edit on the VM** — the cloud-init template in the git repo
was never updated. Traefik was still listed in the `disable` block in `cloud-init.yaml`.

#### Phase 2: Making Traefik Reachable on Tailscale IP (19:23–19:35)

The problem: Traefik was listening on the LAN IP (`192.168.0.212`) but not on the
Tailscale IP (`100.67.90.12`). Traffic arriving over Tailscale couldn't reach Traefik.

This triggered a rapid debugging session — **four commits in 12 minutes**:

| Time | Commit | What was tried |
|------|--------|---------------|
| 19:23 | `b8314b1` | Added `HelmChartConfig` with `hostPort: 80/443` — Traefik pod binds these ports on the host |
| 19:25 | `86b7d47` | Added `hostNetwork: true` — pod uses host's network namespace directly |
| 19:28 | `005f353` | Added `runAsUser: 0` + `NET_BIND_SERVICE` — non-root pods can't bind ports < 1024 |
| 19:35 | `ec66802` | **Removed the entire traefik-config kustomize** — "using systemd iptables instead" |

The progression shows someone troubleshooting port binding issues:

1. **First attempt:** Just set `hostPort: 80/443` on the NodePort service → probably didn't work because Traefik was running as non-root and couldn't bind privileged ports
2. **Second attempt:** Added `hostNetwork: true` → gets the pod into the host network namespace, but still can't bind ports < 1024 as non-root
3. **Third attempt:** Added `runAsUser: 0` and `NET_BIND_SERVICE` capability → this should have worked, but...
4. **Fourth commit:** Gave up on the HelmChartConfig approach entirely, removed it from git, and created a systemd iptables DNAT service instead

The commit message "using systemd iptables instead" suggests the HelmChartConfig approach
was abandoned in favor of iptables forwarding. **But this is a misunderstanding** — the
iptables rules only forward traffic from the Tailscale IP to Traefik's NodePorts; they
don't replace Traefik itself.

#### Phase 3: The Funnel-to-Tailnet Pivot (sometime after April 15)

At some point between April 15 and May 2, the networking model changed fundamentally:

| Aspect | Original (Funnel) | Current (Tailnet-only) |
|--------|--------------------|-----------------------|
| DNS type | CNAME → `k3s-proxmox.tail879302.ts.net` | A record → `100.67.90.12` |
| Public access | Yes (via Tailscale Funnel) | No (tailnet only) |
| TLS termination | Traefik (via Funnel TCP passthrough) | Traefik (via iptables DNAT) |
| Funnel needed | Yes | No |

The README was updated in commit `b3198e0` ("Clarify crib tailnet DNS model in docs")
to reflect this change: `*.crib.scapegoat.dev` is now a tailnet-facing A record, not
a Funnel path.

This change was documented but the **reason for the pivot** was not captured in any
commit message or diary entry. Likely reasons:

- Funnel required a paid Tailscale plan
- Funnel TCP passthrough may have been unreliable or added latency
- The tailnet-only model is simpler and sufficient for a homelab

#### Phase 4: Post-Reboot Outage (May 3)

When the Proxmox host rebooted on May 3:

1. VM boots → cloud-init writes k3s config with `disable: - traefik` (the cloud-init was **never updated** to remove this)
2. k3s starts → sees `disable: - traefik` → does not deploy Traefik
3. No `HelmChartConfig` exists in the cluster (it was removed from git in `ec66802`)
4. `k3s-tailscale-proxy.service` adds iptables DNAT rules → forwards to ports with no listener
5. All `*.crib.scapegoat.dev` services are down

### Root cause summary

The outage is the result of **two independent mistakes that compounded**:

1. **The cloud-init template was never updated.** Traefik was manually re-enabled on the
   VM during initial setup (diary Step 2), but the `cloud-init.yaml` in the git repo
   still has `disable: - traefik`. On a fresh boot, k3s reads this config and disables
   Traefik.

2. **The `HelmChartConfig` was removed from git without replacement.** Commit `ec66802`
   deleted the Traefik kustomize with the message "using systemd iptables instead."
   The iptables rules handle traffic forwarding but do not deploy Traefik itself.
   After the `HelmChartConfig` was removed, ArgoCD would have pruned the corresponding
   Kubernetes resource, but the already-running Traefik pods survived until the reboot.

3. **There was no health check.** The `k3s-tailscale-proxy.service` reported healthy
   regardless of whether Traefik was running, masking the problem.

### What the original developer likely intended

The most likely intended state was:

- k3s config: `disable: - traefik` (keep Traefik disabled by default to control the deployment)
- `HelmChartConfig`: Applied separately to configure Traefik with the right NodePort/hostNetwork settings
- `k3s-tailscale-proxy.service`: iptables DNAT for Tailscale IP reachability

But removing the `HelmChartConfig` from git while keeping k3s config disabled broke
this chain. The fix is to either:

- **Option A:** Remove `traefik` from the k3s `disable` list (let k3s deploy default Traefik)
- **Option B:** Re-add a `HelmChartConfig` as an ArgoCD-managed application (explicit control)
- **Option C:** Deploy Traefik independently via Helm (full control, more complex)

For a homelab cluster, **Option A** (re-enable in k3s config) is the simplest and most
robust approach, combined with updating `cloud-init.yaml` so the fix persists across
VM rebuilds.

## 12. File Reference

Complete map of all important files in the system.

### In the crib-k3s repository

```
crib-k3s/
├── README.md                           # Project overview
├── cloud-init.yaml                      # Cloud-init template (bootstrap)
├── kubeconfig.yaml                      # Local kubeconfig copy
├── scripts/
│   ├── create-k3s-vm.sh                # Proxmox VM creation
│   └── setup-access.sh                 # Fetch kubeconfig from VM
├── gitops/
│   ├── applications/                   # ArgoCD Application CRs
│   │   ├── argocd-crib.yaml
│   │   ├── grafana-crib.yaml
│   │   ├── jellyfin.yaml
│   │   ├── monitoring.yaml
│   │   ├── platform-cert-issuer.yaml
│   │   └── poll-modem.yaml
│   └── kustomize/                      # Kubernetes manifests
│       ├── argocd-crib/                # ArgoCD ingress config
│       ├── grafana-crib/               # Grafana IngressRoute
│       ├── jellyfin/                   # Jellyfin deployment + ingress
│       ├── platform-cert-issuer/       # cert-manager + wildcard cert
│       └── poll-modem/                 # poll-modem deployment + ingress
└── docs/
    └── playbooks/                      # Operational runbooks
        ├── 01-bootstrap-crib-k3s-proxmox.md
        ├── 02-add-a-new-app-via-argocd.md
        ├── ...
        └── 10-expose-grafana-via-traefik.md
```

### On the VM (k3s-server)

```
/etc/rancher/k3s/config.yaml           # k3s configuration
/etc/rancher/k3s/k3s.yaml              # kubeconfig (on VM)
/var/lib/rancher/k3s/server/manifests/  # k3s static manifests
/var/lib/rancher/k3s/server/static/charts/  # Bundled Helm charts
/etc/systemd/system/k3s-tailscale-proxy.service  # iptables DNAT
/usr/local/bin/bootstrap-k3s.sh        # Cloud-init bootstrap script
/root/argocd-password                  # ArgoCD admin password
```

### On the Proxmox host

```
/var/lib/vz/template/iso/noble-server-cloudimg-amd64.img  # Cloud image
/var/lib/vz/snippets/cloud-init-k3s.yaml                  # Cloud-init user-data
```

### External references

| Resource | Location |
|----------|----------|
| Terraform DNS | `~/code/wesen/terraform/dns/zones/scapegoat-dev/envs/prod/` |
| Proxmox article | Obsidian vault: `Projects/2026/04/15/ARTICLE - Deploying k3s on Proxmox` |
| Jellyfin project | Obsidian vault: `Projects/PROJ - Jellyfin Media Server` |
| Hetzner k3s reference | `~/code/wesen/2026-03-27--hetzner-k3s/` |
| poll-modem source | `~/code/wesen/corporate-headquarters/poll-modem/` |

---
