#!/usr/bin/env bash
#
# Customize Ubuntu Desktop or Server
#
# Run:
# git clone https://github.com/syselement/packertron-vms.git && cd packertron-vms/scripts/ubuntu && sudo ./03-customize-system.sh
#
# Notes:
# - Run as root.
# - Console output is colorized when interactive.
# - Log output is written to /var/log/customize-system-<run_id>.log without ANSI escapes.
# - GNOME preferences are written immediately for USER_NAME through GSettings.
#

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
)"

# shellcheck source=lib/ubuntu-context.sh
. "$SCRIPT_DIR/lib/ubuntu-context.sh"

SCRIPT_NAME="customize-system"
LOG_PREFIX="[${SCRIPT_NAME}]"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
REBOOT_AT_END="${REBOOT_AT_END:-true}"
LOG_FILE="/var/log/${SCRIPT_NAME}-${RUN_ID}.log"
APT_SOURCES_CHANGED=false
STARSHIP_INSTALL_URL="${STARSHIP_INSTALL_URL:-https://starship.rs/install.sh}"

readonly -a APT_BOOTSTRAP_PACKAGES=(
  ca-certificates
  curl
  gnupg
  lsb-release
)

readonly -a COMMON_PACKAGES=(
  aptitude
  bash-completion
  bat
  bats
  btop
  build-essential
  docker-ctop
  duf
  eza
  fastfetch
  fd-find
  fontconfig
  gdu
  git
  gping
  htop
  iftop
  imagemagick
  ipcalc
  iperf3
  jq
  lm-sensors
  nano
  net-tools
  nload
  nmap
  npm
  openjdk-21-jre-headless
  pipx
  plocate
  s-tui
  shellcheck
  shfmt
  speedtest-cli
  sshpass
  stress
  sysstat
  tmux
  tor
  tree
  ugrep
  unzip
  vim
  wget
  zsh
)

readonly -a DESKTOP_PACKAGES=(
  brave-browser
  dbeaver-ce
  filezilla
  flatpak
  fonts-noto-color-emoji
  gnome-shell-extension-manager
  gnome-shell-extensions
  gnome-system-monitor
  gnome-tweaks
  mullvad-vpn
  qbittorrent
  sublime-text
  terminator
  vlc
  xclip
)

readonly -a FLATPAK_PACKAGES=(
  com.bitwarden.desktop
  io.ente.auth
  org.gnome.Boxes
)

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[${SCRIPT_NAME}] ERROR must run as root (use: sudo bash $0)" >&2
    exit 1
  fi
}

USER_NAME=""
VERSION_ID=""
CODENAME=""
ARCH=""
t_bold=""
t_dim=""
t_green=""
t_yellow=""
t_red=""
t_reset=""

initialize_runtime() {
  require_root

  # Console keeps ANSI colors, while the log file stores plain text.
  if [[ -t 1 ]]; then
    t_bold=$'\e[1m'
    t_dim=$'\e[2m'
    t_green=$'\e[32m'
    t_yellow=$'\e[33m'
    t_red=$'\e[31m'
    t_reset=$'\e[0m'
  fi
  exec > >(tee >(sed -u -r 's/\x1B\[[0-9;]*[[:alpha:]]//g' >"$LOG_FILE")) 2>&1

  initialize_ubuntu_context
  USER_NAME="$TARGET_USER"
  VERSION_ID="$UBUNTU_VERSION_ID"
  CODENAME="$UBUNTU_CODENAME"
  ARCH="$(dpkg --print-architecture)"
}

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
user_home() {
  local account="$1"
  getent passwd "$account" | cut -d: -f6
}

run_apt_get() {
  DEBIAN_FRONTEND=noninteractive apt-get \
    -o DPkg::Lock::Timeout=300 \
    "$@"
}

run_quiet_command() (
  local description="$1"
  local line
  local output_file
  local status
  shift

  output_file="$(mktemp)"
  trap 'rm -f -- "$output_file"' EXIT

  if "$@" >"$output_file" 2>&1; then
    return 0
  else
    status=$?
  fi

  while IFS= read -r line; do
    error "${description}: ${line}"
  done <"$output_file"
  return "$status"
)

