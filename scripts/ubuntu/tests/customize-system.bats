#!/usr/bin/env bats

setup() {
  CUSTOMIZE_SCRIPT="$BATS_TEST_DIRNAME/../03-customize-system.sh"

  # shellcheck source=../03-customize-system.sh
  source "$CUSTOMIZE_SCRIPT"

  SYSTEM_KEYRING_DIR="$BATS_TEST_TMPDIR/usr/share/keyrings"
  APT_SOURCES_DIR="$BATS_TEST_TMPDIR/etc/apt/sources.list.d"
  APT_TRUSTED_KEY_DIR="$BATS_TEST_TMPDIR/etc/apt/trusted.gpg.d"
  SYSTEMD_RUNTIME_DIR="$BATS_TEST_TMPDIR/run/systemd/system"
  mkdir -p "$SYSTEM_KEYRING_DIR" "$APT_SOURCES_DIR" "$APT_TRUSTED_KEY_DIR"

  info() {
    printf 'INFO: %s\n' "$*"
  }

  ok() {
    printf 'OK: %s\n' "$*"
  }
}

@test "customization script can be sourced without initializing provisioning" {
  declare -F main >/dev/null
  declare -F initialize_runtime >/dev/null
  declare -F section >/dev/null
  declare -F install_package_array >/dev/null
  declare -F install_virtualization_stack >/dev/null
  [[ -z "$USER_NAME" ]]
  [[ -z "$ARCH" ]]
}

@test "logger renders message content literally" {
  t_reset=""

  run log "INFO" "" 'literal \n and %s content'

  [[ "$status" -eq 0 ]]
  [[ "$output" == *' INFO  literal \n and %s content' ]]
}

@test "major section logger uses a strong ANSI-free delimiter without terminal colors" {
  t_bold=""
  t_cyan=""
  t_reset=""

  run section "Repositories"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *" STEP  ==================== Repositories ====================" ]]
  [[ "$output" != *" WARN "* ]]
  [[ "$output" != *$'\e['* ]]
}

@test "manual step logger remains visually lighter than a major section" {
  t_bold=""
  t_cyan=""
  t_reset=""

  run manual_step "1. SSH private key"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *" STEP  --- 1. SSH private key ---" ]]
  [[ "$output" != *"===================="* ]]
  [[ "$output" != *$'\e['* ]]
}

@test "manual setup instructions use clean unprefixed body lines" {
  UBUNTU_VARIANT="desktop"
  USER_NAME="$(id -un)"

  run show_manual_setup_hints

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"STEP  ==================== Manual Post-Install Setup ===================="* ]]
  [[ "$output" == *"STEP  --- 1. Fingerprint login ---"* ]]
  [[ "$output" == *"STEP  --- 11. WireGuard connection ---"* ]]
  [[ "$output" == *"STEP  --- 12. Cockpit web console ---"* ]]
  [[ "$output" == *"STEP  --- 13. Clone Git repositories over SSH ---"* ]]
  [[ "$output" == *"STEP  --- 14. Virtualization ---"* ]]
  [[ "$output" != *"/14"* ]]
  [[ "$output" == *"sudo nmcli connection import type wireguard file /etc/wireguard/wg0.conf"* ]]
  [[ "$output" == *"Visit: https://localhost:9090/"* ]]
  [[ "$output" == *"This applies the new libvirt group membership."* ]]
  [[ "$output" == *$'\n    Open: Settings -> System -> Users -> Fingerprint Login'* ]]
  [[ "$output" == *$'\n    • Name: Claude new chat'* ]]
  [[ "$output" == *$'\n      $ claude-desktop claude://claude.ai/new'* ]]
  [[ "$output" == *$'\n    Shortcut: Ctrl+Alt+Space'* ]]
  [[ "$output" == *$'\n      $ script --quiet --command'* ]]
  [[ "$output" != *" INFO  "* ]]
  [[ "$output" != *" WARN "* ]]
}

@test "Server manual setup uses headless virtualization instructions" {
  UBUNTU_VARIANT="server"
  USER_NAME="$(id -un)"

  run show_manual_setup_hints

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"STEP  --- 1. SSH private key ---"* ]]
  [[ "$output" == *"STEP  --- 6. Virtualization ---"* ]]
  [[ "$output" == *"Manage this headless host with virsh or a remote virt-manager client."* ]]
  [[ "$output" != *'$ virt-manager --connect qemu:///system'* ]]
  [[ "$output" != *"Fingerprint login"* ]]
  [[ "$output" != *"Keyboard shortcuts"* ]]
  [[ "$output" != *"Brave"* ]]
  [[ "$output" != *"Obsidian"* ]]
  [[ "$output" != *"Telegram"* ]]
}

@test "external downloads use bounded transfer settings" {
  local curl_record="$BATS_TEST_TMPDIR/curl-record"

  curl() {
    printf '%s\n' "$@" >"$curl_record"
  }

  fetch_file "https://example.invalid/test" "$BATS_TEST_TMPDIR/download"

  grep -Fxq -- '--connect-timeout' "$curl_record"
  grep -Fxq -- '--max-time' "$curl_record"
  grep -Fxq -- '--speed-limit' "$curl_record"
  grep -Fxq -- '--speed-time' "$curl_record"
  grep -Fxq -- '--retry' "$curl_record"
}

@test "APT and Snap network operations are bounded" {
  local apt_record="$BATS_TEST_TMPDIR/apt-record"

  apt-get() {
    printf '%s\n' "$@" >"$apt_record"
  }

  run_apt_get update

  grep -Fxq 'Acquire::Retries=3' "$apt_record"
  grep -Fxq 'Acquire::http::Timeout=30' "$apt_record"
  grep -Fxq 'Acquire::https::Timeout=30' "$apt_record"
  grep -Fq 'timeout --foreground 15m snap refresh' "$CUSTOMIZE_SCRIPT"
}

@test "provisioning logs enforce mode 0600 before capture" {
  local scripts_dir="$BATS_TEST_DIRNAME/.."

  grep -Fq 'install -m 0600 /dev/null "$LOG_FILE"' "$scripts_dir/02-provision-system.sh"
  grep -Fq 'install -m 0600 /dev/null "$LOG_FILE"' "$scripts_dir/03-customize-system.sh"
  grep -Fq 'chmod 0600 "$LOG_FILE"' "$scripts_dir/90-bootstrap-baremetal.sh"
  grep -Fq 'chmod 0600 "$LOG_FILE"' "$scripts_dir/autoinstall-desktop.yaml"
  grep -Fq 'chmod 0600 "$LOG_FILE"' "$scripts_dir/autoinstall-server.yaml"
}

@test "requested APT and Flatpak packages remain organized by scope" {
  [[ " ${COMMON_PACKAGES[*]} " == *" cockpit "* ]]
  [[ " ${COMMON_PACKAGES[*]} " == *" tailscale "* ]]
  [[ " ${COMMON_PACKAGES[*]} " != *" rdap "* ]]
  [[ " ${RELEASE_OPTIONAL_PACKAGES[*]} " == *" rdap "* ]]
  [[ " ${DESKTOP_PACKAGES[*]} " == *" claude-desktop "* ]]
  [[ " ${DESKTOP_PACKAGES[*]} " == *" meld "* ]]
  [[ " ${DESKTOP_PACKAGES[*]} " == *" typora "* ]]
  [[ " ${FLATPAK_PACKAGES[*]} " == *" org.cryptomator.Cryptomator "* ]]
  [[ " ${VIRTUALIZATION_HOST_PACKAGES[*]} " == *" cockpit-machines "* ]]
  [[ " ${VIRTUALIZATION_HOST_PACKAGES[*]} " == *" libvirt-daemon-system "* ]]
  [[ " ${VIRTUALIZATION_HOST_PACKAGES[*]} " != *" virt-manager "* ]]
  [[ " ${VIRTUALIZATION_DESKTOP_PACKAGES[*]} " == *" virt-manager "* ]]
  [[ " ${VIRTUALIZATION_DESKTOP_PACKAGES[*]} " != *" cockpit-machines "* ]]
  [[ " ${VIRTUALIZATION_HOST_PACKAGES[*]} " != *" qemu-kvm "* ]]
}

