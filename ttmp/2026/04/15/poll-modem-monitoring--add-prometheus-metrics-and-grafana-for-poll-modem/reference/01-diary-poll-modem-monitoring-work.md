---
Title: Diary - poll-modem Monitoring Work
Ticket: poll-modem-monitoring
Status: active
Topics:
    - monitoring
    - prometheus
    - grafana
    - metrics
    - poll-modem
DocType: reference
Intent: long-term
Owners: []
RelatedFiles: []
ExternalSources: []
Summary: ""
LastUpdated: 2026-04-15T21:13:59.873328781-04:00
WhatFor: ""
WhenToUse: ""
---

# Diary - poll-modem Monitoring Work

## Goal

Track the work needed to expose Prometheus metrics from poll-modem, scrape them from crib-k3s, and visualize the results in Grafana with an ArgoCD-managed monitoring stack.

## Context

The poll-modem app had already been converted into a small web service in crib-k3s, but it still lacked proper metrics. The current cluster also did not have a Prometheus/Grafana stack. The goal of this work is to make the app observable without falling back to ad hoc kubectl port-forwards or local helm installs.

Important constraints discovered during planning:

- `argocd` CLI is not installed locally on this machine
- ArgoCD Applications are still the cleanest way to manage cluster resources
- The shared wildcard cert path in crib should be reused where possible
- cert-manager / DigitalOcean DNS traffic has already been noisy, so the monitoring plan should avoid creating unnecessary new certificate churn

## Step 1: Create a dedicated monitoring ticket

I created a new docmgr ticket in the crib-k3s repo:

- ticket: `poll-modem-monitoring`
- topic tags: `monitoring,prometheus,grafana,metrics,poll-modem`

This gives the work a stable home separate from the older deploy ticket.

### Tasks added to the ticket

- add `/metrics` endpoint to poll-modem serve mode
- add ArgoCD-managed `ServiceMonitor`
- add Prometheus/Grafana stack via ArgoCD
- create Grafana access path
- document and commit as we go

## Step 2: Write an implementation plan before changing code

I created a design doc in the ticket workspace:

- `design/01-implementation-plan-poll-modem-metrics-prometheus-and-grafana.md`

The plan lays out the rollout in phases:

1. instrument poll-modem
2. scrape it from Kubernetes
3. install Prometheus/Grafana via ArgoCD
4. add a dashboard path

### Key architecture decision

The app should emit metrics itself rather than relying on sidecars or node-level scrapers. That keeps the signal tied directly to modem polling behavior.

## Step 3: Add a diary doc for the monitoring work

I created this diary document so the work can be recorded in order, with the reasoning preserved rather than just the final state.

## Step 4: Inspect the current poll-modem server shape

The current `serve` mode already exposes:

- `/` → HTML dashboard
- `/api/status` → JSON snapshot
- `/healthz` → health check

That made it a good fit for adding `/metrics` without changing the basic deployment model.

I also confirmed there was no existing Prometheus instrumentation in the repo yet.

## Step 5: Add native Prometheus metrics to poll-modem

I added a new `cmd/metrics.go` file and wired it into `cmd/serve.go`.

### Metrics added

- `poll_modem_polls_total{result="success|failure"}`
- `poll_modem_poll_duration_seconds`
- `poll_modem_last_success_unixtime`
- `poll_modem_last_failure_unixtime`
- `poll_modem_last_error_unixtime`
- `poll_modem_up`
- `poll_modem_downstream_channels`
- `poll_modem_upstream_channels`
- `poll_modem_error_channels`

### Runtime collectors

I also registered:

- Go runtime collector
- process collector

That way the app exports both business metrics and runtime health.

### Serve-mode wiring

The server now exposes:

- `/metrics` using `promhttp.Handler()`

### Polling instrumentation

The polling loop now records:

- poll duration
- success/failure totals
- current status gauge
- latest channel counts

The shape is:

```text
start timer
login + fetch modem HTML
store to SQLite
success: update gauges + success counter + duration histogram
failure: update failure counter + last failure time + duration histogram
```

## Step 6: Update the database path for container use

The SQLite path in `internal/modem/database.go` was hardcoded to `~/.config/poll-modem/history.db`.

That is awkward in containers, so I added support for:

- `POLL_MODEM_DB_PATH`

That allows the k8s deployment to mount a PVC at `/data/history.db` cleanly.

## Step 7: Add the Prometheus dependency

I added `github.com/prometheus/client_golang` and ran `go mod tidy`.

Build validation:

```bash
GOWORK=off go test ./...
```

This passed after the dependency refresh.

## Step 8: Decide on ArgoCD-first monitoring, not local helm

The user explicitly asked for an ArgoCD approach rather than local helm.

Since the cluster already follows the pattern:

- ArgoCD Application
- GitOps manifest tree
- Kubernetes resources committed in repo

…the monitoring stack should follow the same pattern.

I do not need the `argocd` CLI to do that — the application manifests can be committed and ArgoCD will reconcile them.

## Current state

### In poll-modem repo

- `cmd/serve.go` now has a `/metrics` route
- `cmd/metrics.go` defines the Prometheus metrics
- `internal/modem/database.go` supports `POLL_MODEM_DB_PATH`
- `go.mod` has Prometheus client dependencies

### In crib-k3s repo

- the `poll-modem` application already exists
- `modem.crib.scapegoat.dev` is live via Traefik IngressRoute
- the shared wildcard cert approach is being reused to avoid more cert-manager/DigitalOcean churn

## Next steps

1. Add a `ServiceMonitor` for poll-modem in crib-k3s
2. Add a Prometheus/Grafana ArgoCD Application in crib-k3s
3. Keep Grafana access simple at first, then expose it cleanly if needed
4. Verify Prometheus can scrape poll-modem and the metrics show up in Grafana

## Lessons so far

- reusing the shared wildcard TLS secret is much cheaper than issuing more cert-manager DNS01 certs
- the app must be observable at the source; adding `/metrics` to poll-modem is the right first step
- ArgoCD-managed manifests are the cleanest way to add a monitoring stack in this repo
- keeping the plan and diary in the ticket makes the rollout easier to recover if the cluster gets noisy again
