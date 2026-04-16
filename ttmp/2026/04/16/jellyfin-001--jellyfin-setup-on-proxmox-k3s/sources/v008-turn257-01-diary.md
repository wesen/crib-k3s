# Diary - Jellyfin Setup on Proxmox/k3s

## Goal

Deploy Jellyfin media server on Proxmox/k3s with TrueNAS for storage.

---

## Step 1: Initial Setup - Ticket Created
**Date:** 2026-04-16

- Created docmgr ticket `jellyfin-001`
- Discovered Terraform at `corporate-headquarters/go-go-infra/proxmox/`
- Discovered GitOps setup in `crib-k3s` with ArgoCD

---

## Step 2: Hardware Assessment
- CPU: Intel Xeon E-2224 (QuickSync capable but iGPU disabled)
- GPU: None available for transcoding
- **Decision: Software transcoding only**

---

## Step 3: Storage Discovery
- k3s VM: 30GB root (limited)
- sda/sdb: 3.6TB each (Seagate IronWolf 4TB)

---

## Step 4: Decision - k3s Deployment
- Platform: k3s (VM 301) via ArgoCD
- Domain: `watch.crib.scapegoat.dev`
- TLS: cert-manager
- Transcoding: Software only
- Storage: TrueNAS NFS

---

## Step 5: TrueNAS Installation
**Date:** 2026-04-16

1. Wiped old ZFS signatures from disks
2. Reconfigured VM 106 to pass disks individually (not PCI passthrough)
3. Installed TrueNAS SCALE 23.10.2
4. Initial setup via Web UI at `https://192.168.0.25`

---

## Step 6: TrueNAS Configuration via API

### API Key
- Stored in 1Password: `em7avlpdu336i64lgowmxyphhu`
- Saved to Proxmox: `/root/.truenas_api_key`
- Helper script: `/tmp/truenas_api.sh`

### Pool Created
```bash
# Correct API format for pool creation:
{
  "name": "media-pool",
  "encryption": false,
  "topology": {
    "data": [
      {"disks": ["sdb", "sdc"], "type": "MIRROR"}
    ]
  },
  "allow_duplicate_serials": true
}
```

**Pool Details:**
- Name: `media-pool`
- Size: ~4TB (3.98TB)
- Topology: Mirror (sdb + sdc)
- Status: ONLINE ✓

### Dataset Created
- Path: `/mnt/media-pool/media`
- Name: `media-pool/media`

### NFS Share Created
```json
{
  "id": 4,
  "path": "/mnt/media-pool/media",
  "comment": "Jellyfin media",
  "networks": ["192.168.0.0/24"],
  "enabled": true
}
```

**NFS Status:** RUNNING ✓

---

## Step 7: k3s NFS Mount

```bash
# On k3s VM (k3s-proxmox):
sudo mkdir -p /mnt/media
sudo mount -t nfs 192.168.0.25:/mnt/media-pool/media /mnt/media

# Verified:
df -h /mnt/media
# 192.168.0.25:/mnt/media-pool/media  3.6T     0  3.6T   0% /mnt/media
```

---

## Step 8: Jellyfin Deployment via ArgoCD

### GitOps Structure Created

```
gitops/
├── kustomize/jellyfin/
│   ├── namespace.yaml
│   ├── pvc.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   └── kustomization.yaml
└── applications/
    └── jellyfin.yaml
```

### Commit
- Hash: `89e7c40`
- Message: "Add Jellyfin deployment via ArgoCD"

---

## Step 9: SUCCESS - Jellyfin Deployed!

**Date:** 2026-04-16

### Final Status

| Component | Status | Details |
|-----------|--------|---------|
| TrueNAS Pool | ✅ ONLINE | `media-pool` - 3.6TB mirror |
| TrueNAS Dataset | ✅ Created | `/mnt/media-pool/media` |
| NFS Share | ✅ Running | `192.168.0.0/24` access |
| k3s NFS Mount | ✅ Mounted | `/mnt/media` |
| Jellyfin Pod | ✅ Running | `jellyfin-76cc757945-zx95t` |
| Ingress | ✅ Configured | `watch.crib.scapegoat.dev` |
| Web UI | ✅ LIVE | https://watch.crib.scapegoat.dev |

### URLs

- **Jellyfin Web UI:** https://watch.crib.scapegoat.dev
- **TrueNAS Web UI:** https://192.168.0.25/ui

### Jellyfin Log Output

```
[02:24:49] [INF] [6] MediaBrowser.MediaEncoding.Encoder.MediaEncoder: FFmpeg version 7.1.3
[02:24:49] [INF] [6] MediaBrowser.MediaEncoding.Encoder.MediaEncoder: Available hwaccel types: ["cuda", "vaapi", "qsv", "drm", "opencl", "vulkan"]
[02:24:49] [INF] [6] Emby.Server.Implementations.ApplicationHost: ServerId: 6a09fe922bd4486ebc2731dc848db251
[02:24:49] [INF] [6] Main: Startup complete 0:00:13.7665897
```

---

## Commands

### Check Jellyfin
```bash
cd /home/manuel/code/wesen/crib-k3s
export KUBECONFIG=$PWD/kubeconfig.yaml
kubectl get pods -n jellyfin
kubectl logs -n jellyfin -l app=jellyfin --tail=50
```

### SSH Access
```bash
# k3s
ssh ubuntu@k3s-proxmox

# TrueNAS
ssh admin@192.168.0.25

# Proxmox
ssh root@pve
```

### TrueNAS API
```bash
API_KEY=$(cat /root/.truenas_api_key)
curl -s -k -H "Authorization: Bearer $API_KEY" "https://192.168.0.25/api/v2.0/pool"
```

---

## Next Steps (User)

1. Open https://watch.crib.scapegoat.dev
2. Complete Jellyfin initial setup wizard
3. Add media library pointing to `/media`
4. Configure user accounts
5. Transfer media files to NFS mount

