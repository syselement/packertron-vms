#!/usr/bin/env bash

# Third-party and custom tool installers for 03-customize-system.sh.
#
# This file holds every per-tool installer, grouped by how the tool is
# distributed. To add a tool, find the matching section below and follow the
# template comment at the top of it.
#
# Dependencies: these functions call helpers defined in the sourcing script
# (03-customize-system.sh): die, log/info/ok/warn, fetch_file,
# fetch_file_range, run_as_target_user, install_debian_package,
# validate_debian_package, validate_zip_archive, validate_tar_gzip_archive,
# verify_github_asset_digest, fetch_latest_github_asset,
# install_package_array, install_target_config_file, validate_openpgp_key,
# dearmor_openpgp_key, validate_repository_source, apt_transaction_record_file.
# Sourcing only registers function bodies, so definition order across the two
# files does not matter; every helper is defined before main() runs.
# Source this file only from 03-customize-system.sh.

# SECTION: repository

# SECTION: deb-url

install_downloaded_debian_package() (
    set -Eeuo pipefail

    local url="$1"
    local package_name="$2"
    local description="$3"
    local temporary_dir

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "downloading ${description}"
    fetch_file "$url" "$temporary_dir/package.deb" ||
        die "failed downloading ${description}"
    install_debian_package "$temporary_dir/package.deb" "$package_name" "$description"
)

install_latest_url_debian_package() (
    set -Eeuo pipefail

    local url="$1"
    local expected_package="$2"
    local description="$3"
    local control_data installed_version package_architecture package_name package_version
    local temporary_dir

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    installed_version="$(dpkg-query -W -f='${Version}' "$expected_package" 2>/dev/null || true)"
    if [[ -n "$installed_version" ]]; then
        info "checking latest ${description} version"
        fetch_file_range "$url" "0-65535" "$temporary_dir/package-prefix.deb" ||
            die "failed checking latest ${description} version"
        control_data="$(
            ar p "$temporary_dir/package-prefix.deb" control.tar.xz 2>/dev/null |
                tar -xJOf - ./control 2>/dev/null
        )" || die "could not read the latest ${description} package metadata"
        package_name="$(awk -F ': ' '$1 == "Package" { print $2; exit }' <<<"$control_data")"
        package_version="$(awk -F ': ' '$1 == "Version" { print $2; exit }' <<<"$control_data")"
        package_architecture="$(awk -F ': ' '$1 == "Architecture" { print $2; exit }' <<<"$control_data")"

        [[ "$package_name" == "$expected_package" ]] ||
            die "unexpected ${description} package name: ${package_name:-missing}"
        [[ "$package_architecture" == "amd64" ]] ||
            die "unexpected ${description} package architecture: ${package_architecture:-missing}"
        [[ -n "$package_version" ]] ||
            die "latest ${description} package does not declare a version"

        if dpkg --compare-versions "$installed_version" ge "$package_version"; then
            info "${description} ${installed_version} already installed, skipping"
            return
        fi
    fi

    install_downloaded_debian_package \
        "$url" \
        "$expected_package" \
        "$description"
)

# SECTION: github-release

install_latest_github_debian_package() (
    set -Eeuo pipefail

    local repository="$1"
    local asset_suffix="$2"
    local package_name="$3"
    local description="$4"
    local installed_version release_tag release_version
    local temporary_dir

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "checking latest ${description} GitHub release"
    fetch_latest_github_release_metadata \
        "$repository" \
        "$temporary_dir/release.json" \
        "$description"
    release_tag="$(jq -r '.tag_name // empty' "$temporary_dir/release.json")"
    release_version="${release_tag#v}"
    [[ "$release_version" =~ ^[0-9]+(\.[0-9]+)+$ ]] ||
        die "unexpected ${description} release tag: ${release_tag:-missing}"

    installed_version="$(dpkg-query -W -f='${Version}' "$package_name" 2>/dev/null || true)"
    if [[ -n "$installed_version" ]] &&
        dpkg --compare-versions "$installed_version" ge "$release_version"; then
        info "${description} ${installed_version} already matches latest release ${release_version}, skipping download"
        return
    fi

    info "downloading ${description} package"
    fetch_github_asset_from_metadata \
        "suffix" \
        "$asset_suffix" \
        "$temporary_dir/package.deb" \
        "$temporary_dir/release.json" \
        "${description} package"
    install_debian_package "$temporary_dir/package.deb" "$package_name" "$description"
)

# SECTION: snap

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

# SECTION: vendor-script

# SECTION: archive

# SECTION: binary

# SECTION: pipx
