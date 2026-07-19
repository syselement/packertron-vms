#!/usr/bin/env bash
# Shared Ubuntu platform and execution-context detection.
# Context variables are intentionally assigned for scripts that source this file.
# shellcheck disable=SC2034

ubuntu_context_error() {
    printf 'ERROR: %s\n' "$*" >&2
    return 1
}

ubuntu_package_is_installed() {
    local package="$1"
    local status

    status="$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)"
    [[ "$status" == "install ok installed" ]]
}

ubuntu_context_effective_uid() {
    printf '%s\n' "$EUID"
}

ubuntu_context_is_interactive() {
    [[ -t 0 && -t 1 ]]
}

load_ubuntu_release() {
    local os_release_file="${PACKERTRON_OS_RELEASE_FILE:-/etc/os-release}"
    local distro_id=""
    local version_id=""
    local codename=""
    local -a release_values=()

    [[ -r "$os_release_file" ]] ||
        ubuntu_context_error "cannot read operating-system metadata: ${os_release_file}" || return 1

    mapfile -t release_values < <(
        # shellcheck disable=SC1090
        . "$os_release_file"
        printf '%s\n' \
            "${ID:-}" \
            "${VERSION_ID:-}" \
            "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    )

    distro_id="${release_values[0]:-}"
    version_id="${release_values[1]:-}"
    codename="${release_values[2]:-}"

    [[ "$distro_id" == "ubuntu" ]] ||
        ubuntu_context_error "unsupported operating system '${distro_id:-unknown}'; Ubuntu is required" || return 1
    [[ -n "$version_id" ]] ||
        ubuntu_context_error "Ubuntu VERSION_ID is missing from ${os_release_file}" || return 1

    [[ -n "$codename" ]] ||
        ubuntu_context_error "Ubuntu codename is missing from ${os_release_file}" || return 1

    UBUNTU_VERSION_ID="$version_id"
    UBUNTU_CODENAME="$codename"
}

detect_ubuntu_variant() {
    local package
    local -a desktop_metapackages=(
        ubuntu-desktop
        ubuntu-desktop-minimal
    )
    local -a server_metapackages=(
        ubuntu-server
        ubuntu-server-minimal
    )

    for package in "${desktop_metapackages[@]}"; do
        if ubuntu_package_is_installed "$package"; then
            UBUNTU_VARIANT="desktop"
            UBUNTU_VARIANT_SOURCE="metapackage:${package}"
            return 0
        fi
    done

    for package in "${server_metapackages[@]}"; do
        if ubuntu_package_is_installed "$package"; then
            UBUNTU_VARIANT="server"
            UBUNTU_VARIANT_SOURCE="metapackage:${package}"
            return 0
        fi
    done

    UBUNTU_VARIANT="server"
    UBUNTU_VARIANT_SOURCE="default:no-flavor-metapackage"
    printf 'WARNING: no supported Ubuntu flavor metapackage is installed; defaulting to Ubuntu Server\n' >&2
}

target_user_record() {
    local account="$1"
    local record
    local name password uid gid gecos home shell

    [[ -n "$account" && "$account" != -* && "$account" != *:* && "$account" != *$'\n'* ]] ||
        ubuntu_context_error "invalid target user name: ${account:-empty}" || return 1

    record="$(getent passwd "$account" || true)"
    [[ -n "$record" ]] ||
        ubuntu_context_error "target user does not exist: ${account}" || return 1

    IFS=: read -r name password uid gid gecos home shell <<<"$record"
    [[ "$name" == "$account" && "$uid" =~ ^[0-9]+$ && "$uid" -ne 0 ]] ||
        ubuntu_context_error "target user must be an existing non-root account: ${account}" || return 1
    [[ "$home" == /* && -d "$home" ]] ||
        ubuntu_context_error "target home directory is unavailable for ${account}: ${home:-unknown}" || return 1

    TARGET_USER="$name"
    TARGET_UID="$uid"
    TARGET_HOME="$home"
    TARGET_GROUP="$(id -gn "$account")" ||
        ubuntu_context_error "cannot determine primary group for target user: ${account}" || return 1
}

discover_single_target_user() {
    local uid_min=1000
    local name password uid gid gecos home shell
    local -a candidates=()

    while IFS=: read -r name password uid gid gecos home shell; do
        [[ "$uid" =~ ^[0-9]+$ ]] || continue
        ((uid >= uid_min && uid != 65534)) || continue
        [[ "$shell" != */nologin && "$shell" != */false ]] || continue
        [[ "$home" == /* && -d "$home" ]] || continue
        candidates+=("$name")
    done < <(getent passwd)

    if ((${#candidates[@]} == 1)); then
        printf '%s\n' "${candidates[0]}"
        return 0
    fi

    if ((${#candidates[@]} == 0)); then
        ubuntu_context_error \
            "cannot determine a target user; set TARGET_USER to an existing non-root account"
    else
        ubuntu_context_error \
            "multiple target users found (${candidates[*]}); set TARGET_USER explicitly"
    fi
}

determine_target_user() {
    local requested_user="${TARGET_USER:-}"
    local effective_uid

    effective_uid="$(ubuntu_context_effective_uid)"

    if [[ -z "$requested_user" && -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        requested_user="$SUDO_USER"
    fi

    if [[ -z "$requested_user" && "$effective_uid" -ne 0 ]]; then
        requested_user="$(id -un)"
    fi

    if [[ -z "$requested_user" ]]; then
        requested_user="$(discover_single_target_user)" || return 1
    fi

    target_user_record "$requested_user"
}

detect_execution_context() {
    if ubuntu_context_is_interactive; then
        EXECUTION_INTERACTIVE=true
        EXECUTION_MODE="interactive"
    else
        EXECUTION_INTERACTIVE=false
        EXECUTION_MODE="automation"
    fi

    if [[ -n "${PACKER_BUILD_NAME:-}" || -n "${PACKER_BUILDER_TYPE:-}" ]]; then
        EXECUTION_CONTEXT="packer"
    elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        EXECUTION_CONTEXT="sudo"
    elif [[ "$EXECUTION_INTERACTIVE" == true ]]; then
        EXECUTION_CONTEXT="direct"
    else
        EXECUTION_CONTEXT="automation"
    fi
}

initialize_ubuntu_context() {
    load_ubuntu_release || return 1
    detect_ubuntu_variant || return 1
    detect_execution_context
    determine_target_user || return 1
}