install_package_array() {
  local description="$1"
  shift
  local package
  local -a missing=()
  local -a packages=("$@")

  if (( ${#packages[@]} == 0 )); then
    info "${description}: no packages requested, skipping"
    return 0
  fi

  for package in "${packages[@]}"; do
    if [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)" != "install ok installed" ]]; then
      missing+=("$package")
    fi
  done

  if (( ${#missing[@]} == 0 )); then
    info "${description}: all packages already installed"
    return 0
  fi

  info "installing ${#missing[@]} missing ${description} packages: ${missing[*]}"
  if ! run_apt_get install -y -qq "${missing[@]}"; then
    die "failed installing ${description} packages: ${missing[*]}"
  fi
  ok "${description} package installation completed"
}

install_flatpak_package_array() {
  local description="$1"
  shift

  local packages=("$@")
  local missing=()
  local app

  if [[ "$UBUNTU_VARIANT" != "desktop" ]]; then
    info "${description}: desktop-only, skipping"
    return
  fi

  command -v flatpak >/dev/null 2>&1 || die "flatpak is required to install ${description}"

  flatpak remotes --system --columns=name | grep -qx flathub || die "system-wide Flathub remote is not configured"

  if (( ${#packages[@]} == 0 )); then
    info "${description}: no packages requested, skipping"
    return
  fi

  for app in "${packages[@]}"; do
    if flatpak info --system "$app" >/dev/null 2>&1; then
      info "${app} already installed"
    else
      missing+=("$app")
    fi
  done

  if (( ${#missing[@]} == 0 )); then
    info "${description}: all packages already installed"
    return
  fi

  info "installing ${#missing[@]} ${description} packages"
  flatpak install --system --noninteractive -y flathub "${missing[@]}"

  for app in "${missing[@]}"; do
    flatpak info --system "$app" >/dev/null 2>&1 || die "Flatpak installation could not be verified: ${app}"
  done

  ok "${description} package installation completed"
}

write_file_if_changed() {
  local source_file="$1"
  local destination_file="$2"

  if [[ -f "$destination_file" ]] && cmp -s "$source_file" "$destination_file"; then
    return 1
  fi

  install -D -m 0644 "$source_file" "$destination_file"
  return 0
}

# Get the user's D-Bus session bus socket.
gnome_user_bus_available() {
  local uid
  uid="$(id -u "$USER_NAME")"
  [[ -S "/run/user/${uid}/bus" ]]
}

# Run a command as the desktop user on their real per-user D-Bus when one
# exists. This is essential when the script is launched with sudo from a live
# GNOME session: using an isolated dbus-run-session there can race with the
# already-running dconf service. For SSH/Vagrant provisioning before graphical
# login, fall back to a temporary session bus so GSettings can still persist.
run_as_gnome_user() {
  local uid runtime_dir
  uid="$(id -u "$USER_NAME")"
  runtime_dir="/run/user/${uid}"

  if [[ -S "${runtime_dir}/bus" ]]; then
    sudo -u "$USER_NAME" -H env \
      XDG_RUNTIME_DIR="$runtime_dir" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus" \
      "$@"
  else
    sudo -u "$USER_NAME" -H dbus-run-session -- "$@"
  fi
}

apply_gnome_preferences() {
  local bus_mode

  if gnome_user_bus_available; then
    bus_mode="existing per-user D-Bus"
  else
    bus_mode="temporary D-Bus fallback"
  fi
  info "applying GNOME preferences via ${bus_mode}"

  if ! run_as_gnome_user bash <<'GNOME_SETTINGS'
set -uo pipefail

failures=0

schema_exists() {
  # Process substitution avoids a pipefail/SIGPIPE false negative caused by
  # `gsettings list-schemas | grep -q`.
  grep -Fx -- "$1" < <(gsettings list-schemas) >/dev/null
}

key_exists() {
  local schema="$1"
  local key="$2"

  schema_exists "$schema" || return 1
  grep -Fx -- "$key" < <(gsettings list-keys "$schema") >/dev/null
}

gsetting_values_equal() {
  local expected="$1"
  local actual="$2"
  local number_re='^[-+]?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$'

  if [[ "$expected" =~ $number_re && "$actual" =~ $number_re ]]; then
    awk -v expected="$expected" -v actual="$actual" '
      BEGIN {
        delta = actual - expected
        if (delta < 0)
          delta = -delta

        expected_abs = expected < 0 ? -expected : expected
        actual_abs   = actual   < 0 ? -actual   : actual
        scale = expected_abs > actual_abs ? expected_abs : actual_abs

        if (scale < 1)
          scale = 1

        exit !(delta <= 1e-9 * scale)
      }
    '
  else
    [[ "$actual" == "$expected" ]]
  fi
}

set_gsetting() {
  local schema="$1"
  local key="$2"
  local value="$3"
  local actual

  if ! key_exists "$schema" "$key"; then
    printf '[gnome-settings] SKIP missing schema/key: %s %s\n' "$schema" "$key"
    return 0
  fi

  if [[ "$(gsettings writable "$schema" "$key" 2>/dev/null)" != "true" ]]; then
    printf '[gnome-settings] SKIP non-writable key: %s %s\n' "$schema" "$key"
    return 0
  fi

  actual="$(gsettings get "$schema" "$key")"
  if gsetting_values_equal "$value" "$actual"; then
    return 0
  fi

  if ! gsettings set "$schema" "$key" "$value"; then
    printf '[gnome-settings] ERROR failed: %s %s = %s\n' "$schema" "$key" "$value" >&2
    failures=$((failures + 1))
    return 0
  fi

  actual="$(gsettings get "$schema" "$key")"

  if ! gsetting_values_equal "$value" "$actual"; then
    printf '[gnome-settings] ERROR verify failed: %s %s; requested=%s actual=%s\n' "$schema" "$key" "$value" "$actual" >&2
    failures=$((failures + 1))
    return 0
  fi

  printf '[gnome-settings] SET %s %s = %s\n' "$schema" "$key" "$actual"
}

update_string_array() {
  local schema="$1"
  local key="$2"
  local action="$3"
  local item="$4"
  local current updated actual

  if ! key_exists "$schema" "$key"; then
    printf '[gnome-settings] SKIP missing schema/key: %s %s\n' "$schema" "$key"
    return 0
  fi

  current="$(gsettings get "$schema" "$key")"
  if ! updated="$(python3 - "$current" "$action" "$item" <<'PYTHON_ARRAY'
import ast
import sys

raw, action, item = sys.argv[1:]
if raw.startswith("@as "):
    raw = raw[4:]
values = list(ast.literal_eval(raw))

if action == "add":
    if item not in values:
        values.append(item)
elif action == "remove":
    values = [value for value in values if value != item]
else:
    raise SystemExit(f"unsupported action: {action}")

print("[" + ", ".join(repr(value) for value in values) + "]")
PYTHON_ARRAY
  )"; then
    printf '[gnome-settings] ERROR cannot parse/update %s %s\n' "$schema" "$key" >&2
    failures=$((failures + 1))
    return 0
  fi

  if [[ "$current" == "$updated" ]]; then
    return 0
  fi

  if ! gsettings set "$schema" "$key" "$updated"; then
    printf '[gnome-settings] ERROR failed updating: %s %s\n' "$schema" "$key" >&2
    failures=$((failures + 1))
    return 0
  fi

  actual="$(gsettings get "$schema" "$key")"
  printf '[gnome-settings] SET %s %s = %s\n' "$schema" "$key" "$actual"
}

# Appearance
set_gsetting org.gnome.desktop.interface color-scheme "'prefer-dark'"
set_gsetting org.gnome.desktop.interface document-font-name "'JetBrainsMono Nerd Font 11'"
set_gsetting org.gnome.desktop.interface font-name "'JetBrainsMono Nerd Font 11'"
set_gsetting org.gnome.desktop.interface gtk-theme "'Yaru-yellow-dark'"
set_gsetting org.gnome.desktop.interface monospace-font-name "'JetBrainsMono Nerd Font Mono 11'"
set_gsetting org.gnome.desktop.interface show-battery-percentage "true"
set_gsetting org.gnome.desktop.interface text-scaling-factor "1.1"

# Ubuntu Dock
set_gsetting org.gnome.shell.extensions.dash-to-dock click-action "'minimize'"
set_gsetting org.gnome.shell.extensions.dash-to-dock dash-max-icon-size "34"
set_gsetting org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"
set_gsetting org.gnome.shell.extensions.dash-to-dock extend-height "true"
set_gsetting org.gnome.shell.extensions.dash-to-dock show-trash "false"

# Power and lock screen
set_gsetting org.gnome.desktop.notifications show-in-lock-screen "false"
set_gsetting org.gnome.desktop.screensaver lock-delay "uint32 1800"
set_gsetting org.gnome.desktop.screensaver lock-enabled "true"
set_gsetting org.gnome.desktop.screensaver ubuntu-lock-on-suspend "true"
set_gsetting org.gnome.desktop.session idle-delay "uint32 1800"
set_gsetting org.gnome.system.location enabled "false"

# Display color / Night Light
set_gsetting org.gnome.settings-daemon.plugins.color night-light-enabled "true"
set_gsetting org.gnome.settings-daemon.plugins.color night-light-schedule-automatic "false"
set_gsetting org.gnome.settings-daemon.plugins.color night-light-schedule-from "18.0"
set_gsetting org.gnome.settings-daemon.plugins.color night-light-schedule-to "8.0"
set_gsetting org.gnome.settings-daemon.plugins.color night-light-temperature "uint32 4700"

# Sound
set_gsetting org.gnome.desktop.sound allow-volume-above-100-percent "true"

# Power
set_gsetting org.gnome.desktop.interface show-battery-percentage "true"
set_gsetting org.gnome.settings-daemon.plugins.power power-button-action "'suspend'"

# Ubuntu Desktop
set_gsetting org.gnome.shell.extensions.ding show-home "false"

# Notifications
set_gsetting org.gnome.desktop.notifications show-in-lock-screen "false"

# Mouse and Touchpad
# false = traditional scrolling; true = natural/reversed scrolling.
set_gsetting org.gnome.desktop.peripherals.touchpad natural-scroll "false"

# Dock favorites
set_gsetting org.gnome.shell favorite-apps \
  "['org.gnome.Nautilus.desktop', 'brave-browser.desktop', 'terminator.desktop', 'sublime_text.desktop', 'obsidian.desktop', 'code.desktop']"

# Enable System Monitor Panel on Ubuntu 26.04.
# Fall back to the packaged System Monitor extension on Ubuntu 24.04.
new_ext_uuid='system-monitor-panel@naimur'
old_ext_uuid='system-monitor@gnome-shell-extensions.gcampax.github.com'

new_ext_installed=false
old_ext_installed=false

if [[ -d "/usr/share/gnome-shell/extensions/${new_ext_uuid}" ||
      -d "$HOME/.local/share/gnome-shell/extensions/${new_ext_uuid}" ]]; then
  new_ext_installed=true
fi

if [[ -d "/usr/share/gnome-shell/extensions/${old_ext_uuid}" ||
      -d "$HOME/.local/share/gnome-shell/extensions/${old_ext_uuid}" ]]; then
  old_ext_installed=true
fi

if [[ "$new_ext_installed" == true ]]; then
  set_gsetting org.gnome.shell disable-user-extensions "false"
  # Disable the old packaged extension.
  update_string_array  org.gnome.shell enabled-extensions remove "$old_ext_uuid"
  update_string_array org.gnome.shell disabled-extensions add "$old_ext_uuid"
  # Enable the new extension.
  update_string_array org.gnome.shell enabled-extensions add "$new_ext_uuid"
  update_string_array org.gnome.shell disabled-extensions remove "$new_ext_uuid"

elif [[ "$old_ext_installed" == true ]]; then
  # Ubuntu 24.04 fallback.
  set_gsetting org.gnome.shell disable-user-extensions "false"
  update_string_array org.gnome.shell enabled-extensions add "$old_ext_uuid"
  update_string_array org.gnome.shell disabled-extensions remove "$old_ext_uuid"
else
  printf '[gnome-settings] SKIP no supported System Monitor extension installed\n'
fi

# Force a final read through the same backend before the process/session exits.
gsettings get org.gnome.shell favorite-apps >/dev/null

(( failures == 0 ))
GNOME_SETTINGS
  then
    warn "one or more GNOME preferences failed; inspect the log above"
    return 1
  fi

  ok "GNOME preferences applied and verified"
}

install_hide_universal_access_extension() (
  set -euo pipefail

  local account="$1"
  local uuid="hide-universal-access@akiirui.github.io"
  local download_url=""
  local home metadata_file

  case "$VERSION_ID" in
    26.*)
      download_url="https://extensions.gnome.org/review/download/69554.shell-extension.zip"
      ;;
    24.*)
      download_url="https://extensions.gnome.org/review/download/52417.shell-extension.zip"
      ;;
    *)
      warn "Hide Universal Access installation not configured for Ubuntu ${VERSION_ID}"
      return
      ;;
  esac

  command -v curl >/dev/null 2>&1 ||
    die "curl is required to install Hide Universal Access"

  command -v gnome-extensions >/dev/null 2>&1 ||
    die "gnome-extensions is required to install Hide Universal Access"

  home="$(user_home "$account")"
  [[ -n "$home" ]] ||
    die "could not determine home directory for ${account}"

  metadata_file="$home/.local/share/gnome-shell/extensions/$uuid/metadata.json"

  if [[ -f "$metadata_file" ]]; then
    info "Hide Universal Access extension already installed, skipping"
    return
  fi

  info "downloading Hide Universal Access extension"

  sudo -u "$account" -H bash -s -- "$download_url" <<'USER_INSTALL'
set -euo pipefail

download_url="$1"
tmp_file="$(mktemp --suffix=.shell-extension.zip)"

cleanup() {
  rm -f -- "$tmp_file"
}
trap cleanup EXIT

curl -fsSL \
  --retry 3 \
  --retry-all-errors \
  --connect-timeout 15 \
  "$download_url" \
  -o "$tmp_file"

gnome-extensions install --force "$tmp_file"
USER_INSTALL

  [[ -f "$metadata_file" ]] ||
    die "Hide Universal Access extension installation failed"

  ok "Hide Universal Access extension installed for ${account}"
)

install_system_monitor_panel_extension() (
  set -euo pipefail

  local account="$1"
  local uuid="system-monitor-panel@naimur"
  local download_url="https://extensions.gnome.org/review/download/72705.shell-extension.zip"
  local home metadata_file

  case "$VERSION_ID" in
    26.*) ;;
    24.*)
      info "System Monitor Panel requires GNOME 48 or newer; skipping on Ubuntu ${VERSION_ID}"
      return
      ;;
    *)
      warn "System Monitor Panel installation not configured for Ubuntu ${VERSION_ID}"
      return
      ;;
  esac

  command -v curl >/dev/null 2>&1 ||
    die "curl is required to install System Monitor Panel"

  command -v gnome-extensions >/dev/null 2>&1 ||
    die "gnome-extensions is required to install System Monitor Panel"

  home="$(user_home "$account")"
  [[ -n "$home" ]] ||
    die "could not determine home directory for ${account}"

  metadata_file="$home/.local/share/gnome-shell/extensions/$uuid/metadata.json"

  if [[ -f "$metadata_file" ]]; then
    info "System Monitor Panel extension already installed, skipping"
    return
  fi

  info "downloading System Monitor Panel extension"

  sudo -u "$account" -H bash -s -- "$download_url" <<'USER_INSTALL'
set -euo pipefail

download_url="$1"
tmp_file="$(mktemp --suffix=.shell-extension.zip)"

cleanup() {
  rm -f -- "$tmp_file"
}
trap cleanup EXIT

curl -fsSL "$download_url" -o "$tmp_file"
gnome-extensions install --force "$tmp_file"
USER_INSTALL

  [[ -f "$metadata_file" ]] ||
    die "System Monitor Panel extension installation failed"

  ok "System Monitor Panel extension installed for ${account}"
)

enable_battery_health_preservation() {
  local device supported enabled
  local found_battery=false
  local enabled_count=0

  if ! command -v upower >/dev/null 2>&1; then
    warn "upower not found; cannot enable battery health preservation"
    return
  fi

  if ! command -v busctl >/dev/null 2>&1; then
    warn "busctl not found; cannot enable battery health preservation"
    return
  fi

  while IFS= read -r device; do
    [[ "$device" == */battery_* ]] || continue
    found_battery=true

    supported="$(
      busctl --system get-property \
        org.freedesktop.UPower \
        "$device" \
        org.freedesktop.UPower.Device \
        ChargeThresholdSupported 2>/dev/null || true
    )"

    if [[ "$supported" != "b true" ]]; then
      info "battery charge thresholds unsupported for ${device##*/}; skipping"
      continue
    fi

    if ! busctl --system call \
      org.freedesktop.UPower \
      "$device" \
      org.freedesktop.UPower.Device \
      EnableChargeThreshold b true >/dev/null; then
      warn "failed to enable battery health preservation for ${device##*/}"
      continue
    fi

    enabled="$(
      busctl --system get-property \
        org.freedesktop.UPower \
        "$device" \
        org.freedesktop.UPower.Device \
        ChargeThresholdEnabled 2>/dev/null || true
    )"

    if [[ "$enabled" == "b true" ]]; then
      ok "battery health preservation enabled for ${device##*/}"
      enabled_count=$((enabled_count + 1))
    else
      warn "battery health preservation could not be verified for ${device##*/}"
    fi
  done < <(upower -e 2>/dev/null || true)

  if [[ "$found_battery" == false ]]; then
    info "no system battery detected; skipping battery health preservation"
  elif (( enabled_count == 0 )); then
    info "no battery supports UPower charge thresholds"
  fi
}

# --- Repository setup ---
ensure_fastfetch_ppa() {
  local ppa="ppa:zhangsongcui3371/fastfetch"

  case "$VERSION_ID" in
    24.*)
      if grep -Rqs "zhangsongcui3371/fastfetch" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
        info "fastfetch PPA already present"
        return
      fi

      if ! command -v add-apt-repository >/dev/null 2>&1; then
        die "add-apt-repository is required for the fastfetch PPA on Ubuntu ${VERSION_ID}"
      fi

      if add-apt-repository --yes --no-update "$ppa" >/dev/null 2>&1; then
        APT_SOURCES_CHANGED=true
        ok "added fastfetch PPA for Ubuntu ${VERSION_ID}"
      else
        warn "failed to add fastfetch PPA; fastfetch may not be available"
      fi
      ;;
    26.*)
      info "Ubuntu ${VERSION_ID} provides fastfetch; skipping fastfetch PPA"
      ;;
    *)
      warn "Ubuntu ${VERSION_ID} is not explicitly handled for the fastfetch PPA; using configured repositories"
      ;;
  esac
}

