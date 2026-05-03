#!/usr/bin/env bash
# Validate crib-k3s after a reboot.
#
# Runs from the operator workstation. It SSHes to the k3s VM and checks:
# - SSH reachability
# - k3s service active
# - node Ready
# - core pods Running/Completed
# - Traefik pod, CRDs, IngressRoutes
# - ArgoCD Applications synced/healthy
# - legacy k3s-tailscale-proxy disabled/inactive and no stale DNAT rules
# - external crib URLs respond with expected HTTP classes
#
# Usage:
#   ./01-post-reboot-validate.sh
#   K3S_HOST=100.67.90.12 ./01-post-reboot-validate.sh
#   ./01-post-reboot-validate.sh --wait

set -euo pipefail

K3S_HOST="${K3S_HOST:-100.67.90.12}"
K3S_USER="${K3S_USER:-ubuntu}"
SSH_TARGET="${K3S_USER}@${K3S_HOST}"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
WAIT_MODE=false
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-600}"
WAIT_INTERVAL_SECONDS="${WAIT_INTERVAL_SECONDS:-10}"

URLS=(
  "https://argocd.crib.scapegoat.dev/|200"
  "https://watch.crib.scapegoat.dev/|302"
  "https://grafana.crib.scapegoat.dev/|302"
  "https://modem.crib.scapegoat.dev/|200"
)

for arg in "$@"; do
  case "$arg" in
    --wait) WAIT_MODE=true ;;
    -h|--help)
      sed -n '1,35p' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
fail() { printf '[%s] FAIL: %s\n' "$(date -Is)" "$*" >&2; exit 1; }

ssh_k3s() {
  ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$@"
}

wait_for_ssh() {
  local start now
  start=$(date +%s)
  while true; do
    if ssh_k3s 'true' >/dev/null 2>&1; then
      log "SSH reachable: $SSH_TARGET"
      return 0
    fi
    if ! $WAIT_MODE; then
      fail "SSH not reachable: $SSH_TARGET"
    fi
    now=$(date +%s)
    if (( now - start >= WAIT_TIMEOUT_SECONDS )); then
      fail "Timed out waiting for SSH after ${WAIT_TIMEOUT_SECONDS}s: $SSH_TARGET"
    fi
    log "Waiting for SSH: $SSH_TARGET"
    sleep "$WAIT_INTERVAL_SECONDS"
  done
}