@test "Desktop virtualization installs the native QEMU host and virt-manager" {
  ARCH="amd64"
  UBUNTU_VARIANT="desktop"

  install_package_array() {
    printf '<%s>\n' "$@"
  }

  run install_virtualization_stack

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"<cockpit-machines>"* ]]
  [[ "$output" == *"<cpu-checker>"* ]]
  [[ "$output" == *"<libvirt-daemon-system>"* ]]
  [[ "$output" == *"<qemu-system-x86>"* ]]
  [[ "$output" == *"<virt-manager>"* ]]
  [[ "$output" != *"<qemu-kvm>"* ]]
}

@test "Server virtualization installs libvirt and native QEMU without virt-manager" {
  ARCH="amd64"
  UBUNTU_VARIANT="server"

  install_package_array() {
    printf '<%s>\n' "$@"
  }

  run install_virtualization_stack

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"<cockpit-machines>"* ]]
  [[ "$output" == *"<libvirt-daemon-system>"* ]]
  [[ "$output" == *"<qemu-system-x86>"* ]]
  [[ "$output" != *"<virt-manager>"* ]]
}

@test "virtualization rerun skips packages that are already installed" {
  local query_record="$BATS_TEST_TMPDIR/virtualization-query-record"
  ARCH="amd64"
  UBUNTU_VARIANT="desktop"

  dpkg-query() {
    printf '%s\n' "${@: -1}" >>"$query_record"
    printf 'install ok installed'
  }
  run_apt_get() {
    printf 'unexpected package installation: %s\n' "$*" >&2
    return 99
  }

  run install_virtualization_stack

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"virtualization: all packages already installed"* ]]
  [[ "$output" != *"unexpected package installation"* ]]
  grep -Fqx "cockpit-machines" "$query_record"
  grep -Fqx "libvirt-daemon-system" "$query_record"
  grep -Fqx "qemu-system-x86" "$query_record"
  grep -Fqx "virt-manager" "$query_record"
}

@test "virtualization selects native QEMU for ARM64" {
  ARCH="arm64"
  UBUNTU_VARIANT="server"

  install_package_array() {
    printf '<%s>\n' "$@"
  }

  run install_virtualization_stack

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"<qemu-system-arm>"* ]]
}

@test "virtualization rejects an unsupported architecture clearly" {
  ARCH="unsupported"
  UBUNTU_VARIANT="server"

  install_package_array() {
    printf 'unexpected package installation\n' >&2
    return 99
  }

  run install_virtualization_stack

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"virtualization is not configured for architecture unsupported"* ]]
  [[ "$output" != *"unexpected package installation"* ]]
}

@test "target-user helper provides the resolved identity and home" {
  TARGET_USER="testuser"
  TARGET_HOME="/home/testuser"
  TARGET_UID="1234"
  TARGET_GROUP="testgroup"

  sudo() {
    printf '<%s>\n' "$@"
  }

  run run_as_target_user command-name argument

  [[ "$status" -eq 0 ]]
  [[ "$output" == *'<-u>'*'<testuser>'* ]]
  [[ "$output" == *'<-g>'*'<testgroup>'* ]]
  [[ "$output" == *'<HOME=/home/testuser>'* ]]
  [[ "$output" == *'<TARGET_USER=testuser>'* ]]
  [[ "$output" == *'<TARGET_HOME=/home/testuser>'* ]]
  [[ "$output" == *'<TARGET_UID=1234>'* ]]
  [[ "$output" == *'<TARGET_GROUP=testgroup>'* ]]
  [[ "$output" == *'<command-name>'*'<argument>'* ]]
}

@test "GNOME helper uses the target user's existing D-Bus session" {
  TARGET_UID="1234"

  gnome_user_bus_available() {
    return 0
  }
  run_as_target_user() {
    printf '<%s>\n' "$@"
  }

  run run_as_gnome_user command-name argument

  [[ "$status" -eq 0 ]]
  [[ "$output" == *'<XDG_RUNTIME_DIR=/run/user/1234>'* ]]
  [[ "$output" == *'<DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1234/bus>'* ]]
  [[ "$output" == *'<command-name>'*'<argument>'* ]]
  [[ "$output" != *'<dbus-run-session>'* ]]
}

@test "GNOME helper uses one temporary D-Bus session during automation" {
  TARGET_UID="1234"

  gnome_user_bus_available() {
    return 1
  }
  run_as_target_user() {
    printf '<%s>\n' "$@"
  }

  run run_as_gnome_user command-name argument

  [[ "$status" -eq 0 ]]
  [[ "$output" == *'<dbus-run-session>'*'<-->'*'<command-name>'*'<argument>'* ]]
  [[ "$output" != *'<DBUS_SESSION_BUS_ADDRESS='* ]]
}

@test "wallpaper preparation uses the script-local asset without repository synchronization" {
  local source_file="$BATS_TEST_DIRNAME/../ubuntu-wallpaper.png"

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"

  mkdir -p "$TARGET_HOME"

  git() {
    printf 'unexpected wallpaper repository synchronization\n' >&2
    return 99
  }

  run configure_desktop_wallpaper

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"GNOME wallpaper file ready"* ]]
  [[ "$output" != *"unexpected wallpaper repository synchronization"* ]]
  cmp -s "$source_file" "$TARGET_HOME/.config/background"
}

@test "GNOME preferences persist dock position and enable installed user extensions" {
  local fake_bin="$BATS_TEST_TMPDIR/bin"
  local settings_dir="$BATS_TEST_TMPDIR/settings"
  local command_log="$BATS_TEST_TMPDIR/gsettings.log"

  TARGET_HOME="$BATS_TEST_TMPDIR"

  mkdir -p \
    "$fake_bin" \
    "$settings_dir" \
    "$BATS_TEST_TMPDIR/.local/share/gnome-shell/extensions/dim-background-windows@stephane-13.github.com/schemas" \
    "$BATS_TEST_TMPDIR/.local/share/gnome-shell/extensions/system-monitor-panel@naimur" \
    "$BATS_TEST_TMPDIR/.local/share/gnome-shell/extensions/hide-universal-access@akiirui.github.io"

  cat >"$fake_bin/gsettings" <<'FAKE_GSETTINGS'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$1" == "--schemadir" ]]; then
  shift 2
fi

command="$1"
schema="${2:-}"
key="${3:-}"
state_file="${FAKE_SETTINGS_DIR}/${schema}.${key}"

case "$command" in
  list-schemas)
    printf '%s\n' \
      org.gnome.desktop.interface \
      org.gnome.desktop.background \
      org.gnome.shell.extensions.dash-to-dock \
      org.gnome.desktop.notifications \
      org.gnome.desktop.screensaver \
      org.gnome.desktop.session \
      org.gnome.system.location \
      org.gnome.settings-daemon.plugins.color \
      org.gnome.desktop.sound \
      org.gnome.settings-daemon.plugins.power \
      org.gnome.shell.extensions.ding \
      org.gnome.desktop.peripherals.touchpad \
      org.gnome.shell.extensions.dim-background-windows \
      org.gnome.shell
    ;;
  list-keys)
    printf '%s\n' \
      color-scheme document-font-name font-name gtk-theme monospace-font-name \
      show-battery-percentage text-scaling-factor picture-uri picture-uri-dark picture-options \
      click-action dash-max-icon-size \
      dock-position extend-height show-trash show-in-lock-screen lock-delay \
      lock-enabled ubuntu-lock-on-suspend idle-delay enabled night-light-enabled \
      night-light-schedule-automatic night-light-schedule-from night-light-schedule-to \
      night-light-temperature allow-volume-above-100-percent power-button-action \
      show-home natural-scroll favorite-apps disable-user-extensions \
      enabled-extensions disabled-extensions brightness saturation
    ;;
  writable)
    printf 'true\n'
    ;;
  get)
    if [[ -f "$state_file" ]]; then
      cat "$state_file"
    elif [[ "$key" == "dock-position" ]]; then
      printf "'BOTTOM'\n"
    elif [[ "$key" == "enabled-extensions" || "$key" == "disabled-extensions" ]]; then
      printf '@as []\n'
    else
      printf 'false\n'
    fi
    ;;
  set)
    printf '%s\t%s\t%s\n' "$schema" "$key" "$4" >>"$FAKE_GSETTINGS_LOG"
    printf '%s\n' "$4" >"$state_file"
    ;;
  *)
    exit 2
    ;;
