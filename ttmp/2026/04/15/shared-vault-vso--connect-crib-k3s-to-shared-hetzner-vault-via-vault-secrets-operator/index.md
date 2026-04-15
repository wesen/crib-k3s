---
Title: Connect crib-k3s to shared Hetzner Vault via Vault Secrets Operator
Ticket: shared-vault-vso
Status: active
Topics:
    - vault
    - vso
    - secrets
    - argocd
    - kubernetes
DocType: index
Intent: long-term
Owners: []
RelatedFiles:
    - Path: ../../../../../../2026-03-27--hetzner-k3s/gitops/applications/vault-secrets-operator.yaml
      Note: Hetzner VSO helm values reference
    - Path: ../../../../../../2026-03-27--hetzner-k3s/scripts/bootstrap-vault-kubernetes-auth.sh
      Note: Bootstrap script pattern to adapt for crib
    - Path: ../../../../../../2026-03-27--hetzner-k3s/vault/policies/kubernetes/vso-smoke.hcl
      Note: Example policy pattern
    - Path: ../../../../../../2026-03-27--hetzner-k3s/vault/roles/kubernetes/vso-smoke.json
      Note: Example role pattern
ExternalSources: []
Summary: ""
LastUpdated: 2026-04-15T19:38:54.494515477-04:00
WhatFor: ""
WhenToUse: ""
---





# Connect crib-k3s to shared Hetzner Vault via Vault Secrets Operator

## Overview

<!-- Provide a brief overview of the ticket, its goals, and current status -->

## Key Links

- **Related Files**: See frontmatter RelatedFiles field
- **External Sources**: See frontmatter ExternalSources field

## Status

Current status: **active**

## Topics

- vault
- vso
- secrets
- argocd
- kubernetes

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
