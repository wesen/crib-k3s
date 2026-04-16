# Provision and observe poll-modem end to end

## Purpose

This is the full lifecycle playbook for the `poll-modem` service in crib-k3s.

It ties together the app repo, GHCR image, ArgoCD app, ServiceMonitor, Prometheus, Grafana, and the cluster secrets needed to make it all work.

## When to use this

Use this playbook when you want to reproduce the full `poll-modem` deployment from scratch.

## End-to-end sequence

1. add `/metrics` to the app
2. build and push a private GHCR image
3. create a pull secret in `poll-modem`
4. deploy the app through ArgoCD
5. add a ServiceMonitor
6. deploy Prometheus/Grafana through ArgoCD
7. verify Prometheus `up`
8. verify Grafana can query the metrics

## What we ended up with

### App repo

- `cmd/serve.go` serves `/metrics`
- `cmd/metrics.go` owns the metric registry
- `internal/modem/database.go` respects `POLL_MODEM_DB_PATH`
- the image is built and pushed to GHCR

### Cluster repo

- `gitops/applications/poll-modem.yaml`
- `gitops/kustomize/poll-modem/`
- `gitops/applications/monitoring.yaml`
- `gitops/kustomize/poll-modem/servicemonitor.yaml`
- `gitops/kustomize/poll-modem/deployment.yaml` with `imagePullSecrets`

### Secrets

- `modem-credentials` — manual
- `ghcr-pull` — manual
- `crib-scapegoat-dev-tls` — wildcard TLS secret
- `monitoring-kube-prometheus-admission` — monitoring operator bootstrap secret

## Final validation commands

```bash
kubectl get application poll-modem -n argocd -o wide
kubectl get application monitoring -n argocd -o wide
kubectl get servicemonitor -A
kubectl get pods -n poll-modem -o wide
kubectl get pods -n monitoring -o wide
```

Prometheus query:

```promql
up{job="poll-modem"}
```

Direct metrics probe:

```bash
curl -s http://127.0.0.1:18080/metrics | head -20
```

## Result

When everything is healthy, you should have:

- poll-modem serving the dashboard and `/metrics`
- Prometheus scraping the target
- Grafana ready to query Prometheus
- ArgoCD keeping the GitOps state synchronized

## Why this playbook matters

This is the shortest description of the actual pattern we used in crib-k3s:

- cluster resources stay in Git
- secrets stay manual or in Vault
- app images are private and pinned
- monitoring is GitOps-managed
- troubleshooting is done from the actual runtime symptoms, not guesses