esac
FAKE_GSETTINGS
  chmod +x "$fake_bin/gsettings"

  gnome_user_bus_available() {
    return 1
  }
  run_as_gnome_user() {
    HOME="$BATS_TEST_TMPDIR" \
      PATH="$fake_bin:$PATH" \
      FAKE_SETTINGS_DIR="$settings_dir" \
      FAKE_GSETTINGS_LOG="$command_log" \
      "$@"
  }

  run apply_gnome_preferences

  [[ "$status" -eq 0 ]]
  grep -Fq $'org.gnome.shell.extensions.dash-to-dock\tdock-position\t\x27BOTTOM\x27' "$command_log"
  grep -Fq $'org.gnome.desktop.background\tpicture-uri\t\x27file://' "$command_log"
  grep -Fq $'org.gnome.shell.extensions.dim-background-windows\tbrightness\t0.8' "$command_log"
  grep -Fq $'org.gnome.shell.extensions.dim-background-windows\tsaturation\t1.0' "$command_log"
  grep -Fq 'dim-background-windows@stephane-13.github.com' \
    "$settings_dir/org.gnome.shell.enabled-extensions"
  grep -Fq 'hide-universal-access@akiirui.github.io' \
    "$settings_dir/org.gnome.shell.enabled-extensions"
}

@test "GNOME extension download is staged, validated, and installed as the target user" {
  local command_record="$BATS_TEST_TMPDIR/extension-command"
  local validation_record="$BATS_TEST_TMPDIR/extension-validation"
  local uuid="test-extension@example.com"

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  mkdir -p "$TARGET_HOME"

  command() {
    if [[ "$1" == "-v" ]]; then
      return 0
    fi
    builtin command "$@"
  }
  fetch_file() {
    printf 'staged extension\n' >"$2"
  }
  validate_zip_archive() {
    printf '%s|%s\n' "$1" "$2" >"$validation_record"
  }
  validate_gnome_extension_archive() {
    printf '%s\n' "$2" >>"$validation_record"
  }
  run_as_target_user() {
    printf '%s\n' "$*" >"$command_record"
    mkdir -p "$TARGET_HOME/.local/share/gnome-shell/extensions/$uuid"
    printf '{"uuid":"%s"}\n' "$uuid" \
      >"$TARGET_HOME/.local/share/gnome-shell/extensions/$uuid/metadata.json"
  }

  run install_gnome_extension_from_zip \
    "Test Extension" "$uuid" "https://example.invalid/extension.zip"

  [[ "$status" -eq 0 ]]
  grep -Fq 'gnome-extensions install --force' "$command_record"
  grep -Fq "$uuid" "$validation_record"
  [[ "$output" == *"Test Extension extension installed for ${TARGET_USER}"* ]]

  fetch_file() {
    printf 'unexpected extension download\n' >&2
    return 99
  }
  run_as_target_user() {
    printf 'unexpected extension reinstall\n' >&2
    return 99
  }
  run install_gnome_extension_from_zip \
    "Test Extension" "$uuid" "https://example.invalid/extension.zip"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"already installed and verified, skipping"* ]]
  [[ "$output" != *"unexpected extension"* ]]
}

@test "Dim Background Windows uses the pinned stable GNOME Extensions bundle" {
  TARGET_USER="testuser"

  install_gnome_extension_from_zip() {
    printf '<%s>\n' "$@"
  }
  compile_gnome_extension_schemas() {
    printf '<compile:%s>\n' "$*"
  }

  for VERSION_ID in 24.04 26.04; do
    run install_dim_background_windows_extension "$TARGET_USER"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'<Dim Background Windows>'* ]]
    [[ "$output" == *'<dim-background-windows@stephane-13.github.com>'* ]]
    [[ "$output" == *'<https://extensions.gnome.org/download-extension/dim-background-windows@stephane-13.github.com.shell-extension.zip?version_tag=70012>'* ]]
    [[ "$output" == *'<compile:Dim Background Windows dim-background-windows@stephane-13.github.com>'* ]]
  done
}

@test "GNOME extension schemas compile once and remain target-owned" {
  local uuid="test-extension@example.com"
  local schema_dir
  local compile_record="$BATS_TEST_TMPDIR/schema-compile.log"

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  schema_dir="$TARGET_HOME/.local/share/gnome-shell/extensions/$uuid/schemas"

  mkdir -p "$schema_dir"
  printf '<schemalist/>\n' >"$schema_dir/org.example.gschema.xml"

  command() {
    if [[ "$1" == "-v" && "$2" == "glib-compile-schemas" ]]; then
      return 0
    fi
    builtin command "$@"
  }
  run_as_target_user() {
    printf '%s\n' "$*" >>"$compile_record"
    touch "$schema_dir/gschemas.compiled"
  }

  run compile_gnome_extension_schemas "Test Extension" "$uuid"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Test Extension extension schemas compiled"* ]]
  [[ "$(<"$compile_record")" == "glib-compile-schemas $schema_dir" ]]

  run compile_gnome_extension_schemas "Test Extension" "$uuid"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"schemas already compiled"* ]]
  [[ "$(wc -l <"$compile_record")" -eq 1 ]]
}

@test "failed GNOME extension download does not invoke the target installer" {
  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  mkdir -p "$TARGET_HOME/.local/share/gnome-shell/extensions/test-extension@example.com"
  printf 'preserve me\n' >"$TARGET_HOME/.local/share/gnome-shell/extensions/test-extension@example.com/local-state"

  command() {
    if [[ "$1" == "-v" ]]; then
      return 0
    fi
    builtin command "$@"
  }
  fetch_file() {
    return 28
  }
  run_as_target_user() {
    printf 'unexpected target installer\n' >&2
    return 99
  }

  run install_gnome_extension_from_zip \
    "Test Extension" "test-extension@example.com" "https://example.invalid/extension.zip"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"failed downloading Test Extension extension"* ]]
  [[ "$output" != *"unexpected target installer"* ]]
  [[ "$(<"$TARGET_HOME/.local/share/gnome-shell/extensions/test-extension@example.com/local-state")" == "preserve me" ]]
}

@test "APT package helper skips packages that are already installed" {
  dpkg-query() {
    printf 'install ok installed\n'
  }
  apt-get() {
    printf 'unexpected apt invocation\n' >&2
    return 99
  }

  run install_package_array "test" installed-package

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"all packages already installed"* ]]
  [[ "$output" != *"unexpected apt invocation"* ]]
}

@test "APT package helper installs only missing packages with lock handling" {
  dpkg-query() {
    if [[ "${*: -1}" == "installed-package" ]]; then
      printf 'install ok installed\n'
      return 0
    fi
    return 1
  }
  apt-get() {
    printf 'apt-get arguments: %s\n' "$*"
  }

  run install_package_array "test" installed-package missing-package

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"DPkg::Lock::Timeout=300"* ]]
  [[ "$output" == *"missing-package"* ]]
  [[ "$output" != *"install -y -qq installed-package"* ]]
}

@test "APT package helper propagates installation failure" {
  dpkg-query() {
    return 1
  }
  apt-get() {
    return 42
  }

  run install_package_array "test" required-package

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"failed installing test packages: required-package"* ]]
  [[ "$output" != *"package installation completed"* ]]
}

@test "release-optional packages skip entries unavailable on Ubuntu 24.04" {
  VERSION_ID="24.04"
  apt-cache() {
    return 1
  }
  install_package_array() {
    printf 'unexpected package installation\n' >&2
    return 99
  }

  run install_available_package_array "release-optional" rdap

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"rdap is unavailable for Ubuntu 24.04; skipping"* ]]
  [[ "$output" != *"unexpected package installation"* ]]
}

@test "release-optional packages install entries available on Ubuntu 26.04" {
  local install_record="$BATS_TEST_TMPDIR/install-record"

  VERSION_ID="26.04"
  apt-cache() {
    return 0
  }
  install_package_array() {
    printf '%s\n' "$*" >"$install_record"
  }

  install_available_package_array "release-optional" rdap

  [[ "$(<"$install_record")" == "release-optional rdap" ]]
}

@test "Cockpit socket helper skips an already enabled active socket" {
  mkdir -p "$SYSTEMD_RUNTIME_DIR"

  systemctl() {
    case "$1" in
      cat) return 0 ;;
      is-enabled | is-active) return 0 ;;
      *)
        printf 'unexpected Cockpit socket mutation: %s\n' "$*" >&2
        return 99
        ;;
    esac
  }

  run configure_cockpit_socket

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Cockpit socket already enabled and active"* ]]
  [[ "$output" != *"unexpected Cockpit socket mutation"* ]]
}

