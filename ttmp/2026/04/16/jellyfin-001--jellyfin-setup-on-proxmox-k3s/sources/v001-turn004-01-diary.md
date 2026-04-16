# Diary

## Goal

Step-by-step implementation diary for setting up Jellyfin media server on Proxmox infrastructure (either as a VM, LXC, or within the existing k3s cluster).

## Environment Summary

| Component | Details |
|-----------|---------|
| Proxmox Host | root@pve |
| Existing k3s | Yes (running in a VM) |
| Alternatives | Separate VM or LXC |
| Goal | Jellyfin media server |

---

## Step 1: Ticket Created & Environment Assessment

**Date:** 2026-04-16

### Prompt Context

**User prompt (verbatim):** "We are working with proxmox on root@pve, I want to setup jellyfin, I have k3s on a VM, but could do separate VM or LXC on the proxmox too. I want to setup jellyfin. Create a new docmgr ticket and then walkme through the setup of jellyfin step by step asking me choices to make. Keep a detailed diary as we go."

**Assistant interpretation:** User wants to set up Jellyfin on their Proxmox infrastructure and wants guided decision-making with documentation.

**Inferred user intent:** Deploy a functional Jellyfin media server with proper documentation for future reference.

### What I did

1. Created docmgr ticket `jellyfin-001` with title "Jellyfin Setup on Proxmox/k3s"
2. Created diary document at `reference/01-diary.md`
3. Initialized this diary entry

### What should be done next

- Determine deployment target (k3s, VM, or LXC)
- Gather user requirements and preferences

---

## Step 2: Deployment Target Decision

**Date:** 2026-04-16

### Prompt Context

**User prompt (verbatim):** (see Step 1)

**Assistant interpretation:** Need to decide where to deploy Jellyfin.

**Inferred user intent:** Choose optimal deployment method for Jellyfin.

### Decision Points

| Option | Pros | Cons |
|--------|------|------|
| **k3s (existing VM)** | Single control plane, GitOps friendly, easy updates | More resource overhead, complexity |
| **New LXC** | Lightweight, fast, easy snapshots, GPU passthrough possible | Separate from k3s management |
| **New VM** | Isolated, full OS flexibility | More resource overhead |

### What I need from you

1. **Primary question:** Where do you want to run Jellyfin?
   - Option A: Run as a k3s deployment (using existing k3s VM)
   - Option B: Run in a new LXC container on Proxmox
   - Option C: Run in a new VM on Proxmox

2. **Hardware considerations:**
   - Do you have GPU hardware (Intel QuickSync, NVIDIA) for hardware transcoding?
   - How much RAM/CPU do you want to allocate?
   - Where will media files be stored (local storage, NAS, etc.)?

3. **Networking:**
   - Do you want Jellyfin accessible via a specific domain/subdomain?
   - Will you use Traefik/Caddy for reverse proxy?

### Current Status

**AWAITING USER CHOICE** - Need deployment target decision to proceed.

---

<!-- Future steps will be added here as we progress -->

