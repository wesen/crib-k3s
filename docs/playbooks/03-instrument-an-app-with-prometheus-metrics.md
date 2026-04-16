# Instrument an app with Prometheus metrics

## Purpose

Add a real `/metrics` endpoint to an app so Prometheus can scrape it and Grafana can visualize it.

This playbook is based on the `poll-modem` instrumentation work.

## When to use this

Use this playbook when an app already has business logic but needs observability:

- polling loops
- background workers
- API request handling
- scheduled jobs

## Metric design goals

Keep the metrics:

- low-cardinality
- stable
- cheap to update
- useful for alerting and dashboards

Prefer a few good metrics over a giant wall of labels.

## Recommended metrics set

For a collector-style app like `poll-modem`, a good first set is:

- counter for total success/failure attempts
- histogram for operation duration
- gauge for last success timestamp
- gauge for last failure timestamp
- gauge for current health / up status
- domain-specific gauges for counts or sizes

Example names:

- `poll_modem_polls_total{result="success|failure"}`
- `poll_modem_poll_duration_seconds`
- `poll_modem_last_success_unixtime`
- `poll_modem_last_failure_unixtime`
- `poll_modem_up`
- `poll_modem_downstream_channels`
- `poll_modem_upstream_channels`
- `poll_modem_error_channels`

Also register the Go runtime and process collectors.

## Step 1: Add the Prometheus dependency

In Go, add `github.com/prometheus/client_golang` and tidy the module.

```bash
GOWORK=off go get github.com/prometheus/client_golang@v1.23.2
GOWORK=off go mod tidy
```

## Step 2: Create a metrics package or file

Keep the metric registration logic in a small, dedicated file.

For `poll-modem`, this was `cmd/metrics.go`.

### Important lesson

Do **not** register collectors repeatedly against the global default registry from code that may initialize more than once.

That caused a panic in the first implementation:

```text
panic: duplicate metrics collector registration attempted
```

The fix was to create a dedicated `prometheus.Registry` and serve it with `promhttp.HandlerFor(...)`.

## Step 3: Instrument the work loop

Wrap the business operation with timing and success/failure updates.

General pattern:

```text
start timer
perform work
if success:
  increment success counter
  observe duration
  update gauges
else:
  increment failure counter
  observe duration
  update error timestamps
```

For collector apps, it is useful to update the snapshot object and the metrics from the same code path.

## Step 4: Add the `/metrics` route

Expose the handler on the HTTP server.

```go
mux.Handle("/metrics", promhttp.HandlerFor(metricsRegistry, promhttp.HandlerOpts{}))
```

Keep `/healthz` and the dashboard/API routes too.

## Step 5: Validate locally

Run the app and inspect `/metrics` directly.

```bash
curl -s http://127.0.0.1:8080/metrics | head -20
```

You should see Prometheus text exposition, not HTML.

## Step 6: Build and push the image

If the app runs in Kubernetes, build a new image and push it to GHCR.

```bash
make docker-push IMAGE_TAG=<git-sha>
```

Avoid relying on a floating `latest` tag in the cluster unless you are very sure the node pull behavior will not surprise you.

## Step 7: Roll the deployment

Update the deployment to the new image tag and let ArgoCD sync it.

If the node already cached an old `latest`, pinning to a commit tag is much safer.

## Validation checklist

- app starts without panic
- `/metrics` returns text format
- a Prometheus target for the app is `UP`
- domain-specific gauges look reasonable
- there are no duplicate collector registration logs

## Common failure modes

### Duplicate registration panic

This means a collector is being added to a registry more than once.

Fix by:

- using a dedicated registry
- ensuring initialization only happens once
- avoiding package-level side effects that register collectors multiple times

### `/metrics` returns HTML

This usually means one of:

- the app image is stale
- the pod is running the old binary
- the route points to `/` instead of the metrics handler

### Prometheus target is present but scrape fails

Check the content type and the endpoint path.

The scrape should return Prometheus text, not `text/html`.