@test "Cockpit socket helper enables and starts a missing socket state" {
  local command_record="$BATS_TEST_TMPDIR/cockpit-systemctl-record"
  mkdir -p "$SYSTEMD_RUNTIME_DIR"

  systemctl() {
    printf '%s\n' "$*" >>"$command_record"
    case "$1" in
      cat | enable | start) return 0 ;;
      is-enabled | is-active) return 1 ;;
      *) return 2 ;;
    esac
  }

  run configure_cockpit_socket

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Cockpit socket enabled and active"* ]]
  grep -Fqx 'enable cockpit.socket' "$command_record"
  grep -Fqx 'start cockpit.socket' "$command_record"
}

@test "Cockpit socket activation is deferred when systemd is not running" {
  local command_record="$BATS_TEST_TMPDIR/cockpit-deferred-record"

  systemctl() {
    printf '%s\n' "$*" >>"$command_record"
    case "$1" in
      cat | enable) return 0 ;;
      is-enabled) return 1 ;;
      *) return 99 ;;
    esac
  }

  run configure_cockpit_socket

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Cockpit socket activation is deferred until boot"* ]]
  grep -Fqx 'enable cockpit.socket' "$command_record"
  ! grep -Fq 'start cockpit.socket' "$command_record"
}

@test "Libvirt configuration skips existing access and active socket state" {
  TARGET_USER="testuser"
  mkdir -p "$SYSTEMD_RUNTIME_DIR"

  getent() {
    [[ "$1" == "group" && "$2" == "libvirt" ]]
  }
  id() {
    [[ "$1" == "-nG" && "$2" == "$TARGET_USER" ]]
    printf 'testgroup libvirt\n'
  }
  usermod() {
    printf 'unexpected libvirt group mutation\n' >&2
    return 99
  }
  systemctl() {
    case "$1" in
      cat | is-enabled | is-active) return 0 ;;
      *)
        printf 'unexpected Libvirt socket mutation: %s\n' "$*" >&2
        return 99
        ;;
    esac
  }

  run configure_libvirt

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"already a member of the libvirt group"* ]]
  [[ "$output" == *"Libvirt socket already enabled and active"* ]]
  [[ "$output" != *"unexpected"* ]]
}

@test "Libvirt configuration adds only missing target-user membership" {
  local usermod_record="$BATS_TEST_TMPDIR/libvirt-usermod-record"
  TARGET_USER="testuser"
  mkdir -p "$SYSTEMD_RUNTIME_DIR"

  getent() {
    [[ "$1" == "group" && "$2" == "libvirt" ]]
  }
  id() {
    [[ "$1" == "-nG" && "$2" == "$TARGET_USER" ]]
    printf 'testgroup\n'
  }
  usermod() {
    printf '%s\n' "$*" >"$usermod_record"
  }
  systemctl() {
    case "$1" in
      cat | is-enabled | is-active) return 0 ;;
      *) return 99 ;;
    esac
  }

  run configure_libvirt

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"added testuser to the libvirt group"* ]]
  [[ "$(<"$usermod_record")" == "-aG libvirt testuser" ]]
}

@test "Libvirt configuration enables only its local Unix socket" {
  local command_record="$BATS_TEST_TMPDIR/libvirt-systemctl-record"
  TARGET_USER="testuser"
  mkdir -p "$SYSTEMD_RUNTIME_DIR"

  getent() {
    [[ "$1" == "group" && "$2" == "libvirt" ]]
  }
  id() {
    printf 'testgroup libvirt\n'
  }
  systemctl() {
    printf '%s\n' "$*" >>"$command_record"
    case "$1" in
      cat | enable | start) return 0 ;;
      is-enabled | is-active) return 1 ;;
      *) return 2 ;;
    esac
  }

  run configure_libvirt

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Libvirt socket enabled and active"* ]]
  grep -Fqx 'enable libvirtd.socket' "$command_record"
  grep -Fqx 'start libvirtd.socket' "$command_record"
  ! grep -Eq 'libvirtd-(tcp|tls)\\.socket' "$command_record"
}

@test "virtualization validation defers services and tolerates missing KVM" {
  KVM_DEVICE="$BATS_TEST_TMPDIR/missing-kvm"
  SYSTEMD_RUNTIME_DIR="$BATS_TEST_TMPDIR/missing-systemd"

  kvm-ok() {
    return 1
  }
  virsh() {
    printf 'unexpected virsh invocation\n' >&2
    return 99
  }

  run validate_virtualization_stack

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"KVM hardware acceleration is unavailable"* ]]
  [[ "$output" == *"libvirt connection validation is deferred until boot"* ]]
  [[ "$output" != *"unexpected virsh invocation"* ]]
}

@test "Desktop virtualization validation checks local service without changing networks" {
  local virsh_record="$BATS_TEST_TMPDIR/virtualization-virsh-record"
  KVM_DEVICE="/dev/null"
  UBUNTU_VARIANT="desktop"
  mkdir -p "$SYSTEMD_RUNTIME_DIR"

  virt-manager() {
    return 0
  }
  virsh() {
    printf '%s\n' "$*" >>"$virsh_record"
    if [[ "$*" == *" net-info default" ]]; then
      printf 'Name: default\nActive: no\n'
    fi
  }

  run validate_virtualization_stack

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"KVM hardware acceleration is available"* ]]
  [[ "$output" == *"local qemu:///system libvirt connection verified"* ]]
  [[ "$output" == *"Virtual Machine Manager installation verified"* ]]
  [[ "$output" == *"default network is defined but inactive"* ]]
  grep -Fqx -- '--connect qemu:///system list --all' "$virsh_record"
  grep -Fqx -- '--connect qemu:///system net-info default' "$virsh_record"
  ! grep -Eq 'net-(start|autostart)' "$virsh_record"
}

@test "virtualization validation fails on an unusable local libvirt service" {
  KVM_DEVICE="/dev/null"
  UBUNTU_VARIANT="server"
  mkdir -p "$SYSTEMD_RUNTIME_DIR"

  virsh() {
    return 1
  }

  run validate_virtualization_stack

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"cannot connect to the local qemu:///system libvirt service"* ]]
}

@test "Snap package helper skips an installed package" {
  snap() {
    if [[ "$1" == "list" ]]; then
      return 0
    fi
    printf 'unexpected snap mutation: %s\n' "$*" >&2
    return 99
  }

  run install_snap_package discord "Discord"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"already installed, skipping"* ]]
  [[ "$output" != *"unexpected snap mutation"* ]]
}

@test "Snap package helper installs a missing package once" {
  snap() {
    case "$1" in
      list) return 1 ;;
      install)
        printf 'snap install arguments: %s\n' "$*"
        return 0
        ;;
      *) return 2 ;;
    esac
  }

  run install_snap_package telegram-desktop "Telegram Desktop"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"snap install arguments: install telegram-desktop"* ]]
  [[ "$output" == *"Telegram Desktop snap installed"* ]]
}

@test "Snap package helper reports installation failure" {
  snap() {
    return 1
  }

  run install_snap_package postman "Postman"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"failed installing Postman snap (postman)"* ]]
  [[ "$output" != *"Postman snap installed"* ]]
}

@test "Flameshot writes one exact target-owned configuration and skips an identical rerun" {
  local config_file
  local first_inode

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  config_file="$TARGET_HOME/.config/flameshot/flameshot.ini"
  mkdir -p "$TARGET_HOME"

  run configure_flameshot
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Flameshot configured"* ]]
  [[ "$(stat -c '%U:%G:%a' "$config_file")" == "$TARGET_USER:$TARGET_GROUP:644" ]]
  grep -Fxq "savePath=${TARGET_HOME}/Pictures/flameshot" "$config_file"
  [[ "$(grep -Fc '[General]' "$config_file")" -eq 1 ]]
  first_inode="$(stat -c '%i' "$config_file")"

  run configure_flameshot
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Flameshot already configured, skipping"* ]]
  [[ "$(stat -c '%i' "$config_file")" == "$first_inode" ]]
  [[ ! -e "${config_file}.packertron.bak" ]]
}