install_docker_ctop_repository() {
  local key_file="/usr/share/keyrings/azlux-archive-keyring.gpg"
  local source_file="/etc/apt/sources.list.d/azlux.sources"
  local tmp_key
  local tmp_source

  tmp_key="$(mktemp)"
  tmp_source="$(mktemp)"

  if ! curl -fsSL https://azlux.fr/repo.gpg.key | gpg --dearmor --yes -o "$tmp_key"; then
    rm -f "$tmp_key" "$tmp_source"
    die "failed to download the AZLux repository signing key"
  fi

  cat > "$tmp_source" <<'EOF'
Types: deb
URIs: http://packages.azlux.fr/debian/
Suites: stable
Components: main
Signed-By: /usr/share/keyrings/azlux-archive-keyring.gpg
EOF

  if write_file_if_changed "$tmp_key" "$key_file"; then
    APT_SOURCES_CHANGED=true
    ok "installed AZLux repository signing key"
  else
    info "AZLux repository signing key already current"
  fi

  if write_file_if_changed "$tmp_source" "$source_file"; then
    APT_SOURCES_CHANGED=true
    ok "configured AZLux repository"
  else
    info "AZLux repository already configured"
  fi

  rm -f "$tmp_key" "$tmp_source"
}

ensure_sublime_text_repository() {
  local key_file="/usr/share/keyrings/sublimehq-pub.asc"
  local source_file="/etc/apt/sources.list.d/sublime-text.sources"
  local tmp_key
  local tmp_source

  tmp_key="$(mktemp)"
  tmp_source="$(mktemp)"
  curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg -o "$tmp_key"
  cat > "$tmp_source" <<'EOF'
Types: deb
URIs: https://download.sublimetext.com/
Suites: apt/stable/
Signed-By: /usr/share/keyrings/sublimehq-pub.asc
EOF

  if write_file_if_changed "$tmp_key" "$key_file"; then
    APT_SOURCES_CHANGED=true
  fi
  if write_file_if_changed "$tmp_source" "$source_file"; then
    APT_SOURCES_CHANGED=true
  fi
  rm -f "$tmp_key" "$tmp_source"
}

ensure_brave_browser_repository() {
  local key_file="/usr/share/keyrings/brave-browser-archive-keyring.gpg"
  local source_file="/etc/apt/sources.list.d/brave-browser-release.sources"
  local tmp_key
  local tmp_source

  tmp_key="$(mktemp)"
  tmp_source="$(mktemp)"
  curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg -o "$tmp_key"
  curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser.sources -o "$tmp_source"

  if write_file_if_changed "$tmp_key" "$key_file"; then
    APT_SOURCES_CHANGED=true
  fi
  if write_file_if_changed "$tmp_source" "$source_file"; then
    APT_SOURCES_CHANGED=true
  fi
  rm -f "$tmp_key" "$tmp_source"
  if compgen -G '/etc/apt/sources.list.d/brave-browser-*.list' >/dev/null; then
    APT_SOURCES_CHANGED=true
  fi
  rm -f /etc/apt/sources.list.d/brave-browser-*.list
}

ensure_dbeaver_repository() {
  local key_file="/usr/share/keyrings/dbeaver.gpg.key"
  local source_file="/etc/apt/sources.list.d/dbeaver.list"
  local tmp_key
  local tmp_source

  tmp_key="$(mktemp)"
  tmp_source="$(mktemp)"
  if ! curl -fsSL https://dbeaver.io/debs/dbeaver.gpg.key | gpg --dearmor --yes -o "$tmp_key"; then
    rm -f "$tmp_key" "$tmp_source"
    die "failed to download the DBeaver repository signing key"
  fi
  cat > "$tmp_source" <<'EOF'
deb [signed-by=/usr/share/keyrings/dbeaver.gpg.key] https://dbeaver.io/debs/dbeaver-ce /
EOF

  if write_file_if_changed "$tmp_key" "$key_file"; then
    APT_SOURCES_CHANGED=true
  fi
  if write_file_if_changed "$tmp_source" "$source_file"; then
    APT_SOURCES_CHANGED=true
  fi
  rm -f "$tmp_key" "$tmp_source"
}

