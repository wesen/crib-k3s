# Diary

## Goal

Step-by-step implementation diary for setting up Jellyfin media server on Proxmox/k3s infrastructure.

## Environment Summary

| Component | Details |
|-----------|---------|
| Proxmox Host | root@pve |
| Existing k3s | VM 301 (k3s-server), 4 cores, 8GB RAM |
| Terraform | `/home/manuel/code/wesen/corporate-headquarters/go-go-infra/proxmox/` |
| ArgoCD | GitOps at `https://github.com/wesen/crib-k3s.git` |
| Domain | `watch.crib.scapegoat.dev` (covered by *.crib wildcard) |
| DNS | Terraform at `/home/manuel/code/wesen/terraform/dns/` |

---

## Step 1: Ticket Created

**Date:** 2026-04-16

### Prompt Context

**User prompt (verbatim):** "We are working with proxmox on root@pve, I want to setup jellyfin, I have k3s on a VM, but could do separate VM or LXC on the proxmox too. I want to setup jellyfin. Create a new docmgr ticket and then walkme through the setup of jellyfin step by step asking me choices to make. Keep a detailed diary as we go."

**Assistant interpretation:** User wants to set up Jellyfin on their Proxmox infrastructure with guided decision-making and documentation.

**Inferred user intent:** Deploy a functional Jellyfin media server with proper documentation for future reference.

### What I did

1. Created docmgr ticket `jellyfin-001` with title "Jellyfin Setup on Proxmox/k3s"
2. Created diary document at `reference/01-diary.md`
3. Discovered Terraform infrastructure at `corporate-headquarters/go-go-infra/proxmox/`
4. Discovered existing GitOps setup in `crib-k3s` with ArgoCD

---

## Step 2: Hardware Assessment

**Date:** 2026-04-16

### Prompt Context

**User prompt (verbatim):** "2. o we have gpuu? log in and assess"

**Assistant interpretation:** User wants to check hardware capabilities for transcoding.

**Inferred user intent:** Determine if hardware transcoding (GPU) is available.

### Hardware Findings

| Resource | Details |
|----------|---------|
| **CPU** | Intel Xeon E-2224 (Coffee Lake) |
| **iGPU** | Intel UHD Graphics P630 (present but disabled) |
| **Discrete GPU** | None |
| **Current VGA** | Matrox G200eH3 (BMC/iLO graphics only) |
| **iGPU Status** | Not enabled in BIOS/UEFI |

### iGPU Note

The Xeon E-2224 has an integrated GPU that *could* do QuickSync transcoding, but it's:
- Not enabled in the server BIOS
- Not passed through to any VM
- Would require physical/ILO access to enable

### Transcoding Decision

**Software transcoding only** - Works fine for:
- H.264/AVC (most common)
- 1080p without issues
- 4K H.264 acceptable on Xeon E-2224

---

## Step 3: Storage Assessment

**Date:** 2026-04-16

### Storage Inventory

| Storage | Size | Status |
|---------|------|--------|
| k3s VM root (local-lvm) | 30GB | Full OS, not much room |
| Proxmox local storage | ~98GB | Available |
| sda (3.6TB) | TrueNAS disk | Unavailable (TrueNAS won't boot) |
| sdb (3.6TB) | TrueNAS disk | Unavailable (TrueNAS won't boot) |
| NFS | None | Not configured |

### TrueNAS Issue

VM 106 (TrueNAS) has VFIO PCI passthrough that prevents it from starting:
```
kvm: vfio: Cannot reset device 0000:00:17.0, no available reset mechanism.
```

The sda/sdb disks belong to the TrueNAS ZFS pool and can't be easily repurposed.

---

## Step 4: Decision Made - k3s Deployment

**Date:** 2026-04-16

### Prompt Context

**User prompt (verbatim):** "alright, k3s then"

**Assistant interpretation:** User chose k3s as the deployment platform.

**Inferred user intent:** Deploy Jellyfin within the existing k3s cluster managed by ArgoCD.

### Deployment Plan

| Component | Decision |
|-----------|----------|
| Platform | k3s (VM 301) via ArgoCD GitOps |
| Domain | `watch.crib.scapegoat.dev` |
| DNS | Already covered by `*.crib.scapegoat.dev → 100.67.90.12` |
| TLS | cert-manager (existing `crib-scapegoat-dev-tls` secret) |
| Ingress | Traefik IngressRoute |
| Transcoding | Software only |
| Media Storage | **NEEDS DECISION** |

### GitOps Structure (to be created)

```
gitops/
├── kustomize/
│   └── jellyfin/              # Jellyfin manifests
│       ├── namespace.yaml
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       └── kustomization.yaml
└── applications/
    └── jellyfin.yaml          # ArgoCD Application
```

---

## Step 5: Storage Decision Needed

**Date:** 2026-04-16

### Options for Media Storage

| Option | Pros | Cons |
|--------|------|------|
| **1. Add disk to k3s VM** | Dedicated storage, easy to manage | Requires Proxmox config, resizing complex |
| **2. Proxmox hostPath** | Fast, uses existing storage | Less portable, host-dependent |
| **3. K3s PVC (local-path)** | GitOps native | Limited to 30GB root disk |
| **4. NFS mount** | Portable, network-accessible | Requires NFS server setup |

### Question for User

**Where are your media files now, or will this be new storage?**

---

## Implementation Steps (To Be Executed)

Once storage decision is made:

1. [ ] Create `gitops/kustomize/jellyfin/` directory
2. [ ] Write `namespace.yaml` - create `jellyfin` namespace
3. [ ] Write `deployment.yaml` - Jellyfin container with software transcoding
4. [ ] Write `service.yaml` - ClusterIP service
5. [ ] Write `ingress.yaml` - Traefik IngressRoute for `watch.crib.scapegoat.dev`
6. [ ] Write `kustomization.yaml` - Kustomize config
7. [ ] Write `applications/jellyfin.yaml` - ArgoCD Application
8. [ ] Commit and push to GitHub
9. [ ] Verify ArgoCD syncs the application
10. [ ] Initial Jellyfin setup via web UI

---

<!-- Future steps will be added here as we progress -->