@test "changed target configuration is backed up once and replaced atomically" {
  local destination_file="$BATS_TEST_TMPDIR/home/.config/test/config"
  local source_file="$BATS_TEST_TMPDIR/expected-config"

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  mkdir -p "$(dirname "$destination_file")"
  printf 'old configuration\n' >"$destination_file"
  printf 'expected configuration\n' >"$source_file"
  chmod 0600 "$destination_file"

  run install_target_config_file "$source_file" "$destination_file" "test application"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"preserved previous test application configuration"* ]]
  [[ "$(<"$destination_file")" == "expected configuration" ]]
  [[ "$(<"${destination_file}.packertron.bak")" == "old configuration" ]]
  [[ "$(stat -c '%U:%G:%a' "$destination_file")" == "$TARGET_USER:$TARGET_GROUP:644" ]]

  printf 'another local change\n' >"$destination_file"
  run install_target_config_file "$source_file" "$destination_file" "test application"
  [[ "$status" -eq 0 ]]
  [[ "$(<"${destination_file}.packertron.bak")" == "old configuration" ]]
}

@test "failed atomic activation preserves the existing target configuration" {
  local destination_file="$BATS_TEST_TMPDIR/home/.config/test/config"
  local source_file="$BATS_TEST_TMPDIR/expected-config"

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  mkdir -p "$(dirname "$destination_file")"
  printf 'existing configuration\n' >"$destination_file"
  printf 'expected configuration\n' >"$source_file"

  mv() {
    return 42
  }

  run install_target_config_file "$source_file" "$destination_file" "test application"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"failed activating test application configuration"* ]]
  [[ "$(<"$destination_file")" == "existing configuration" ]]
}

@test "Terminator exact configuration is idempotent" {
  local config_file
  local first_inode

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  config_file="$TARGET_HOME/.config/terminator/config"
  mkdir -p "$TARGET_HOME"

  configure_terminator
  first_inode="$(stat -c '%i' "$config_file")"

  run configure_terminator

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Terminator already configured, skipping"* ]]
  [[ "$(stat -c '%i' "$config_file")" == "$first_inode" ]]
  grep -Fxq '    font = JetBrainsMono Nerd Font Mono 16' "$config_file"
  [[ ! -e "${config_file}.packertron.bak" ]]
}

@test "Ubuntu 26 Terminator default is written through the target-user helper only when changed" {
  local config_file
  local first_inode

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  VERSION_ID="26.04"
  TERMINATOR_DESKTOP_FILE="$BATS_TEST_TMPDIR/terminator.desktop"
  config_file="$TARGET_HOME/.config/ubuntu-xdg-terminals.list"
  mkdir -p "$TARGET_HOME/.config"
  printf '[Desktop Entry]\n' >"$TERMINATOR_DESKTOP_FILE"
  printf '%s\n' org.gnome.Console.desktop terminator.desktop >"$config_file"

  command() {
    if [[ "$1" == "-v" && "$2" == "terminator" ]]; then
      printf '/usr/bin/terminator\n'
      return
    fi
    builtin command "$@"
  }
  run_as_target_user() {
    local target_group="$TARGET_GROUP"
    local target_home="$TARGET_HOME"
    local target_uid="$TARGET_UID"
    local target_user="$TARGET_USER"

    HOME="$target_home" \
      USER="$target_user" \
      LOGNAME="$target_user" \
      TARGET_HOME="$target_home" \
      TARGET_UID="$target_uid" \
      TARGET_GROUP="$target_group" \
      "$@"
  }

  run configure_terminator_as_default "$TARGET_USER"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Terminator configured as default terminal"* ]]
  [[ "$(sed -n '1p' "$config_file")" == "terminator.desktop" ]]
  [[ "$(grep -Fc terminator.desktop "$config_file")" -eq 1 ]]
  grep -Fxq org.gnome.Console.desktop "$config_file"
  first_inode="$(stat -c '%i' "$config_file")"

  run configure_terminator_as_default "$TARGET_USER"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"already configured as default terminal"* ]]
  [[ "$(stat -c '%i' "$config_file")" == "$first_inode" ]]
}

@test "Starship installer output stays quiet on success" {
  export STARSHIP_TEST_MARKER="$BATS_TEST_TMPDIR/starship-installed"

  command() {
    if [[ "$1" == "-v" && "$2" == "starship" && ! -f "$STARSHIP_TEST_MARKER" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  curl() {
    local output_file=""

    while (($# > 0)); do
      if [[ "$1" == "--output" ]]; then
        output_file="$2"
        shift 2
      else
        shift
      fi
    done

    printf '#!/usr/bin/env sh\nprintf "verbose installer instructions\\n"\ntouch "$STARSHIP_TEST_MARKER"\n' >"$output_file"
  }
  starship() {
    printf 'starship test-version\n'
  }

  run install_starship

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Starship installed"* ]]
  [[ "$output" != *"verbose installer instructions"* ]]
}

@test "existing Starship skips the installer download" {
  starship() {
    printf 'starship test-version\n'
  }
  curl() {
    printf 'unexpected Starship download\n' >&2
    return 99
  }

  run install_starship

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"starship test-version already installed, skipping"* ]]
  [[ "$output" != *"unexpected Starship download"* ]]
}

@test "installed tldr skips pipx mutation" {
  run_as_target_user() {
    if [[ "$*" == "pipx list --short" ]]; then
      printf 'tldr 3.4.0\n'
      return
    fi
    printf 'unexpected pipx mutation: %s\n' "$*" >&2
    return 99
  }

  run install_tldr_pipx

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"tldr already installed via pipx, skipping"* ]]
  [[ "$output" != *"unexpected pipx mutation"* ]]
}

@test "complete fzf installation skips checkout and installer mutations" {
  local test_home="$BATS_TEST_TMPDIR/home"

  mkdir -p "$test_home/.fzf/.git" "$test_home/.fzf/bin"
  touch "$test_home/.fzf.bash" "$test_home/.fzf/bin/fzf"
  chmod +x "$test_home/.fzf/bin/fzf"

  user_home() {
    printf '%s\n' "$test_home"
  }
  sudo() {
    printf 'unexpected fzf mutation: %s\n' "$*" >&2
    return 99
  }

  run install_fzf_for_user testuser

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"fzf already installed for testuser, skipping"* ]]
  [[ "$output" != *"unexpected fzf mutation"* ]]
}

@test "fzf clone has total and low-speed timeouts" {
  local test_home="$BATS_TEST_TMPDIR/home"
  local timeout_record="$BATS_TEST_TMPDIR/timeout-record"

  mkdir -p "$test_home"
  user_home() {
    printf '%s\n' "$test_home"
  }
  timeout() {
    printf '%s\n' "$@" >"$timeout_record"
    return 124
  }

  run install_fzf_for_user testuser

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"fzf clone failed or timed out for testuser"* ]]
  grep -Fxq -- '--foreground' "$timeout_record"
  grep -Fxq '180' "$timeout_record"
  grep -Fxq 'http.lowSpeedLimit=1024' "$timeout_record"
  grep -Fxq 'http.lowSpeedTime=30' "$timeout_record"
}

@test "Desktop target receives full updateos while root receives system-only updateos" {
  local root_home="$BATS_TEST_TMPDIR/root"
  local target_home="$BATS_TEST_TMPDIR/desktop-user"

  TARGET_USER="desktop-user"
  UBUNTU_VARIANT="desktop"
  mkdir -p "$root_home" "$target_home"

  user_home() {
    if [[ "$1" == "$TARGET_USER" ]]; then
      printf '%s\n' "$target_home"
    else
      printf '%s\n' "$root_home"
    fi
  }
  ensure_bat_symlink_for_user() { return 0; }
  sudo() {
    [[ "$1" == "-u" ]]
    shift 2
    [[ "$1" == "-H" ]]
    shift
    "$@"
  }

  configure_bash_for_user "$TARGET_USER"
  configure_bash_for_user root

  grep -Fq 'snap refresh && flatpak update -y" && brew upgrade' "$target_home/.bash_aliases"
  if grep -Fq 'snap refresh' "$root_home/.bash_aliases" ||
    grep -Fq 'flatpak update' "$root_home/.bash_aliases" ||
    grep -Fq 'brew upgrade' "$root_home/.bash_aliases"; then
    return 1
  fi
}

