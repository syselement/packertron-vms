#!/usr/bin/env bash
#
# First-boot orchestration for physical Ubuntu workstations.
#

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
)"

STATE_DIR="/var/lib/packertron-bootstrap"
LOG_FILE="/var/log/packertron-bootstrap.log"
LOCK_FILE="/run/lock/packertron-bootstrap.lock"

[[ "$EUID" -eq 0 ]] || {
  echo "ERROR: run as root" >&2
  exit 1
}

mkdir -p "$STATE_DIR"
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Another bootstrap execution is already running"
  exit 0
fi

if [[ -f "$STATE_DIR/complete" ]]; then
  echo "Bare-metal bootstrap already completed"
  exit 0
fi

run_step() {
  local name="$1"
  local script="$2"
  local marker="$STATE_DIR/${name}.done"

  if [[ -f "$marker" ]]; then
    echo "SKIP: ${name} already completed"
    return
  fi

  echo "RUN: ${name}"

  REBOOT_AT_END=false \
    bash "$SCRIPT_DIR/$script"

  touch "$marker"
  echo "DONE: ${name}"
}

# Intentionally omitted:
# 00-update-system.sh  - VMware-specific
# 01-cleanup-system.sh - template hygiene, unsafe/unnecessary here

run_step "02-provision-system" "02-provision-system.sh"
run_step "03-customize-system" "03-customize-system.sh"

touch "$STATE_DIR/complete"

echo "Bare-metal bootstrap completed successfully"
echo "Log: $LOG_FILE"

# Return control to cloud-init, then reboot after cloud-init-final completes.
systemd-run \
  --unit=packertron-bootstrap-reboot \
  --on-active=2m \
  /usr/bin/systemctl reboot
