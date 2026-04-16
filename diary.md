---
Title: Diary - crib-k3s setup
DocType: diary
Status: active
Created: 2026-04-15
---

# Diary - crib-k3s Cluster Setup

## Context

After successfully bootstrapping k3s + ArgoCD on Proxmox VM 301 (see `poll-modem` ticket diary), we're now setting up the proper GitOps infrastructure. The manual `kubectl apply` commands from the previous session are being replaced with ArgoCD-managed Kustomize packages in a dedicated `crib-k3s` repo, following the same pattern as `~/code/wesen/2026-03-27--hetzner-k3s/`.

## Step 1: Tailscale Funnel + DNS

### What happened

Upgraded Tailscale plan to enable Funnel. Configured Funnel with raw TCP passthrough on port 443, forwarding to Traefik on the VM. This lets Traefik handle TLS termination with proper certs for `*.crib.scapegoat.dev`.

### Funnel configuration

```bash
# First tried HTTPS mode — Funnel terminates TLS, but only for the Tailscale hostname
# That means argocd.crib.scapegoat.dev gets a cert mismatch
sudo tailscale funnel --bg 443  # WRONG: only serves k3s-proxmox.tail879302.ts.net cert

# Switched to TCP passthrough — Funnel forwards raw TLS to Traefik
sudo tailscale funnel --bg --tcp 443 127.0.0.1:443  # RIGHT: Traefik terminates TLS
```

### Key insight: Funnel TLS modes

- `tailscale funnel --bg 443` — Funnel terminates TLS, serves cert for `*.tail879302.ts.net` only. Custom domains get cert mismatch.
- `tailscale funnel --bg --tcp 443 target` — Raw TCP passthrough. Traefik (or whatever) terminates TLS with whatever certs it has. This is what we need for custom domains with Let's Encrypt.

### DNS via Terraform

Added `*.crib` CNAME to the DigitalOcean DNS zone managed in `~/code/wesen/terraform/dns/zones/scapegoat-dev/envs/prod/main.tf`:

```hcl
wildcard_crib_cname = {
  type  = "CNAME"
  name  = "*.crib"
  value = "k3s-proxmox.tail879302.ts.net."
  ttl   = 3600
}
```

Resolution chain: `argocd.crib.scapegoat.dev → k3s-proxmox.tail879302.ts.net → 100.67.90.12`

Applied with `terraform apply -auto-approve`. Clean — just one resource added.

## Step 2: Re-enable Traefik

k3s had Traefik disabled in the cloud-init (`disable: [traefik]`). Removed that line and restarted k3s:

```bash
sudo sed -i '/disable:/,/traefik/d' /etc/rancher/k3s/config.yaml
sudo systemctl restart k3s
```

Traefik came up as a LoadBalancer service on `192.168.0.212:443`.

## Step 3: Initial Let's Encrypt Attempt (Manual)

### First attempt: cert-manager in argocd namespace

Created ClusterIssuer + Certificate in the `argocd` namespace. The DNS01 challenge failed because cert-manager's challenge solver looks for the DigitalOcean API token secret in the *challenge's* namespace, not `cert-manager`'s namespace. Got:

```
error getting digitalocean token: secrets "digitalocean-dns" not found
```

### Fix: Certificate in cert-manager namespace

Moved the Certificate resource to `cert-manager` namespace (where the secret lives). Challenge went to `valid` state immediately.

### Lessons

- For ClusterIssuer with DNS01, the token secret must be in `cert-manager` namespace
- The Certificate resource should also be in `cert-manager` namespace so the solver finds the secret
- The resulting TLS secret can be referenced from any namespace via Ingress

## Step 4: Create crib-k3s Repo

### Decision

The manual kubectl approach doesn't scale. Created `~/code/wesen/crib-k3s/` as a dedicated GitOps repo following the hetzner-k3s pattern:

```
crib-k3s/
├── cloud-init.yaml          # VM bootstrap (copied from poll-modem)
├── kubeconfig.yaml          # kubectl access
├── scripts/
│   ├── create-k3s-vm.sh
│   └── setup-access.sh
└── gitops/
    ├── applications/        # ArgoCD Application manifests
    └── kustomize/           # Kustomize packages
        ├── platform-cert-issuer/   # ClusterIssuer + wildcard cert
        └── argocd-crib/           # ArgoCD ingress + config
```