@test "Server target receives system-only updateos" {
  local target_home="$BATS_TEST_TMPDIR/server-user"

  TARGET_USER="server-user"
  UBUNTU_VARIANT="server"
  mkdir -p "$target_home"

  user_home() { printf '%s\n' "$target_home"; }
  ensure_bat_symlink_for_user() { return 0; }
  sudo() {
    [[ "$1" == "-u" ]]
    shift 2
    [[ "$1" == "-H" ]]
    shift
    "$@"
  }

  configure_bash_for_user "$TARGET_USER"

  grep -Fq 'apt update && apt -y upgrade && apt -y autoremove"' "$target_home/.bash_aliases"
  if grep -Fq 'snap refresh' "$target_home/.bash_aliases" ||
    grep -Fq 'flatpak update' "$target_home/.bash_aliases" ||
    grep -Fq 'brew upgrade' "$target_home/.bash_aliases"; then
    return 1
  fi
}

@test "Nerd Font detection does not reinstall a matched font" {
  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"

  user_home() {
    printf '%s\n' "$BATS_TEST_TMPDIR/home"
  }
  run_as_target_user() {
    if [[ "$*" == *"fc-match"* ]]; then
      printf 'JetBrainsMono Nerd Font,JetBrainsMono NFM\n'
      return
    fi
    printf 'unexpected font mutation: %s\n' "$*" >&2
    return 99
  }

  run install_jetbrainsmono_nerd_font_for_user "$TARGET_USER"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Nerd Font already installed for ${TARGET_USER}, skipping"* ]]
  [[ "$output" != *"unexpected font mutation"* ]]
}

@test "failed Nerd Font metadata download preserves the existing font directory" {
  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  mkdir -p "$TARGET_HOME/.local/share/fonts"
  printf 'existing font\n' >"$TARGET_HOME/.local/share/fonts/existing.ttf"

  user_home() {
    printf '%s\n' "$TARGET_HOME"
  }
  run_as_target_user() {
    if [[ "$*" == *"fc-match"* ]]; then
      printf 'DejaVu Sans\n'
      return
    fi
    printf 'unexpected font installer\n' >&2
    return 99
  }
  fetch_file() {
    return 28
  }

  run install_jetbrainsmono_nerd_font_for_user "$TARGET_USER"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"failed downloading JetBrainsMono Nerd Font release metadata"* ]]
  [[ "$output" != *"unexpected font installer"* ]]
  [[ "$(<"$TARGET_HOME/.local/share/fonts/existing.ttf")" == "existing font" ]]
}

@test "failed Obsidian metadata download preserves the installed snap" {
  local snap_record="$BATS_TEST_TMPDIR/snap-record"

  VERSION_ID="26.04"

  dpkg() {
    if [[ "$1" == "--print-architecture" ]]; then
      printf 'amd64\n'
      return
    fi
    return 2
  }
  snap() {
    if [[ "$1" == "list" && "$2" == "obsidian" ]]; then
      return 0
    fi
    printf '%s\n' "$*" >>"$snap_record"
  }
  fetch_file() {
    return 28
  }

  run install_obsidian

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"failed downloading Obsidian release metadata"* ]]
  [[ ! -e "$snap_record" ]]
}

@test "correct bat symlink is left unchanged" {
  local test_home="$BATS_TEST_TMPDIR/home"

  mkdir -p "$test_home/.local/bin"
  ln -s /usr/bin/batcat "$test_home/.local/bin/bat"
  sudo() {
    printf 'unexpected bat symlink mutation: %s\n' "$*" >&2
    return 99
  }

  run ensure_bat_symlink_for_user testuser "$test_home"

  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
  [[ "$(readlink -- "$test_home/.local/bin/bat")" == "/usr/bin/batcat" ]]
}

@test "matching Git configuration is not rewritten" {
  local expected_config="$BATS_TEST_TMPDIR/expected.gitconfig"

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  mkdir -p "$TARGET_HOME"

  HOME="$TARGET_HOME" git config --global user.name syselement
  HOME="$TARGET_HOME" git config --global user.email 81392234+syselement@users.noreply.github.com
  HOME="$TARGET_HOME" git config --global pull.rebase true
  HOME="$TARGET_HOME" git config --global rebase.autoStash true
  cp "$TARGET_HOME/.gitconfig" "$expected_config"

  run_as_target_user() {
    HOME="$TARGET_HOME" "$@"
  }

  run configure_git_for_user "$TARGET_USER"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Git already configured for ${TARGET_USER}, skipping"* ]]
  cmp -s "$expected_config" "$TARGET_HOME/.gitconfig"
}

@test "existing Homebrew skips installer prerequisites and verifies ownership" {
  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  HOMEBREW_PREFIX="$BATS_TEST_TMPDIR/homebrew"

  mkdir -p "$TARGET_HOME" "$HOMEBREW_PREFIX/bin"
  cat >"$HOMEBREW_PREFIX/bin/brew" <<'FAKE_BREW'
#!/usr/bin/env bash
case "$1" in
  --prefix) printf '%s\n' "$FAKE_BREW_PREFIX" ;;
  --version) printf 'Homebrew test-version\n' ;;
  *) exit 2 ;;
esac
FAKE_BREW
  chmod +x "$HOMEBREW_PREFIX/bin/brew"

  apt-get() {
    printf 'unexpected prerequisite installation\n' >&2
    return 99
  }
  fetch_file() {
    printf 'unexpected installer download\n' >&2
    return 99
  }
  run_as_target_user() {
    HOME="$TARGET_HOME" FAKE_BREW_PREFIX="$HOMEBREW_PREFIX" "$@"
  }
  homebrew_cpu_is_supported() {
    return 0
  }

  run install_homebrew_for_user

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"skipping installer prerequisites"* ]]
  [[ "$output" == *"Homebrew test-version installed and verified"* ]]
  grep -Fqx "eval \"\$(${HOMEBREW_PREFIX}/bin/brew shellenv)\"" "$TARGET_HOME/.bashrc"
  [[ "$output" != *"unexpected prerequisite installation"* ]]
  [[ "$output" != *"unexpected installer download"* ]]
}

@test "Homebrew installer is staged and verbose success output stays quiet" {
  local brew_template="$BATS_TEST_TMPDIR/brew-template"
  local download_record="$BATS_TEST_TMPDIR/download-record"
  local execution_record="$BATS_TEST_TMPDIR/execution-record"

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  HOMEBREW_PREFIX="$BATS_TEST_TMPDIR/homebrew"

  mkdir -p "$TARGET_HOME"
  cat >"$brew_template" <<'FAKE_BREW'
#!/usr/bin/env bash
case "$1" in
  --prefix) printf '%s\n' "$FAKE_BREW_PREFIX" ;;
  --version) printf 'Homebrew staged-test\n' ;;
  *) exit 2 ;;
esac
FAKE_BREW
  chmod +x "$brew_template"

  dpkg-query() {
    printf 'install ok installed\n'
  }
  apt-get() {
    printf 'unexpected prerequisite installation\n' >&2
    return 99
  }
  fetch_file() {
    printf '%s\n' "$2" >"$download_record"
    cat >"$2" <<'FAKE_INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$FAKE_BREW_PREFIX/bin"
cp "$FAKE_BREW_TEMPLATE" "$FAKE_BREW_PREFIX/bin/brew"
chmod +x "$FAKE_BREW_PREFIX/bin/brew"
printf 'verbose Homebrew installer output\n'
FAKE_INSTALLER
  }
  run_as_target_user() {
    printf '%s\n' "$*" >>"$execution_record"
    HOME="$TARGET_HOME" \
      FAKE_BREW_PREFIX="$HOMEBREW_PREFIX" \
      FAKE_BREW_TEMPLATE="$brew_template" \
      "$@"
  }
  homebrew_cpu_is_supported() {
    return 0
  }

  run install_homebrew_for_user

  [[ "$status" -eq 0 ]]
  [[ "$(<"$download_record")" == */install.sh ]]
  grep -Eq 'env NONINTERACTIVE=1 /bin/bash .*/install\.sh' "$execution_record"
  [[ "$output" == *"Homebrew staged-test installed and verified"* ]]
  [[ "$output" != *"verbose Homebrew installer output"* ]]
  [[ "$output" != *"unexpected prerequisite installation"* ]]
}

@test "Homebrew skips unsupported CPUs before changing the system" {
  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  HOMEBREW_PREFIX="$BATS_TEST_TMPDIR/homebrew"

  homebrew_cpu_is_supported() {
    return 1
  }
  install_package_array() {
    printf 'unexpected prerequisite installation\n' >&2
    return 99
  }
  fetch_file() {
    printf 'unexpected installer download\n' >&2
    return 99
  }

  run install_homebrew_for_user

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"skipping Homebrew"* ]]
  [[ "$output" != *"unexpected prerequisite installation"* ]]
  [[ "$output" != *"unexpected installer download"* ]]
  [[ ! -e "$HOMEBREW_PREFIX" ]]
}

