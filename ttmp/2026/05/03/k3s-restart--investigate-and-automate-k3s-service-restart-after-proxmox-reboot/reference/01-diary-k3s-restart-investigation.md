---
Title: Diary - k3s Restart Investigation
Ticket: k3s-restart
Status: active
Topics:
    - k3s
    - proxmox
    - recovery
    - systemd
    - tailscale
DocType: reference
Intent: long-term
Owners:
    - manuel
RelatedFiles:
    - /home/manuel/code/wesen/obsidian-vault/Projects/2026/04/15/ARTICLE - Deploying k3s on Proxmox - A Technical Deep Dive.md
    - /home/manuel/code/wesen/obsidian-vault/Projects/PROJ - Jellyfin Media Server.md
    - /home/manuel/code/wesen/crib-k3s/kubeconfig.yaml
    - /home/manuel/code/wesen/crib-k3s/cloud-init.yaml
    - /home/manuel/code/wesen/crib-k3s/scripts/create-k3s-vm.sh
ExternalSources: []
Summary: >
    Investigation of k3s service recovery after Proxmox server reboot.
    The k3s-server VM was rebooted along with the Proxmox host. All systemd services
    came back automatically, but DNS resolution for *.crib.scapegoat.dev pointed
    to a stale Tailscale IP (100.97.160.12) instead of the current one (100.67.90.12).
    Additionally, Traefik is disabled in k3s config but the iptables proxy service
    forwards ports 80/443 to Traefik NodePorts 32277/32241 — which have no listener
    because Traefik is not running.
LastUpdated: 2026-05-03
WhatFor: "Post-reboot recovery investigation and automation for crib k3s cluster"
WhenToUse: "When the k3s VM or Proxmox host reboots and services need to be verified"
---

# Diary - k3s Restart Investigation

## Goal

Investigate why `watch.crib.scapegoat.dev` and `argocd.crib.scapegoat.dev` are not
reachable after a Proxmox server reboot. Determine if services auto-restart or need
manual intervention, and create scripts/procedures for future reboots.

## Session Reference

- **Session file:** `/home/manuel/.pi/agent/sessions/--home-manuel-code-wesen-crib-k3s--/2026-05-03T11-37-51-600Z_019deda1-68ef-7233-a49b-487d09b04b5d.jsonl`
- **Session ID:** `019deda1-68ef-7233-a49b-487d09b04b5d`

## Step 1: Create ticket and gather existing documentation

Read all existing documentation to understand the crib-k3s architecture before touching
the live server. Created a docmgr ticket `k3s-restart` with 7 tasks covering the full
investigation from VM status to playbook creation.

### Prompt Context

**User prompt (verbatim):** "We had to reboot the k3s-server proxmox server, which is now back on tailscale too, but the watch.crib.scapegoat.dev and argocd.crib.scapegoat.dev servers are not back online. Create a new docmgr ticket to investigate how to restart the services after a reboot, and if it is just taking time or so. Look at your documents and tickets in here, and potentially in /home/manuel/code/wesen/obsidian-vault/Projects/2026/04/15/ARTICLE - Deploying k3s on Proxmox - A Technical Deep Dive.md where we documented our setup jellyfin: /home/manuel/code/wesen/obsidian-vault/Projects/PROJ - Jellyfin Media Server.md keep a detailed diary as you work. Store all the scripts you write in the scripts/ folder of the ticket."

**Assistant interpretation:** Create a docmgr ticket for post-reboot recovery investigation, read existing docs, keep a diary.

**Inferred user intent:** Figure out why services are down and create a reproducible procedure for bringing them back up after reboot.

### What I did

- Created docmgr ticket `k3s-restart` with 7 tasks
- Read `/home/manuel/code/wesen/obsidian-vault/Projects/2026/04/15/ARTICLE - Deploying k3s on Proxmox - A Technical Deep Dive.md` — full k3s + Proxmox setup narrative
- Read `/home/manuel/code/wesen/obsidian-vault/Projects/PROJ - Jellyfin Media Server.md` — Jellyfin deployment details, services, DNS, network
- Read `README.md` — project overview with access model, bootstrap steps, DNS model
- Read `cloud-init.yaml` — k3s bootstrap with Traefik **disabled** (`disable: - traefik`)
- Read `scripts/create-k3s-vm.sh` — VM creation script
- Read all playbooks in `docs/playbooks/`
- Checked `docmgr status` — found 3 existing tickets (jellyfin-001, poll-modem-monitoring, shared-vault-vso)

### What I learned

