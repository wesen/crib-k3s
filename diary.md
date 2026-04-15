---
Title: Diary - crib-k3s setup
DocType: diary
Status: active
Created: 2026-04-15
---

# Diary - crib-k3s Cluster Setup

## Context

After successfully bootstrapping k3s + ArgoCD on Proxmox VM 301 (see `poll-modem` ticket diary), we're now setting up the proper GitOps infrastructure. The manual `kubectl apply` commands from the previous session are being replaced with ArgoCD-managed Kustomize packages in a dedicated `crib-k3s` repo, following the same pattern as `~/code/wesen/2026-03-27--hetzner-k3s/`.

## Step 1: Tailscale Funnel + DNS

### What happened

Upgraded Tailscale plan to enable Funnel. Configured Funnel with raw TCP passthrough on port 443, forwarding to Traefik on the VM. This lets Traefik handle TLS termination with proper certs for `*.crib.scapegoat.dev`.

### Funnel configuration

```bash
# First tried HTTPS mode — Funnel terminates TLS, but only for the Tailscale hostname
# That means argocd.crib.scapegoat.dev gets a cert mismatch
sudo tailscale funnel --bg 443  # WRONG: only serves k3s-proxmox.tail879302.ts.net cert

# Switched to TCP passthrough — Funnel forwards raw TLS to Traefik
sudo tailscale funnel --bg --tcp 443 127.0.0.1:443  # RIGHT: Traefik terminates TLS
```

### Key insight: Funnel TLS modes

- `tailscale funnel --bg 443` — Funnel terminates TLS, serves cert for `*.tail879302.ts.net` only. Custom domains get cert mismatch.
- `tailscale funnel --bg --tcp 443 target` — Raw TCP passthrough. Traefik (or whatever) terminates TLS with whatever certs it has. This is what we need for custom domains with Let's Encrypt.

### DNS via Terraform

Added `*.crib` CNAME to the DigitalOcean DNS zone managed in `~/code/wesen/terraform/dns/zones/scapegoat-dev/envs/prod/main.tf`:

```hcl
wildcard_crib_cname = {
  type  = "CNAME"
  name  = "*.crib"
  value = "k3s-proxmox.tail879302.ts.net."
  ttl   = 3600
}
```

Resolution chain: `argocd.crib.scapegoat.dev → k3s-proxmox.tail879302.ts.net → 100.67.90.12`

Applied with `terraform apply -auto-approve`. Clean — just one resource added.

## Step 2: Re-enable Traefik

k3s had Traefik disabled in the cloud-init (`disable: [traefik]`). Removed that line and restarted k3s:

```bash
sudo sed -i '/disable:/,/traefik/d' /etc/rancher/k3s/config.yaml
sudo systemctl restart k3s
```

Traefik came up as a LoadBalancer service on `192.168.0.212:443`.

## Step 3: Initial Let's Encrypt Attempt (Manual)

### First attempt: cert-manager in argocd namespace

Created ClusterIssuer + Certificate in the `argocd` namespace. The DNS01 challenge failed because cert-manager's challenge solver looks for the DigitalOcean API token secret in the *challenge's* namespace, not `cert-manager`'s namespace. Got:

```
error getting digitalocean token: secrets "digitalocean-dns" not found
```

### Fix: Certificate in cert-manager namespace

Moved the Certificate resource to `cert-manager` namespace (where the secret lives). Challenge went to `valid` state immediately.

### Lessons

- For ClusterIssuer with DNS01, the token secret must be in `cert-manager` namespace
- The Certificate resource should also be in `cert-manager` namespace so the solver finds the secret
- The resulting TLS secret can be referenced from any namespace via Ingress

## Step 4: Create crib-k3s Repo

### Decision

The manual kubectl approach doesn't scale. Created `~/code/wesen/crib-k3s/` as a dedicated GitOps repo following the hetzner-k3s pattern:

```
crib-k3s/
├── cloud-init.yaml          # VM bootstrap (copied from poll-modem)
├── kubeconfig.yaml          # kubectl access
├── scripts/
│   ├── create-k3s-vm.sh
│   └── setup-access.sh
└── gitops/
    ├── applications/        # ArgoCD Application manifests
    └── kustomize/           # Kustomize packages
        ├── platform-cert-issuer/   # ClusterIssuer + wildcard cert
        └── argocd-crib/           # ArgoCD ingress + config
```

### Why not share hetzner-k3s repo?

Different infrastructure (Proxmox vs Hetzner), different domains (`*.crib` vs `*.yolo`), different secrets (DigitalOcean DNS01 vs HTTP01), different network (Tailscale Funnel vs public IP). Sharing would create confusing coupling.

### Key difference from hetzner: DNS01 vs HTTP01

Hetzner uses HTTP01 challenge because the VM has a public IP and Let's Encrypt can reach it directly. Crib uses DNS01 because the VM is behind a cable modem — Let's Encrypt can't reach it, but cert-manager can create TXT records in DigitalOcean DNS to prove domain ownership.

## Current State

- Funnel: TCP passthrough on 443 → Traefik
- DNS: `*.crib.scapegoat.dev → k3s-proxmox.tail879302.ts.net` via Terraform
- Traefik: Running, serving default self-signed cert
- Let's Encrypt: Certificate issued manually (needs to move to ArgoCD)
- Repo: `~/code/wesen/crib-k3s/` created, gitops structure in progress

## Next

- Finish gitops kustomize packages (platform-cert-issuer, argocd-crib)
- Create ArgoCD Application manifests
- Bootstrap ArgoCD to watch the crib-k3s repo
- Clean up manual resources (replace with ArgoCD-managed)
