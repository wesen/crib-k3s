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

## Step 7: Next Steps

1. [ ] Mount NFS in k3s VM
2. [ ] Deploy Jellyfin via ArgoCD
3. [ ] Configure Jellyfin via web UI

---

## Commands Used

### API Helper (Proxmox)
```bash
# Save API key
echo '1-H9cSRrFHeDLdMZiuFCnCV8qwkskbSrmC5LVcWiMWA5sEA29lYQFVsH1FOwzg6EwH' > /root/.truenas_api_key
chmod 600 /root/.truenas_api_key

# API call
API_KEY=$(cat /root/.truenas_api_key)
curl -s -k -H "Authorization: Bearer $API_KEY" "https://192.168.0.25/api/v2.0/..."
```

### Create Pool
```bash
curl -s -k -X POST -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  'https://192.168.0.25/api/v2.0/pool' \
  -d '{"name": "media-pool", "encryption": false, "topology": {"data": [{"disks": ["sdb", "sdc"], "type": "MIRROR"}]}, "allow_duplicate_serials": true}'
```

### Create Dataset
```bash
curl -s -k -X POST -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  'https://192.168.0.25/api/v2.0/pool/dataset' \
  -d '{"name": "media-pool/media"}'
```

### Create NFS Share
```bash
curl -s -k -X POST -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  'https://192.168.0.25/api/v2.0/sharing/nfs' \
  -d '{"path": "/mnt/media-pool/media", "comment": "Jellyfin media", "networks": ["192.168.0.0/24"], "enabled": true}'
```

---

<!-- Ongoing - to be updated -->

