#!/bin/bash
# Create a k3s VM on Proxmox with cloud-init bootstrap
# Usage: ./create-k3s-vm.sh [VM_ID] [VM_NAME]
#
# Prerequisites:
#   - Ubuntu Noble cloud image in /var/lib/vz/template/iso/
#   - cloud-init.yaml uploaded to /var/lib/vz/snippets/
#   - Proxmox vmbr0 bridged to physical NIC

set -euo pipefail

VM_ID=${1:-301}
VM_NAME=${2:-k3s-server}
MEMORY=${3:-8192}
CORES=${4:-4}
DISK_SIZE=${5:-30G}
BRIDGE=${6:-vmbr0}
TEMPLATE=${7:-noble-server-cloudimg-amd64.img}
SNIPPET=${8:-cloud-init-k3s.yaml}

echo "Creating VM ${VM_ID} (${VM_NAME})..."
echo "  Memory: ${MEMORY}MB, Cores: ${CORES}, Disk: ${DISK_SIZE}"
echo "  Network: ${BRIDGE}, Template: ${TEMPLATE}"

# Check template exists
if ! ssh root@pve "test -f /var/lib/vz/template/iso/${TEMPLATE}"; then
    echo "ERROR: Template not found: /var/lib/vz/template/iso/${TEMPLATE}"
    echo "Download with: ssh root@pve 'cd /var/lib/vz/template/iso && wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img'"
    exit 1
fi

# Check snippet exists
if ! ssh root@pve "test -f /var/lib/vz/snippets/${SNIPPET}"; then
    echo "ERROR: Cloud-init snippet not found: /var/lib/vz/snippets/${SNIPPET}"
    echo "Upload with: scp cloud-init.yaml root@pve:/var/lib/vz/snippets/${SNIPPET}"
    exit 1
fi

# Create VM
ssh root@pve "qm create ${VM_ID} \
  --name ${VM_NAME} \
  --memory ${MEMORY} \
  --cores ${CORES} \
  --cpu host \
  --net0 virtio,bridge=${BRIDGE} \
  --bios ovmf \
  --machine q35 \
  --agent enabled=1"

# Import disk
echo "Importing disk image..."
ssh root@pve "qm importdisk ${VM_ID} /var/lib/vz/template/iso/${TEMPLATE} local-lvm"

# Configure VM
echo "Configuring VM..."
ssh root@pve "qm set ${VM_ID} \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:vm-${VM_ID}-disk-0 \
  --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=0 \
  --ide2 local-lvm:cloudinit \
  --boot order=scsi0 \
  --serial0 socket \
  --vga serial0 \
  --ciuser ubuntu \
  --sshkeys /root/.ssh/authorized_keys \
  --ipconfig0 ip=dhcp \
  --cicustom user=local:snippets/${SNIPPET}"

# Resize disk
echo "Resizing disk to ${DISK_SIZE}..."
ssh root@pve "qm resize ${VM_ID} scsi0 ${DISK_SIZE}"

# Start VM
echo "Starting VM..."
ssh root@pve "qm start ${VM_ID}"

echo ""
echo "VM ${VM_ID} created and started!"
echo ""
echo "Cloud-init is running. Watch progress with:"
echo "  ssh root@pve 'qm terminal ${VM_ID}'"
echo ""
echo "After cloud-init completes (~2-3 min):"
echo "  1. Find IP: ssh root@pve 'nmap -sn 192.168.0.0/24 | grep -B1 BC:24'"
echo "  2. SSH in:  ssh ubuntu@<IP>"
echo "  3. Check:   cat /etc/motd"
echo "  4. Join tailscale: sudo tailscale up --auth-key=<your-key>"
echo "  5. Get kubeconfig: scp ubuntu@<IP>:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml"
echo ""
