# crib-k3s Docs

Operational playbooks for the crib-k3s homelab cluster.

These docs capture the actual workflows used to build and run the cluster:

- bootstrap the Proxmox VM and k3s control plane
- expose services with ArgoCD and Traefik
- add Prometheus metrics to apps
- deploy Prometheus/Grafana with GitOps
- handle GHCR images and pull secrets
- recover from cert-manager / DigitalOcean DNS issues

## How to use this folder

Start with the playbook that matches the task you want to do. Each playbook is written as a runbook with:

- purpose
- prerequisites
- exact steps
- validation checks
- common failure modes
- recovery notes

## Playbooks

- `docs/playbooks/README.md` — index of all playbooks
- `docs/playbooks/01-bootstrap-crib-k3s-proxmox.md` — create and bootstrap the cluster VM
- `docs/playbooks/02-add-a-new-app-via-argocd.md` — deploy a new app using GitOps
- `docs/playbooks/03-instrument-an-app-with-prometheus-metrics.md` — add `/metrics` to an app
- `docs/playbooks/04-add-prometheus-and-grafana-with-argocd.md` — install monitoring via ArgoCD
- `docs/playbooks/05-manage-ghcr-images-and-pull-secrets.md` — build/push private images and let k8s pull them
- `docs/playbooks/06-recover-from-cert-manager-digitalocean-429s.md` — avoid or recover from DNS01 rate limits
- `docs/playbooks/07-troubleshoot-monitoring-rollouts.md` — debug operator/webhook and scrape issues
- `docs/playbooks/08-provision-and-observe-poll-modem.md` — full end-to-end poll-modem observability flow
- `docs/playbooks/09-create-grafana-dashboards-for-poll-modem.md` — build and load Grafana dashboards for modem signal metrics

## Related repo areas

- `gitops/` — ArgoCD Application manifests and kustomize overlays
- `scripts/` — VM bootstrap and access helpers
- `diary.md` — chronological record of the cluster build-out
- `ttmp/` — docmgr ticket workspaces and implementation notes
