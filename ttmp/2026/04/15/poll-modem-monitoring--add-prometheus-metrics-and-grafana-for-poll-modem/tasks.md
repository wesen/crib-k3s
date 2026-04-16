# Tasks

## TODO

- [ ] Add /metrics endpoint to poll-modem serve mode and expose app counters/histograms
- [ ] Add ArgoCD-managed ServiceMonitor for poll-modem so Prometheus can scrape it
- [ ] Add a Prometheus/Grafana stack to crib-k3s via ArgoCD (no local helm CLI)
- [ ] Create Grafana access path in crib-k3s and verify dashboards can read poll-modem metrics
- [ ] Document the cert-manager / ingress / scrape setup and commit as you go
- [ ] Export per-channel downstream SNR, power, frequency, and lock-state gauges from poll-modem
- [ ] Export per-channel upstream power, frequency, symbol-rate, and lock-state gauges from poll-modem
- [ ] Export per-channel error-codeword gauges so Grafana can plot error growth over time
- [ ] Add a Grafana dashboard ConfigMap for poll-modem signal-quality panels
- [ ] Validate Prometheus scrape targets and Grafana panels with the new modem metrics
- [ ] Expose Grafana at grafana.crib.scapegoat.dev via Traefik IngressRoute
- [ ] Copy the wildcard TLS secret into the monitoring namespace for Grafana TLS
- [ ] Add a second poll-modem dashboard focused on downstream SNR and power trends
- [ ] Validate Grafana loads the new dashboards and serves the public ingress
- [x] Change the Average Downstream SNR panel to a 1h rolling average
