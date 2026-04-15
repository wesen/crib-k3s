# crib-k3s

k3s cluster on Proxmox with ArgoCD GitOps, exposed via Tailscale Funnel at `*.crib.scapegoat.dev`.

## Infrastructure

| Resource | Value |
|----------|-------|
| Proxmox VM 301 | Ubuntu Noble, 4 cores, 8GB RAM, 30GB disk |
| Tailscale | `k3s-proxmox` at `100.67.90.12` |
| k3s | v1.34.6+k3s1 |
| ArgoCD | admin password in `/root/argocd-password` on VM |
| DNS | `*.crib.scapegoat.dev → k3s-proxmox.tail879302.ts.net` (DigitalOcean) |
| TLS | Let's Encrypt via cert-manager DNS01 (DigitalOcean) |
| Ingress | Traefik (k3s default) |
| Funnel | TCP passthrough 443 → Traefik |

## Access

```bash
# kubectl
export KUBECONFIG=$PWD/kubeconfig.yaml
kubectl get nodes

# ArgoCD UI
open https://argocd.crib.scapegoat.dev

# SSH
ssh ubuntu@k3s-proxmox
```

## GitOps structure

```
gitops/
├── applications/                  # ArgoCD Application manifests
│   ├── platform-cert-issuer.yaml  # ClusterIssuer + wildcard cert
│   └── argocd-crib.yaml          # ArgoCD ingress
└── kustomize/
    ├── platform-cert-issuer/      # cert-manager config
    └── argocd-crib/              # ArgoCD public access
```

## Bootstrapping a new VM

```bash
# 1. Create VM
./scripts/create-k3s-vm.sh 301 k3s-server

# 2. Wait ~3 min, then join Tailscale
ssh ubuntu@<vm-ip> "sudo tailscale up --auth-key=<key> --hostname=k3s-proxmox"

# 3. Pull kubeconfig
./scripts/setup-access.sh

# 4. Point ArgoCD at this repo (first time only)
kubectl apply -f gitops/applications/platform-cert-issuer.yaml
kubectl apply -f gitops/applications/argocd-crib.yaml

# 5. Enable Funnel
ssh ubuntu@k3s-proxmox "sudo tailscale funnel --bg --tcp 443 127.0.0.1:443"
```

## Adding a new service

1. Create `gitops/kustomize/<service>/` with K8s manifests
2. Create `gitops/applications/<service>.yaml` pointing to it
3. Push to main — ArgoCD syncs automatically

## DNS changes

DNS is managed via Terraform at `~/code/wesen/terraform/dns/zones/scapegoat-dev/envs/prod/`.

## Related

- Reference: `~/code/wesen/2026-03-27--hetzner-k3s/` — same pattern, public IP
- poll-modem: `~/code/wesen/corporate-headquarters/poll-modem/` — first app to deploy