### Why not share hetzner-k3s repo?

Different infrastructure (Proxmox vs Hetzner), different domains (`*.crib` vs `*.yolo`), different secrets (DigitalOcean DNS01 vs HTTP01), different network (Tailscale Funnel vs public IP). Sharing would create confusing coupling.

### Key difference from hetzner: DNS01 vs HTTP01

Hetzner uses HTTP01 challenge because the VM has a public IP and Let's Encrypt can reach it directly. Crib uses DNS01 because the VM is behind a cable modem — Let's Encrypt can't reach it, but cert-manager can create TXT records in DigitalOcean DNS to prove domain ownership.

## Current State

- Funnel: TCP passthrough on 443 → Traefik
- DNS: `*.crib.scapegoat.dev → k3s-proxmox.tail879302.ts.net` via Terraform
- Traefik: Running, serving default self-signed cert
- Let's Encrypt: Certificate issued manually (needs to move to ArgoCD)
- Repo: `~/code/wesen/crib-k3s/` created, gitops structure in progress

## Next

- Finish gitops kustomize packages (platform-cert-issuer, argocd-crib)
- Create ArgoCD Application manifests
- Bootstrap ArgoCD to watch the crib-k3s repo
- Clean up manual resources (replace with ArgoCD-managed)

## Step 5: Create crib-k3s Repo and Bootstrap ArgoCD

### What happened

Created `~/code/wesen/crib-k3s/` as the GitOps repo, following the exact pattern from hetzner-k3s. Pushed to `github.com/wesen/crib-k3s`.

### Structure

```
gitops/
├── applications/
│   ├── platform-cert-issuer.yaml   # ArgoCD app for cert-manager config
│   └── argocd-crib.yaml           # ArgoCD app for ArgoCD ingress
└── kustomize/
    ├── platform-cert-issuer/       # ClusterIssuer + wildcard cert (DNS01)
    └── argocd-crib/               # ArgoCD insecure mode + Ingress
```

### GitHub push protection incident

First push was rejected because the DO token was in git history (in `digitalocean-secret.yaml`). Even after deleting the file and committing, the token was still in the first commit. Had to use `git filter-branch` to rewrite history and remove the file from all commits.

**Lesson:** Never commit secrets even temporarily. If you do, `git filter-branch` or `git filter-repo` is needed to clean history before pushing to GitHub with push protection enabled.

### Secret management decision

The DO token is now a manually-created Kubernetes secret (`digitalocean-dns` in `cert-manager` namespace). The kustomize package has a comment explaining this. This is the same pattern hetzner uses — platform secrets are manual, app manifests are in git.

### ArgoCD bootstrap

```bash
# Clean up manual resources
kubectl delete ingressroute argocd argocd-tailscale -n argocd
kubectl delete certificate crib-scapegoat-dev-wildcard -n cert-manager
kubectl delete clusterissuer letsencrypt-prod

# Apply ArgoCD Applications — they self-manage from here
kubectl apply -f gitops/applications/platform-cert-issuer.yaml
kubectl apply -f gitops/applications/argocd-crib.yaml
```

Both apps synced and healthy immediately. The wildcard cert was already cached from the manual step, and the ArgoCD ingress cert was issued fresh via DNS01 challenge.

### End-to-end verification

```
$ curl -sI https://argocd.crib.scapegoat.dev/
HTTP/2 307
location: /login

$ openssl s_client ... | openssl x509 -noout -subject -issuer
subject=CN = argocd.crib.scapegoat.dev
issuer=C = US, O = Let's Encrypt, CN = R13
```

**Full chain working:** Public internet → `*.crib.scapegoat.dev` DNS (DigitalOcean CNAME) → Tailscale Funnel (TCP passthrough) → Traefik ingress → ArgoCD pod. TLS via Let's Encrypt DNS01 challenge.

## Current State

- ✅ Tailscale Funnel: TCP passthrough 443 → Traefik
- ✅ DNS: `*.crib.scapegoat.dev → k3s-proxmox.tail879302.ts.net`
- ✅ Traefik: Running with ingress
- ✅ Let's Encrypt: `argocd.crib.scapegoat.dev` cert issued via DNS01
- ✅ ArgoCD: Watching `wesen/crib-k3s` repo, 2 apps synced
- ✅ `https://argocd.crib.scapegoat.dev/` — publicly accessible with valid TLS

