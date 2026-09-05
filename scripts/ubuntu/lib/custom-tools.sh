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

CHATGPT_DEB_URL="${CHATGPT_DEB_URL:-https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb}"
CLOCKIFY_DEB_URL="${CLOCKIFY_DEB_URL:-https://clockify.me/downloads/Clockify_Setup_x64.deb}"
STRAWBERRY_FILES_URL="${STRAWBERRY_FILES_URL:-https://files.strawberrymusicplayer.org}"

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

install_termix() (
    set -Eeuo pipefail

    local app_id="com.karmaa.termix"
    local installed_version=""
    local release_tag release_version
    local temporary_dir
    local was_installed=false

    termix_installed_version() {
        run_as_target_user flatpak list --user --app --columns=application,version |
            awk -F '\t' -v app_id="$app_id" '$1 == app_id { print $2; exit }'
    }

    if [[ "$ARCH" != "amd64" ]]; then
        warn "Termix Flatpak bundle is only configured for amd64; skipping on ${ARCH}"
        return
    fi
    command -v flatpak >/dev/null 2>&1 ||
        die "flatpak is required to install Termix"

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "checking latest Termix GitHub release"
    fetch_latest_github_release_metadata "Termix-SSH/Termix" "$temporary_dir/release.json" "Termix"
    release_tag="$(jq -r '.tag_name // empty' "$temporary_dir/release.json")"
    release_version="${release_tag#release-}"
    release_version="${release_version%-tag}"
    [[ "$release_tag" == release-* && "$release_version" =~ ^[0-9]+(\.[0-9]+)+$ ]] ||
        die "unexpected Termix release tag: ${release_tag:-missing}"

    if run_as_target_user flatpak info --user "$app_id" >/dev/null 2>&1; then
        was_installed=true
        installed_version="$(termix_installed_version)" ||
            die "installed Termix Flatpak version could not be read"
        [[ -n "$installed_version" ]] ||
            die "installed Termix Flatpak returned an empty version"

        if dpkg --compare-versions "$installed_version" ge "$release_version"; then
            info "Termix Flatpak ${installed_version} already matches latest release ${release_version}, skipping"
            return
        fi
    fi

    info "downloading Termix Flatpak bundle"
    fetch_github_asset_from_metadata \
        "exact" \
        "termix_linux_flatpak.flatpak" \
        "$temporary_dir/termix.flatpak" \
        "$temporary_dir/release.json" \
        "Termix Flatpak bundle"

    chmod 0755 "$temporary_dir"
    chmod 0644 "$temporary_dir/termix.flatpak"
    if [[ "$was_installed" == true ]]; then
        info "updating Termix Flatpak from ${installed_version} to ${release_version} for ${TARGET_USER}"
    else
        info "installing Termix Flatpak ${release_version} for ${TARGET_USER}"
    fi
    run_quiet_command "Termix Flatpak installation failed" \
        run_as_target_user flatpak install --user --noninteractive --or-update -y \
        "$temporary_dir/termix.flatpak" ||
        die "failed installing Termix Flatpak"
    installed_version="$(termix_installed_version)" ||
        die "Termix Flatpak installation could not be verified"
    if [[ -z "$installed_version" ]] ||
        ! dpkg --compare-versions "$installed_version" ge "$release_version"; then
        die "Termix Flatpak ${release_version} installation could not be verified"
    fi

    if [[ "$was_installed" == true ]]; then
        ok "Termix Flatpak updated to ${installed_version} for ${TARGET_USER}"
    else
        ok "Termix Flatpak ${installed_version} installed for ${TARGET_USER}"
    fi
)

install_termius() {
    if [[ "$ARCH" != "amd64" ]]; then
        warn "Termius DEB is only configured for amd64; skipping on ${ARCH}"
        return
    fi

    install_downloaded_debian_package \
        "https://download.termius.com/linux/Termius.deb" \
        "termius-app" \
        "Termius"
}

install_chatgpt() {
    install_latest_url_debian_package "$CHATGPT_DEB_URL" "chatgpt" "ChatGPT"
}

