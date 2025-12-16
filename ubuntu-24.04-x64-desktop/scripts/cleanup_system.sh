#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[cleanup] apt autoremove/clean"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*


echo "[cleanup] journal cleanup (best effort)"
journalctl --rotate || true
journalctl --vacuum-time=1s || true

echo "[cleanup] reset machine-id (for templating/cloning)"
truncate -s 0 /etc/machine-id /var/lib/dbus/machine-id || true

echo "[cleanup] remove temp files and history"
rm -rf /tmp/* /var/tmp/* || true

if command -v cloud-init &> /dev/null; then
  echo "[cleanup] cloud-init clean"
  cloud-init clean --logs || true
  rm -rf /var/lib/cloud/* || true
fi

echo "[cleanup] done"