- k3s config explicitly disables Traefik via `disable: - traefik` in `/etc/rancher/k3s/config.yaml`
- The README says "Ingress: Traefik (k3s default)" but the actual config disables it — potential documentation drift
- DNS model: `*.crib.scapegoat.dev → 100.67.90.12` (Tailscale IP) via DigitalOcean A record (note: README says this, but actual DNS resolved to 100.97.160.12 — see Step 2)
- There's a `k3s-tailscale-proxy.service` (found in Step 2) not mentioned in README or cloud-init
- Git history shows Traefik was configured via `traefik-config` kustomize (hostPort 80/443), then removed in commit `ec66802` and replaced with systemd iptables

### What should be done in the future

- Update README to document the `k3s-tailscale-proxy.service` iptables forwarding
- Update README to clarify that Traefik is disabled in k3s config but available via k3s packaged Traefik

---

## Step 2: SSH into k3s-server and check service status

Connected to the k3s-server VM via its Tailscale IP `100.67.90.12` (not `100.97.160.12`
which is listed as `k3s-server` in Tailscale status but is offline). The VM was only 7
minutes old from reboot. k3s service was active, all pods were running, but Traefik
was completely absent from the cluster.

### Prompt Context

**User prompt (verbatim):** (see Step 1)

**Assistant interpretation:** Connect to the VM and diagnose what's running vs what's missing.

**Inferred user intent:** Determine if services just need time or if manual intervention is required.

### What I did

- `tailscale status` — showed `k3s-server` at `100.97.160.12` as **offline (17d)**, `k3s-proxmox` at `100.67.90.12` as **idle**, `pve` as **active**
- `tailscale ping k3s-server` — timed out (100.97.160.12 unreachable)
- User corrected: SSH to `100.67.90.12` (which is `k3s-proxmox` in Tailscale, not `k3s-server`)
- `ssh ubuntu@100.67.90.12` — connected, VM uptime only 7 minutes
- `systemctl status k3s.service` — **active (running)**, started at 11:36:23 UTC
- `kubectl get nodes` — `k3s-server` is **Ready**, running k3s v1.35.4+k3s1
- `kubectl get pods -A` — all 18 pods Running, ArgoCD pods freshly restarted (~6 min ago)
- `kubectl get ingress -A` — one Ingress `argocd-server-crib` in `argocd` namespace, `ingressClassName: traefik`
- `dig watch.crib.scapegoat.dev` → `100.67.90.12` (correct, resolves to k3s-proxmox Tailscale IP)
- `dig argocd.crib.scapegoat.dev` → `100.67.90.12` (same)
- `kubectl get pods -A | grep traefik` — **no Traefik pods at all**
- `kubectl get ingressclass` — **no ingress classes**
- `kubectl get crd | grep traefik` — **no Traefik CRDs**
- Found `k3s-tailscale-proxy.service` — systemd oneshot that adds iptables DNAT rules:
  - Port 80 → 127.0.0.1:32277 (Traefik HTTP NodePort)
  - Port 443 → 127.0.0.1:32241 (Traefik HTTPS NodePort)
- Service status: **active (exited)**, started at 11:34:43 UTC (ran successfully)
- But `ss -tlnp` shows nothing listening on 32277 or 32241

### What worked

- k3s service auto-starts via systemd (`enabled`)
- `k3s-tailscale-proxy.service` auto-starts and sets up iptables rules correctly
- All ArgoCD-managed pods came back healthy
- DNS resolves to the correct Tailscale IP

### What didn't work

- **Traefik is not running** — k3s config disables it (`disable: - traefik`), so there's no ingress controller
- The iptables proxy forwards 80/443 to NodePorts 32277/32241 but nothing listens there
- `k3s-server` Tailscale name (100.97.160.12) is stale/offline — the actual VM is registered as `k3s-proxmox` (100.67.90.12)
- No Traefik CRDs (`IngressRoute`) or IngressClasses exist

### What I learned

- **Tailscale naming confusion:** The VM has two Tailscale identities? `k3s-server` (100.97.160.12, offline 17d) and `k3s-proxmox` (100.67.90.12, active). The cloud-init TLS SANs list both hostnames. The stale `k3s-server` entry may be from a previous Tailscale auth.
- **Traefik gap:** The k3s config disables Traefik, but git history shows it was previously enabled via `HelmChartConfig`. The `ec66802` commit removed the Traefik kustomize, replacing it with the iptables proxy. But Traefik itself must have been running before the reboot — it's a k3s packaged component that would be enabled by default unless explicitly disabled. The cloud-init explicitly disables it, so Traefik was never auto-started by k3s.
- **Key question:** How was Traefik running before if k3s config disables it? Possible answers:
  1. It was manually enabled after bootstrap
  2. The config was changed after initial boot
  3. It was deployed via ArgoCD/helm separately

