---
Title: Investigate and automate k3s service restart after Proxmox reboot
Ticket: k3s-restart
Status: active
Topics:
    - k3s
    - proxmox
    - recovery
    - systemd
    - tailscale
DocType: index
Intent: long-term
Owners: []
RelatedFiles:
    - Path: ../../../../../../obsidian-vault/Projects/2026/04/15/ARTICLE - Deploying k3s on Proxmox - A Technical Deep Dive.md
      Note: Full setup documentation with k3s config
    - Path: ../../../../../../obsidian-vault/Projects/PROJ - Jellyfin Media Server.md
      Note: Jellyfin deployment details including services
    - Path: README.md
      Note: Updated final ingress model after takeover recovery
    - Path: cloud-init.yaml
      Note: Cloud-init template that disables Traefik - root cause
    - Path: kubeconfig.yaml
      Note: Kubeconfig for accessing the k3s cluster
    - Path: ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/playbooks/01-post-reboot-recovery-and-validation.md
      Note: Operator playbook for post-reboot recovery
    - Path: ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/reference/02-diary-takeover-crashloop-investigation.md
      Note: Independent takeover diary and successful recovery trail
    - Path: ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/scripts/01-post-reboot-validate.sh
      Note: Post-reboot validation script tested before and after real VM reboot
    - Path: ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/sources/ARTICLE - Debugging a k3s Post-Reboot Outage.md
      Note: Obsidian vault article copied into ticket workspace
ExternalSources: []
Summary: ""
LastUpdated: 2026-05-03T07:40:39.245382313-04:00
WhatFor: ""
WhenToUse: ""
---








# Investigate and automate k3s service restart after Proxmox reboot

## Overview

<!-- Provide a brief overview of the ticket, its goals, and current status -->

## Key Links

- **Related Files**: See frontmatter RelatedFiles field
- **External Sources**: See frontmatter ExternalSources field

## Status

Current status: **active**

## Topics

- k3s
- proxmox
- recovery
- systemd
- tailscale

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