install_clockify() {
    install_latest_url_debian_package "$CLOCKIFY_DEB_URL" "clockify" "Clockify"
}

install_strawberry() (
    set -Eeuo pipefail

    local actual_digest asset_name asset_version checksum_name installed_version published_digest
    local temporary_dir

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "checking latest Strawberry package for Ubuntu ${CODENAME}"
    fetch_file "${STRAWBERRY_FILES_URL}/" "$temporary_dir/index.html" ||
        die "failed downloading the Strawberry package index"

    asset_name="$(
        sed -n 's/.*href="\([^"]*\.deb\)".*/\1/p' "$temporary_dir/index.html" |
            awk -v codename="$CODENAME" \
                '$0 ~ ("^strawberry_[0-9]+(\\.[0-9]+)+-" codename "_amd64\\.deb$")' |
            sort -V |
            tail -n 1
    )"
    [[ -n "$asset_name" ]] ||
        die "no stable Strawberry Debian package found for Ubuntu ${CODENAME} on amd64"

    asset_version="${asset_name#strawberry_}"
    asset_version="${asset_version%-"${CODENAME}"_amd64.deb}"
    installed_version="$(dpkg-query -W -f='${Version}' strawberry 2>/dev/null || true)"
    if [[ -n "$installed_version" ]] &&
        dpkg --compare-versions "$installed_version" ge "$asset_version"; then
        info "Strawberry ${installed_version} already installed, skipping"
        return
    fi

    info "downloading Strawberry ${asset_version} for Ubuntu ${CODENAME}"
    fetch_file "${STRAWBERRY_FILES_URL}/${asset_name}" "$temporary_dir/package.deb" ||
        die "failed downloading Strawberry ${asset_version}"

    checksum_name="$(
        sed -n 's/.*href="\([^"]*\.sha256sum\)".*/\1/p' "$temporary_dir/index.html" |
            awk -v expected="${asset_name}.sha256sum" '$0 == expected { print; exit }'
    )"
    if [[ -n "$checksum_name" ]]; then
        fetch_file "${STRAWBERRY_FILES_URL}/${checksum_name}" "$temporary_dir/package.sha256sum" ||
            die "failed downloading the Strawberry ${asset_version} checksum"

        published_digest="$(awk 'NF { print $1; exit }' "$temporary_dir/package.sha256sum")"
        [[ "$published_digest" =~ ^[[:xdigit:]]{64}$ ]] ||
            die "invalid Strawberry ${asset_version} SHA-256 checksum"
        actual_digest="$(sha256sum "$temporary_dir/package.deb")"
        actual_digest="${actual_digest%% *}"
        [[ "${actual_digest,,}" == "${published_digest,,}" ]] ||
            die "SHA-256 verification failed for Strawberry ${asset_version}"
    else
        warn "Strawberry does not publish a SHA-256 checksum for ${asset_name}; relying on Debian package validation"
    fi

    install_debian_package "$temporary_dir/package.deb" "strawberry" "Strawberry"
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

install_balena_etcher() {
    install_latest_github_debian_package \
        "balena-io/etcher" \
        "_amd64.deb" \
        "balena-etcher" \
        "balenaEtcher"
}

install_rustdesk() {
    local asset_suffix

    case "$ARCH" in
        amd64) asset_suffix="-x86_64.deb" ;;
        arm64) asset_suffix="-aarch64.deb" ;;
        *)
            warn "RustDesk release installation is not configured for ${ARCH}; skipping"
            return
            ;;
    esac

    install_latest_github_debian_package \
        "rustdesk/rustdesk" \
        "$asset_suffix" \
        "rustdesk" \
        "RustDesk"
}

install_pandoc() {
    local asset_suffix

    case "$ARCH" in
        amd64 | arm64) asset_suffix="-1-${ARCH}.deb" ;;
        *)
            warn "Pandoc release installation is not configured for ${ARCH}; skipping"
            return
            ;;
    esac

    install_latest_github_debian_package \
        "jgm/pandoc" \
        "$asset_suffix" \
        "pandoc" \
        "Pandoc"
}

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
