# Changelog

## 2026-05-03

- Initial workspace created


## 2026-05-03

Created 12-section architecture and recovery guide (1037 lines), uploaded to reMarkable

### Related Files

- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/design/01-system-architecture-and-recovery-guide-crib-k3s-cluster.md — Comprehensive onboarding document covering all system layers


## 2026-05-03

Added Appendix A: full historical analysis of why Traefik was disabled, traced from git history and diaries. Two compounding oversights: cloud-init never updated + HelmChartConfig removed without replacement.

### Related Files

- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/design/01-system-architecture-and-recovery-guide-crib-k3s-cluster.md — Added 136-line Appendix A with historical timeline


## 2026-05-03

Wrote 360-line Obsidian vault article covering the full investigation, historical reconstruction, crash loop analysis, and working rules. Diary updated to Step 6.

### Related Files

- /home/manuel/code/wesen/obsidian-vault/Projects/2026/05/03/ARTICLE - Debugging a k3s Post-Reboot Outage.md — Comprehensive article in Obsidian vault


## 2026-05-03

Takeover recovery completed: stabilized k3s via temporary CCM disable, re-enabled CCM after RBAC existed, restored Traefik hostPort ingress, disabled stale DNAT proxy, resynced ArgoCD apps, validated argocd/watch/grafana/modem URLs, and updated cloud-init/README for final ingress model.

### Related Files

- /home/manuel/code/wesen/crib-k3s/README.md — Document final ingress model and disabled legacy proxy
- /home/manuel/code/wesen/crib-k3s/cloud-init.yaml — Persist final Traefik-enabled hostPort model
- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/reference/02-diary-takeover-crashloop-investigation.md — Takeover diary with recovery steps


## 2026-05-03

Updated Obsidian project report with successful takeover recovery: CCM ordering workaround, hostPort Traefik model, disabled DNAT proxy, ArgoCD manual retries, final URL validation; copied updated 507-line article back to ticket sources.

### Related Files

- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/sources/ARTICLE - Debugging a k3s Post-Reboot Outage.md — Copied updated report into ticket sources
- /home/manuel/code/wesen/obsidian-vault/Projects/2026/05/03/ARTICLE - Debugging a k3s Post-Reboot Outage.md — Updated vault project report with completed recovery


## 2026-05-03

Added post-reboot validation script and operator playbook, performed real k3s VM reboot, fixed validation wait-loop bugs, and confirmed all crib URLs and cluster checks pass after reboot.

### Related Files

- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/playbooks/01-post-reboot-recovery-and-validation.md — Operator playbook for reboot validation and recovery
- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/reference/02-diary-takeover-crashloop-investigation.md — Recorded real reboot validation results
- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/scripts/01-post-reboot-validate.sh — Post-reboot validation script tested before and after real VM reboot


## 2026-05-03

Updated Obsidian project report with real reboot validation: baseline validation, VM reboot, script wait-loop fixes, successful post-reboot validation, and commit 26ccbcc; copied updated 574-line report back to ticket sources.

### Related Files

- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/sources/ARTICLE - Debugging a k3s Post-Reboot Outage.md — Copied updated report into ticket sources
- /home/manuel/code/wesen/obsidian-vault/Projects/2026/05/03/ARTICLE - Debugging a k3s Post-Reboot Outage.md — Updated project report with validation step


## 2026-05-03

Investigated argocd-crib Progressing health, identified empty Ingress loadBalancer status under hostPort Traefik, configured Traefik to publish Tailscale IP 100.67.90.12, changed Traefik updates to Recreate for hostPort safety, tightened validation, and updated diary/report.

### Related Files

- /home/manuel/code/wesen/crib-k3s/README.md — Document explicit Traefik Ingress status IP
- /home/manuel/code/wesen/crib-k3s/cloud-init.yaml — Persist Traefik Ingress status IP and Recreate strategy
- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/reference/02-diary-takeover-crashloop-investigation.md — Record argocd-crib Progressing investigation
- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/scripts/01-post-reboot-validate.sh — Tighten ArgoCD health and Ingress status validation
- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/sources/ARTICLE - Debugging a k3s Post-Reboot Outage.md — Updated project report copy with argocd-crib health fix


## 2026-05-03

Performed final controlled reboot after Traefik Ingress status fix; validation retried through transient monitoring Progressing and ArgoCD 503, then passed with all ArgoCD apps Healthy and all crib URLs correct; updated final diary and project report and synchronized the vault and ticket copies.

### Related Files

- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/reference/02-diary-takeover-crashloop-investigation.md — Recorded final reboot validation after ArgoCD health fix
- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/scripts/01-post-reboot-validate.sh — URL mismatches are retryable in --wait mode
- /home/manuel/code/wesen/crib-k3s/ttmp/2026/05/03/k3s-restart--investigate-and-automate-k3s-service-restart-after-proxmox-reboot/sources/ARTICLE - Debugging a k3s Post-Reboot Outage.md — Final project report copy with second reboot validation
- /home/manuel/code/wesen/obsidian-vault/Projects/2026/05/03/ARTICLE - Debugging a k3s Post-Reboot Outage.md — Vault copy synchronized with final project report


## 2026-05-03

Ticket closed

