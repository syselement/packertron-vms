#!/usr/bin/env bats

setup() {
  CUSTOMIZE_SCRIPT="$BATS_TEST_DIRNAME/../03-customize-system.sh"

  # shellcheck source=../03-customize-system.sh
  source "$CUSTOMIZE_SCRIPT"

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

@test "Starship installer output stays quiet on success" {
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

    printf '#!/usr/bin/env sh\nprintf "verbose installer instructions\\n"\n' >"$output_file"
  }
  starship() {
    return 0
  }

  run install_starship

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Starship installed"* ]]
  [[ "$output" != *"verbose installer instructions"* ]]
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