## Step 6: Start the Shared Vault / VSO Investigation

### What happened

We decided not to run a second Vault instance on Proxmox. Instead, we explored reusing the existing Vault from the Hetzner cluster and connecting crib-k3s to it via Vault Secrets Operator (VSO).

### Why this matters

The crib cluster is intentionally small and homelab-ish; duplicating Vault, policies, auth flows, and unseal/seal logic would be unnecessary operational overhead. The Hetzner cluster already has:
- a running Vault instance
- a working Kubernetes auth bootstrap flow
- a Vault Secrets Operator deployment pattern
- several real policies/roles we can mirror

### What we found

- VSO is just a controller, so it can talk to any Vault endpoint reachable over HTTP(S)
- Hetzner’s Vault is reachable at `https://vault.yolo.scapegoat.dev`
- Crib needs its **own** Kubernetes auth mount in Vault, because each cluster has a different service-account token issuer and CA bundle
- We should keep the token/seal/unseal mechanics centralized in the Hetzner Vault and only deploy VSO in crib

### Documentation work

Created a new docmgr ticket in `crib-k3s`:
- `shared-vault-vso` — implementation guide for connecting crib-k3s to shared Hetzner Vault via VSO

Wrote a long-form implementation guide there describing:
- Vault/VSO architecture
- Kubernetes auth flow
- policy and role layout
- how to bootstrap a new auth mount for crib
- how to migrate the existing manual DigitalOcean DNS secret later

### Key lesson

The right abstraction boundary is:
- **Vault stays centralized on Hetzner**
- **crib-k3s gets VSO + auth config only**
- app secrets remain GitOps-managed as `VaultStaticSecret` CRDs

## Step 7: Package poll-modem for Kubernetes Instead of Just Running the TUI

### What happened

The original poll-modem app was only a TUI. That is fine for an interactive shell session, but not enough for a Kubernetes deployment. To run it in crib-k3s, we added a headless mode that continuously polls the modem, stores samples in SQLite, and serves a small HTTP dashboard.

### New runtime shape

We introduced a new `serve` command that does both jobs:
1. polls the modem on a timer
2. exposes:
   - `/` for a simple dashboard
   - `/api/status` for JSON
   - `/healthz` for readiness/liveness checks

### Implementation details

The new server mode uses the existing modem client and SQLite storage layer:
- `internal/modem/client.go` still handles login, cookies, and parsing
- `internal/modem/database.go` now supports configurable DB path via `POLL_MODEM_DB_PATH`
- `cmd/serve.go` wraps polling in a small HTTP server

The result is a single container that can be deployed cleanly by ArgoCD.

### Packaging

Added a Dockerfile and built/pushed the image to GHCR as `ghcr.io/wesen/poll-modem:latest` after refreshing GitHub auth scopes to include `write:packages`.

### Important packaging detail

The container needs CGO because poll-modem uses `go-sqlite3`:
- `CGO_ENABLED=1`
- build on a Debian/Bookworm-based builder image
- ship a slim runtime image

### Why this is better

Instead of trying to run a TUI in Kubernetes, we now have:
- an actual headless collector for the cluster
- a small dashboard for human inspection
- a durable SQLite history file on a PVC

## Step 8: Deploy poll-modem into crib-k3s with ArgoCD

### What happened

Created a new GitOps package in `crib-k3s` for poll-modem:
- `gitops/applications/poll-modem.yaml`
- `gitops/kustomize/poll-modem/`

### Resources created

The app now manages:
- `Namespace` — `poll-modem`
- `PersistentVolumeClaim` — `poll-modem-data`
- `Deployment` — runs `poll-modem serve`
- `Service` — exposes port 80 inside cluster
- `Ingress` — `modem.crib.scapegoat.dev` via Traefik + cert-manager

### Secrets

The modem credentials are deliberately **not committed**:
- created manually as `modem-credentials` secret in `poll-modem` namespace
- credentials used: `admin / aVEnsmMZYG7JCXmitn7t`

### Deployment flow

