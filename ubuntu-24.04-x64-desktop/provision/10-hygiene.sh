#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

MARKER="/var/lib/provision/10-hygiene.done"
LOG="/var/log/provision-10-hygiene.log"

mkdir -p /var/lib/provision
exec > >(tee -a "$LOG") 2>&1

if [[ -f "$MARKER" ]]; then
  echo "[10-hygiene] already applied: $MARKER"
  exit 0
fi

echo "[10-hygiene] start: $(date -Is)"

# --- apt reliability / base packages ---
echo "[10-hygiene] apt update/dist-upgrade"
apt-get update -y
apt-get dist-upgrade -y

echo "[10-hygiene] install baseline packages"
apt-get install -y --no-install-recommends \
  ca-certificates curl wget gnupg lsb-release \
  unzip zip jq git \
  software-properties-common apt-transport-https \
  build-essential \
  python3 python3-venv python3-pip \
  bash-completion vim tmux \
  openssh-client

# --- time sync ---
echo "[10-hygiene] enable NTP"
timedatectl set-ntp true || true

# --- sudoers sanity (you already set NOPASSWD in autoinstall; enforce perms) ---
if [[ -f /etc/sudoers.d/syselement ]]; then
  chmod 0440 /etc/sudoers.d/syselement || true
fi

# --- journald trimming (best effort) ---
echo "[10-hygiene] journal cleanup"
journalctl --rotate || true
journalctl --vacuum-time=7d || true

# --- apt cleanup ---
echo "[10-hygiene] apt cleanup"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*

# --- cloud-init reset for templating (optional but recommended) ---
# If you rely on cloud-init on clones, this makes next boot behave like first boot.
if command -v cloud-init >/dev/null 2>&1; then
  echo "[10-hygiene] cloud-init clean"
  cloud-init clean --logs || true
  rm -rf /var/lib/cloud/* || true
fi

echo "[10-hygiene] done: $(date -Is)"
touch "$MARKER"
