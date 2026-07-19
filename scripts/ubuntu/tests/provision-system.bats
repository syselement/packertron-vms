#!/usr/bin/env bats

setup() {
  PROVISION_SCRIPT="$BATS_TEST_DIRNAME/../02-provision-system.sh"

  # shellcheck source=../02-provision-system.sh
  source "$PROVISION_SCRIPT"

  APT_KEYRING_DIR="$BATS_TEST_TMPDIR/etc/apt/keyrings"
  SYSTEM_KEYRING_DIR="$BATS_TEST_TMPDIR/usr/share/keyrings"
  APT_SOURCES_DIR="$BATS_TEST_TMPDIR/etc/apt/sources.list.d"
  SYSTEMD_RUNTIME_DIR="$BATS_TEST_TMPDIR/run/systemd/system"
  ARCH="arm64"
  UBUNTU_CODENAME="noble"
  USER_NAME="testuser"

  mkdir -p \
    "$APT_KEYRING_DIR" \
    "$SYSTEM_KEYRING_DIR" \
    "$APT_SOURCES_DIR" \
    "$SYSTEMD_RUNTIME_DIR"

  log() {
    printf 'LOG: %s\n' "$*"
  }

  warn() {
    printf 'WARN: %s\n' "$*" >&2
  }
}

@test "package installation failure is returned to the caller" {
  dpkg-query() {
    return 1
  }
  apt-get() {
    return 42
  }

  run install_missing_packages required-package

  [[ "$status" -eq 42 ]]
  [[ "$output" == *"required-package"* ]]
}

@test "already installed packages do not invoke apt-get" {
  dpkg-query() {
    printf 'install ok installed\n'
  }
  apt-get() {
    printf 'unexpected apt invocation\n' >&2
    return 99
  }

  run install_missing_packages installed-package

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"already installed"* ]]
  [[ "$output" != *"unexpected apt invocation"* ]]
}

@test "identical managed files remain unchanged" {
  local source_file="$BATS_TEST_TMPDIR/source"
  local destination_file="$BATS_TEST_TMPDIR/destination"
  local before
  local after

  printf 'managed content\n' > "$source_file"
  cp "$source_file" "$destination_file"
  before="$(stat -c '%Y:%i' "$destination_file")"

  install_file_if_changed "$source_file" "$destination_file"
  after="$(stat -c '%Y:%i' "$destination_file")"

  [[ "$before" == "$after" ]]
}

@test "failed repository download preserves existing repository state" {
  printf 'existing key\n' > "$SYSTEM_KEYRING_DIR/microsoft.gpg"
  printf 'existing source\n' > "$APT_SOURCES_DIR/vscode.sources"
  fetch_file() {
    return 1
  }

  run setup_vscode_repo

  [[ "$status" -ne 0 ]]
  [[ "$(<"$SYSTEM_KEYRING_DIR/microsoft.gpg")" == "existing key" ]]
  [[ "$(<"$APT_SOURCES_DIR/vscode.sources")" == "existing source" ]]
}

@test "Docker repository uses detected architecture and is repeatable" {
  fetch_file() {
    printf 'test signing key\n' > "$2"
  }
  validate_signing_key() {
    return 0
  }

  setup_docker_repo
  local first_checksum
  first_checksum="$(sha256sum "$APT_KEYRING_DIR/docker.asc" "$APT_SOURCES_DIR/docker.sources")"

  setup_docker_repo
  local second_checksum
  second_checksum="$(sha256sum "$APT_KEYRING_DIR/docker.asc" "$APT_SOURCES_DIR/docker.sources")"

  [[ "$first_checksum" == "$second_checksum" ]]
  grep -Fqx 'Architectures: arm64' "$APT_SOURCES_DIR/docker.sources"
  grep -Fqx "Signed-By: ${APT_KEYRING_DIR}/docker.asc" "$APT_SOURCES_DIR/docker.sources"
}

@test "missing LVM root is a successful no-op" {
  EXPAND_LVM_ROOT=true
  lvs() {
    return 1
  }
  vgs() {
    printf 'unexpected vgs invocation\n' >&2
    return 99
  }
  lvextend() {
    printf 'unexpected lvextend invocation\n' >&2
    return 99
  }

  run expand_root_lvm_if_present

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"expansion skipped"* ]]
  [[ "$output" != *"unexpected"* ]]
}

@test "fully allocated LVM root does not invoke lvextend" {
  EXPAND_LVM_ROOT=true
  lvs() {
    return 0
  }
  vgs() {
    printf '0\n'
  }
  lvextend() {
    printf 'unexpected lvextend invocation\n' >&2
    return 99
  }

  run expand_root_lvm_if_present

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"already uses all free extents"* ]]
  [[ "$output" != *"unexpected"* ]]
}

@test "Docker conflict detection fails with an actionable package list" {
  dpkg-query() {
    if [[ "${*: -1}" == "docker.io" ]]; then
      printf 'install ok installed\n'
      return 0
    fi
    return 1
  }

  run check_docker_package_conflicts

  [[ "$status" -ne 0 ]]
  [[ "$output" == *"docker.io"* ]]
  [[ "$output" == *"remove them explicitly"* ]]
}

@test "Docker setup avoids repeated group and service changes" {
  docker() {
    return 0
  }
  getent() {
    [[ "$1" == "group" && "$2" == "docker" ]]
  }
  id() {
    if [[ "$1" == "-nG" ]]; then
      printf 'testuser docker\n'
    else
      return 2
    fi
  }
  usermod() {
    printf 'unexpected usermod invocation\n' >&2
    return 99
  }
  systemctl() {
    case "$1" in
      cat|is-enabled|is-active) return 0 ;;
      enable|start)
        printf 'unexpected systemctl mutation: %s\n' "$1" >&2
        return 99
        ;;
      *) return 2 ;;
    esac
  }

  run configure_docker

  [[ "$status" -eq 0 ]]
  [[ "$output" != *"unexpected"* ]]
  [[ "$output" == *"already a member"* ]]
  [[ "$output" == *"enabled and active"* ]]
}
