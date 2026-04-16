# Troubleshoot monitoring rollouts

## Purpose

Diagnose common failures in the Prometheus/Grafana stack and the `poll-modem` scrape path.

## When to use this

Use this playbook when:

- the `monitoring` ArgoCD app is not Healthy
- the operator pod crashloops
- Prometheus does not show the app target
- Grafana is up but cannot query Prometheus
- the app target shows `HTML` instead of metrics text

## Common checks

### ArgoCD state

```bash
kubectl get application monitoring -n argocd -o wide
kubectl get application poll-modem -n argocd -o wide
```

### Monitoring namespace

```bash
kubectl get pods -n monitoring -o wide
kubectl get svc -n monitoring
kubectl get secret -n monitoring
```

### App namespace

```bash
kubectl get pods -n poll-modem -o wide
kubectl get svc -n poll-modem -o wide
kubectl get servicemonitor -n poll-modem
```

## Failure: operator pod cannot mount `/cert/cert`

### Symptom

The operator logs mention a missing file like:

```text
failed to load serving certificate and key: open /cert/cert: no such file or directory
```

### Fix

Create the expected secret in the `monitoring` namespace with the exact keys and filenames the pod wants:

- `cert`
- `key`
- `ca`

For the self-signed bootstrap secret, the `ca` can be the same cert data.

## Failure: Prometheus skips the app target because of TLS config

### Symptom

The Prometheus logs mention a `tlsConfig` problem or a missing secret key.

### Fix

Make sure the `monitoring-kube-prometheus-admission` secret exists and contains the keys the rendered chart expects.

## Failure: target exists but scrape says `text/html`

### Symptom

Prometheus logs say it received `text/html; charset=utf-8` from `/metrics`.

### Cause

The pod is still running the old binary or the `/metrics` route is not wired correctly.

### Fix

- confirm the app image is the metrics-enabled build
- confirm the service points at the right container port
- confirm the metrics handler is registered with the right registry

## Failure: `ImagePullBackOff`

### Symptom

The pod cannot pull the new GHCR image.

### Fix

- ensure the image was pushed
- ensure the namespace has the `ghcr-pull` secret
- ensure the deployment has `imagePullSecrets`
- ensure the tag is correct

## Failure: ServiceMonitor not discovered

### Symptom

The ServiceMonitor exists but Prometheus never scrapes it.

### Fix

Check all of these:

- Service label matches the ServiceMonitor selector
- ServiceMonitor namespace is correct
- `namespaceSelector` includes the app namespace
- Prometheus `serviceMonitorSelector` is empty or matches your labels

## Failure: ArgoCD app is Synced but the pod is stale

### Symptom

The repo has changed, but the cluster still seems to run the old version.

### Fix

Force a hard refresh:

```bash
kubectl annotate application poll-modem -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl annotate application monitoring -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## Validation checklist

- operator pod is `Running`
- Prometheus pod is `Running`
- Grafana pod is `Running`
- `up{job="poll-modem"}` is `1`
- `/metrics` returns Prometheus exposition format

## Recovery notes

When in doubt, work from the bottom up:

1. app binary
2. app pod
3. Service / ServiceMonitor
4. Prometheus
5. Grafana
6. ArgoCD state
