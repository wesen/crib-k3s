# crib-k3s

k3s cluster on Proxmox with ArgoCD GitOps, reached over Tailscale at `*.crib.scapegoat.dev`.

## Infrastructure

| Resource | Value |
|----------|-------|
| Proxmox VM 301 | Ubuntu Noble, 4 cores, 8GB RAM, 30GB disk |
| Tailscale | `k3s-proxmox` at `100.67.90.12` |
| k3s | v1.34.6+k3s1 |
| ArgoCD | admin password in `/root/argocd-password` on VM |
| DNS | `*.crib.scapegoat.dev → 100.67.90.12` (DigitalOcean A record to the Tailscale IP) |
| TLS | Let's Encrypt via cert-manager DNS01 (DigitalOcean), with a shared wildcard cert reused by app routes |
| Ingress | k3s packaged Traefik, configured by cloud-init HelmChartConfig with hostNetwork + hostPort 80/443 and explicit Ingress status IP `100.67.90.12` |
| Access model | Custom `*.crib.scapegoat.dev` names are tailnet-facing; Tailscale Funnel was tried for custom domains but is not the current model |
| Legacy proxy | `k3s-tailscale-proxy.service` DNAT-to-NodePort is disabled; do not enable it with the Traefik hostPort model |

## Access

Traefik is intentionally configured to publish `100.67.90.12` into standard Kubernetes `Ingress` status. Without that explicit status IP, `argocd-crib` can remain `Progressing` in ArgoCD even while the route serves correctly, because ArgoCD's built-in health check treats an Ingress with empty `.status.loadBalancer` as not fully healthy.


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
    └── argocd-crib/              # ArgoCD tailnet ingress

docs/
└── playbooks/                     # Operational runbooks and troubleshooting guides
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

# 5. Confirm the crib DNS record exists in Terraform
cd /home/manuel/code/wesen/terraform
direnv exec . terraform -chdir=dns/zones/scapegoat-dev/envs/prod plan -detailed-exitcode

# The expected DNS model is:
# *.crib.scapegoat.dev A 100.67.90.12
```

## Adding a new service

1. Create `gitops/kustomize/<service>/` with K8s manifests
2. Create `gitops/applications/<service>.yaml` pointing to it
3. Push to main — ArgoCD syncs automatically

## DNS changes

DNS is managed via Terraform at `~/code/wesen/terraform/dns/zones/scapegoat-dev/envs/prod/`.

## Docs

- `docs/README.md` — overview of the runbook set
- `docs/playbooks/README.md` — index of the operational playbooks

## Related

- Reference: `~/code/wesen/2026-03-27--hetzner-k3s/` — same pattern, public IP
- poll-modem: `~/code/wesen/corporate-headquarters/poll-modem/` — first app to deploy