ensure_mullvad_repository() {
  local key_file="/usr/share/keyrings/mullvad-keyring.asc"
  local source_file="/etc/apt/sources.list.d/mullvad.list"
  local tmp_key
  local tmp_source

  if [[ "$UBUNTU_VARIANT" != "desktop" ]]; then
    info "Mullvad VPN is desktop-only; skipping"
    return
  fi

  tmp_key="$(mktemp)"
  tmp_source="$(mktemp)"

  if ! curl -fsSLo "$tmp_key" https://repository.mullvad.net/deb/mullvad-keyring.asc; then
    rm -f "$tmp_key" "$tmp_source"
    die "failed to download the Mullvad repository signing key"
  fi

  cat > "$tmp_source" <<EOF
deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$(dpkg --print-architecture)] https://repository.mullvad.net/deb/stable stable main
EOF

  if write_file_if_changed "$tmp_key" "$key_file"; then
    APT_SOURCES_CHANGED=true
    ok "installed Mullvad repository signing key"
  else
    info "Mullvad repository signing key already current"
  fi

  if write_file_if_changed "$tmp_source" "$source_file"; then
    APT_SOURCES_CHANGED=true
    ok "configured Mullvad repository"
  else
    info "Mullvad repository already configured"
  fi

  rm -f "$tmp_key" "$tmp_source"
}

configure_flathub() (
  set -euo pipefail

  local remote_url="https://dl.flathub.org/repo/flathub.flatpakrepo"

  if [[ "$UBUNTU_VARIANT" != "desktop" ]]; then
    info "Flathub is desktop-only; skipping"
    return
  fi

  command -v flatpak >/dev/null 2>&1 || die "flatpak is required to configure Flathub"

  info "configuring the system-wide Flathub remote"

  flatpak remote-add --system --if-not-exists flathub "$remote_url"
  flatpak remote-modify --system --enable flathub

  flatpak remotes --system --columns=name | grep -qx flathub ||
    die "Flathub remote configuration could not be verified"

  ok "Flathub system remote configured"
)

# --- Desktop tools ---

configure_desktop_wallpaper() (
  set -euo pipefail

  local repo_url="https://github.com/syselement/packertron-vms.git"
  local repo_dir="/opt/packertron-vms"
  local source_file="${repo_dir}/scripts/ubuntu/ubuntu-wallpaper.png"
  local home
  local group
  local uid
  local runtime_dir
  local destination_file
  local wallpaper_uri

  home="$(user_home "$USER_NAME")"
  [[ -n "$home" && -d "$home" ]] ||
    die "could not determine home directory for ${USER_NAME}"

  group="$(id -gn "$USER_NAME")"
  uid="$(id -u "$USER_NAME")"
  runtime_dir="/run/user/${uid}"

  destination_file="$home/.config/background"
  wallpaper_uri="file://${destination_file}"

  command -v git >/dev/null 2>&1 ||
    die "git is required to synchronize ${repo_dir}"

  install -d -m 0755 "$(dirname "$repo_dir")"

  if [[ ! -e "$repo_dir" ]]; then
    info "cloning Packertron repository"

    git clone --quiet \
      --branch main \
      --single-branch \
      --depth 1 \
      "$repo_url" \
      "$repo_dir"

    ok "Packertron repository cloned"
  elif [[ -d "$repo_dir/.git" ]]; then
    info "synchronizing Packertron repository"

    git -C "$repo_dir" pull --quiet --ff-only

    ok "Packertron repository synchronized"
  else
    die "${repo_dir} exists but is not a Git repository"
  fi

  [[ -f "$source_file" ]] ||
    die "wallpaper not found: ${source_file}"

  install -d \
    -o "$USER_NAME" \
    -g "$group" \
    -m 0755 \
    "$home/.config"

  install \
    -o "$USER_NAME" \
    -g "$group" \
    -m 0644 \
    "$source_file" \
    "$destination_file"

  run_gsettings() {
    if [[ -S "$runtime_dir/bus" ]]; then
      sudo -u "$USER_NAME" \
        env \
          HOME="$home" \
          XDG_RUNTIME_DIR="$runtime_dir" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime_dir}/bus" \
        gsettings "$@"
    else
      sudo -u "$USER_NAME" -H \
        dbus-run-session -- gsettings "$@"
    fi
  }

  info "configuring GNOME wallpaper"

  run_gsettings set \
    org.gnome.desktop.background \
    picture-uri \
    "$wallpaper_uri"

  run_gsettings set \
    org.gnome.desktop.background \
    picture-uri-dark \
    "$wallpaper_uri"

  run_gsettings set \
    org.gnome.desktop.background \
    picture-options \
    "zoom"

  [[ "$(run_gsettings get org.gnome.desktop.background picture-uri)" \
      == "'${wallpaper_uri}'" ]] ||
    die "failed to configure light wallpaper"

  [[ "$(run_gsettings get org.gnome.desktop.background picture-uri-dark)" \
      == "'${wallpaper_uri}'" ]] ||
    die "failed to configure dark wallpaper"

  [[ "$(run_gsettings get org.gnome.desktop.background picture-options)" \
      == "'zoom'" ]] ||
    die "failed to configure wallpaper display mode"

  ok "GNOME wallpaper configured: ${destination_file}"
)

configure_terminator() {
  if sudo -u "$USER_NAME" -H bash -lc '
    [[ -f "$HOME/.config/terminator/config" ]] && \
    grep -q "font = JetBrainsMono Nerd Font Mono 16" "$HOME/.config/terminator/config" && \
    grep -q "scrollback_infinite = True" "$HOME/.config/terminator/config"
  '; then
    info "Terminator already configured, skipping"
    return
  fi

  sudo -u "$USER_NAME" -H bash -lc '
    set -euo pipefail
    mkdir -p "$HOME/.config/terminator"
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
  ok "Terminator configured"
}

configure_terminator_as_default() {
  local account="$1"
  local home
  local group
  local terminator_bin
  local desktop_file="/usr/share/applications/terminator.desktop"
  local desktop_id="terminator.desktop"

  home="$(user_home "$account")"
  [[ -n "$home" ]] || die "could not determine home directory for ${account}"
  group="$(id -gn "$account")"

  terminator_bin="$(command -v terminator 2>/dev/null || true)"
  if [[ -z "$terminator_bin" ]]; then
    warn "Terminator is not installed; cannot configure default terminal"
    return
  fi

  case "$VERSION_ID" in
    24.*)
      # Ubuntu 24.04: legacy system-wide alternatives mechanism.
      if ! grep -Fx -- "$terminator_bin" \
        < <(update-alternatives --list x-terminal-emulator 2>/dev/null); then
        warn "Terminator is not registered as an x-terminal-emulator alternative"
        return
      fi

      update-alternatives --set x-terminal-emulator "$terminator_bin"
      ok "Terminator configured as system default terminal on Ubuntu ${VERSION_ID}"
      ;;

    26.*)
      # Ubuntu 26.04: per-user xdg-terminal-exec configuration.
      if [[ ! -f "$desktop_file" ]]; then
        warn "Terminator desktop file not found: ${desktop_file}"
        return
      fi

      install -d -m 0755 -o "$account" -g "$group" "$home/.config"

      sudo -u "$account" -H bash -s -- "$desktop_id" <<'EOF'
set -euo pipefail

desktop_id="$1"
config_file="$HOME/.config/ubuntu-xdg-terminals.list"
tmp_file="$(mktemp "$HOME/.config/.ubuntu-xdg-terminals.list.XXXXXX")"

cleanup() {
  rm -f "$tmp_file"
}
trap cleanup EXIT

# Put Terminator first while preserving other configured terminals.
{
  printf '%s\n' "$desktop_id"

  if [[ -f "$config_file" ]]; then
    grep -Fxv -- "$desktop_id" "$config_file" || true
  fi
} > "$tmp_file"

chmod 0644 "$tmp_file"
mv -f "$tmp_file" "$config_file"
trap - EXIT
EOF

      ok "Terminator configured as default terminal for ${account} on Ubuntu ${VERSION_ID}"
      ;;

    *)
      warn "default terminal configuration not implemented for Ubuntu ${VERSION_ID}"
      ;;
  esac
}