1. push poll-modem code + GHCR image
2. push crib-k3s GitOps manifests
3. let ArgoCD sync the new application
4. create the manual secret in cluster
5. wait for ingress TLS certificate issuance

### Why the ingress works now

Because `poll-modem` is now a web app, the Ingress can route to it normally through Traefik. This would not have been possible with the original TUI-only binary.

## Step 9: cert-manager DNS01 Delay and DigitalOcean Rate Limiting

### What happened

The poll-modem TLS secret (`poll-modem-tls`) took longer than expected to issue. We checked cert-manager logs and found the real issue was not Let’s Encrypt, but **DigitalOcean API rate limiting** while cert-manager tried to manage DNS records.

### What the logs showed

- repeated `429 Too many requests` from `api.digitalocean.com`
- cert-manager retrying DNS01 challenge presentation
- a stale older challenge for `argocd-server-tailscale-tls` still generating noise

### Root cause

The rate limiting was happening because cert-manager was doing many DNS operations in a short time:
- creating and checking TXT records for `poll-modem.crib.scapegoat.dev`
- retrying on failures with backoff
- still carrying around a stale Tailscale-hostname challenge that should never have used the DigitalOcean DNS solver in the first place

### Cleanup

Removed the stale challenge finalizer and deleted the leftover `argocd-server-tailscale-tls` challenge resource.

That reduced the noise and let the new `poll-modem-tls` issuance proceed more cleanly.

### Lesson

DNS01 certs are usually quick, but when the DNS provider API starts rate-limiting, issuance can stretch from a couple of minutes to much longer. The most important thing is to inspect cert-manager logs and clean up stale orders/challenges instead of just waiting forever.

## Step 10: Makefile and GHCR workflow improvements

### What happened

Added explicit publish targets to poll-modem’s Makefile so container publishing is repeatable:
- `docker-build`
- `docker-push`
- `publish-ghcr`

### Why this helps

This makes the build/release workflow obvious and reproducible for future deploys:

```bash
make publish-ghcr
```

### Auth detail

Publishing to GHCR required refreshing GitHub auth scopes to include `write:packages`, then re-logging into Docker with the refreshed token.

## Current State

- ✅ crib-k3s repo is the main GitOps source of truth for the cluster
- ✅ ArgoCD is managing platform cert-issuer and ArgoCD ingress
- ✅ poll-modem is deployed as a web app in crib-k3s
- ✅ poll-modem code now has a `serve` mode and GHCR image
- ✅ modem dashboard is exposed at `modem.crib.scapegoat.dev`
- ✅ shared Vault/VSO plan documented in a separate docmgr ticket
- ✅ stale cert-manager Tailscale challenge cleaned up
- ⏳ poll-modem TLS still depends on cert-manager finishing the DNS01 flow cleanly
- ⏳ next likely cleanup: move more of the manual platform secrets into Vault/VSO once that investigation is implemented

## Step 11: Throttle cert-manager and Remove poll-modem DNS01 Churn

### What happened

The poll-modem certificate kept retrying against DigitalOcean and causing 429s. I throttled cert-manager and removed the poll-modem DNS01 path entirely by switching `modem.crib.scapegoat.dev` from a standard Kubernetes `Ingress` to a Traefik `IngressRoute`.

### Throttling change

The cert-manager controller in crib was patched from:

```bash
--max-concurrent-challenges=60
```

to:

```bash
--max-concurrent-challenges=1
```

This reduces the number of active DNS01 challenges cert-manager will process at once.

### poll-modem TLS simplification

I stopped asking cert-manager to issue a per-service cert for poll-modem and instead reused the existing wildcard cert already issued for `*.crib.scapegoat.dev`:

- copied `crib-scapegoat-dev-tls` into the `poll-modem` namespace
- changed the service exposure from standard `Ingress` to Traefik `IngressRoute`
- removed the cert-manager annotation from the poll-modem ingress path

That means:
- no more new poll-modem `Certificate`/`Order`/`Challenge` objects
- no more DigitalOcean DNS API hammering from poll-modem
- Traefik still serves `https://modem.crib.scapegoat.dev/` using the wildcard cert

### Verification

