#!/usr/bin/env bash
#
# Customize Ubuntu 24.04 Desktop
#
# Set up additional packages and customize system settings
# Made for Ubuntu 24.04 Desktop
#
# Runs as root. User-scoped settings are applied via sudo -u.
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
USER_NAME="syselement"
SCRIPT_NAME="customize-system"

# --- ANSI Colors for output ---
if [[ -t 1 ]]; then
  t_bold=$'\e[1m'; t_dim=$'\e[2m'
  t_green=$'\e[32m'; t_yellow=$'\e[33m'; t_red=$'\e[31m'
  t_reset=$'\e[0m'
else
  t_bold=""; t_dim=""; t_green=""; t_yellow=""; t_red=""; t_reset=""
fi

# --- Logging ---
LOG_PREFIX="[${SCRIPT_NAME}]"
LOG_FILE="/var/log/${SCRIPT_NAME}.log"
if ! touch "$LOG_FILE" &>/dev/null; then
  LOG_FILE="$HOME/${SCRIPT_NAME}.log"
fi

_ts() { date +'%F %T'; }
_strip_ansi() { sed -r 's/\x1B\[[0-9;]*[[:alpha:]]//g'; }

log() {
  local msg="$*"
  local ts; ts="$(_ts)"
  # Console (colored if enabled)
  printf '%s %s %b\n' "[$ts]" "$LOG_PREFIX" "$msg" >&2
  # File (plain, strip ANSI)
  printf '%s %s %s\n' "[$ts]" "$LOG_PREFIX" \
    "$(printf '%b' "$msg" | _strip_ansi)" >> "$LOG_FILE"
}
info()  { log "${t_dim}INFO${t_reset}  $*"; }
ok()    { log "${t_green}${t_bold}OK${t_reset}    $*"; }
warn()  { log "${t_yellow}${t_bold}WARN${t_reset}  $*"; }
error() { log "${t_red}${t_bold}ERROR${t_reset} $*"; }
die()   { error "$*"; exit 1; }

# ---------------------------
echo "################################"
echo "# Customize System"
echo "################################"
info "start: $(date -Is)"
START_TS="$(date +%s)"

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
ARCH="$(dpkg --print-architecture)"
info "distro codename=${CODENAME} arch=${ARCH}"

# --- must be root ---
[[ "${EUID}" -eq 0 ]] || die "must run as root"

if id "$USER_NAME" >/dev/null 2>&1; then
  ok "running user-scoped commands as: ${USER_NAME}"
else
  die "user not found: ${USER_NAME}"
fi

# ---------------------------
# 1) Internet connectivity and DNS check
# ---------------------------
info "check internet connectivity"

if ping -c 1 -W 1 1.1.1.1 &>/dev/null || ping -c 1 -W 1 8.8.8.8 &>/dev/null || ping -c 1 -W 1 9.9.9.9 &>/dev/null; then
  ok "Internet connected (ICMP ping)"
else
  warn "Internet not connected (ICMP ping failed)"
fi

if getent hosts ubuntu.com >/dev/null 2>&1; then
  ok "DNS resolution OK (ubuntu.com)"
else
  warn "DNS resolution FAILED (ubuntu.com)"
fi

# ---------------------------
# 2) APT update/upgrade
# ---------------------------
info "apt update/dist-upgrade"
apt-get update -y
apt-get dist-upgrade -y
ok "apt update/dist-upgrade completed"

# ---------------------------
# 3) Install desktop packages
# ---------------------------
info "install desktop packages"
apt-get install -y --no-install-recommends \
  gnome-tweaks \
  gnome-shell-extensions \
  dconf-cli \
  dbus-x11 \
  papirus-icon-theme \
  fonts-firacode \
  xclip
ok "desktop packages installed"

# ---------------------------
# 4) GNOME preferences
# ---------------------------
info "apply GNOME preferences (dark mode, icons, dock)"
run_user_gsettings_try org.gnome.desktop.interface color-scheme 'prefer-dark'
run_user_gsettings_try org.gnome.desktop.interface gtk-theme 'Yaru-dark'
run_user_gsettings_try org.gnome.desktop.interface icon-theme 'Papirus'
ok "GNOME preferences applied (best effort)"

