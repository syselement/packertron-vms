#!/usr/bin/env bats

setup() {
  CUSTOMIZE_SCRIPT="$BATS_TEST_DIRNAME/../03-customize-system.sh"

  # shellcheck source=../03-customize-system.sh
  source "$CUSTOMIZE_SCRIPT"

  SYSTEM_KEYRING_DIR="$BATS_TEST_TMPDIR/usr/share/keyrings"
  APT_SOURCES_DIR="$BATS_TEST_TMPDIR/etc/apt/sources.list.d"
  mkdir -p "$SYSTEM_KEYRING_DIR" "$APT_SOURCES_DIR"

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
  declare -F install_package_array >/dev/null
  [[ -z "$USER_NAME" ]]
  [[ -z "$ARCH" ]]
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

@test "GNOME preferences persist dock position and enable installed user extensions" {
  local fake_bin="$BATS_TEST_TMPDIR/bin"
  local settings_dir="$BATS_TEST_TMPDIR/settings"
  local command_log="$BATS_TEST_TMPDIR/gsettings.log"

  mkdir -p \
    "$fake_bin" \
    "$settings_dir" \
    "$BATS_TEST_TMPDIR/.local/share/gnome-shell/extensions/system-monitor-panel@naimur" \
    "$BATS_TEST_TMPDIR/.local/share/gnome-shell/extensions/hide-universal-access@akiirui.github.io"

  cat >"$fake_bin/gsettings" <<'FAKE_GSETTINGS'
#!/usr/bin/env bash
set -euo pipefail

command="$1"
schema="${2:-}"
key="${3:-}"
state_file="${FAKE_SETTINGS_DIR}/${schema}.${key}"

case "$command" in
  list-schemas)
    printf '%s\n' \
      org.gnome.desktop.interface \
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
      org.gnome.shell
    ;;
  list-keys)
    printf '%s\n' \
      color-scheme document-font-name font-name gtk-theme monospace-font-name \
      show-battery-percentage text-scaling-factor click-action dash-max-icon-size \
      dock-position extend-height show-trash show-in-lock-screen lock-delay \
      lock-enabled ubuntu-lock-on-suspend idle-delay enabled night-light-enabled \
      night-light-schedule-automatic night-light-schedule-from night-light-schedule-to \
      night-light-temperature allow-volume-above-100-percent power-button-action \
      show-home natural-scroll favorite-apps disable-user-extensions \
      enabled-extensions disabled-extensions
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
  grep -Fq 'hide-universal-access@akiirui.github.io' \
    "$settings_dir/org.gnome.shell.enabled-extensions"
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

@test "Flameshot repairs Pictures ownership before an idempotent configuration skip" {
  TARGET_USER="testuser"
  TARGET_HOME="/home/testuser"
  TARGET_GROUP="testgroup"
  USER_NAME="$TARGET_USER"

  install() {
    printf 'install arguments: %s\n' "$*"
  }
  sudo() {
    return 0
  }

  run configure_flameshot

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"install arguments: -d -m 0755 -o testuser -g testgroup /home/testuser/Pictures /home/testuser/Pictures/flameshot"* ]]
  [[ "$output" == *"Flameshot already configured, skipping"* ]]
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

@test "Nerd Font detection does not reinstall a matched font" {
  user_home() {
    printf '%s\n' "$BATS_TEST_TMPDIR/home"
  }
  sudo() {
    if [[ "$*" == *"fc-match"* ]]; then
      printf 'JetBrainsMono Nerd Font,JetBrainsMono NFM\n'
      return
    fi
    printf 'unexpected font mutation: %s\n' "$*" >&2
    return 99
  }

  run install_jetbrainsmono_nerd_font_for_user testuser

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Nerd Font already installed for testuser, skipping"* ]]
  [[ "$output" != *"unexpected font mutation"* ]]
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

  run install_homebrew_for_user

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"skipping installer prerequisites"* ]]
  [[ "$output" == *"Homebrew test-version installed and verified"* ]]
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

  run install_homebrew_for_user

  [[ "$status" -eq 0 ]]
  [[ "$(<"$download_record")" == */install.sh ]]
  grep -Eq 'env NONINTERACTIVE=1 /bin/bash .*/install\.sh' "$execution_record"
  [[ "$output" == *"Homebrew staged-test installed and verified"* ]]
  [[ "$output" != *"verbose Homebrew installer output"* ]]
  [[ "$output" != *"unexpected prerequisite installation"* ]]
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

@test "Desktop repositories are repeatable and reference their scoped keys" {
  local setup_function
  local -a setup_functions=(
    ensure_brave_browser_repository
    ensure_dbeaver_repository
    ensure_mullvad_repository
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
  grep -Fq "$SYSTEM_KEYRING_DIR/dbeaver.gpg.key" "$APT_SOURCES_DIR/dbeaver.list"
  grep -Fq "$SYSTEM_KEYRING_DIR/mullvad-keyring.asc" "$APT_SOURCES_DIR/mullvad.list"
}
