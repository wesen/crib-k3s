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
      Note: Prometheus metric definitions and collectors for poll-modem
    - Path: ../../../../../../corporate-headquarters/poll-modem/cmd/serve.go
      Note: /metrics handler and poll instrumentation wiring
    - Path: ../../../../../../corporate-headquarters/poll-modem/go.mod
      Note: Prometheus client dependency
    - Path: gitops/applications/monitoring.yaml
      Note: ArgoCD Application for kube-prometheus-stack monitoring stack
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