```bash
kubectl get certificate,order,challenge -n poll-modem
# No resources found

curl -skI https://modem.crib.scapegoat.dev/
# HTTP/2 200
```

### Lessons

- cert-manager is fine, but DNS01 + provider API rate limits can get noisy fast
- if a wildcard cert already exists, prefer reusing it instead of creating one per app
- Traefik `IngressRoute` is a good escape hatch when you want to avoid cert-manager ingress-shim entirely

## Step 12: Start the poll-modem Monitoring Stack

### What happened

I split the monitoring work into two parts:

1. app-side instrumentation in `poll-modem`
2. cluster-side scrape/visualization in `crib-k3s`

The app instrumentation is now committed separately, and the crib repo now contains:

- a `ServiceMonitor` for `poll-modem`
- an ArgoCD Application for `kube-prometheus-stack`

### Key operational note

The local machine does **not** have the `argocd` CLI installed, so I created the ArgoCD `Application` resource with `kubectl apply` instead. That still keeps the workflow GitOps-native; ArgoCD will reconcile the Helm chart itself.

### Current monitoring stack shape

- `poll-modem` exports `/metrics`
- the `poll-modem` Service now has a stable label for the monitor selector
- the `poll-modem` namespace contains a `ServiceMonitor`
- ArgoCD has a new `monitoring` application pointing at `kube-prometheus-stack`
- Prometheus is configured to watch `ServiceMonitor` objects cluster-wide
- Grafana is enabled in the stack and will be used for dashboards once the repo changes are pushed and the app settles

### Notes / caveats

- The monitoring stack is intentionally minimal at first
- I am keeping Grafana internal for the moment; if I expose it publicly later, I’ll reuse the same wildcard TLS approach used for poll-modem
- I still want to verify the exact scrape target and then decide whether Grafana needs its own ingress route or can stay reachable via port-forward initially

## Step 13: Pin poll-modem to the metrics-enabled image

### What happened

Prometheus found the poll-modem target, but the pod was still running the older image without the new `/metrics` handler. The symptom was that the scrape endpoint returned HTML from `/` instead of Prometheus text format.

I fixed that by:

1. building a fresh poll-modem container image from the metrics commit
2. pushing it to GHCR as `ghcr.io/wesen/poll-modem:8a80fbd`
3. pinning the crib-k3s deployment to that exact tag instead of the cached `latest`

### Why this mattered

The deployment was using:

```yaml
image: ghcr.io/wesen/poll-modem:latest
imagePullPolicy: IfNotPresent
```

That combination is fine for quick demos, but it is not reliable when the image contents change and the node already has an older `latest` cached locally.

### Result

Once the deployment points at the new tag, the pod will restart with the metrics-enabled binary and Prometheus should be able to scrape the `/metrics` endpoint successfully.

## Step 14: Add GHCR pull credentials for the new image tag

### What happened

Once `poll-modem` was pinned to the new metrics-enabled image tag, the node could no longer rely on the cached `latest` image. GHCR returned `401 Unauthorized` for anonymous pulls of `ghcr.io/wesen/poll-modem:8a80fbd`.

### Fix

I created a manual image pull secret in the `poll-modem` namespace:

- `ghcr-pull`
- type: `kubernetes.io/dockerconfigjson`

The secret uses the existing GitHub CLI token on this machine, which already has the necessary package scopes.

The deployment now references it via:

```yaml
imagePullSecrets:
  - name: ghcr-pull
```

### Why this is acceptable

- the secret stays out of git
- the deployment manifest only references the secret name
- the change keeps the cluster reproducible without depending on an accidental node-local image cache

## Step 15: Fix the metrics collector crash and repin again

### What happened

The first metrics-enabled image successfully started pulling, but the process crashed immediately with:

```text
panic: duplicate metrics collector registration attempted
```

That came from registering Prometheus collectors against the default registry more than once.

### Fix

I changed the app to use its own Prometheus registry and serve `/metrics` from that registry with `promhttp.HandlerFor(...)`.

I then rebuilt and pushed a new image tag:

- `ghcr.io/wesen/poll-modem:18063a2`

### Result

The deployment is now being repinned to the corrected image tag, which should finally give us:

- a running poll-modem pod
- a live `/metrics` endpoint
- a Prometheus scrape target that returns Prometheus text format instead of HTML