@test "incomplete Homebrew installation reruns the staged installer" {
  local brew_template="$BATS_TEST_TMPDIR/repaired-brew"

  TARGET_USER="$(id -un)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  TARGET_UID="$(id -u)"
  TARGET_GROUP="$(id -gn)"
  HOMEBREW_PREFIX="$BATS_TEST_TMPDIR/homebrew"

  mkdir -p "$TARGET_HOME" "$HOMEBREW_PREFIX/bin"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$HOMEBREW_PREFIX/bin/brew"
  chmod +x "$HOMEBREW_PREFIX/bin/brew"
  cat >"$brew_template" <<'FAKE_BREW'
#!/usr/bin/env bash
case "$1" in
  --prefix) printf '%s\n' "$FAKE_BREW_PREFIX" ;;
  --version) printf 'Homebrew repaired-test\n' ;;
  *) exit 2 ;;
esac
FAKE_BREW
  chmod +x "$brew_template"

  dpkg-query() {
    printf 'install ok installed\n'
  }
  fetch_file() {
    cat >"$2" <<'FAKE_INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
cp "$FAKE_BREW_TEMPLATE" "$FAKE_BREW_PREFIX/bin/brew"
chmod +x "$FAKE_BREW_PREFIX/bin/brew"
FAKE_INSTALLER
  }
  run_as_target_user() {
    HOME="$TARGET_HOME" \
      FAKE_BREW_PREFIX="$HOMEBREW_PREFIX" \
      FAKE_BREW_TEMPLATE="$brew_template" \
      "$@"
  }
  homebrew_cpu_is_supported() {
    return 0
  }

  run install_homebrew_for_user

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"installation is incomplete; rerunning the installer"* ]]
  [[ "$output" == *"Homebrew repaired-test installed and verified"* ]]
}

@test "quiet command helper replays output only on failure" {
  noisy_success() {
    printf 'successful noise\n'
  }
  noisy_failure() {
    printf 'actionable failure\n' >&2
    return 23
  }

  run run_quiet_command "test command" noisy_success
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]

  run run_quiet_command "test command" noisy_failure
  [[ "$status" -eq 23 ]]
  [[ "$output" == *"test command: actionable failure"* ]]
}

@test "GitHub asset digest helper accepts a match and rejects a mismatch" {
  local asset_file="$BATS_TEST_TMPDIR/asset"
  local digest

  printf 'verified asset\n' >"$asset_file"
  digest="$(sha256sum "$asset_file")"
  digest="${digest%% *}"

  run verify_github_asset_digest "$asset_file" "sha256:${digest}" "test asset"
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]

  run verify_github_asset_digest \
    "$asset_file" \
    'sha256:0000000000000000000000000000000000000000000000000000000000000000' \
    "test asset"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"SHA-256 verification failed for test asset"* ]]
}

@test "validated downloaded DEB skips an installed equal version" {
  local package_dir="$BATS_TEST_TMPDIR/package"
  local deb_file="$BATS_TEST_TMPDIR/test-package.deb"

  ARCH="amd64"
  mkdir -p "$package_dir/DEBIAN"
  cat >"$package_dir/DEBIAN/control" <<'EOF'
Package: test-package
Version: 1.2.3-1
Architecture: amd64
Maintainer: Test <test@example.invalid>
Description: Test package
EOF
  dpkg-deb --build "$package_dir" "$deb_file" >/dev/null

  dpkg-query() {
    printf '1.2.3-1\n'
  }
  run_apt_get() {
    printf 'unexpected APT installation\n' >&2
    return 99
  }

  run install_debian_package "$deb_file" "test-package" "Test package"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"already installed, skipping"* ]]
  [[ "$output" != *"unexpected APT installation"* ]]
}

@test "GitHub DEB installer selects one architecture-specific asset" {
  local install_record="$BATS_TEST_TMPDIR/install-record"

  fetch_file() {
    if [[ "$1" == *"/releases/latest" ]]; then
      cat >"$2" <<'EOF'
{
  "tag_name": "1.2.3",
  "assets": [
    {
      "name": "rustdesk-1.2.3-x86_64.deb",
      "browser_download_url": "https://github.com/rustdesk/rustdesk/releases/download/1.2.3/rustdesk-1.2.3-x86_64.deb",
      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    },
    {
      "name": "rustdesk-1.2.3-aarch64.deb",
      "browser_download_url": "https://github.com/rustdesk/rustdesk/releases/download/1.2.3/rustdesk-1.2.3-aarch64.deb",
      "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  ]
}
EOF
    else
      printf 'test package\n' >"$2"
    fi
  }
  verify_github_asset_digest() {
    return 0
  }
  dpkg-query() {
    return 1
  }
  install_debian_package() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" >"$install_record"
  }

  run install_latest_github_debian_package \
    "rustdesk/rustdesk" \
    "-x86_64.deb" \
    "rustdesk" \
    "RustDesk"

  [[ "$status" -eq 0 ]]
  [[ "$(<"$install_record")" == *"/package.deb|rustdesk|RustDesk" ]]
}

@test "current GitHub DEB release skips the asset download" {
  dpkg-query() {
    printf '1.2.3-1\n'
  }
  fetch_file() {
    if [[ "$1" == *"/releases/latest" ]]; then
      printf '{"tag_name":"v1.2.3","assets":[]}\n' >"$2"
      return
    fi
    printf 'unexpected GitHub asset download\n' >&2
    return 99
  }
  install_debian_package() {
    printf 'unexpected package installation\n' >&2
    return 99
  }

  run install_latest_github_debian_package \
    "example/project" \
    "-amd64.deb" \
    "example-package" \
    "Example"

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"already matches latest release 1.2.3, skipping download"* ]]
  [[ "$output" != *"unexpected GitHub asset download"* ]]
  [[ "$output" != *"unexpected package installation"* ]]
}

@test "installed target-user Termix Flatpak skips release download" {
  ARCH="amd64"
  TARGET_USER="testuser"

  flatpak() {
    return 0
  }
  run_as_target_user() {
    "$@"
  }
  fetch_file() {
    printf 'unexpected Termix download\n' >&2
    return 99
  }

  run install_termix

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Termix Flatpak already installed"* ]]
  [[ "$output" != *"unexpected Termix download"* ]]
}

@test "Termix bundle is installed before its application ID is verified" {
  local command_record="$BATS_TEST_TMPDIR/termix-command-record"
  local installed_marker="$BATS_TEST_TMPDIR/termix-installed"

  ARCH="amd64"
  TARGET_USER="testuser"

  flatpak() {
    printf '%s\n' "$*" >>"$command_record"
    case "$1" in
      info)
        [[ -e "$installed_marker" ]]
        ;;
      install)
        touch "$installed_marker"
        ;;
      *)
        return 2
        ;;
    esac
  }
  run_as_target_user() {
    "$@"
  }
  fetch_file() {
    if [[ "$1" == *"/releases/latest" ]]; then
      cat >"$2" <<'EOF'
{
  "assets": [
    {
      "name": "termix_linux_flatpak.flatpak",
      "browser_download_url": "https://github.com/Termix-SSH/Termix/releases/download/test/termix_linux_flatpak.flatpak",
      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
  ]
}
EOF
    else
      printf 'test Flatpak bundle\n' >"$2"
    fi
  }
  verify_github_asset_digest() {
    return 0
  }

  run install_termix

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Termix Flatpak installed for testuser"* ]]
  grep -Fq 'install --user --noninteractive -y' "$command_record"
  ! grep -Fq -- '--show-ref' "$command_record"
}

@test "current Typora Themeable release repairs directory ownership before skipping download" {
  TARGET_USER="$(id -un)"
  TARGET_GROUP="$(id -gn)"
  TARGET_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TARGET_HOME/.config/Typora/themes"
  chmod 0700 "$TARGET_HOME/.config/Typora" "$TARGET_HOME/.config/Typora/themes"
  printf 'v1.2.3\n' >"$TARGET_HOME/.config/Typora/themes/.packertron-themeable-version"
  printf 'theme\n' >"$TARGET_HOME/.config/Typora/themes/themeable.css"

  fetch_file() {
    if [[ "$1" == *"/releases/latest" ]]; then
      printf '{"tag_name":"v1.2.3","assets":[]}\n' >"$2"
      return
    fi
    printf 'unexpected theme archive download\n' >&2
    return 99
  }

  run install_typora_themeable

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Typora Themeable v1.2.3 already installed, skipping"* ]]
  [[ "$output" != *"unexpected theme archive download"* ]]
  [[ "$(stat -c '%U:%G:%a' "$TARGET_HOME/.config/Typora")" == "$TARGET_USER:$TARGET_GROUP:755" ]]
  [[ "$(stat -c '%U:%G:%a' "$TARGET_HOME/.config/Typora/themes")" == "$TARGET_USER:$TARGET_GROUP:755" ]]
}

