---
Title: Tasks
Ticket: jellyfin-001
Status: active
Topics:
  - proxmox
  - k3s
  - jellyfin
  - media-server
DocType: tasks
Intent: long-term
Owners: []
LastUpdated: 2026-04-16
---

# Tasks

## Completed
- [x] Create docmgr ticket and diary
- [x] Assess hardware (Xeon E-2224, no GPU, iGPU disabled)
- [x] Choose deployment target (k3s via ArgoCD)
- [x] Liberate sda/sdb disks from vfio-pci binding
- [x] Reinstall TrueNAS SCALE 23.10.2 on VM 106
- [x] Create ZFS mirror pool `media-pool` (~3.6TB usable)
- [x] Create dataset `/mnt/media-pool/media`
- [x] Enable NFS share for 192.168.0.0/24
- [x] Mount NFS on k3s VM at `/mnt/media`
- [x] Create Jellyfin GitOps manifests (deployment, service, ingress, PVC)
- [x] Deploy via ArgoCD (namespace: jellyfin)
- [x] Add IngressRoutes (HTTPS + HTTP + IP-based for TV)
- [x] Add DNS record for watch.crib.scapegoat.dev
- [x] Fix media permissions (chmod 777)
- [x] Upload test movies
- [x] Recover diary from lost docmgr ticket (reconstruct_files.py)

## Remaining
- [ ] Start TrueNAS SMB service (via Web UI → Services → CIFS/SMB)
- [ ] Test SMB share connectivity
- [ ] Configure Jellyfin media library (Dashboard → Libraries → /media)
- [ ] Test on Samsung TV with Jellyfin app
- [ ] Enable DLNA if TV doesn't support Jellyfin app
