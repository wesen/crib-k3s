---
Title: Jellyfin Setup on Proxmox/k3s
Ticket: jellyfin-001
Status: active
Topics:
    - proxmox
    - k3s
    - jellyfin
    - media-server
DocType: index
Intent: long-term
Owners: []
RelatedFiles: []
ExternalSources: []
Summary: >
  Set up Jellyfin media server on Proxmox/k3s with TrueNAS SCALE storage,
  deployed via ArgoCD GitOps at watch.crib.scapegoat.dev.
LastUpdated: 2026-04-16T14:34:28.36822497-04:00
WhatFor: ""
WhenToUse: ""
---

# Jellyfin Setup on Proxmox/k3s

## Overview

Jellyfin media server deployed on k3s cluster with TrueNAS SCALE providing NFS storage.
Accessible at `watch.crib.scapegoat.dev` and `http://192.168.0.212:32277`.

**Note:** This ticket was originally created on 2026-04-15 but the docmgr files vanished
(probably pi agent sandbox issue). Recovered from session transcript using reconstruct_files.py.
Diary restored to richest version (v005 from turn 74).

## Key Links

- **Jellyfin**: https://watch.crib.scapegoat.dev
- **TrueNAS UI**: https://192.168.0.25/ui
- **k3s node**: 192.168.0.212
- **Obsidian report**: `Projects/PROJ - Jellyfin Media Server.md`
- **Transcript**: `~/.pi/agent/sessions/--home-manuel-code-wesen-crib-k3s--/2026-04-16T01-34-34-242Z_*.jsonl`

## Status

Current status: **completed** — Jellyfin deployed and running. Remaining: SMB service, TV testing.

## Topics

- proxmox
- k3s
- jellyfin
- media-server

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
