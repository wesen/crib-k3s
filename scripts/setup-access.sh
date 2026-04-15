#!/bin/bash
# Post-bootstrap setup: join Tailscale, get kubeconfig
# Usage: ./setup-access.sh <VM_IP> [tailscale-auth-key]
#
# After cloud-init completes, run this to:
#   1. Join the VM to your Tailscale tailnet
#   2. Pull kubeconfig configured for Tailscale DNS

set -euo pipefail

VM_IP=${1:?"Usage: $0 <VM_IP> [tailscale-auth-key]"}
TS_KEY=${2:-}

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "VM IP: ${VM_IP}"

# --- Join Tailscale ---
if [ -n "$TS_KEY" ]; then
    echo "Joining Tailscale..."
    ssh $SSH_OPTS ubuntu@${VM_IP} "sudo tailscale up --auth-key=${TS_KEY}" 2>/dev/null
    sleep 3

    TS_IP=$(ssh $SSH_OPTS ubuntu@${VM_IP} "tailscale ip -4" 2>/dev/null)
    TS_HOST=$(ssh $SSH_OPTS ubuntu@${VM_IP} "tailscale status | grep $(tailscale ip -4 2>/dev/null || echo $TS_IP) | awk '{print \$2}'" 2>/dev/null || echo "unknown")

    echo "Tailscale IP: ${TS_IP}"
    echo "Tailscale hostname: ${TS_HOST}"
else
    echo "No Tailscale auth key provided. Join manually:"
    echo "  ssh ubuntu@${VM_IP} 'sudo tailscale up'"
    TS_IP=""
fi

# --- Get ArgoCD password ---
echo ""
echo "Getting ArgoCD password..."
ARGO_PASS=$(ssh $SSH_OPTS ubuntu@${VM_IP} "sudo cat /root/argocd-password" 2>/dev/null || echo "not found")
echo "ArgoCD admin password: ${ARGO_PASS}"

# --- Get kubeconfig ---
if [ -n "$TS_IP" ]; then
    echo ""
    echo "Pulling kubeconfig (Tailscale)..."
    ssh $SSH_OPTS ubuntu@${TS_IP} "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig.yaml 2>/dev/null
    # Replace 127.0.0.1 with Tailscale DNS name
    TS_HOSTNAME=$(ssh $SSH_OPTS ubuntu@${TS_IP} "hostname" 2>/dev/null)
    sed -i "s/127.0.0.1/${TS_HOSTNAME}/" kubeconfig.yaml
    echo "Saved: ./kubeconfig.yaml (server: https://${TS_HOSTNAME}:6443)"

    # Verify
    echo ""
    echo "Verifying cluster access..."
    KUBECONFIG=./kubeconfig.yaml kubectl get nodes
else
    echo ""
    echo "Pulling kubeconfig (local IP)..."
    ssh $SSH_OPTS ubuntu@${VM_IP} "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig.yaml 2>/dev/null
    sed -i "s/127.0.0.1/${VM_IP}/" kubeconfig.yaml
    echo "Saved: ./kubeconfig.yaml (server: https://${VM_IP}:6443)"
    echo "NOTE: This only works from the Proxmox host. Join Tailscale for direct access."
fi

echo ""
echo "Done! Next steps:"
echo "  export KUBECONFIG=\$PWD/kubeconfig.yaml"
echo "  kubectl get pods -A"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  # Open https://localhost:8080 (admin / ${ARGO_PASS})"
