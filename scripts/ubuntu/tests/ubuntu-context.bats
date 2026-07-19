#!/usr/bin/env bats

setup() {
  CONTEXT_LIBRARY="$BATS_TEST_DIRNAME/../lib/ubuntu-context.sh"
  TEST_HOME="$BATS_TEST_TMPDIR/home/testuser"
  mkdir -p "$TEST_HOME"

  cat > "$BATS_TEST_TMPDIR/os-release" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
VERSION_CODENAME=noble
EOF

  export PACKERTRON_OS_RELEASE_FILE="$BATS_TEST_TMPDIR/os-release"
  export TARGET_USER="testuser"
  unset SUDO_USER PACKER_BUILD_NAME PACKER_BUILDER_TYPE

  # shellcheck source=../lib/ubuntu-context.sh
  source "$CONTEXT_LIBRARY"

  getent() {
    if [[ "$1" == "passwd" && "${2:-}" == "testuser" ]]; then
      printf 'testuser:x:1000:1000:Test User:%s:/bin/bash\n' "$TEST_HOME"
    elif [[ "$1" == "passwd" && -z "${2:-}" ]]; then
      printf 'testuser:x:1000:1000:Test User:%s:/bin/bash\n' "$TEST_HOME"
    else
      return 2
    fi
  }

  id() {
    case "$1" in
      -gn) printf 'testgroup\n' ;;
      -un) printf 'testuser\n' ;;
      *) return 2 ;;
    esac
  }

  ubuntu_context_is_interactive() {
    return 1
  }
}

@test "detects Ubuntu Desktop and an explicit target user" {
  ubuntu_package_is_installed() {
    [[ "$1" == "ubuntu-desktop-minimal" ]]
  }

  initialize_ubuntu_context

  [[ "$UBUNTU_VERSION_ID" == "24.04" ]]
  [[ "$UBUNTU_CODENAME" == "noble" ]]
  [[ "$UBUNTU_VARIANT" == "desktop" ]]
  [[ "$TARGET_USER" == "testuser" ]]
  [[ "$TARGET_HOME" == "$TEST_HOME" ]]
  [[ "$TARGET_GROUP" == "testgroup" ]]
  [[ "$EXECUTION_MODE" == "automation" ]]
}

@test "detects Ubuntu Server from its metapackage" {
  ubuntu_package_is_installed() {
    [[ "$1" == "ubuntu-server" ]]
  }

  initialize_ubuntu_context

  [[ "$UBUNTU_VARIANT" == "server" ]]
}

@test "rejects non-Ubuntu systems" {
  cat > "$PACKERTRON_OS_RELEASE_FILE" <<'EOF'
ID=debian
VERSION_ID="13"
VERSION_CODENAME=trixie
EOF

  run initialize_ubuntu_context

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"Ubuntu is required"* ]]
}

@test "fails when package state cannot distinguish Desktop from Server" {
  ubuntu_package_is_installed() {
    return 1
  }

  run initialize_ubuntu_context

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"cannot determine Ubuntu Desktop or Server"* ]]
}

@test "uses SUDO_USER when no explicit target is supplied" {
  unset TARGET_USER
  export SUDO_USER="testuser"
  ubuntu_package_is_installed() {
    [[ "$1" == "ubuntu-server" ]]
  }

  initialize_ubuntu_context

  [[ "$TARGET_USER" == "testuser" ]]
  [[ "$EXECUTION_CONTEXT" == "sudo" ]]
}

@test "discovers one eligible user during root automation" {
  unset TARGET_USER
  ubuntu_context_effective_uid() {
    printf '0\n'
  }
  ubuntu_package_is_installed() {
    [[ "$1" == "ubuntu-server" ]]
  }

  initialize_ubuntu_context

  [[ "$TARGET_USER" == "testuser" ]]
  [[ "$EXECUTION_CONTEXT" == "automation" ]]
}

@test "identifies Packer execution" {
  export PACKER_BUILD_NAME="ubuntu-test"
  ubuntu_package_is_installed() {
    [[ "$1" == "ubuntu-desktop" ]]
  }

  initialize_ubuntu_context

  [[ "$EXECUTION_CONTEXT" == "packer" ]]
}
