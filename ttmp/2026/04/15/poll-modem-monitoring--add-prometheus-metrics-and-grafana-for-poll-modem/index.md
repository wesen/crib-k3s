---
Title: Add Prometheus metrics and Grafana for poll-modem
Ticket: poll-modem-monitoring
Status: active
Topics:
    - monitoring
    - prometheus
    - grafana
    - metrics
    - poll-modem
DocType: index
Intent: long-term
Owners: []
RelatedFiles:
    - Path: ../../../../../../corporate-headquarters/poll-modem/cmd/metrics.go
      Note: |-
        Prometheus metric definitions and collectors for poll-modem
        Rich Prometheus signal metrics and per-channel gauges
    - Path: ../../../../../../corporate-headquarters/poll-modem/cmd/metrics_test.go
      Note: Parsing and lock-state normalization tests
    - Path: ../../../../../../corporate-headquarters/poll-modem/cmd/serve.go
      Note: /metrics handler and poll instrumentation wiring
    - Path: ../../../../../../corporate-headquarters/poll-modem/go.mod
      Note: Prometheus client dependency
    - Path: docs/playbooks/09-create-grafana-dashboards-for-poll-modem.md
      Note: Grafana dashboard playbook for poll-modem signal metrics
    - Path: docs/playbooks/10-expose-grafana-via-traefik.md
      Note: Grafana exposure runbook
    - Path: gitops/applications/grafana-crib.yaml
      Note: ArgoCD Application for Grafana ingress exposure
    - Path: gitops/applications/monitoring.yaml
      Note: ArgoCD Application for kube-prometheus-stack monitoring stack
    - Path: gitops/kustomize/grafana-crib/ingressroute.yaml
      Note: Traefik IngressRoute for grafana.crib.scapegoat.dev
    - Path: gitops/kustomize/poll-modem/dashboard-configmap.yaml
      Note: Grafana dashboard ConfigMap for modem signal panels
    - Path: gitops/kustomize/poll-modem/deployment.yaml
      Note: Pin poll-modem to the metrics-enabled image tag and GHCR pull secret
    - Path: gitops/kustomize/poll-modem/downstream-signal-dashboard-configmap.yaml
      Note: Downstream SNR and power trends dashboard
    - Path: gitops/kustomize/poll-modem/service.yaml
      Note: Service label required for ServiceMonitor selection
    - Path: gitops/kustomize/poll-modem/servicemonitor.yaml
      Note: ServiceMonitor for poll-modem scrape configuration
ExternalSources: []
Summary: ""
LastUpdated: 2026-04-15T21:12:44.591281559-04:00
WhatFor: ""
WhenToUse: ""
---






# Add Prometheus metrics and Grafana for poll-modem

## Overview

<!-- Provide a brief overview of the ticket, its goals, and current status -->

## Key Links

- **Related Files**: See frontmatter RelatedFiles field
- **External Sources**: See frontmatter ExternalSources field

## Status

Current status: **active**

## Topics

- monitoring
- prometheus
- grafana
- metrics
- poll-modem

## Tasks

See [tasks.md](./tasks.md) for the current task list.

## Changelog

See [changelog.md](./changelog.md) for recent changes and decisions.

## Structure

- design/ - Architecture and design documents
- reference/ - Prompt packs, API contracts, context summaries
- playbooks/ - Command sequences and test procedures
- scripts/ - Temporary code and tooling
- various/ - Working notes and research
- archive/ - Deprecated or reference-only artifacts
