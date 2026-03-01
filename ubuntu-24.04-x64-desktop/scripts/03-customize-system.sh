#!/usr/bin/env bash
#
# Customize Ubuntu 24.04 Desktop
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

USER_NAME="syselement"
SCRIPT_NAME="customize-system"
LOG_PREFIX="[${SCRIPT_NAME}]"
LOG_FILE="/var/log/${SCRIPT_NAME}.log"

# --- ANSI Colors for output ---
if [[ -t 1 ]]; then
  t_bold=$'\e[1m'; t_dim=$'\e[2m'
  t_green=$'\e[32m'; t_yellow=$'\e[33m'; t_red=$'\e[31m'
  t_reset=$'\e[0m'
else
  t_bold=""; t_dim=""; t_green=""; t_yellow=""; t_red=""; t_reset=""
fi

# --- Logging ---
if ! touch "$LOG_FILE" &>/dev/null; then
  LOG_FILE="$HOME/${SCRIPT_NAME}.log"
fi

_ts() { date +'%F %T'; }
_strip_ansi() { sed -r 's/\x1B\[[0-9;]*[[:alpha:]]//g'; }

log() {
  local msg="$*"
  local ts
  ts="$(_ts)"
  # Console (colored if enabled)
  printf '%s %s %b\n' "[$ts]" "$LOG_PREFIX" "$msg" >&2
  # Log file (stripped of ANSI codes)
  printf '%s %s %s\n' "[$ts]" "$LOG_PREFIX" "$(printf '%b' "$msg" | _strip_ansi)" >> "$LOG_FILE"
}

info()  { log "${t_dim}INFO${t_reset}  $*"; }
ok()    { log "${t_green}${t_bold}OK${t_reset}    $*"; }
warn()  { log "${t_yellow}${t_bold}WARN${t_reset}  $*"; }
error() { log "${t_red}${t_bold}ERROR${t_reset} $*"; }
die()   { error "$*"; exit 1; }

# --- Helpers ---
run_user_gsettings_try() {
  local schema="$1"
  local key="$2"
  local value="$3"
  sudo -u "$USER_NAME" -H dbus-run-session -- bash -lc \
    "gsettings set ${schema} ${key} ${value}" >/dev/null 2>&1 || true
}

# --- Repository setup ---
ensure_fastfetch_ppa() {
  local ppa="ppa:zhangsongcui3371/fastfetch"
  if grep -Rqs "zhangsongcui3371/fastfetch" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    info "fastfetch PPA already present"
    return
  fi

  if add-apt-repository --yes "$ppa" >/dev/null 2>&1; then
    ok "added fastfetch PPA"
  else
    warn "failed to add fastfetch PPA; fastfetch may not be available"
  fi
}

# --- Package installation ---
install_packages() {
  local pkgs=(
    aptitude
    bash-completion
    bat
    btop
    build-essential
    ca-certificates
    curl
    duf
    eza
    fastfetch
    filezilla
    flameshot
    flatpak
    fonts-noto-color-emoji
    fzf
    gdu
    git
    gnome-shell-extensions
    gnome-shell-extension-manager
    gnome-tweaks
    gnupg
    gping
    htop
    iftop
    imagemagick
    ipcalc
    iperf3
    jq
    lsb-release
    nano
    net-tools
    nload
    nmap
    npm
    pipx
    plocate
    software-properties-common
    speedtest-cli
    sshpass
    sysstat
    terminator
    tmux
    tor
    tree
    unzip
    ugrep
    vim
    vlc
    wget
    xclip
    zsh
  )

  info "installing ${#pkgs[@]} packages"
  apt-get install -y "${pkgs[@]}"
  ok "package installation completed"
}

# --- Fonts ---
install_jetbrainsmono_nerd_font() {
  sudo -u "$USER_NAME" -H bash -lc '
    set -euo pipefail
    mkdir -p "$HOME/.local/share/fonts"
    cd "$HOME/.local/share/fonts"
    curl -fL -o JetBrainsMono.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    unzip -o JetBrainsMono.zip
    rm -f JetBrainsMono.zip
    fc-cache -fv
  '
}

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

# --- Connectivity checks ---
info "checking internet and DNS"
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

# --- Update system ---
info "apt update/dist-upgrade"
apt-get update -y
apt-get dist-upgrade -y
ok "apt update/dist-upgrade completed"

# --- APT prerequisites ---
info "ensuring repository prerequisites"
apt-get install -y software-properties-common ca-certificates curl gnupg lsb-release

# --- Fastfetch PPA ---
info "ensuring fastfetch repository"
ensure_fastfetch_ppa

# --- Refresh APT cache ---
info "apt update after repository changes"
apt-get update -y

# --- Install requested tools ---
install_packages

# --- Install Nerd Font ---
info "installing JetBrainsMono Nerd Font"
install_jetbrainsmono_nerd_font
ok "JetBrainsMono Nerd Font installed"

# --- Post-install tweaks ---
info "updating locate database (best effort)"
updatedb || true

# --- GNOME and Dock customization ---
info "applying GNOME preferences (best effort)"

run_user_gsettings_try org.gnome.desktop.interface color-scheme "'prefer-dark'"
run_user_gsettings_try org.gnome.desktop.interface gtk-theme "'Yaru-dark'"
run_user_gsettings_try org.gnome.desktop.interface show-battery-percentage "true"
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock extend-height "false"
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock dash-max-icon-size "40"
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock click-action "'minimize'"

# --- Power / lockscreen: disable blank + lock ---
run_user_gsettings_try org.gnome.desktop.session idle-delay "uint32 0"
run_user_gsettings_try org.gnome.desktop.screensaver lock-enabled "false"
run_user_gsettings_try org.gnome.desktop.screensaver lock-delay "uint32 0"
run_user_gsettings_try org.gnome.desktop.notifications show-in-lock-screen "false"
run_user_gsettings_try org.gnome.desktop.screensaver ubuntu-lock-on-suspend "false"
run_user_gsettings_try org.gnome.system.location enabled "false"
ok "GNOME preferences applied"

info "setting GNOME favorites (best effort)"
sudo -u "$USER_NAME" -H dbus-run-session -- bash -lc \
  "gsettings set org.gnome.shell favorite-apps \"[
    'firefox_firefox.desktop',
    'org.gnome.Nautilus.desktop',
    'terminator.desktop',
    'sublime_text.desktop'
  ]\" || true"
ok "GNOME favorites set"

# --- Cleanup and update repositories ---
info "cleanup"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*
apt-get -y update >/dev/null 2>&1 || true
ok "cleanup completed"

# --- Manual SSH key setup hint ---
echo "# --- Manual SSH private key setup (run as ${USER_NAME}) ---"
echo "# cat > \$HOME/.ssh/id_ed25519"
echo "# (paste private key content, then Ctrl-D)"
echo "# chmod 600 \$HOME/.ssh/*"
echo "# eval \"\$(ssh-agent -s)\" && ssh-add \$HOME/.ssh/id_ed25519"

END_TS="$(date +%s)"
ELAPSED="$((END_TS - START_TS))"
info "done: $(date -Is)"
info "elapsed: $(printf '%02d:%02d:%02d' "$((ELAPSED / 3600))" "$((ELAPSED % 3600 / 60))" "$((ELAPSED % 60))")"
info "log file: ${LOG_FILE}"

echo "################################"
echo "# Customize System Complete"
echo "################################"
