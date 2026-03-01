#!/usr/bin/env bash
#
# Customize Ubuntu 24.04 Desktop
#
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

USER_NAME="syselement"
SCRIPT_NAME="customize-system"
LOG_PREFIX="[${SCRIPT_NAME}]"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/var/log/${SCRIPT_NAME}-${RUN_ID}.log"

# --- Logging setup ---
# --- ANSI Colors for console output ---
if [[ -t 1 ]]; then
  t_bold=$'\e[1m'; t_dim=$'\e[2m'
  t_green=$'\e[32m'; t_yellow=$'\e[33m'; t_red=$'\e[31m'
  t_reset=$'\e[0m'
else
  t_bold=""; t_dim=""; t_green=""; t_yellow=""; t_red=""; t_reset=""
fi

# Console keeps ANSI colors, log file stores ANSI-stripped output.
exec > >(tee >(sed -u -r 's/\x1B\[[0-9;]*[[:alpha:]]//g' > "$LOG_FILE")) 2>&1

_ts() { date +'%F %T'; }
log() {
  local msg="$*"
  local ts
  ts="$(_ts)"
  printf '%s %s %b\n' "[$ts]" "$LOG_PREFIX" "$msg"
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

enable_system_monitor_extension() {
  sudo -u "$USER_NAME" -H dbus-run-session -- bash -lc '
    set -euo pipefail
    if ! command -v gnome-extensions >/dev/null 2>&1; then
      exit 0
    fi

    ext_uuid="$(gnome-extensions list | grep -E "system-monitor|SystemMonitor" | head -n1 || true)"
    if [[ -z "$ext_uuid" ]]; then
      ext_uuid="system-monitor@gnome-shell-extensions.gcampax.github.com"
    fi

    gnome-extensions enable "$ext_uuid" >/dev/null 2>&1 || true
  ' || true
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

# --- Specific tools ---
install_terminator_and_config() {
  if sudo -u "$USER_NAME" -H bash -lc '
    dpkg -s terminator >/dev/null 2>&1 && \
    [[ -f "$HOME/.config/terminator/config" ]] && \
    grep -q "font = JetBrainsMono Nerd Font Mono 16" "$HOME/.config/terminator/config" && \
    grep -q "scrollback_infinite = True" "$HOME/.config/terminator/config"
  '; then
    info "Terminator already configured, skipping"
    return
  fi

  apt-get install -y terminator

  sudo -u "$USER_NAME" -H bash -lc '
    set -euo pipefail
    rm -f "$HOME/.config/terminator/config"
    mkdir -p "$HOME/.config/terminator"
    touch "$HOME/.config/terminator/config"
    cat > "$HOME/.config/terminator/config" << '"'"'EOF'"'"'
[global_config]
  window_state = maximise
[keybindings]
[profiles]
  [[default]]
    font = JetBrainsMono Nerd Font Mono 16
    foreground_color = "#f6f5f4"
    show_titlebar = False
    scrollback_infinite = True
    disable_mousewheel_zoom = True
    use_system_font = False
[layouts]
  [[default]]
    [[[window0]]]
      type = Window
      parent = ""
    [[[child1]]]
      type = Terminal
      parent = window0
[plugins]
EOF
  '
}

install_sublime_text() {
  if dpkg -s sublime-text >/dev/null 2>&1; then
    info "Sublime Text already installed, skipping"
    return
  fi

  if [[ ! -f /usr/share/keyrings/sublimehq-pub.asc ]]; then
    wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | tee /usr/share/keyrings/sublimehq-pub.asc >/dev/null
  fi

  cat > /etc/apt/sources.list.d/sublime-text.sources <<EOF
Types: deb
URIs: https://download.sublimetext.com/
Suites: apt/stable/
Signed-By: /usr/share/keyrings/sublimehq-pub.asc
EOF

  apt-get update -y
  apt-get install -y sublime-text
  ok "Sublime Text installed"
}

install_brave_browser() {
  if dpkg -s brave-browser >/dev/null 2>&1; then
    info "Brave already installed, skipping"
    return
  fi

  if [[ ! -f /usr/share/keyrings/brave-browser-archive-keyring.gpg ]]; then
    curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
      https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  fi

  cat > /etc/apt/sources.list.d/brave-browser-release.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main
EOF

  apt-get update -y
  apt-get install -y libu2f-udev brave-browser
  ok "Brave installed"
}

install_emote_snap() {
  if command -v snap >/dev/null 2>&1 && snap list emote >/dev/null 2>&1; then
    info "Emote snap already installed, skipping"
    return
  fi

  if ! command -v snap >/dev/null 2>&1; then
    warn "snap command not found, cannot install Emote"
    return
  fi

  snap install emote
  ok "Emote installed"
}

install_dbeaver() {
  if dpkg -s dbeaver-ce >/dev/null 2>&1; then
    info "DBeaver CE already installed, skipping"
    return
  fi

  if [[ ! -f /usr/share/keyrings/dbeaver.gpg.key ]]; then
    wget -O /usr/share/keyrings/dbeaver.gpg.key https://dbeaver.io/debs/dbeaver.gpg.key
  fi

  cat > /etc/apt/sources.list.d/dbeaver.list <<EOF
deb [signed-by=/usr/share/keyrings/dbeaver.gpg.key] https://dbeaver.io/debs/dbeaver-ce /
EOF

  apt-get update -y
  apt-get install -y dbeaver-ce
  ok "DBeaver CE installed"
}

install_postman_snap() {
  if command -v snap >/dev/null 2>&1 && snap list postman >/dev/null 2>&1; then
    info "Postman snap already installed, skipping"
    return
  fi

  if ! command -v snap >/dev/null 2>&1; then
    warn "snap command not found, cannot install Postman"
    return
  fi

  snap install postman
  ok "Postman installed"
}

install_flameshot_and_config() {
  if sudo -u "$USER_NAME" -H bash -lc '
    dpkg -s flameshot >/dev/null 2>&1 && \
    [[ -f "$HOME/.config/flameshot/flameshot.ini" ]] && \
    grep -q "^startupLaunch=true$" "$HOME/.config/flameshot/flameshot.ini" && \
    grep -q "^savePathFixed=true$" "$HOME/.config/flameshot/flameshot.ini"
  '; then
    info "Flameshot already configured, skipping"
    return
  fi

  apt-get install -y flameshot

  sudo -u "$USER_NAME" -H bash -lc '
    set -euo pipefail
    mkdir -p "$HOME/.config/flameshot"
    cat > "$HOME/.config/flameshot/flameshot.ini" << '"'"'EOF'"'"'
[General]
contrastOpacity=188
copyPathAfterSave=false
saveAfterCopy=true
saveAsFileExtension=png
saveLastRegion=true
savePath=/home/'"$USER_NAME"'/Pictures/flameshot
savePathFixed=true
showHelp=false
showMagnifier=false
showStartupLaunchMessage=false
squareMagnifier=true
startupLaunch=true
EOF
  '

  ok "Flameshot installed and configured"
}

install_obsidian_snap() {
  if command -v snap >/dev/null 2>&1 && snap list obsidian >/dev/null 2>&1; then
    info "Obsidian snap already installed, skipping"
    return
  fi

  if ! command -v snap >/dev/null 2>&1; then
    warn "snap command not found, cannot install Obsidian"
    return
  fi

  snap install obsidian --classic
  ok "Obsidian installed"
}

# --- Pipx tools ---
install_tldr_pipx() {
  if sudo -u "$USER_NAME" -H bash -lc 'pipx list 2>/dev/null | grep -q "package tldr"'; then
    info "tldr already installed via pipx, skipping"
    return
  fi

  sudo -u "$USER_NAME" -H bash -lc 'pipx install tldr && pipx ensurepath'
  ok "tldr installed via pipx"
}

# --- Fonts ---
install_jetbrainsmono_nerd_font() {
  if sudo -u "$USER_NAME" -H bash -lc 'fc-list | grep -qi "JetBrainsMono Nerd Font"'; then
    info "JetBrainsMono Nerd Font already installed, skipping"
    return
  fi

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

info "================ RUN START ================"
info "run_id: ${RUN_ID}"
info "started_at: $(date -Is)"
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

# --- Update snaps ---
if command -v snap >/dev/null 2>&1; then
  info "snap refresh"
  if snap refresh; then
    ok "snap refresh completed"
  else
    warn "snap refresh failed, continuing"
  fi
else
  warn "snap command not found, skipping snap refresh"
fi

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

# --- Install specific tools ---
info "installing specific tools"
install_terminator_and_config
install_sublime_text
install_brave_browser
install_emote_snap
install_dbeaver
install_postman_snap
install_flameshot_and_config
install_obsidian_snap
install_tldr_pipx
ok "specific tools installed/configured"

# --- Post-install tweaks ---
info "updating locate database (best effort)"
updatedb || true

# --- GNOME and Dock customization ---
info "applying GNOME preferences (best effort)"

run_user_gsettings_try org.gnome.desktop.interface color-scheme "'prefer-dark'"
run_user_gsettings_try org.gnome.desktop.interface gtk-theme "'Yaru-dark'"
run_user_gsettings_try org.gnome.desktop.interface show-battery-percentage "true"
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock extend-height "true"
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock dash-max-icon-size "32"
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock click-action "'minimize'"
run_user_gsettings_try org.gnome.shell.extensions.dash-to-dock show-trash "false"

# --- Power / lockscreen: disable blank + lock ---
run_user_gsettings_try org.gnome.desktop.session idle-delay "uint32 0"
run_user_gsettings_try org.gnome.desktop.screensaver lock-enabled "false"
run_user_gsettings_try org.gnome.desktop.screensaver lock-delay "uint32 0"
run_user_gsettings_try org.gnome.desktop.notifications show-in-lock-screen "false"
run_user_gsettings_try org.gnome.desktop.screensaver ubuntu-lock-on-suspend "false"
run_user_gsettings_try org.gnome.system.location enabled "false"

# --- GNOME extensions tweaks ---
enable_system_monitor_extension

# --- Dock favorites ---
info "setting GNOME favorites (best effort)"
sudo -u "$USER_NAME" -H dbus-run-session -- bash -lc \
  "gsettings set org.gnome.shell favorite-apps \"[
    'org.gnome.Nautilus.desktop',
    'brave-browser.desktop',
    'terminator.desktop',
    'sublime_text.desktop',
    'obsidian_obsidian.desktop'
  ]\" || true"
ok "GNOME preferences applied"

# --- Cleanup and update repositories ---
info "cleanup"
apt-get -y autoremove --purge
apt-get -y clean
rm -rf /var/lib/apt/lists/*
apt-get -y update >/dev/null 2>&1 || true
ok "cleanup completed"

# --- Manual SSH key setup hint ---
warn "=============================================================="
warn "MANUAL SECTION"
warn "=============================================================="
info "--- SSH private key setup (run as ${USER_NAME}):"
info "mkdir -p \$HOME/.ssh && chmod 700 \$HOME/.ssh"
info "cat > \$HOME/.ssh/id_ed25519"
info "# paste key, then Ctrl-D"
info "chmod 600 \$HOME/.ssh/id_ed25519"
info "eval \"\$(ssh-agent -s)\" && ssh-add \$HOME/.ssh/id_ed25519"
info "--- Flameshot keyboard shortcut command:"
info "script --command \"flameshot gui\" /dev/null"
warn "=============================================================="

END_TS="$(date +%s)"
ELAPSED="$((END_TS - START_TS))"
info "done: $(date -Is)"
info "elapsed: $(printf '%02d:%02d:%02d' "$((ELAPSED / 3600))" "$((ELAPSED % 3600 / 60))" "$((ELAPSED % 60))")"
info "log file: ${LOG_FILE}"
info "run_id: ${RUN_ID}"
info "================= RUN END ================="

echo "################################"
echo "# Customize System Complete"
echo "[provision-system] rebooting in 5 seconds ..."
echo "################################"
sleep 5
sync
shutdown -r now