# ---------------------------
# 5) Dock/Toolbar
# ---------------------------
info "configure dock (best effort)"
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock extend-height false
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 40
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock show-mounts false
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock show-trash false
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock click-action 'minimize'
run_user_gsettings_try org.gnome.desktop.interface show-battery-percentage true
run_user_gsettings_try org.gnome.desktop.interface enable-hot-corners false
ok "dock settings applied (best effort)"

# Favorites (best effort)
info "set GNOME favorites (best effort)"
sudo -u "$USER_NAME" -H dbus-run-session -- bash -lc \
  "gsettings set org.gnome.shell favorite-apps \"[
    'firefox_firefox.desktop',
    'org.gnome.Terminal.desktop',
    'code.desktop',
    'org.gnome.Nautilus.desktop'
  ]\" || true"
ok "favorites set (best effort)"

# ---------------------------
# 6) User shell basics
# ---------------------------
info "user shell defaults"
sudo -u "$USER_NAME" -H bash -lc "git config --global init.defaultBranch main || true"
sudo -u "$USER_NAME" -H bash -lc "git config --global pull.rebase false || true"
ok "git defaults set (best effort)"

# ---------------------------
# 7) Cleanup and reboot
# ---------------------------
info "cleanup"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*
ok "cleanup completed"

info "done: $(date -Is)"
END_TS="$(date +%s)"
ELAPSED="$((END_TS - START_TS))"
info "$(printf 'elapsed: %02d:%02d:%02d' "$((ELAPSED / 3600))" "$((ELAPSED % 3600 / 60))" "$((ELAPSED % 60))")"
info "LOG: ${LOG_FILE}"

echo "################################"
echo "# Customize System Complete"
warn "rebooting in 10 seconds ..."
echo "################################"
sleep 10
sync
shutdown -r now



################## --- OLD CONTENT BELOW (FROM provision_system.sh) --- ##################

# --- Ansible PPA ---
echo "[customize-system] configure ansible repo"
if ! grep -Rqs "^deb .*\bansible/ansible\b" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  add-apt-repository --yes ppa:ansible/ansible
fi

# --- VS Code repo ---
echo "[customize-system] configure vscode repo"
if [[ ! -f /usr/share/keyrings/microsoft.gpg ]]; then
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg >/dev/null
  sudo chmod a+r /usr/share/keyrings/microsoft.gpg
fi
cat > /etc/apt/sources.list.d/vscode.sources <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF
sudo chmod a+r /etc/apt/sources.list.d/vscode.sources

# --- Docker Engine repo ---
echo "[customize-system] configure docker repo"
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo chmod a+r /etc/apt/sources.list.d/docker.sources

# --- OpenTofu repo ---
echo "[customize-system] configure opentofu repo"
if [[ ! -f /etc/apt/keyrings/opentofu.gpg ]]; then
  curl -fsSL https://get.opentofu.org/opentofu.gpg | sudo tee /etc/apt/keyrings/opentofu.gpg >/dev/null
  curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey | sudo gpg --no-tty --batch --dearmor -o /etc/apt/keyrings/opentofu-repo.gpg >/dev/null
  sudo chmod a+r /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg
fi
cat > /etc/apt/sources.list.d/opentofu.list <<EOF
deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
deb-src [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main
EOF
sudo chmod a+r /etc/apt/sources.list.d/opentofu.list

# --- Packer - HashiCorp repo ---
echo "[customize-system] configure hashicorp repo"
if [[ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]]; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
fi
cat > /etc/apt/sources.list.d/hashicorp.list <<EOF
deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main
EOF
sudo chmod a+r /etc/apt/sources.list.d/hashicorp.list

# --- Install toolchain ---
echo "[customize-system] apt update (after adding repos)"
apt-get update -y
echo "[customize-system] install toolchain packages"
apt-get install -y --no-install-recommends \
  ansible \
  code \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  packer \
  tofu