### What was tricky

- The `k3s-server` vs `k3s-proxmox` Tailscale identity confusion delayed initial connection attempts. `tailscale ping k3s-server` goes to a dead IP.
- The `k3s-tailscale-proxy.service` appears healthy (active/exited) even though it's forwarding to ports with no listener — the service only manages iptables rules, not the actual backend.

### What warrants a second pair of eyes

- The relationship between `k3s-server` (offline) and `k3s-proxmox` (active) Tailscale identities — is this a duplicate registration or a renamed machine?
- Whether Traefik needs to be re-enabled in k3s config or deployed separately

### What should be done in the future

- Clean up the stale `k3s-server` Tailscale registration
- Decide on a single Tailscale hostname for this VM
- Document how Traefik is supposed to be deployed (it's not in cloud-init, not in ArgoCD apps)

### Technical details

**Current iptables DNAT rules (from `k3s-tailscale-proxy.service`):**
```
DNAT  tcp  --  *  *  0.0.0.0/0  100.67.90.12  tcp dpt:80  to:127.0.0.1:32277
DNAT  tcp  --  *  *  0.0.0.0/0  100.67.90.12  tcp dpt:443  to:127.0.0.1:32241
```

**k3s config (`/etc/rancher/k3s/config.yaml`):**
```yaml
write-kubeconfig-mode: "0644"
disable:
  - traefik
tls-san:
  - k3s-server
  - k3s-server.tail879302.ts.net
  - k3s-proxmox
  - k3s-proxmox.tail879302.ts.net
```

**Tailscale status (relevant entries):**
```
100.67.90.12   k3s-proxmox    idle
100.97.160.12  k3s-server     idle; offline, last seen 17d ago
100.81.254.116 pve            active; direct 192.168.0.227:41641
```

---

## Step 3: Root cause identified — Traefik disabled in k3s config

The root cause is now clear: **Traefik is disabled in the k3s config** (`disable: - traefik`),
so after a reboot k3s does not deploy Traefik. Before the reboot, Traefik was likely
still running from a previous state where it was either not disabled or was deployed
via a `HelmChartConfig` that has since been removed from the repo.

### Prompt Context

**User prompt (verbatim):** (see Step 1)

**Assistant interpretation:** Continue investigating and fix the root cause of services being down.

**Inferred user intent:** Get watch.crib.scapegoat.dev and argocd.crib.scapegoat.dev back online.

### What I did

- Checked git history: commits `b8314b1` → `86b7d47` → `005f353` → `ec66802` show
  Traefik was configured via `HelmChartConfig` (hostNetwork + hostPort 80/443),
  then the entire `traefik-config` kustomize was removed in `ec66802` with message
  "using systemd iptables instead"
- Confirmed no `HelmChart` or `HelmChartConfig` resources exist in the cluster
- Confirmed no Traefik pods, CRDs, or IngressClasses exist
- Found `k3s-tailscale-proxy.service` (systemd oneshot) that adds iptables DNAT:
  - port 80 → 127.0.0.1:32277 (Traefik HTTP NodePort)
  - port 443 → 127.0.0.1:32241 (Traefik HTTPS NodePort)
- But nothing listens on 32277/32241 because Traefik isn't deployed

### Root cause analysis

1. The `cloud-init.yaml` disables Traefik: `disable: - traefik`
2. A `HelmChartConfig` was added to re-enable and configure Traefik (hostNetwork, NodePort)
3. Later, the `HelmChartConfig` was removed from git and ArgoCD cleaned it up
4. But Traefik pods kept running (already deployed) until the reboot
5. After reboot, k3s reconciles desired state: sees `disable: - traefik` and no HelmChartConfig → no Traefik
6. The iptables proxy forwards to NodePorts that have no listener → connection refused

### User action: Tailscale cleanup

While investigating, the user asked to remove `k3s-demo-1` and `k3s-server` from Tailscale
(both stale leftovers from previous installs). The user handled this manually via the
Tailscale admin console.

### What should be done in the future

- Either re-enable Traefik in k3s config, or create a proper ArgoCD-managed Traefik deployment
- The `k3s-tailscale-proxy.service` iptables approach only works if Traefik is actually running
- Consider a health check in the proxy service that verifies the NodePorts are listening

### Technical details

**Previous HelmChartConfig (from git history, commit 005f353):**
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: traefik
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      type: NodePort
    deployment:
      hostNetwork: true
    securityContext:
      capabilities:
        drop: []
        add:
          - NET_BIND_SERVICE
      runAsNonRoot: false
      runAsUser: 0
    ports:
      web:
        hostPort: 80
      websecure:
        hostPort: 443
```

**Recovery plan:**
1. Remove `traefik` from the k3s `disable` list in `/etc/rancher/k3s/config.yaml`
2. Apply a `HelmChartConfig` for Traefik with the NodePort settings above
3. Restart k3s service
4. Verify Traefik pods start, NodePorts are listening, and services are reachable

---

## Step 4: Created comprehensive architecture and recovery guide

Wrote a 1000+ line technical guide covering every layer of the system, designed
for onboarding someone completely new to the crib cluster. The guide covers
physical infrastructure, VM layer, four-layer networking, k3s internals, Traefik
ingress, TLS, ArgoCD GitOps, post-reboot recovery procedures, systemd services,
diagnostic commands, and future improvements.

### Prompt Context

**User prompt (verbatim):** "Create a detailed analysis / design / implementation guide that is for a new intern, explaining all the parts of the system needed to understand what it is, with prose paragraphs and bullet points and pseudocode and diagrams and api references and file references. It should be very clear and technical. Store in the ticket and then upload to remarkable. Write large documents in smaller write calls to avoid writing too much at once"

**Assistant interpretation:** Create a comprehensive onboarding-style technical document covering all system layers, then upload to reMarkable.

**Inferred user intent:** Ensure all knowledge about the cluster is captured in a single reference document that can be read on reMarkable.

### What I did

- Created `design/01-system-architecture-and-recovery-guide-crib-k3s-cluster.md` in the ticket workspace
- Document has 12 sections covering all system layers
- Uploaded both the guide and the diary to reMarkable at `/ai/2026/05/03/k3s-restart/`

### What I learned

- Writing the document in multiple `edit` calls (one per section) works well to avoid token limits
- The document naturally grew to cover the full stack because every layer depends on the one below it

### What should be done in the future

- After fixing Traefik, update the document to reflect the actual running state
- Consider adding a troubleshooting decision tree ("if X is down, check Y, then Z")

---

## Step 5: Historical analysis — Why Traefik was disabled

Investigated git history and past diary entries to understand the full chain of decisions
that led to Traefik being disabled. The answer is: it wasn't a single mistake but a
compounding of two independent oversights.

### Prompt Context

**User prompt (verbatim):** "why was traefik disabled at some point? was that a mistake? look at past diaries and potentially git history (or both, to correlate), and update the document."

**Assistant interpretation:** Trace the full history of Traefik configuration changes through git commits and diary entries to determine why it was disabled.

**Inferred user intent:** Understand the root cause chain to prevent it from happening again.

### What I did

- Read the original diary (`fbd83ba:diary.md`) which documented the initial setup
- Traced all Traefik-related commits in chronological order
- Found that Traefik was manually re-enabled on the VM (diary Step 2) but cloud-init was never updated
- Found that 4 commits in 12 minutes show a debugging session trying to make Traefik reachable on the Tailscale IP
- The `HelmChartConfig` was removed in `ec66802` with message "using systemd iptables instead" — this was a misunderstanding of the architecture
- Added Appendix A to the architecture document with the full timeline and root cause analysis

### What I learned

- The original networking model used **Tailscale Funnel** (public access via TCP passthrough 443 → Traefik)
- At some point it was pivoted to **tailnet-only** access (A record → Tailscale IP → iptables DNAT → Traefik)
- The commit `ec66802` is the smoking gun: removing the HelmChartConfig while keeping k3s disabled Traefik means nothing deploys it after a reboot
- The iptables proxy service ("using systemd iptables instead") only does DNAT forwarding, it doesn't replace Traefik
- The cloud-init was never updated to reflect the manual re-enablement done in diary Step 2

### What was tricky

- Correlating git history with diary entries required matching timestamps and understanding the developer's intent from commit messages
- The 12-minute debugging session (4 commits) was clearly someone trying different approaches rapidly and then pivoting
- The commit message "using systemd iptables instead" is misleading — iptables replaces Funnel's TCP forwarding, not Traefik itself

### What warrants a second pair of eyes

- The conclusion that this was two compounding oversights rather than a single mistake
- Whether the intended architecture was Option A, B, or C (re-enable in k3s config, HelmChartConfig, or standalone Helm)

### What should be done in the future

- Fix cloud-init.yaml to match the intended state
- Add a comment in k3s config explaining why Traefik is (or isn't) disabled
- Consider a reconciliation script that checks if cloud-init matches the actual running state
