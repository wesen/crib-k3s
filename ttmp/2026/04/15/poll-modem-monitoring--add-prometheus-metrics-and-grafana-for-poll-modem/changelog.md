# Changelog

## 2026-04-15

- Initial workspace created

## 2026-04-16

- Added richer modem signal metrics for downstream SNR, power, frequency, lock state, upstream symbol rate, and error codewords
- Added Grafana dashboard manifests for poll-modem overview and downstream signal trends
- Exposed Grafana at `grafana.crib.scapegoat.dev` through a dedicated Traefik IngressRoute
- Copied the wildcard TLS secret into the `monitoring` namespace for Grafana TLS
- Verified Grafana loads both poll-modem dashboards via the sidecar/search API
