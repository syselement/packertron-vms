#!/usr/bin/env bats

@test "customization script can be sourced without initializing provisioning" {
  local customize_script="$BATS_TEST_DIRNAME/../03-customize-system.sh"

  run bash -c '
    set -euo pipefail
    source "$1"
    declare -F initialize_runtime >/dev/null
    declare -F install_package_array >/dev/null
    [[ -z "$USER_NAME" ]]
    [[ -z "$ARCH" ]]
  ' _ "$customize_script"

  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}
