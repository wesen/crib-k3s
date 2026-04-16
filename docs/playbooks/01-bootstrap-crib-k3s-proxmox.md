# Bootstrap crib-k3s on Proxmox

## Purpose

Create the Proxmox VM that runs k3s, connect to it via Tailscale, and bootstrap the GitOps control plane with cert-manager and ArgoCD.

This is the base playbook for getting a fresh crib cluster online in a reproducible way.

## When to use this

Use this playbook when you need to:

- create a brand new crib-k3s VM
- rebuild the cluster from scratch
- recover from a broken VM or LXC experiment
- re-establish Tailscale and ArgoCD access after reinstalling

## Why VM instead of LXC

A full VM is much less painful than LXC for k3s in this environment.

LXC tends to require a pile of kernel, sysctl, and AppArmor tweaks before k3s behaves correctly. The VM path is simpler and closer to a normal Kubernetes host.

## Prerequisites

- access to the Proxmox UI or API
- working Tailscale account and auth key
- DNS zone managed in Terraform
- the crib-k3s repo cloned locally
- SSH access to the host that will become the VM

## Relevant repo files

- `scripts/create-k3s-vm.sh`
- `scripts/setup-access.sh`
- `cloud-init.yaml`
- `gitops/applications/platform-cert-issuer.yaml`
- `gitops/applications/argocd-crib.yaml`
- `gitops/kustomize/platform-cert-issuer/`
- `gitops/kustomize/argocd-crib/`

## Step 1: Create the VM

Use the helper script to create the VM with the right CPU, memory, disk, and cloud-init settings.

```bash
./scripts/create-k3s-vm.sh 301 k3s-server
```

The VM should be an Ubuntu Noble guest with enough resources for k3s, ArgoCD, cert-manager, and a few apps.

## Step 2: Make the VM reachable

The network path to the Proxmox host is not always directly reachable from the dev machine, so Tailscale is the reliable access layer.

On the VM:

```bash
sudo tailscale up --auth-key=<key> --hostname=k3s-proxmox
```

Make sure the host name and any SANs you need are already covered in the cloud-init or TLS setup you intend to use later.

## Step 3: Install k3s

Install k3s normally, then confirm the node is ready.

```bash
kubectl get nodes
kubectl get pods -A
```

You want the server node to show `Ready` before you bootstrap GitOps.

## Step 4: Pull kubeconfig locally

Use the access helper to fetch the kubeconfig and point local kubectl at it.

```bash
./scripts/setup-access.sh
export KUBECONFIG=$PWD/kubeconfig.yaml
kubectl get nodes
```

## Step 5: Bootstrap cert-manager and the wildcard certificate

Apply the platform issuer first.

```bash
kubectl apply -f gitops/applications/platform-cert-issuer.yaml
```

That app creates the cert-manager resources needed for the wildcard TLS certificate used by the cluster ingress.

Validate:

```bash
kubectl get clusterissuer
kubectl get certificate -A
kubectl get secret -n cert-manager
```

## Step 6: Bootstrap ArgoCD ingress

Apply the ArgoCD app next.

```bash
kubectl apply -f gitops/applications/argocd-crib.yaml
```

This exposes the ArgoCD server through Traefik and the wildcard certificate.

Validate:

```bash
kubectl get application -n argocd
kubectl get ingress -n argocd
curl -kI https://argocd.crib.scapegoat.dev/
```

## Step 7: Enable Funnel

The cluster is reached through Tailscale Funnel / TCP passthrough.

```bash
sudo tailscale funnel --bg --tcp 443 127.0.0.1:443
```

Then verify the hostname resolves and the ingress is reachable through the funnel path.

## Validation checklist

- node is `Ready`
- ArgoCD application exists and syncs
- wildcard cert secret exists
- `https://argocd.crib.scapegoat.dev/` responds
- Tailscale access to the VM is stable

## Common failure modes

### k3s not ready

If the node never becomes `Ready`, check:

- cloud-init output
- container runtime status
- network setup
- whether the VM got the expected cloud-init user and keys

### Tailscale unreachable

If the machine is not reachable, confirm:

- the auth key is valid
- the hostname is correct
- Funnel is enabled on the VM
- the machine has a proper Tailscale IP / DNS identity

### cert-manager / DNS problems

If wildcard cert issuance fails, inspect cert-manager logs and the DigitalOcean DNS API rate limit status.

## Recovery notes

If the VM path is broken beyond quick repair, it is often faster to recreate the VM than to keep debugging a bad LXC conversion. The docs and GitOps manifests should make that recovery predictable.
