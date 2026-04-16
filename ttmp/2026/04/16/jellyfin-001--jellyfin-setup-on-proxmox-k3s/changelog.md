---
Title: Changelog
Ticket: jellyfin-001
Status: active
Topics:
  - proxmox
  - k3s
  - jellyfin
  - media-server
DocType: changelog
Intent: long-term
Owners: []
LastUpdated: 2026-04-16
---

# Changelog

## 2026-04-16 — Ticket recovered from transcript

- Recreated docmgr ticket jellyfin-001 (original was lost due to pi agent sandbox issue)
- Recovered diary from session transcript using `reconstruct_files.py` (8 versions found)
- Restored richest diary version (v005, 10831 bytes, from turn 74)
- Stored all diary versions in `sources/` for historical reference

## 2026-04-16 — Jellyfin deployment completed

- Liberated sda/sdb from vfio-pci, rebound to ahci driver
- Reinstalled TrueNAS SCALE 23.10.2 on VM 106
- Created ZFS mirror pool `media-pool` (2x 4TB Seagate IronWolf)
- Created dataset and NFS share
- Mounted NFS on k3s VM
- Deployed Jellyfin via ArgoCD GitOps (commit 89e7c40, then 4b200e4 for ingress)
- Configured Traefik IngressRoutes for watch.crib.scapegoat.dev
- Added DNS A record via Terraform
- Uploaded test media files
