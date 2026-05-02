# Expose Grafana via Traefik

## Purpose

Expose the in-cluster Grafana instance at `https://grafana.crib.scapegoat.dev/` using the existing crib networking model.

This playbook uses a Traefik `IngressRoute` and the shared wildcard TLS secret pattern already used for other crib services.

## When to use this

Use this playbook when:

- the `monitoring` ArgoCD app is already healthy
- Grafana is running in the `monitoring` namespace
- you want a browser-friendly Grafana URL instead of port-forwarding
- you want to keep TLS consistent with the rest of crib

## Core idea

Grafana is exposed as a separate ArgoCD-managed app that only owns the ingress resources.

That keeps the monitoring stack itself simple while still giving Grafana a clean tailnet URL.

## Prerequisites

- `monitoring-grafana` service exists in the `monitoring` namespace
- Traefik is running in the cluster
- the wildcard secret `crib-scapegoat-dev-tls` exists in the `monitoring` namespace
- the app repo has the `grafana-crib` manifests committed

## Relevant files

- `gitops/applications/grafana-crib.yaml`
- `gitops/kustomize/grafana-crib/kustomization.yaml`
- `gitops/kustomize/grafana-crib/ingressroute.yaml`

## Step 1: Copy the wildcard TLS secret into monitoring

The TLS secret is namespace-scoped, so Grafana needs its own copy in `monitoring`.

Use the existing certificate secret as the source of truth and copy it into the monitoring namespace. Keep this out of git.

Example pattern:

```bash
kubectl get secret crib-scapegoat-dev-tls -n cert-manager -o yaml \
  | sed 's/namespace: cert-manager/namespace: monitoring/' \
  | kubectl apply -f -
```

If your source secret lives in a different namespace, adjust the command accordingly.

## Step 2: Apply the ArgoCD application

The Grafana ingress is managed by a separate ArgoCD Application:

```bash
kubectl apply -f gitops/applications/grafana-crib.yaml
```

That app points at the `grafana-crib` kustomize overlay and creates the `IngressRoute` in the `monitoring` namespace.

## Step 3: Validate the route

Check that ArgoCD sees the app and the IngressRoute exists:

```bash
kubectl get application grafana-crib -n argocd -o wide
kubectl get ingressroute -n monitoring
```

Then test the tailnet URL from a client that can reach the crib Tailscale address:

```bash
curl -skI https://grafana.crib.scapegoat.dev/
```

You want an HTTP response from Grafana, not a TLS error or a 404.

## Step 4: Log into Grafana

Grafana’s admin credentials are managed by the monitoring chart.

If you need the login secret, inspect the monitoring namespace secrets or use the existing bootstrap notes for the `monitoring-grafana` secret.

## Validation checklist

- wildcard TLS secret exists in `monitoring`
- `grafana-crib` Application is synced
- `IngressRoute` exists in `monitoring`
- `https://grafana.crib.scapegoat.dev/` responds
- Grafana loads dashboards from the sidecar

## Common failure modes

### TLS error

Usually means the wildcard secret is missing from the `monitoring` namespace.

### 404 from Traefik

Check that the service name and service port in the IngressRoute match the `monitoring-grafana` service.

### Grafana login page loads but dashboards are missing

Check the dashboard ConfigMap labels and Grafana sidecar logs.

## Recovery notes

If Grafana exposure causes noise, keep the ingress app separate from the monitoring stack so you can remove or replace just the ingress without touching the core Prometheus installation.
