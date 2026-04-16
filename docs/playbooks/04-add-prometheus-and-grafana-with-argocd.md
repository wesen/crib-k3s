# Add Prometheus and Grafana with ArgoCD

## Purpose

Install a Prometheus/Grafana monitoring stack in crib-k3s using the same GitOps style as the rest of the cluster.

## When to use this

Use this playbook when you want to:

- scrape app metrics from the cluster
- query time series in Prometheus
- build dashboards in Grafana
- avoid manual helm installs on the cluster host

## Core constraints

- use ArgoCD Applications for cluster management
- do not rely on a local `helm` CLI install
- keep the stack small enough for a single-node 8 GB VM
- prefer ServiceMonitors over ad hoc annotations when possible

## Step 1: Add an ArgoCD Application for the monitoring stack

Create a manifest that points ArgoCD at the monitoring chart.

The live example in this repo is `gitops/applications/monitoring.yaml`.

Important settings:

- `CreateNamespace=true`
- `ServerSideApply=true`
- automated sync and self-heal
- a small resource profile
- Grafana enabled

## Step 2: Keep the chart lean

For a small cluster, disable or trim the pieces you do not need immediately.

In the crib cluster we reduced the footprint by disabling or trimming some of the optional extras while keeping the core stack functional.

## Step 3: Be careful with the Prometheus Operator webhook

The monitoring chart’s operator expects a TLS secret for its webhook server.

If you disable the webhook path incorrectly, the operator pod may still try to mount a secret that does not exist.

### Symptom

The pod logs may show something like:

```text
failed to load serving certificate and key: open /cert/cert: no such file or directory
```

### Fix

Create the expected secret in the monitoring namespace with the filenames the container wants:

- `cert`
- `key`
- `ca`

That is a manual bootstrap secret in this setup, not a git-managed secret.

## Step 4: Create a ServiceMonitor for the app

A ServiceMonitor is the clean way to tell Prometheus to scrape the app.

Example shape:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: poll-modem
  namespace: poll-modem
spec:
  namespaceSelector:
    matchNames:
      - poll-modem
  selector:
    matchLabels:
      app: poll-modem
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
```

Make sure the Service has the matching label:

```yaml
metadata:
  labels:
    app: poll-modem
```

## Step 5: Refresh ArgoCD after pushing

If you need the new manifests immediately, annotate the Application with a hard refresh.

```bash
kubectl annotate application monitoring -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl annotate application poll-modem -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

## Step 6: Validate Prometheus

Check that the application is present and healthy:

```bash
kubectl get application monitoring -n argocd -o wide
kubectl get pods -n monitoring
kubectl get servicemonitor -A
```

Then query Prometheus.

A simple test is:

```promql
up{job="poll-modem"}
```

You want the result to be `1`.

## Step 7: Validate Grafana

Grafana should be running in the monitoring namespace and able to query Prometheus.

A simple validation path is:

```bash
kubectl get svc -n monitoring
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
```

Then log in and query the `poll-modem` series.

## Validation checklist

- `monitoring` app is `Synced` and `Healthy`
- operator pod is running
- Prometheus pod is running
- Grafana pod is running
- `up{job="poll-modem"}` returns `1`
- the app’s `/metrics` endpoint returns text exposition

## Common failure modes

### Prometheus sees the target but scrape fails with HTML content type

That means the app is not actually serving `/metrics` yet, or the deployment is still on an old image.

### Operator pod crashloops on cert files

Check whether the secret contains the exact keys the pod expects.

### Prometheus does not discover the ServiceMonitor

Check:

- the Service label selector
- namespace selector
- ServiceMonitor namespace
- Prometheus selector fields

## Recovery notes

If the stack is too heavy, cut back the optional components first. Keep the operator, Prometheus, and Grafana before adding extras like alerting or exporter sidecars.