check_remote() {
  log "Running remote k3s validation on $SSH_TARGET"
  ssh_k3s 'bash -s' <<'REMOTE'
set -euo pipefail

fail() { echo "REMOTE FAIL: $*" >&2; exit 1; }

echo "--- host"
hostname
uptime

echo "--- k3s service"
[[ "$(sudo systemctl is-active k3s.service)" == "active" ]] || fail "k3s.service is not active"
sudo systemctl status k3s.service --no-pager | sed -n '1,18p'

echo "--- k3s config"
sudo cat /etc/rancher/k3s/config.yaml
if sudo grep -q '^disable-cloud-controller: true$' /etc/rancher/k3s/config.yaml; then
  fail "disable-cloud-controller is still enabled; expected embedded CCM enabled"
fi
if sudo grep -q '^  - traefik$' /etc/rancher/k3s/config.yaml; then
  fail "traefik is disabled in k3s config"
fi

echo "--- node readiness"
sudo kubectl wait --for=condition=Ready node/k3s-server --timeout=120s
sudo kubectl get nodes -o wide

echo "--- pod health"
sudo kubectl get pods -A
bad_pods=$(sudo kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null || true)
if [[ -n "$bad_pods" ]]; then
  echo "$bad_pods" >&2
  fail "Found pods not Running/Succeeded"
fi

echo "--- cloud controller RBAC"
can_i=$(sudo kubectl auth can-i get configmap/extension-apiserver-authentication --as=k3s-cloud-controller-manager -n kube-system)
[[ "$can_i" == "yes" ]] || fail "k3s-cloud-controller-manager cannot read extension-apiserver-authentication"

echo "--- traefik"
sudo kubectl get helmchart,helmchartconfig -A | grep -E 'traefik|NAMESPACE'
sudo kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik -o wide | grep -q 'Running' || fail "Traefik pod not Running"
sudo kubectl get crd ingressroutes.traefik.io >/dev/null || fail "IngressRoute CRD missing"
sudo kubectl get ingressroute -A
route_count=$(sudo kubectl get ingressroute -A --no-headers | wc -l | tr -d ' ')
[[ "$route_count" -ge 5 ]] || fail "Expected at least 5 IngressRoutes, got $route_count"
argocd_ingress_ip=$(sudo kubectl get ingress argocd-server-crib -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
[[ "$argocd_ingress_ip" == "100.67.90.12" ]] || fail "argocd-server-crib Ingress status IP is '$argocd_ingress_ip', expected 100.67.90.12"

echo "--- ArgoCD apps"
sudo kubectl get application -n argocd -o wide
not_synced=$(sudo kubectl get application -n argocd --no-headers | awk '$2 != "Synced" {print}' || true)
if [[ -n "$not_synced" ]]; then
  echo "$not_synced" >&2
  fail "Some ArgoCD apps are not Synced"
fi
unhealthy=$(sudo kubectl get application -n argocd --no-headers | awk '$3 != "Healthy" {print}' || true)
if [[ -n "$unhealthy" ]]; then
  echo "$unhealthy" >&2
  fail "Some ArgoCD apps are unhealthy"
fi

echo "--- legacy DNAT proxy"
proxy_enabled=$(sudo systemctl is-enabled k3s-tailscale-proxy.service 2>/dev/null || true)
proxy_active=$(sudo systemctl is-active k3s-tailscale-proxy.service 2>/dev/null || true)
echo "k3s-tailscale-proxy enabled=$proxy_enabled active=$proxy_active"
[[ "$proxy_enabled" == "disabled" ]] || fail "k3s-tailscale-proxy.service should be disabled"
[[ "$proxy_active" == "inactive" ]] || fail "k3s-tailscale-proxy.service should be inactive"
if sudo iptables -t nat -L PREROUTING -n --line-numbers | grep -E '100\.67\.90\.12|32277|32241'; then
  fail "Found stale DNAT proxy rules"
fi

echo "--- listeners"
sudo ss -tlnp | grep -E ':80 |:443 ' || true

echo "REMOTE OK"
REMOTE
}

check_urls() {
  log "Checking external crib URLs"
  local item url expected code
  for item in "${URLS[@]}"; do
    url="${item%%|*}"
    expected="${item##*|}"
    code=$(curl -skL -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 20 "$url" || true)
    # Use non-following code as primary for redirects, because Jellyfin/Grafana intentionally redirect.
    code=$(curl -skI -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 20 "$url" || true)
    log "$url -> HTTP $code (expected $expected)"
    [[ "$code" == "$expected" ]] || fail "Unexpected HTTP code for $url: got $code expected $expected"
  done
}

run_once() {
  wait_for_ssh || return $?
  check_remote || return $?
  check_urls || return $?
}

main() {
  if ! $WAIT_MODE; then
    run_once
    log "POST-REBOOT VALIDATION OK"
    return 0
  fi

  local start now attempt rc
  start=$(date +%s)
  attempt=1
  while true; do
    log "Validation attempt $attempt"
    set +e
    run_once
    rc=$?
    set -e
    if [[ "$rc" -eq 0 ]]; then
      log "POST-REBOOT VALIDATION OK"
      return 0
    fi
    now=$(date +%s)
    if (( now - start >= WAIT_TIMEOUT_SECONDS )); then
      fail "Timed out waiting for full validation after ${WAIT_TIMEOUT_SECONDS}s"
    fi
    log "Validation attempt $attempt failed with rc=$rc; retrying in ${WAIT_INTERVAL_SECONDS}s"
    attempt=$((attempt + 1))
    sleep "$WAIT_INTERVAL_SECONDS"
  done
}

main "$@"