@test "failed repository download preserves existing files" {
  local key_file="$SYSTEM_KEYRING_DIR/sublimehq-pub.asc"
  local source_file="$APT_SOURCES_DIR/sublime-text.sources"

  printf 'existing key\n' >"$key_file"
  printf 'existing source\n' >"$source_file"
  fetch_file() {
    return 1
  }

  run apply_repository_setup ensure_sublime_text_repository

  [[ "$status" -ne 0 ]]
  [[ "$(<"$key_file")" == "existing key" ]]
  [[ "$(<"$source_file")" == "existing source" ]]
}

@test "invalid OpenPGP repository key is rejected" {
  local invalid_key="$BATS_TEST_TMPDIR/invalid-key"
  printf 'not an OpenPGP key\n' >"$invalid_key"

  run validate_openpgp_key "$invalid_key" "test repository"

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"invalid test repository signing key"* ]]
}

@test "unchanged repository files do not request an APT refresh" {
  fetch_file() {
    printf 'Sublime test key\n' >"$2"
  }
  validate_openpgp_key() {
    return 0
  }

  apply_repository_setup ensure_sublime_text_repository
  [[ "$APT_SOURCES_CHANGED" == true ]]

  APT_SOURCES_CHANGED=false
  apply_repository_setup ensure_sublime_text_repository

  [[ "$APT_SOURCES_CHANGED" == false ]]
  grep -Fqx 'URIs: https://download.sublimetext.com/' "$APT_SOURCES_DIR/sublime-text.sources"
}

@test "Tailscale repository is repeatable and uses the Ubuntu codename" {
  CODENAME="resolute"

  fetch_file() {
    printf 'Tailscale test key\n' >"$2"
  }
  validate_openpgp_key() {
    return 0
  }

  apply_repository_setup ensure_tailscale_repository
  [[ "$APT_SOURCES_CHANGED" == true ]]

  APT_SOURCES_CHANGED=false
  apply_repository_setup ensure_tailscale_repository

  [[ "$APT_SOURCES_CHANGED" == false ]]
  grep -Fqx \
    "deb [signed-by=${SYSTEM_KEYRING_DIR}/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu resolute main" \
    "$APT_SOURCES_DIR/tailscale.list"
}

@test "Typora repository removes its obsolete key and is repeatable" {
  printf 'obsolete key\n' >"$APT_TRUSTED_KEY_DIR/typora.asc"

  fetch_file() {
    printf 'Typora test key\n' >"$2"
  }
  validate_openpgp_key() {
    return 0
  }

  apply_repository_setup ensure_typora_repository
  [[ "$APT_SOURCES_CHANGED" == true ]]
  [[ ! -e "$APT_TRUSTED_KEY_DIR/typora.asc" ]]

  APT_SOURCES_CHANGED=false
  apply_repository_setup ensure_typora_repository

  [[ "$APT_SOURCES_CHANGED" == false ]]
  grep -Fqx \
    "deb [signed-by=${SYSTEM_KEYRING_DIR}/typora.gpg] https://downloads.typora.io/linux ./" \
    "$APT_SOURCES_DIR/typora.list"
}

@test "AZLux repository uses HTTPS and validates its published fingerprint" {
  local validation_record="$BATS_TEST_TMPDIR/azlux-validation"

  fetch_file() {
    printf 'AZLux test key\n' >"$2"
  }
  dearmor_openpgp_key() {
    cp "$1" "$2"
  }
  validate_openpgp_key() {
    printf '%s|%s\n' "$2" "$3" >"$validation_record"
  }

  apply_repository_setup install_docker_ctop_repository

  [[ "$APT_SOURCES_CHANGED" == true ]]
  grep -Fqx 'URIs: https://packages.azlux.fr/debian/' "$APT_SOURCES_DIR/azlux.sources"
  [[ "$(<"$validation_record")" == 'AZLux|98B824A5FA7D3A10FDB225B7CA548A0A0312D8E6' ]]
}

@test "Claude Desktop repository uses the official fingerprint and amd64 architecture" {
  local validation_record="$BATS_TEST_TMPDIR/claude-validation"

  fetch_file() {
    printf 'Claude Desktop test key\n' >"$2"
  }
  validate_openpgp_key() {
    printf '%s|%s\n' "$2" "$3" >"$validation_record"
  }

  apply_repository_setup ensure_claude_desktop_repository

  [[ "$APT_SOURCES_CHANGED" == true ]]
  grep -Fqx \
    "deb [arch=amd64 signed-by=${SYSTEM_KEYRING_DIR}/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
    "$APT_SOURCES_DIR/claude-desktop.list"
  [[ "$(<"$validation_record")" == 'Claude Desktop|31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE' ]]
}

@test "Desktop repositories are repeatable and reference their scoped keys" {
  local setup_function
  local -a setup_functions=(
    ensure_brave_browser_repository
    ensure_claude_desktop_repository
    ensure_dbeaver_repository
    ensure_mullvad_repository
    ensure_typora_repository
  )
  UBUNTU_VARIANT="desktop"

  fetch_file() {
    if [[ "$1" == *"brave-browser.sources" ]]; then
      printf 'Types: deb\nURIs: https://brave-browser-apt-release.s3.brave.com\nSigned-By: %s/brave-browser-archive-keyring.gpg\n' \
        "$SYSTEM_KEYRING_DIR" >"$2"
    else
      printf 'test signing key\n' >"$2"
    fi
  }
  dearmor_openpgp_key() {
    cp "$1" "$2"
  }
  validate_openpgp_key() {
    return 0
  }
  dpkg() {
    [[ "$1" == "--print-architecture" ]] || return 2
    printf 'amd64\n'
  }

  for setup_function in "${setup_functions[@]}"; do
    APT_SOURCES_CHANGED=false
    apply_repository_setup "$setup_function"
    [[ "$APT_SOURCES_CHANGED" == true ]]

    APT_SOURCES_CHANGED=false
    apply_repository_setup "$setup_function"
    [[ "$APT_SOURCES_CHANGED" == false ]]
  done

  grep -Fq "$SYSTEM_KEYRING_DIR/brave-browser-archive-keyring.gpg" \
    "$APT_SOURCES_DIR/brave-browser-release.sources"
  grep -Fq "$SYSTEM_KEYRING_DIR/claude-desktop-archive-keyring.asc" \
    "$APT_SOURCES_DIR/claude-desktop.list"
  grep -Fq "$SYSTEM_KEYRING_DIR/dbeaver.gpg.key" "$APT_SOURCES_DIR/dbeaver.list"
  grep -Fq "$SYSTEM_KEYRING_DIR/mullvad-keyring.asc" "$APT_SOURCES_DIR/mullvad.list"
  grep -Fq "$SYSTEM_KEYRING_DIR/typora.gpg" "$APT_SOURCES_DIR/typora.list"
}

@test "cleanup keeps the current APT package lists" {
  run grep -Fq 'rm -rf /var/lib/apt/lists/' "$CUSTOMIZE_SCRIPT"

  [[ "$status" -ne 0 ]]
}

@test "post-install instructions include the Cockpit URL" {
  UBUNTU_VARIANT="desktop"
  USER_NAME="testuser"
  user_home() {
    printf '/home/testuser\n'
  }

  run show_manual_setup_hints

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"11. WireGuard connection"* ]]
  [[ "$output" == *"sudo nmcli connection import type wireguard file /etc/wireguard/wg0.conf"* ]]
  [[ "$output" == *"12. Cockpit web console"* ]]
  [[ "$output" == *"https://localhost:9090/"* ]]
  [[ "$output" == *"13. Clone Git repositories over SSH"* ]]
  [[ "$output" == *"14. Virtualization"* ]]
  [[ "$output" == *"virsh --connect qemu:///system list --all"* ]]
}