install_snap_package() {
  local snap_name="$1"
  local display_name="$2"

  if ! command -v snap >/dev/null 2>&1; then
    warn "snap command not found; cannot install ${display_name}"
    return 0
  fi

  if snap list "$snap_name" >/dev/null 2>&1; then
    info "${display_name} snap already installed, skipping"
    return 0
  fi

  if ! snap install "$snap_name"; then
    die "failed installing ${display_name} snap (${snap_name})"
  fi
  ok "${display_name} snap installed"
}

connect_snap_interface() {
  local connection="$1"
  local description="$2"

  if ! command -v snap >/dev/null 2>&1; then
    return 0
  fi

  if snap connect "$connection" >/dev/null 2>&1; then
    info "${description} interface connected"
  else
    warn "could not connect ${description} interface (${connection})"
  fi
}

install_flameshot() (
  set -euo pipefail

  local api_url="https://api.github.com/repos/flameshot-org/flameshot/releases/latest"
  local release_json tag latest_version installed_version
  local architecture platform asset_url asset_name
  local tmp_dir deb_file checksum_file
  local -a platform_candidates

  for cmd in curl jq unzip sha256sum dpkg-query apt-get; do
    command -v "$cmd" >/dev/null 2>&1 ||
      die "${cmd} is required to install Flameshot"
  done

  architecture="$(dpkg --print-architecture)"
  case "$architecture" in
    amd64|arm64) ;;
    *)
      warn "unsupported Flameshot architecture: ${architecture}"
      return
      ;;
  esac

  case "$VERSION_ID" in
    24.*)
      platform_candidates=("ubuntu-24.04")
      ;;
    26.*)
      # Use a native 26.04 artifact when upstream provides one;
      # otherwise fall back to the Ubuntu 24.04 package.
      platform_candidates=("ubuntu-26.04" "ubuntu-24.04")
      ;;
    *)
      warn "Flameshot release installation not configured for Ubuntu ${VERSION_ID}"
      return
      ;;
  esac

  info "checking latest Flameshot GitHub release"

  release_json="$(curl -fsSL "$api_url")"
  tag="$(jq -r '.tag_name // empty' <<<"$release_json")"
  [[ -n "$tag" ]] || die "could not determine latest Flameshot release"

  latest_version="${tag#v}"
  installed_version="$(
    dpkg-query -W -f='${Version}' flameshot 2>/dev/null || true
  )"

  if [[ -n "$installed_version" ]] &&
    dpkg --compare-versions "$installed_version" ge "$latest_version"; then
    info "Flameshot ${installed_version} already installed, skipping"
    return
  fi

  asset_url=""
  for platform in "${platform_candidates[@]}"; do
    asset_url="$(
      jq -r \
        --arg suffix "artifact-${platform}-${architecture}.zip" \
        '[.assets[]
          | select(.name | endswith($suffix))
        ][0].browser_download_url // empty' \
        <<<"$release_json"
    )"

    [[ -n "$asset_url" ]] && break
  done

  [[ -n "$asset_url" ]] ||
    die "no compatible Flameshot artifact for Ubuntu ${VERSION_ID}/${architecture}"

  asset_name="${asset_url##*/}"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$tmp_dir"' EXIT

  info "downloading Flameshot ${tag} (${platform}/${architecture})"
  curl -fL "$asset_url" -o "$tmp_dir/$asset_name"

  unzip -q "$tmp_dir/$asset_name" -d "$tmp_dir/extracted"

  deb_file="$(
    find "$tmp_dir/extracted" -maxdepth 2 -type f \
      -name 'flameshot*.deb' -print -quit
  )"

  checksum_file="$(
    find "$tmp_dir/extracted" -maxdepth 2 -type f \
      -name 'flameshot*.deb.sha256sum' -print -quit
  )"

  [[ -n "$deb_file" ]] ||
    die "Flameshot archive does not contain a Debian package"

  [[ -n "$checksum_file" ]] ||
    die "Flameshot archive does not contain the Debian package checksum"

  info "verifying Flameshot package checksum"
  (
    cd "$(dirname "$deb_file")"
    sha256sum --check "$(basename "$checksum_file")"
  )

  info "installing Flameshot ${tag}"
  run_apt_get install -y "$deb_file"

  installed_version="$(
    dpkg-query -W -f='${Version}' flameshot 2>/dev/null || true
  )"

  [[ -n "$installed_version" ]] ||
    die "Flameshot installation could not be verified"

  ok "Flameshot ${installed_version} installed from the official GitHub release"
)

configure_flameshot() {
  local flameshot_dir="${TARGET_HOME}/Pictures/flameshot"

  if sudo -u "$USER_NAME" -H bash -lc '
    [[ -f "$HOME/.config/flameshot/flameshot.ini" ]] && \
    grep -q "^startupLaunch=true$" "$HOME/.config/flameshot/flameshot.ini" && \
    grep -q "^savePathFixed=true$" "$HOME/.config/flameshot/flameshot.ini"
  '; then
    info "Flameshot already configured, skipping"
    return
  fi

  install -d -o "$TARGET_USER" -g "$TARGET_GROUP" "$flameshot_dir"
  sudo -u "$TARGET_USER" -H bash -s -- "$flameshot_dir" <<'USER_CONFIG'
set -euo pipefail

flameshot_dir="$1"
mkdir -p "$HOME/.config/flameshot"
cat > "$HOME/.config/flameshot/flameshot.ini" <<EOF
[General]
contrastOpacity=188
copyOnDoubleClick=true
copyPathAfterSave=false
saveAfterCopy=true
saveAsFileExtension=png
saveLastRegion=false
savePath=${flameshot_dir}
savePathFixed=true
showHelp=false
showMagnifier=true
showStartupLaunchMessage=false
squareMagnifier=true
startupLaunch=true
EOF
USER_CONFIG

  ok "Flameshot configured"
}

install_obsidian() (
  set -euo pipefail

  local api_url="https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest"
  local release_json tag latest_version
  local architecture asset_url asset_name asset_digest
  local installed_version tmp_dir deb_file package_name

  for cmd in curl jq dpkg dpkg-query dpkg-deb apt-get; do
    command -v "$cmd" >/dev/null 2>&1 ||
      die "${cmd} is required to install Obsidian"
  done

  architecture="$(dpkg --print-architecture)"
  case "$architecture" in
    amd64|arm64) ;;
    *)
      warn "unsupported Obsidian architecture: ${architecture}"
      return
      ;;
  esac

  # Remove the Snap version to avoid duplicate launchers.
  if command -v snap >/dev/null 2>&1 &&
    snap list obsidian >/dev/null 2>&1; then
    info "removing Obsidian snap"
    snap remove obsidian
  fi

  info "checking latest Obsidian GitHub release"

  release_json="$(curl -fsSL --retry 3 "$api_url")"
  tag="$(jq -r '.tag_name // empty' <<<"$release_json")"
  [[ -n "$tag" ]] ||
    die "could not determine the latest Obsidian release"

  latest_version="${tag#v}"

  installed_version="$(
    dpkg-query -W -f='${Version}' obsidian 2>/dev/null || true
  )"

  if [[ -n "$installed_version" ]] &&
    dpkg --compare-versions "$installed_version" ge "$latest_version"; then
    info "Obsidian ${installed_version} already installed, skipping"
    return
  fi

asset_url="$(
  jq -r --arg arch "$architecture" '
    first(
      .assets[]
      | select(.name | endswith("_" + $arch + ".deb"))
      | .browser_download_url
    ) // empty
  ' <<<"$release_json"
)"

  [[ -n "$asset_url" ]] ||
    die "no Obsidian Debian package found for ${architecture}"

  asset_name="${asset_url##*/}"

  asset_digest="$(
    jq -r --arg name "$asset_name" '
      [.assets[] | select(.name == $name)][0].digest // empty
    ' <<<"$release_json"
  )"

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$tmp_dir"' EXIT

  deb_file="$tmp_dir/$asset_name"

  info "downloading Obsidian ${tag} for ${architecture}"
  curl -fL --retry 3 "$asset_url" -o "$deb_file"

  # Verify the GitHub-provided SHA-256 digest when available.
  if [[ "$asset_digest" == sha256:* ]]; then
    printf '%s  %s\n' \
      "${asset_digest#sha256:}" \
      "$deb_file" |
      sha256sum --check -
  else
    warn "GitHub API did not provide an asset digest; continuing after package validation"
  fi

  dpkg-deb --info "$deb_file" >/dev/null

  package_name="$(dpkg-deb -f "$deb_file" Package)"
  [[ "$package_name" == "obsidian" ]] ||
    die "unexpected Debian package name: ${package_name}"

  info "installing Obsidian ${tag}"
  run_apt_get install -y "$deb_file"

  installed_version="$(
    dpkg-query -W -f='${Version}' obsidian 2>/dev/null || true
  )"

  [[ -n "$installed_version" ]] ||
    die "Obsidian installation could not be verified"

  ok "Obsidian ${installed_version} installed from the official GitHub release"
)

