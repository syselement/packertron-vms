#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Update and upgrade the system
echo "[update] apt update / dist-upgrade"
apt-get update -y
apt-get dist-upgrade -y

# Install baseline tools
echo "[update] install baseline tools"
apt-get install -y --no-install-recommends \
  net-tools unzip

# VMware tools for Desktop guests: open-vm-tools + desktop integration
echo "[update] install VMware tools"
apt-get install -y --no-install-recommends \
  open-vm-tools open-vm-tools-desktop || apt-get install -y --no-install-recommends open-vm-tools
if systemctl list-unit-files | grep -q '^open-vm-tools\.service'; then
  systemctl enable --now open-vm-tools.service
fi

echo "[update] done updating system and installing necessary packages"
