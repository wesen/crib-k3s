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

**Hardware Findings:**
- CPU: Intel Xeon E-2224 (QuickSync capable but iGPU disabled)
- GPU: None available for transcoding
- **Decision: Software transcoding only**

---

## Step 3: Storage Discovery

**Initial storage:**
- k3s VM: 30GB root (limited)
- sda/sdb: 3.6TB each (TrueNAS ZFS mirror) - Unavailable due to VFIO

---

## Step 4: Decision - k3s Deployment

- Platform: k3s (VM 301) via ArgoCD
- Domain: `watch.crib.scapegoat.dev`
- TLS: cert-manager
- Transcoding: Software only
- Storage: TBD (TrueNAS option)

---

## Step 5: Disk Liberation

**The Problem:**
- SATA controller bound to vfio-pci
- Disks invisible to host

**The Solution:**
```bash
# Stop TrueNAS VM
qm stop 106

# Unbind from vfio-pci
echo '0000:00:17.0' > /sys/bus/pci/drivers/vfio-pci/unbind

# Bind to ahci
echo '0000:00:17.0' > /sys/bus/pci/drivers/ahci/bind
```

**Result:** Disks visible!
- sda: ST4000VN008 (Seagate IronWolf 4TB)
- sdb: ST4000VN008 (Seagate IronWolf 4TB)

---

## Step 6: Wipe Disks

```bash
# Wipe ZFS signatures
dd if=/dev/zero of=/dev/sda bs=1M count=100
dd if=/dev/zero of=/dev/sdb bs=1M count=100
```

---

## Step 7: Reconfigure TrueNAS VM

**New VM 106 config:**
```
scsi0: local-lvm:vm-106-disk-0 (32GB boot)
scsi1: /dev/disk/by-id/ata-ST4000VN008-2DR166_ZDHA5J5T (4TB)
scsi2: /dev/disk/by-id/ata-ST4000VN008-2DR166_ZDHA5KRC (4TB)
vga: virtio
serial0: socket
```

---

## Step 8: TrueNAS Installation

**Date:** 2026-04-16

**Status:** TrueNAS ISO booted, user sees install wizard in Proxmox UI console.

### Installation Guide:

1. **Welcome Screen:** Select "Install/Upgrade"
2. **Select Boot Device:** Choose `vm-106-disk-0` (32GB)
3. **Warning:** Confirm boot device (data will be preserved)
4. **Set Root Password:** Choose a strong password
5. **Boot Mode:** Select "UEFI Boot" (default)
6. **Finish:** Remove ISO after reboot

### Post-Installation Steps (to be done after install):

1. Access TrueNAS web UI
2. Create ZFS pool (mirror of sda + sdb)
3. Create dataset for media
4. Configure NFS share
5. Mount NFS in k3s

---

## Step 9: TrueNAS Post-Install (Pending)

### After TrueNAS is installed:

1. [ ] Remove ISO from VM
2. [ ] Access TrueNAS web UI
3. [ ] Configure storage pool
4. [ ] Create NFS share
5. [ ] Configure k3s NFS mount
6. [ ] Deploy Jellyfin
7. [ ] Configure Jellyfin

---

<!-- Ongoing - to be updated -->

