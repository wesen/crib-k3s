# Create Grafana dashboards for poll-modem

## Purpose

Create a Grafana dashboard that makes the poll-modem metrics useful at a glance.

This playbook covers the dashboard we added to crib-k3s for the app’s Prometheus metrics.

## When to use this

Use this playbook when:

- poll-modem is already exporting `/metrics`
- Prometheus is scraping the target
- Grafana is running in the monitoring namespace
- you want to plot modem signal quality over time, especially SNR, power, frequency, symbol rate, lock state, and error-codeword growth

## Discovery mechanism

The kube-prometheus-stack Grafana sidecar looks for dashboard ConfigMaps with:

- label key: `grafana_dashboard`
- label value: `1`

It searches all namespaces, so the dashboard ConfigMap can live next to the app in `poll-modem`.

## Where the dashboard lives

In this repo, the dashboard is deployed from:

- `gitops/kustomize/poll-modem/dashboard-configmap.yaml`

The ConfigMap carries:

- `grafana_dashboard: "1"`
- `grafana_folder: Poll Modem` annotation
- `grafana_uid: poll-modem-overview` annotation

## Dashboard design

Keep the first dashboard simple and operational.

The repo now ships with two dashboards:

1. an overview dashboard for health, timing, and channel counts
2. a downstream signal trends dashboard for SNR and power plots

Recommended panels for the overview dashboard:

- collector health
- age since last success
- age since last failure
- downstream SNR over time
- downstream and upstream power over time
- downstream and upstream frequency over time
- upstream symbol rate over time
- lock state over time
- error-codeword growth over time

## Example queries

### Health

```promql
poll_modem_up
```

### Time since last success

```promql
time() - poll_modem_last_success_unixtime
```

### Downstream SNR by channel

```promql
poll_modem_downstream_snr_db
```

### Channel power

```promql
poll_modem_downstream_power_dbmv
poll_modem_upstream_power_dbmv
```

### Channel frequency

```promql
poll_modem_downstream_frequency_hz
poll_modem_upstream_frequency_hz
```

### Upstream symbol rate

```promql
poll_modem_upstream_symbol_rate_sps
```

### Lock state

```promql
poll_modem_downstream_locked
poll_modem_upstream_locked
```

### Error codewords

```promql
poll_modem_error_correctable_codewords
poll_modem_error_uncorrectable_codewords
poll_modem_error_unerrored_codewords
```

## Step-by-step

### 1. Add the dashboard JSON

Create the dashboard as a ConfigMap data entry.

The JSON should use the Prometheus datasource UID `prometheus`.

### 2. Label the ConfigMap correctly

Grafana will only discover the dashboard if the label is present.

```yaml
labels:
  grafana_dashboard: "1"
```

### 3. Put the ConfigMap in the app overlay

Because the Grafana sidecar searches all namespaces, placing the dashboard in the `poll-modem` overlay keeps it close to the app.

### 4. Push and let ArgoCD sync

Once the repo is pushed, ArgoCD should create the ConfigMap in the cluster.

### 5. Verify the dashboard shows up in Grafana

Port-forward Grafana or use the existing ingress path and confirm the dashboard appears under the Poll Modem folder.

## Validation checklist

- ConfigMap exists in `poll-modem`
- ConfigMap has `grafana_dashboard=1`
- Grafana sidecar logs show the dashboard was loaded
- Dashboard appears in Grafana
- the downstream signal trends dashboard appears too
- panels render without datasource errors

## Common failure modes

### Dashboard not appearing

Check:

- label typo
- ConfigMap namespace
- Grafana sidecar logs
- JSON syntax errors

### Panels show “No data”

Check:

- Prometheus target is up
- metric names match the app
- queries are correct for counter vs gauge vs histogram

### Datasource errors

Check that the dashboard targets use the `prometheus` datasource UID or the correct name for the in-cluster datasource.

## Recovery notes

If the dashboard becomes too noisy, simplify it. Start with one page that answers: is the modem up, when did we last succeed, and are the signal/channel counts sane?