# --- Common user tools and shell configuration ---
prepare_user_workspace() (
  set -euo pipefail

  local account="${1:-$USER_NAME}"
  local home
  local group
  local repos_root
  local obsidian_dir
  local ssh_dir

  home="$(user_home "$account")"
  [[ -n "$home" && -d "$home" ]] ||
    die "could not determine home directory for ${account}"

  group="$(id -gn "$account")"

  repos_root="$home/repos"
  obsidian_dir="$home/obsidian"
  ssh_dir="$home/.ssh"

  info "preparing workspace directories for ${account}"

  install -d \
    -o "$account" \
    -g "$group" \
    -m 0755 \
    "$repos_root" \
    "$repos_root/github" \
    "$repos_root/gitlab" \
    "$repos_root/forgejo" \
    "$obsidian_dir"

  install -d \
    -o "$account" \
    -g "$group" \
    -m 0700 \
    "$ssh_dir"

  ok "GitHub repository directory ready: ${repos_root}/github"
  ok "GitLab repository directory ready: ${repos_root}/gitlab"
  ok "Forgejo repository directory ready: ${repos_root}/forgejo"
  ok "Obsidian directory ready: ${obsidian_dir}"
  ok "SSH directory ready: ${ssh_dir}"
)

install_tldr_pipx() {
  if sudo -u "$USER_NAME" -H bash -lc 'pipx list 2>/dev/null | grep -q "package tldr"'; then
    info "tldr already installed via pipx, skipping"
    return
  fi

  sudo -u "$USER_NAME" -H bash -lc 'pipx install tldr && pipx ensurepath'
  ok "tldr installed via pipx"
}

install_fzf_for_user() {
  local account="$1"
  local home
  home="$(user_home "$account")"
  [[ -n "$home" ]] || die "could not determine home directory for ${account}"

  if [[ -d "$home/.fzf/.git" ]]; then
    info "updating fzf checkout for ${account}"
    sudo -u "$account" -H git -C "$home/.fzf" pull --quiet --ff-only
  elif [[ -e "$home/.fzf" ]]; then
    warn "${home}/.fzf exists but is not a Git checkout; skipping fzf for ${account}"
    return
  else
    info "cloning fzf for ${account}"
    sudo -u "$account" -H git clone --quiet --depth 1 https://github.com/junegunn/fzf.git "$home/.fzf"
  fi

  run_quiet_command \
    "fzf installer for ${account}" \
    sudo -u "$account" -H "$home/.fzf/install" \
    --all --no-update-rc --no-zsh --no-fish --no-nushell ||
    die "fzf installation failed for ${account}"
  ok "fzf installed for ${account}"
}

install_starship() (
  set -Eeuo pipefail

  local line
  local temporary_dir
  temporary_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temporary_dir"' EXIT

  info "installing/updating Starship"
  curl \
    --fail \
    --show-error \
    --silent \
    --location \
    --output "$temporary_dir/install.sh" \
    "$STARSHIP_INSTALL_URL" || die "failed downloading the Starship installer"

  if ! sh "$temporary_dir/install.sh" --yes >"$temporary_dir/install.log" 2>&1; then
    while IFS= read -r line; do
      error "Starship installer: ${line}"
    done <"$temporary_dir/install.log"
    die "Starship installation failed"
  fi

  command -v starship >/dev/null 2>&1 || die "Starship installation did not provide a starship command"
  ok "Starship installed"
)

install_jetbrainsmono_nerd_font_for_user() {
  local account="$1"
  local home
  home="$(user_home "$account")"
  [[ -n "$home" ]] || die "could not determine home directory for ${account}"

  if sudo -u "$account" -H fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    info "JetBrainsMono Nerd Font already installed for ${account}, skipping"
    return
  fi

  sudo -u "$account" -H bash -c '
    set -euo pipefail
    font_dir="$HOME/.local/share/fonts"
    archive="$(mktemp --suffix=.zip)"
    mkdir -p "$font_dir"
    curl --fail --show-error --silent --location --output "$archive" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    unzip -q -o "$archive" -d "$font_dir"
    rm -f "$archive"
    fc-cache -f "$font_dir"
  '
  ok "JetBrainsMono Nerd Font installed for ${account}"
}

