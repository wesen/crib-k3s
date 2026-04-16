# Playbooks

This directory contains detailed operational runbooks for the crib-k3s cluster.

Each playbook is intended to be practical and reusable. If you are doing a related task, read the matching playbook first instead of rediscovering the steps from scratch.

## Index

1. [Bootstrap crib-k3s on Proxmox](./01-bootstrap-crib-k3s-proxmox.md)
2. [Add a new app via ArgoCD](./02-add-a-new-app-via-argocd.md)
3. [Instrument an app with Prometheus metrics](./03-instrument-an-app-with-prometheus-metrics.md)
4. [Add Prometheus and Grafana with ArgoCD](./04-add-prometheus-and-grafana-with-argocd.md)
5. [Manage GHCR images and pull secrets](./05-manage-ghcr-images-and-pull-secrets.md)
6. [Recover from cert-manager DigitalOcean 429s](./06-recover-from-cert-manager-digitalocean-429s.md)
7. [Troubleshoot monitoring rollouts](./07-troubleshoot-monitoring-rollouts.md)
8. [Provision and observe poll-modem](./08-provision-and-observe-poll-modem.md)
9. [Create Grafana dashboards for poll-modem](./09-create-grafana-dashboards-for-poll-modem.md)

## Writing style

These playbooks are intentionally opinionated:

- prefer GitOps and ArgoCD over manual `kubectl apply`
- keep secrets out of git
- reuse the wildcard TLS secret when possible
- avoid cert-manager DNS01 churn unless the app really needs its own certificate
- validate every step with a command, not just by reading YAML