configure_bash_for_user() {
  local account="$1"
  local home
  local bat_link
  home="$(user_home "$account")"
  [[ -n "$home" ]] || die "could not determine home directory for ${account}"
  bat_link="$home/.local/bin/bat"

  sudo -u "$account" -H mkdir -p "$home/.local/bin"
  if [[ -L "$bat_link" ]]; then
    sudo -u "$account" -H ln -sfn /usr/bin/batcat "$bat_link"
  elif [[ -e "$bat_link" ]]; then
    warn "${bat_link} is not a symlink; preserving it"
  else
    sudo -u "$account" -H ln -s /usr/bin/batcat "$bat_link"
  fi

  sudo -u "$account" -H python3 - "$home" <<'PY'
from datetime import datetime
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

home = Path(sys.argv[1])
bashrc = home / ".bashrc"
aliases_path = home / ".bash_aliases"

aliases = r'''# $HOME/.bash_aliases — centralized interactive aliases

# System update
# alias updateos='sudo sh -c "apt update && apt -y upgrade && apt -y autoremove"'
# Comment above & Uncomment the following for full Ubuntu + Snap + Brew update
alias updateos='sudo sh -c "apt update && apt -y upgrade && apt -y autoremove && snap refresh && flatpak update -y" && brew upgrade'

# Core utils
alias brave='brave-browser'
alias cat='batcat -pp'
alias df='df -h'
alias diff='diff --color=auto'
alias dir='dir --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
alias fd='fdfind -H'
alias grep='grep --color=auto'
alias vdir='vdir --color=auto'
alias which-command='type'

# Listing
alias ls='ls -lh --color=auto'
alias la='ls -A'
alias l='eza -lah --group-directories-first'
alias ll='l -T'

# History
alias h='history'
alias hl='history | less'
alias hs='history | grep'
alias hsi='history | grep -i'

# Network / ports
alias ip='ip --color=auto'
alias ipa='ip -br -c a'
alias ports='ss -tunlp'

# Python
alias p3='python3'
alias python='python3'

# Search
alias ugq='ugrep --pretty --hidden -Qria'

# Mask stdin after first 5 chars
alias mask='awk '\''{ printf substr($0, 1, 5); for (i=6; i<=length($0); i++) printf "*"; print "" }'\'''

# Preserve alias expansion after sudo
alias sudo='sudo '

# Ubuntu default long-running command notification
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'
'''

fzf_block = r'''# >>> fzf (managed) >>>
export FZF_DEFAULT_OPTS='-m --height 50% --border'
export FZF_CTRL_R_OPTS="$FZF_DEFAULT_OPTS"
export FZF_CTRL_T_OPTS="$FZF_DEFAULT_OPTS"
export FZF_ALT_C_OPTS="$FZF_DEFAULT_OPTS"

[ -f "$HOME/.fzf.bash" ] && source "$HOME/.fzf.bash"
# <<< fzf (managed) <<<'''

fastfetch_block = r'''# >>> fastfetch (managed) >>>
# Fastfetch - login shells only
if shopt -q login_shell && command -v fastfetch >/dev/null 2>&1; then
    clear
    fastfetch
fi
# <<< fastfetch (managed) <<<'''

starship_block = r'''# >>> starship (managed) >>>
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init bash)"
else
  PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
fi
# <<< starship (managed) <<<'''

dotfiles_hook = r'''# >>> future dotfiles hook (disabled) >>>
# DOTFILES_REPO_URL="https://github.com/<owner>/<dotfiles-repository>.git"
# DOTFILES_DIR="$HOME/.local/share/dotfiles"
# if [ -d "$DOTFILES_DIR/.git" ]; then
#   git -C "$DOTFILES_DIR" pull --ff-only
# else
#   git clone "$DOTFILES_REPO_URL" "$DOTFILES_DIR"
# fi
# "$DOTFILES_DIR/install.sh"
# <<< future dotfiles hook (disabled) <<<'''

def backup(path: Path) -> None:
    stamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
    destination = path.with_name(f"{path.name}.bak.{stamp}")
    counter = 1
    while destination.exists():
        destination = path.with_name(f"{path.name}.bak.{stamp}.{counter}")
        counter += 1
    shutil.copy2(path, destination)

def install_if_changed(path: Path, content: str) -> bool:
    content = content.rstrip() + "\n"
    old = path.read_text(encoding="utf-8") if path.exists() else None
    if old == content:
        return False

    path.parent.mkdir(parents=True, exist_ok=True)
    fd, candidate_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    candidate = Path(candidate_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
        subprocess.run(["bash", "-n", str(candidate)], check=True)
        if path.exists():
            backup(path)
            candidate.chmod(path.stat().st_mode & 0o777)
        else:
            candidate.chmod(0o644)
        os.replace(candidate, path)
    finally:
        candidate.unlink(missing_ok=True)
    return True

def set_line(content: str, pattern: str, replacement: str) -> str:
    if re.search(pattern, content, flags=re.M):
        replaced = False

        def replace_once(match: re.Match[str]) -> str:
            nonlocal replaced
            if not replaced:
                replaced = True
                return replacement
            return ""

        return re.sub(pattern, replace_once, content, flags=re.M)
    return content.rstrip() + "\n" + replacement + "\n"

source = bashrc.read_text(encoding="utf-8") if bashrc.exists() else ""

# Comment active aliases while preserving indentation and commented aliases.
source = re.sub(
    r'^(?![ \t]*#)([ \t]*)(alias[ \t].*)$',
    r'\1# \2',
    source,
    flags=re.M,
)

source = set_line(source, r'^[ \t]*HISTCONTROL=.*$', 'HISTCONTROL=ignoreboth:erasedups')
source = set_line(source, r'^[ \t]*HISTSIZE=.*$', 'HISTSIZE=50000')
source = set_line(source, r'^[ \t]*HISTFILESIZE=.*$', 'HISTFILESIZE=100000')
source = re.sub(r'^[ \t]*HISTTIMEFORMAT=.*\n?', '', source, flags=re.M)
source = re.sub(
    r'(^HISTFILESIZE=.*$)',
    lambda match: match.group(1) + "\nHISTTIMEFORMAT='%F %T '",
    source,
    count=1,
    flags=re.M,
)
source = set_line(source, r'^[ \t]*PROMPT_COMMAND=.*$', "PROMPT_COMMAND='history -a; history -n'")
source = set_line(source, r'^[ \t]*#?[ \t]*shopt -s checkwinsize.*$', 'shopt -s checkwinsize')
source = set_line(source, r'^[ \t]*#?[ \t]*shopt -s globstar.*$', 'shopt -s globstar 2>/dev/null')
source = re.sub(r'^[ \t]*#?[ \t]*set -o vi[ \t]*\n?', '', source, flags=re.M)

for name in ("fzf", "fastfetch", "starship", "future dotfiles hook"):
    source = re.sub(
        rf'\n?# >>> {re.escape(name)} \((?:managed|disabled)\) >>>.*?# <<< {re.escape(name)} \((?:managed|disabled)\) <<<\n?',
        '\n',
        source,
        flags=re.S,
    )

source = re.sub(
    r'^[ \t]*\[ -[fr] (?:~|"\$HOME)/\.fzf\.bash"? \] && source (?:~|"\$HOME)/\.fzf\.bash"?[ \t]*\n?',
    '',
    source,
    flags=re.M,
)

if not re.search(r'^[^#\n]*\.bash_aliases', source, flags=re.M):
    source = source.rstrip() + r'''

# Load centralized aliases.
if [ -f "$HOME/.bash_aliases" ]; then
  . "$HOME/.bash_aliases"
fi
'''

source = source.rstrip() + "\n\n" + fzf_block + "\n\n" + fastfetch_block + "\n\n" + starship_block + "\n\n" + dotfiles_hook + "\n"

install_if_changed(aliases_path, aliases)
install_if_changed(bashrc, source)
PY

  sudo -u "$account" -H bash -n "$home/.bashrc"
  sudo -u "$account" -H bash -n "$home/.bash_aliases"
  ok "Bash configuration installed for ${account}"
}

configure_starship_for_user() {
  local account="$1"
  local home
  home="$(user_home "$account")"
  [[ -n "$home" ]] || die "could not determine home directory for ${account}"

  sudo -u "$account" -H python3 - "$home" <<'PY'
from datetime import datetime
from pathlib import Path
import os
import shutil
import sys
import tempfile

home = Path(sys.argv[1])
path = home / ".config" / "starship.toml"
content = """format = \"\"\"
${custom.root_marker}\\
$username\\
${custom.directory_icon}\\
$directory\\
$git_branch\\
$git_status\\
$fill\\
$hostname\\
$jobs\\
$cmd_duration\\
$status\\
$time\\
$line_break\\
$character\"\"\"

add_newline = false

[custom.root_marker]
command = "printf ''"
when = 'test "$(id -u)" -eq 0'
format = "[$output]($style) "
style = "bold red"

[username]
show_always = true
format = "[$user]($style) "
style_user = "bold yellow"
style_root = "bold red"

[custom.directory_icon]
command = '''
if [ "$PWD" = "$HOME" ]; then
    printf ''
else
    printf ''
fi
'''
when = true
format = "[$output]($style) "
style = "bold cyan"

[directory]
format = "[$path]($style) "
style = "bold cyan"
home_symbol = "~"
truncation_length = 3
truncation_symbol = "…/"
truncate_to_repo = false
read_only = " "
read_only_style = "bold red"

[git_branch]
symbol = " "
format = "[$symbol$branch]($style) "
style = "bold green"

[git_status]
format = "([$all_status$ahead_behind]($style) )"
style = "bold yellow"

[hostname]
ssh_only = true
format = "[$ssh_symbol$hostname]($style) "
style = "dimmed cyan"
ssh_symbol = "󰣀 "

[jobs]
symbol = " "
format = "[$symbol$number]($style) "
style = "bold red"
number_threshold = 1

[cmd_duration]
min_time = 2000
format = "[$duration]($style) "
style = "dimmed yellow"

[status]
disabled = false
format = "[$symbol$signal_name$maybe_int]($style) "
symbol = "✘ "
sigint_symbol = "✘ "
signal_symbol = "✘ "
not_executable_symbol = "✘ "
not_found_symbol = "✘ "
recognize_signal_code = true
map_symbol = false
style = "bold red"

[time]
disabled = false
format = "[ $time]($style)"
time_format = "%H:%M:%S"
style = "bold cyan"

[character]
format = "$symbol "
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"

[fill]
symbol = " "
"""

content = content.rstrip() + "\n"
old = path.read_text(encoding="utf-8") if path.exists() else None
if old != content:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        stamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
        backup = path.with_name(f"{path.name}.bak.{stamp}")
        counter = 1
        while backup.exists():
            backup = path.with_name(f"{path.name}.bak.{stamp}.{counter}")
            counter += 1
        shutil.copy2(path, backup)
    fd, candidate_name = tempfile.mkstemp(prefix=".starship.toml.", dir=path.parent)
    candidate = Path(candidate_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(content)
        candidate.chmod(0o644)
        os.replace(candidate, path)
    finally:
        candidate.unlink(missing_ok=True)
PY
  ok "Starship configuration installed for ${account}"
}

configure_git_for_user() {
  local account="$1"
  local git_name="syselement"
  local git_email="81392234+syselement@users.noreply.github.com"

  if ! id "$account" >/dev/null 2>&1; then
    warn "user not found: ${account}; skipping Git configuration"
    return
  fi

  sudo -u "$account" -H git config --global user.name "$git_name"
  sudo -u "$account" -H git config --global user.email "$git_email"
  sudo -u "$account" -H git config --global pull.rebase true
  sudo -u "$account" -H git config --global rebase.autoStash true

  if [[ "$(
    sudo -u "$account" -H git config --global --get user.name
  )" != "$git_name" ]] ||
     [[ "$(
       sudo -u "$account" -H git config --global --get user.email
     )" != "$git_email" ]] ||
     [[ "$(
       sudo -u "$account" -H git config --global --get pull.rebase
     )" != "true" ]] ||
     [[ "$(
       sudo -u "$account" -H git config --global --get rebase.autoStash
     )" != "true" ]]; then
    die "failed to configure Git for ${account}"
  fi

  ok "Git configured for ${account}: identity and pull-rebase policy"
}

install_homebrew_for_user() {
  local home
  local group
  local prefix="/home/linuxbrew/.linuxbrew"
  local brew_bin="${prefix}/bin/brew"
  local install_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

  home="$(user_home "$USER_NAME")"
  [[ -n "$home" ]] ||
    die "could not determine home directory for ${USER_NAME}"

  group="$(id -gn "$USER_NAME")"

  info "installing Homebrew prerequisites"
  run_apt_get install -y -qq \
    build-essential \
    procps \
    curl \
    file \
    git

  if [[ -x "$brew_bin" ]]; then
    info "Homebrew already installed"
  else
    info "installing Homebrew for ${USER_NAME}"

    # Pre-create the supported Linux prefix so the non-interactive installer does not require password-based sudo access.
    install -d -o "$USER_NAME" -g "$group" /home/linuxbrew
    install -d -o "$USER_NAME" -g "$group" "$prefix"

    sudo -u "$USER_NAME" -H env NONINTERACTIVE=1 USER="$USER_NAME" \
      /bin/bash -c "$(curl -fsSL --retry 3 --retry-all-errors --connect-timeout 15 "$install_url")"

    [[ -x "$brew_bin" ]] ||
      die "Homebrew installation did not provide ${brew_bin}"
  fi

  # Add Homebrew to Bash PATH idempotently.
  sudo -u "$USER_NAME" -H bash -c '
    set -euo pipefail

    rc="$HOME/.bashrc"
    line='\''eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'\''

    touch "$rc"

    if ! grep -Fqx "$line" "$rc"; then
      {
        printf "\n# Homebrew\n"
        printf "%s\n" "$line"
      } >> "$rc"
    fi
  '

  ok "$("$brew_bin" --version | sed -n '1p') installed"
}

show_manual_setup_hints() {
  local home
  home="$(user_home "$USER_NAME")"

  warn "=============================================================="
  warn "MANUAL POST-INSTALL SETUP"
  warn "=============================================================="
  info "1. Fingerprint login"
  info "   Settings → System → Users → Fingerprint Login"
  info "   Enroll at least two fingers and verify sudo authentication."
  info "=============================================================="
  info "2. Keyboard shortcuts"
  info "   Settings → Keyboard → View and Customize Shortcuts"
  info "   → Custom Shortcuts → Add Shortcut"
  info ""
  info "   - Flameshot"
  info "   Name: Flameshot"
  info "   Command:"
  info "   script --quiet --command \"/usr/bin/flameshot gui --clipboard --path ${home}/Pictures/flameshot\" /dev/null"
  info "   Recommended shortcut: Print, or Shift+Alt+S"
  info ""
  info "   - Emote keyboard shortcut"
  info "   Name: Emote"
  info "   Command:"
  info "   /snap/bin/emote"
  info "   Shortcut: Super+Period (Windows key + .)"
  info "=============================================================="
  info "3. Bluetooth devices"
  info "   Settings → Bluetooth"
  info "   Pair the mouse, soundbar, etc."
  info "=============================================================="
  info "4. Visual Studio Code"
  info "   Open VS Code → Accounts → Sign in with GitHub"
  info "   Enable Settings Sync and verify extensions/settings are restored."
  info "=============================================================="
  info "5. Bitwarden and EnteAuth"
  info "   Sign in and complete MFA."
  info "   Verify vault synchronization."
  info "=============================================================="
  info "6. Brave"
  info "   Open brave://settings/braveSync/setup"
  info "   Join the existing sync chain and verify bookmarks/extensions."
  info "=============================================================="
  info "7. Obsidian"
  info "   Create Obsidian vault inside:"
  info "   ${home}/obsidian"
  info "   Configure Obsidian Sync, Git, or the selected backup method."
  info "=============================================================="
  info "8. Telegram"
  info "   Sign in and verify the session."
  info "=============================================================="
  info "9. SSH private key"
  info "   - Copy the private key from a trusted offline source/password manager:"
  info "   cat > ${home}/.ssh/id_ed25519"
  info "   # paste key, then Ctrl-D"
  info "   chmod 600 ${home}/.ssh/id_ed25519"
  info ""
  info "   - Generate the matching public key:"
  info "   ssh-keygen -y -f ${home}/.ssh/id_ed25519 > ${home}/.ssh/id_ed25519.pub"
  info "   chmod 0644 ${home}/.ssh/id_ed25519.pub"
  info ""
  info "   - Load and test the key:"
  info "   ssh-add ${home}/.ssh/id_ed25519 || { eval \"\$(ssh-agent -s)\"; ssh-add ${home}/.ssh/id_ed25519; }"
  info "   ssh -T git@github.com"
  info "=============================================================="
  info "10. Clone GitHub repositories over SSH"
  info "    - GitHub:  cd ${home}/repos/github"
  info "    - GitLab:  cd ${home}/repos/gitlab"
  info "    - Forgejo: cd ${home}/repos/forgejo"
  info "    git clone git@github.com:syselement/<repository>.git"
  info ""
  info "    - Verify configured Git identity:"
  info "    git config list"
  warn "=============================================================="
}

main() {
  local end_ts elapsed start_ts

  initialize_runtime

  echo "################################"
  echo "# Customize System"
  echo "################################"

  info "================ RUN START ================"
  info "run_id: ${RUN_ID}"
  info "started_at: $(date -Is)"
  start_ts="$(date +%s)"

  info "distro version=${VERSION_ID} codename=${CODENAME} variant=${UBUNTU_VARIANT} variant_source=${UBUNTU_VARIANT_SOURCE} arch=${ARCH}"
  info "execution mode=${EXECUTION_MODE} context=${EXECUTION_CONTEXT} interactive=${EXECUTION_INTERACTIVE}"
  ok "target user=${TARGET_USER} home=${TARGET_HOME}"

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
  run_apt_get update -qq
  run_apt_get dist-upgrade -y -qq
  ok "apt update/dist-upgrade completed"

  # --- Update snaps (Desktop only) ---
  if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
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
  else
    info "server variant detected; skipping Desktop snap refresh"
  fi

  # --- APT prerequisites ---
  install_package_array "APT bootstrap" "${APT_BOOTSTRAP_PACKAGES[@]}"
  if [[ "$VERSION_ID" == 24.* ]]; then
    install_package_array "Ubuntu 24 repository bootstrap" software-properties-common
  fi

  # --- Configure repositories before one cache refresh ---
  info "ensuring common repositories"
  ensure_fastfetch_ppa
  install_docker_ctop_repository

  if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
    info "ensuring Desktop application repositories"
    ensure_sublime_text_repository
    ensure_brave_browser_repository
    ensure_dbeaver_repository
    ensure_mullvad_repository
  else
    info "server variant detected; skipping Desktop application repositories"
  fi

  if [[ "$APT_SOURCES_CHANGED" == true ]]; then
    info "apt update after repository changes"
    run_apt_get update -qq
  else
    info "APT repositories unchanged; existing package cache is current"
  fi

  # --- Install requested tools ---
  install_package_array "common" "${COMMON_PACKAGES[@]}"
  if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
    install_package_array "Desktop" "${DESKTOP_PACKAGES[@]}"
    configure_flathub
    install_flatpak_package_array "Desktop Flatpak" "${FLATPAK_PACKAGES[@]}"
  else
    info "server variant detected; skipping Desktop packages"
  fi

  # --- Install common user tools and shell configuration ---
  info "installing common user tools and shell configuration"
  prepare_user_workspace "$USER_NAME"
  install_starship
  for account in "$USER_NAME" root; do
    install_fzf_for_user "$account"
    install_jetbrainsmono_nerd_font_for_user "$account"
    configure_bash_for_user "$account"
    configure_starship_for_user "$account"
  done
  install_tldr_pipx
  configure_git_for_user "$USER_NAME"
  install_homebrew_for_user
  ok "common user tools and shell configuration completed"

  # --- Install/configure Desktop-specific tools ---
  if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
    info "installing/configuring Desktop-specific tools"
    configure_desktop_wallpaper
    install_flameshot
    configure_flameshot
    install_obsidian
    configure_terminator
    configure_terminator_as_default "$USER_NAME"
    install_snap_package discord "Discord"
    connect_snap_interface discord:system-observe "Discord system-observe"
    install_snap_package emote "Emote"
    install_snap_package postman "Postman"
    install_snap_package telegram-desktop "Telegram Desktop"
    ok "Desktop-specific tools installed/configured"
  else
    info "server variant detected; skipping Desktop-specific tools"
  fi

  # --- Post-install tweaks ---
  info "updating locate database (best effort)"
  updatedb || true

  # --- GNOME and Dock customization (Desktop only) ---
  if [[ "$UBUNTU_VARIANT" == "desktop" ]]; then
    # Apply now, inside this provisioning run. When GNOME is already running,
    # target its real per-user bus; during headless SSH/Vagrant provisioning,
    # use the temporary-bus fallback from run_as_gnome_user().
    install_system_monitor_panel_extension "$USER_NAME"
    install_hide_universal_access_extension "$USER_NAME"
    apply_gnome_preferences
    enable_battery_health_preservation
  else
    info "server variant detected; skipping GNOME preferences"
  fi

  # --- Cleanup and update repositories ---
  info "cleanup"
  run_apt_get -y -qq autoremove --purge
  run_apt_get -y clean
  rm -rf /var/lib/apt/lists/*
  if ! run_apt_get -y update >/dev/null 2>&1; then
    warn "apt update after cleanup failed; package lists will be refreshed on the next run"
  fi
  ok "cleanup completed"

  # --- Manual setup hints ---
  show_manual_setup_hints

  end_ts="$(date +%s)"
  elapsed="$((end_ts - start_ts))"
  info "done: $(date -Is)"
  info "elapsed: $(printf '%02d:%02d:%02d' "$((elapsed / 3600))" "$((elapsed % 3600 / 60))" "$((elapsed % 60))")"
  info "log file: ${LOG_FILE}"
  info "run_id: ${RUN_ID}"
  info "================= RUN END ================="

  echo "################################"
  echo "# System Provisioning Complete"
  echo "################################"

  if [[ "$REBOOT_AT_END" == "true" ]]; then
    echo "[${SCRIPT_NAME}] rebooting in 10 seconds..."
    sleep 10
    sync
    shutdown -r now
  else
    echo "[${SCRIPT_NAME}] reboot deferred to orchestrator"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
