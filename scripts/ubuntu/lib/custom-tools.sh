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

STARSHIP_INSTALL_URL="${STARSHIP_INSTALL_URL:-https://starship.rs/install.sh}"
CLAUDE_CODE_INSTALL_URL="${CLAUDE_CODE_INSTALL_URL:-https://claude.ai/install.sh}"
LABCTL_INSTALL_URL="${LABCTL_INSTALL_URL:-https://labs.iximiuz.com/cli/install.sh}"
KUBECTL_STABLE_URL="${KUBECTL_STABLE_URL:-https://dl.k8s.io/release/stable.txt}"
YUBICO_AUTHENTICATOR_URL="${YUBICO_AUTHENTICATOR_URL:-https://developers.yubico.com/yubioath-flutter/Releases/yubico-authenticator-latest-linux.tar.gz}"
YUBICO_AUTHENTICATOR_INSTALL_DIR="${PACKERTRON_YUBICO_AUTHENTICATOR_INSTALL_DIR:-/opt/yubico-authenticator}"
ZED_INSTALL_URL="${ZED_INSTALL_URL:-https://zed.dev/install.sh}"
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

install_starship() (
    set -Eeuo pipefail

    local line
    local temporary_dir
    local version_output

    if command -v starship >/dev/null 2>&1; then
        version_output="$(starship --version)" || die "existing Starship command is not usable"
        [[ "$version_output" == starship* ]] || die "existing Starship version could not be verified"
        info "${version_output%%$'\n'*} already installed, skipping"
        return
    fi

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "installing Starship"
    fetch_file "$STARSHIP_INSTALL_URL" "$temporary_dir/install.sh" ||
        die "failed downloading the Starship installer"

    [[ -s "$temporary_dir/install.sh" ]] || die "downloaded Starship installer is empty"
    sh -n "$temporary_dir/install.sh" || die "downloaded Starship installer is not valid shell"

    if ! sh "$temporary_dir/install.sh" --yes >"$temporary_dir/install.log" 2>&1; then
        while IFS= read -r line; do
            error "Starship installer: ${line}"
        done <"$temporary_dir/install.log"
        die "Starship installation failed"
    fi

    command -v starship >/dev/null 2>&1 || die "Starship installation did not provide a starship command"
    ok "Starship installed"
)

install_claude_code() (
    set -Eeuo pipefail

    local claude_bin="${TARGET_HOME}/.local/bin/claude"
    local claude_config_dir="${TARGET_HOME}/.claude"
    local claude_download_dir="${TARGET_HOME}/.claude/downloads"
    local temporary_dir version_output

    if [[ -x "$claude_bin" ]]; then
        version_output="$(run_as_target_user "$claude_bin" --version)" ||
            die "existing Claude Code installation is not usable"
        [[ -n "$version_output" ]] ||
            die "existing Claude Code version could not be verified"
        info "Claude Code ${version_output%%$'\n'*} already installed, skipping"
        return
    fi

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "installing Claude Code for ${TARGET_USER}"
    fetch_file "$CLAUDE_CODE_INSTALL_URL" "$temporary_dir/install.sh" ||
        die "failed downloading the Claude Code installer"
    [[ -s "$temporary_dir/install.sh" ]] ||
        die "downloaded Claude Code installer is empty"
    bash -n "$temporary_dir/install.sh" ||
        die "downloaded Claude Code installer is not valid Bash"
    chmod 0755 "$temporary_dir"
    chmod 0644 "$temporary_dir/install.sh"

    [[ ! -L "$claude_config_dir" ]] ||
        die "refusing symlinked Claude Code configuration directory: ${claude_config_dir}"
    [[ ! -L "$claude_download_dir" ]] ||
        die "refusing symlinked Claude Code download directory: ${claude_download_dir}"
    install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_GROUP" \
        "$claude_config_dir" \
        "$claude_download_dir"
    [[ ! -L "${TARGET_HOME}/.local" ]] ||
        die "refusing symlinked target-user local directory: ${TARGET_HOME}/.local"
    [[ ! -L "${TARGET_HOME}/.local/bin" ]] ||
        die "refusing symlinked target-user local bin directory: ${TARGET_HOME}/.local/bin"
    if [[ ! -d "${TARGET_HOME}/.local" ]]; then
        install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_GROUP" "${TARGET_HOME}/.local"
    fi
    if [[ ! -d "${TARGET_HOME}/.local/bin" ]]; then
        install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "${TARGET_HOME}/.local/bin"
    fi
    chown -R -- "$TARGET_USER:$TARGET_GROUP" "$claude_download_dir"

    if ! run_as_target_user \
        timeout --foreground --kill-after=10s 10m \
        bash "$temporary_dir/install.sh" </dev/null; then
        die "Claude Code installation failed or timed out"
    fi

    [[ -x "$claude_bin" ]] ||
        die "Claude Code installation did not provide ${claude_bin}"
    version_output="$(run_as_target_user "$claude_bin" --version)" ||
        die "Claude Code installation could not be verified"
    [[ -n "$version_output" ]] ||
        die "Claude Code installation returned an empty version"
    ok "Claude Code ${version_output%%$'\n'*} installed for ${TARGET_USER}"
)

install_labctl() (
    set -Eeuo pipefail

    local install_root="${TARGET_HOME}/.iximiuz/labctl"
    local labctl_bin="${TARGET_HOME}/.iximiuz/labctl/bin/labctl"
    local temporary_dir version_output

    if [[ -x "$labctl_bin" ]]; then
        version_output="$(run_as_target_user "$labctl_bin" --version)" ||
            die "existing labctl installation is not usable"
        [[ -n "$version_output" ]] ||
            die "existing labctl version could not be verified"
        info "${version_output%%$'\n'*} already installed, skipping"
        return
    fi

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "installing iximiuz Labs control (labctl) for ${TARGET_USER}"
    fetch_file "$LABCTL_INSTALL_URL" "$temporary_dir/install.sh" ||
        die "failed downloading the labctl installer"
    [[ -s "$temporary_dir/install.sh" ]] ||
        die "downloaded labctl installer is empty"
    bash -n "$temporary_dir/install.sh" ||
        die "downloaded labctl installer is not valid Bash"
    chmod 0755 "$temporary_dir"
    chmod 0644 "$temporary_dir/install.sh"

    [[ ! -L "${TARGET_HOME}/.iximiuz" ]] ||
        die "refusing symlinked iximiuz configuration directory: ${TARGET_HOME}/.iximiuz"
    [[ ! -L "$install_root" ]] ||
        die "refusing symlinked labctl installation directory: ${install_root}"
    if [[ ! -d "${TARGET_HOME}/.iximiuz" ]]; then
        install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_GROUP" "${TARGET_HOME}/.iximiuz"
    fi
    if [[ ! -d "$install_root" ]]; then
        install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$install_root"
    fi
    chown -R -- "$TARGET_USER:$TARGET_GROUP" "$install_root"

    if ! run_as_target_user_in_home \
        timeout --foreground --kill-after=10s 10m \
        bash "$temporary_dir/install.sh" </dev/null; then
        die "labctl installation failed or timed out"
    fi

    [[ -x "$labctl_bin" ]] ||
        die "labctl installation did not provide ${labctl_bin}"
    version_output="$(run_as_target_user "$labctl_bin" --version)" ||
        die "labctl installation could not be verified"
    [[ -n "$version_output" ]] ||
        die "labctl installation returned an empty version"
    ok "${version_output%%$'\n'*} installed for ${TARGET_USER}"
)

install_zed() (
    set -Eeuo pipefail

    local desktop_file="${TARGET_HOME}/.local/share/applications/dev.zed.Zed.desktop"
    local temporary_dir
    local version_output
    local zed_bin="${TARGET_HOME}/.local/bin/zed"

    if [[ "$ARCH" != "amd64" ]]; then
        warn "Zed is only configured for amd64; skipping on ${ARCH}"
        return
    fi

    if [[ -x "$zed_bin" && -f "$desktop_file" ]]; then
        version_output="$(run_as_target_user "$zed_bin" --version)" ||
            die "existing Zed installation is not usable"
        [[ -n "$version_output" ]] ||
            die "existing Zed version could not be verified"
        info "${version_output%%$'\n'*} already installed for ${TARGET_USER}, skipping"
        return
    fi

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "installing Zed for ${TARGET_USER}"
    fetch_file "$ZED_INSTALL_URL" "$temporary_dir/install.sh" ||
        die "failed downloading the Zed installer"
    [[ -s "$temporary_dir/install.sh" ]] ||
        die "downloaded Zed installer is empty"
    sh -n "$temporary_dir/install.sh" ||
        die "downloaded Zed installer is not valid shell"
    chmod 0755 "$temporary_dir"
    chmod 0644 "$temporary_dir/install.sh"

    if ! run_as_target_user \
        timeout --foreground --kill-after=10s 10m \
        sh "$temporary_dir/install.sh" </dev/null; then
        die "Zed installation failed or timed out"
    fi

    [[ -x "$zed_bin" ]] ||
        die "Zed installation did not provide ${zed_bin}"
    [[ -f "$desktop_file" ]] ||
        die "Zed installation did not provide ${desktop_file}"
    version_output="$(run_as_target_user "$zed_bin" --version)" ||
        die "Zed installation could not be verified"
    [[ -n "$version_output" ]] ||
        die "Zed installation returned an empty version"
    ok "${version_output%%$'\n'*} installed for ${TARGET_USER}"
)

# SECTION: archive

install_yubico_authenticator() (
    set -Eeuo pipefail

    local archive_root archive_version
    local backup_directory=""
    local desktop_file="${TARGET_HOME}/.local/share/applications/com.yubico.yubioath.desktop"
    local extracted_directory
    local install_directory="$YUBICO_AUTHENTICATOR_INSTALL_DIR"
    local install_parent
    local installed_version=""
    local marker_file="${YUBICO_AUTHENTICATOR_INSTALL_DIR}/.packertron-version"
    local release_version
    local staged_directory=""
    local temporary_dir

    restore_previous_yubico_authenticator() {
        rm -rf -- "$install_directory"
        if [[ -n "$backup_directory" && -d "$backup_directory" ]]; then
            mv -- "$backup_directory" "$install_directory"
            backup_directory=""
            if [[ -f "$install_directory/desktop_integration.sh" ]]; then
                run_as_target_user \
                    bash "$install_directory/desktop_integration.sh" --install \
                    >/dev/null 2>&1 || true
            fi
        fi
    }

    if [[ "$ARCH" != "amd64" ]]; then
        warn "Yubico Authenticator is only configured for amd64; skipping on ${ARCH}"
        return
    fi

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"; [[ -z "$staged_directory" ]] || rm -rf -- "$staged_directory"; [[ -z "$backup_directory" ]] || rm -rf -- "$backup_directory"' EXIT

    info "checking latest Yubico Authenticator release"
    fetch_file "$YUBICO_AUTHENTICATOR_URL" "$temporary_dir/yubico-authenticator.tar.gz" ||
        die "failed downloading Yubico Authenticator"
    validate_tar_gzip_archive \
        "$temporary_dir/yubico-authenticator.tar.gz" \
        "Yubico Authenticator"

    archive_root="$(
        tar -tzf "$temporary_dir/yubico-authenticator.tar.gz" |
            awk -F/ 'NF && $1 != "" { print $1 }' |
            sort -u
    )"
    [[ "$archive_root" =~ ^yubico-authenticator-([0-9]+(\.[0-9]+)+)-linux$ ]] ||
        die "unexpected Yubico Authenticator archive layout: ${archive_root:-missing}"
    archive_version="${BASH_REMATCH[1]}"

    install -d -m 0755 "$temporary_dir/extracted"
    tar \
        --extract \
        --gzip \
        --file "$temporary_dir/yubico-authenticator.tar.gz" \
        --directory "$temporary_dir/extracted" \
        --no-same-owner \
        --no-same-permissions
    extracted_directory="$temporary_dir/extracted/$archive_root"
    [[ -x "$extracted_directory/authenticator" ]] ||
        die "Yubico Authenticator archive does not contain its executable"
    [[ -f "$extracted_directory/desktop_integration.sh" ]] ||
        die "Yubico Authenticator archive does not contain desktop_integration.sh"
    [[ -f "$extracted_directory/data/flutter_assets/version.json" ]] ||
        die "Yubico Authenticator archive does not contain version metadata"

    release_version="$(
        jq -r '.version // empty' \
            "$extracted_directory/data/flutter_assets/version.json"
    )" || die "Yubico Authenticator version metadata is invalid"
    [[ "$release_version" == "$archive_version" ]] ||
        die "Yubico Authenticator archive version mismatch: ${archive_version} != ${release_version:-missing}"

    [[ ! -f "$marker_file" ]] || installed_version="$(<"$marker_file")"
    if [[ -n "$installed_version" ]] &&
        dpkg --compare-versions "$installed_version" ge "$release_version" &&
        [[ -x "$install_directory/authenticator" ]] &&
        grep -Fqx "Exec=\"${install_directory}/authenticator\"" "$desktop_file" 2>/dev/null; then
        info "Yubico Authenticator ${installed_version} already installed for ${TARGET_USER}, skipping"
        return
    fi

    install_parent="$(dirname -- "$install_directory")"
    [[ "$(basename -- "$install_directory")" == "yubico-authenticator" && "$install_parent" != "/" ]] ||
        die "unsafe Yubico Authenticator installation directory: ${install_directory}"
    [[ ! -L "${TARGET_HOME}/.local" ]] ||
        die "refusing symlinked target-user local directory: ${TARGET_HOME}/.local"
    [[ ! -L "$install_directory" ]] ||
        die "refusing symlinked Yubico Authenticator directory: ${install_directory}"
    [[ ! -L "${TARGET_HOME}/.local/share" ]] ||
        die "refusing symlinked target-user share directory: ${TARGET_HOME}/.local/share"
    [[ ! -L "${TARGET_HOME}/.local/share/applications" ]] ||
        die "refusing symlinked target-user applications directory: ${TARGET_HOME}/.local/share/applications"

    if [[ ! -d "${TARGET_HOME}/.local" ]]; then
        install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_GROUP" "${TARGET_HOME}/.local"
    fi
    for directory in \
        "${TARGET_HOME}/.local/share" \
        "${TARGET_HOME}/.local/share/applications"; do
        if [[ ! -d "$directory" ]]; then
            install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_GROUP" "$directory"
        fi
    done

    install -d -m 0755 "$install_parent"
    staged_directory="$(mktemp -d "${install_parent}/.yubico-authenticator.stage.XXXXXX")"
    cp -a -- "$extracted_directory/." "$staged_directory/"
    chmod 0755 "$staged_directory"
    chmod 0755 \
        "$staged_directory/authenticator" \
        "$staged_directory/desktop_integration.sh"
    printf '%s\n' "$release_version" >"$staged_directory/.packertron-version"
    chmod 0644 "$staged_directory/.packertron-version"

    if [[ -e "$install_directory" ]]; then
        backup_directory="${install_parent}/.yubico-authenticator.backup.$$"
        [[ ! -e "$backup_directory" ]] ||
            die "Yubico Authenticator backup path already exists: ${backup_directory}"
        mv -- "$install_directory" "$backup_directory"
    fi
    if ! mv -- "$staged_directory" "$install_directory"; then
        restore_previous_yubico_authenticator
        die "failed activating Yubico Authenticator ${release_version}"
    fi
    staged_directory=""
    [[ -x "$install_directory/authenticator" &&
        -f "$install_directory/desktop_integration.sh" ]] ||
        die "Yubico Authenticator ${release_version} installation directory is incomplete"

    info "installing Yubico Authenticator ${release_version} for ${TARGET_USER}"
    if ! run_quiet_command "Yubico Authenticator desktop integration failed" \
        run_as_target_user bash "$install_directory/desktop_integration.sh" --install; then
        restore_previous_yubico_authenticator
        die "failed installing Yubico Authenticator desktop integration"
    fi
    if ! grep -Fqx "Exec=\"${install_directory}/authenticator\"" "$desktop_file"; then
        restore_previous_yubico_authenticator
        die "Yubico Authenticator desktop integration could not be verified"
    fi
    if [[ -n "$backup_directory" ]]; then
        rm -rf -- "$backup_directory"
        backup_directory=""
    fi
    ok "Yubico Authenticator ${release_version} installed for ${TARGET_USER}"
)

install_typora_themeable() (
    set -Eeuo pipefail

    local installed_version release_version
    local typora_config_directory="${TARGET_HOME}/.config/Typora"
    local marker_file="${TARGET_HOME}/.config/Typora/themes/.packertron-themeable-version"
    local theme_directory="${TARGET_HOME}/.config/Typora/themes"
    local temporary_dir

    install -d \
        -m 0755 \
        -o "$TARGET_USER" \
        -g "$TARGET_GROUP" \
        "$typora_config_directory" \
        "$theme_directory"
    verify_target_ownership "$typora_config_directory" "Typora configuration directory"
    verify_target_ownership "$theme_directory" "Typora theme directory"

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "checking latest Typora Themeable release"
    fetch_latest_github_release_metadata \
        "jhildenbiddle/typora-themeable" \
        "$temporary_dir/release.json" \
        "Typora Themeable"
    release_version="$(jq -r '.tag_name // empty' "$temporary_dir/release.json")"
    [[ -n "$release_version" ]] ||
        die "Typora Themeable release metadata does not contain a version"

    installed_version=""
    [[ ! -f "$marker_file" ]] || installed_version="$(<"$marker_file")"
    if [[ "$installed_version" == "$release_version" &&
        -f "$theme_directory/themeable.css" ]]; then
        info "Typora Themeable ${release_version} already installed, skipping"
        return
    fi

    info "downloading Typora Themeable ${release_version}"
    fetch_github_asset_from_metadata \
        "exact" \
        "typora-themeable.zip" \
        "$temporary_dir/typora-themeable.zip" \
        "$temporary_dir/release.json" \
        "Typora Themeable archive"
    info "installing Typora Themeable ${release_version}"
    validate_zip_archive "$temporary_dir/typora-themeable.zip" "Typora Themeable"

    chmod 0755 "$temporary_dir"
    chmod 0644 "$temporary_dir/typora-themeable.zip"
    run_quiet_command "Typora Themeable extraction failed" \
        run_as_target_user unzip -q -o \
        "$temporary_dir/typora-themeable.zip" \
        -d "$theme_directory" ||
        die "failed installing Typora Themeable"
    [[ -f "$theme_directory/themeable.css" ]] ||
        die "Typora Themeable installation could not be verified"

    printf '%s\n' "$release_version" >"$temporary_dir/theme-version"
    install \
        -o "$TARGET_USER" \
        -g "$TARGET_GROUP" \
        -m 0644 \
        "$temporary_dir/theme-version" \
        "$marker_file"
    verify_target_ownership "$marker_file" "Typora Themeable version marker"
    ok "Typora Themeable ${release_version} installed for ${TARGET_USER}"
)

install_flameshot() (
    set -euo pipefail

    local api_url="https://api.github.com/repos/flameshot-org/flameshot/releases/latest"
    local cmd
    local release_json tag latest_version installed_version
    local architecture platform asset_url asset_name asset_digest
    local tmp_dir deb_file checksum_file package_architecture package_name package_version
    local -a checksum_files deb_files
    local -a platform_candidates

    for cmd in curl jq unzip sha256sum dpkg dpkg-query dpkg-deb apt-get; do
        command -v "$cmd" >/dev/null 2>&1 ||
            die "${cmd} is required to install Flameshot"
    done

    architecture="$(dpkg --print-architecture)"
    case "$architecture" in
        amd64 | arm64) ;;
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

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$tmp_dir"' EXIT

    info "checking latest Flameshot GitHub release"

    fetch_file "$api_url" "$tmp_dir/release.json" ||
        die "failed downloading Flameshot release metadata"
    release_json="$(<"$tmp_dir/release.json")"
    tag="$(jq -r '.tag_name // empty' <<<"$release_json")" ||
        die "Flameshot release metadata is invalid"
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
        )" || die "Flameshot release metadata is invalid"

        [[ -n "$asset_url" ]] && break
    done

    [[ -n "$asset_url" ]] ||
        die "no compatible Flameshot artifact for Ubuntu ${VERSION_ID}/${architecture}"

    asset_name="${asset_url##*/}"
    asset_digest="$(
        jq -r --arg name "$asset_name" '
      [.assets[] | select(.name == $name)][0].digest // empty
    ' <<<"$release_json"
    )" || die "Flameshot release metadata is invalid"

    info "downloading Flameshot ${tag} (${platform}/${architecture})"
    fetch_file "$asset_url" "$tmp_dir/$asset_name" ||
        die "failed downloading Flameshot ${tag}"
    verify_github_asset_digest "$tmp_dir/$asset_name" "$asset_digest" "Flameshot ${tag} archive"
    validate_zip_archive "$tmp_dir/$asset_name" "Flameshot ${tag}"

    mkdir "$tmp_dir/extracted"
    unzip -q "$tmp_dir/$asset_name" -d "$tmp_dir/extracted"

    mapfile -t deb_files < <(
        find "$tmp_dir/extracted" -maxdepth 2 -type f -name 'flameshot*.deb' -print
    )
    mapfile -t checksum_files < <(
        find "$tmp_dir/extracted" -maxdepth 2 -type f -name 'flameshot*.deb.sha256sum' -print
    )

    ((${#deb_files[@]} == 1)) ||
        die "Flameshot archive must contain exactly one Debian package"
    ((${#checksum_files[@]} == 1)) ||
        die "Flameshot archive must contain exactly one Debian package checksum"
    deb_file="${deb_files[0]}"
    checksum_file="${checksum_files[0]}"

    info "verifying Flameshot package checksum"
    (
        cd "$(dirname "$deb_file")"
        sha256sum --check "$(basename "$checksum_file")"
    )

    dpkg-deb --info "$deb_file" >/dev/null ||
        die "Flameshot Debian package is invalid"
    package_name="$(dpkg-deb -f "$deb_file" Package)"
    package_architecture="$(dpkg-deb -f "$deb_file" Architecture)"
    package_version="$(dpkg-deb -f "$deb_file" Version)"

    [[ "$package_name" == "flameshot" ]] ||
        die "unexpected Flameshot package name: ${package_name}"
    [[ "$package_architecture" == "$architecture" || "$package_architecture" == "all" ]] ||
        die "unexpected Flameshot package architecture: ${package_architecture}"
    dpkg --compare-versions "$package_version" ge "$latest_version" ||
        die "unexpected Flameshot package version: ${package_version}"

    info "installing Flameshot ${tag}"
    run_apt_get install -y "$deb_file"

    installed_version="$(
        dpkg-query -W -f='${Version}' flameshot 2>/dev/null || true
    )"

    [[ -n "$installed_version" ]] ||
        die "Flameshot installation could not be verified"

    ok "Flameshot ${installed_version} installed from the official GitHub release"
)

install_obsidian() (
    set -euo pipefail

    local api_url="https://api.github.com/repos/obsidianmd/obsidian-releases/releases?per_page=5"
    local cmd
    local release_json tag latest_version
    local architecture asset_url asset_name asset_digest package_architecture package_version
    local installed_version tmp_dir deb_file package_name
    local snap_installed=false

    for cmd in curl jq sha256sum dpkg dpkg-query dpkg-deb apt-get; do
        command -v "$cmd" >/dev/null 2>&1 ||
            die "${cmd} is required to install Obsidian"
    done

    architecture="$(dpkg --print-architecture)"
    case "$architecture" in
        amd64 | arm64) ;;
        *)
            warn "unsupported Obsidian architecture: ${architecture}"
            return
            ;;
    esac

    if command -v snap >/dev/null 2>&1 &&
        snap list obsidian >/dev/null 2>&1; then
        snap_installed=true
    fi

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf -- "$tmp_dir"' EXIT

    info "checking recent Obsidian GitHub releases for a Debian package"

    fetch_file "$api_url" "$tmp_dir/release.json" ||
        die "failed downloading Obsidian release metadata"
    release_json="$(
        jq -c --arg suffix "_${architecture}.deb" '
          first(
            .[]
            | select(.draft == false and .prerelease == false)
            | select(any(.assets[]?; .name | endswith($suffix)))
          ) // empty
        ' "$tmp_dir/release.json"
    )" || die "Obsidian release metadata is invalid"
    [[ -n "$release_json" ]] ||
        die "no recent stable Obsidian Debian package found for ${architecture}"

    tag="$(jq -r '.tag_name // empty' <<<"$release_json")" ||
        die "Obsidian release metadata is invalid"
    [[ -n "$tag" ]] ||
        die "could not determine the latest Obsidian Debian release"

    latest_version="${tag#v}"

    installed_version="$(
        dpkg-query -W -f='${Version}' obsidian 2>/dev/null || true
    )"

    if [[ -n "$installed_version" ]] &&
        dpkg --compare-versions "$installed_version" ge "$latest_version"; then
        if [[ "$snap_installed" == true ]]; then
            info "removing duplicate Obsidian snap"
            snap remove obsidian || die "failed removing duplicate Obsidian snap"
        fi
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
    )" || die "Obsidian release metadata is invalid"

    [[ -n "$asset_url" ]] ||
        die "selected Obsidian release has no Debian package for ${architecture}"

    asset_name="${asset_url##*/}"

    asset_digest="$(
        jq -r --arg name "$asset_name" '
      [.assets[] | select(.name == $name)][0].digest // empty
    ' <<<"$release_json"
    )" || die "Obsidian release metadata is invalid"

    deb_file="$tmp_dir/$asset_name"

    info "downloading Obsidian ${tag} for ${architecture}"
    fetch_file "$asset_url" "$deb_file" ||
        die "failed downloading Obsidian ${tag}"
    [[ -s "$deb_file" ]] || die "downloaded Obsidian package is empty"

    verify_github_asset_digest "$deb_file" "$asset_digest" "Obsidian ${tag} package"

    dpkg-deb --info "$deb_file" >/dev/null ||
        die "downloaded Obsidian Debian package is invalid"

    package_name="$(dpkg-deb -f "$deb_file" Package)"
    package_architecture="$(dpkg-deb -f "$deb_file" Architecture)"
    package_version="$(dpkg-deb -f "$deb_file" Version)"
    [[ "$package_name" == "obsidian" ]] ||
        die "unexpected Debian package name: ${package_name}"
    [[ "$package_architecture" == "$architecture" || "$package_architecture" == "all" ]] ||
        die "unexpected Obsidian package architecture: ${package_architecture}"
    dpkg --compare-versions "$package_version" ge "$latest_version" ||
        die "unexpected Obsidian package version: ${package_version}"

    info "installing Obsidian ${tag}"
    run_apt_get install -y "$deb_file"

    installed_version="$(
        dpkg-query -W -f='${Version}' obsidian 2>/dev/null || true
    )"

    [[ -n "$installed_version" ]] ||
        die "Obsidian installation could not be verified"

    if [[ "$snap_installed" == true ]]; then
        info "removing duplicate Obsidian snap"
        snap remove obsidian || die "failed removing duplicate Obsidian snap"
    fi

    ok "Obsidian ${installed_version} installed from the official GitHub release"
)

# SECTION: binary

install_kubectl() (
    set -Eeuo pipefail

    local kubectl_bin="${LOCAL_BIN_DIR}/kubectl"
    local installed_version=""
    local published_checksum
    local stable_version
    local temporary_dir

    temporary_dir="$(mktemp -d)"
    trap 'rm -rf -- "$temporary_dir"' EXIT

    info "checking the latest stable kubectl release"
    fetch_file "$KUBECTL_STABLE_URL" "$temporary_dir/stable.txt" ||
        die "failed downloading the stable kubectl version"
    stable_version="$(tr -d '\r\n' <"$temporary_dir/stable.txt")"
    [[ "$stable_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
        die "unexpected stable kubectl version: ${stable_version:-missing}"

    if [[ -x "$kubectl_bin" && ! -L "$kubectl_bin" ]]; then
        installed_version="$("$kubectl_bin" version --client --output=json 2>/dev/null |
            jq -r '.clientVersion.gitVersion // empty' 2>/dev/null || true)"
    fi
    if [[ "$installed_version" == "$stable_version" ]]; then
        info "kubectl ${installed_version} already installed, skipping"
        return
    fi

    info "downloading kubectl ${stable_version} for linux/amd64"
    fetch_file \
        "https://dl.k8s.io/release/${stable_version}/bin/linux/amd64/kubectl" \
        "$temporary_dir/kubectl" ||
        die "failed downloading kubectl ${stable_version}"
    fetch_file \
        "https://dl.k8s.io/release/${stable_version}/bin/linux/amd64/kubectl.sha256" \
        "$temporary_dir/kubectl.sha256" ||
        die "failed downloading the kubectl ${stable_version} checksum"

    published_checksum="$(tr -d '[:space:]' <"$temporary_dir/kubectl.sha256")"
    [[ "$published_checksum" =~ ^[[:xdigit:]]{64}$ ]] ||
        die "invalid published checksum for kubectl ${stable_version}"
    printf '%s  %s\n' "${published_checksum,,}" "$temporary_dir/kubectl" |
        sha256sum --check --status ||
        die "SHA-256 verification failed for kubectl ${stable_version}"

    [[ ! -L "$kubectl_bin" ]] ||
        die "refusing to replace symlinked kubectl binary: ${kubectl_bin}"
    install -d -m 0755 "$LOCAL_BIN_DIR"
    install -m 0755 "$temporary_dir/kubectl" "$kubectl_bin"

    installed_version="$("$kubectl_bin" version --client --output=json 2>/dev/null |
        jq -r '.clientVersion.gitVersion // empty' 2>/dev/null || true)"
    [[ "$installed_version" == "$stable_version" ]] ||
        die "kubectl ${stable_version} installation could not be verified"
    ok "kubectl ${installed_version} installed"
)

# SECTION: pipx

install_tldr_pipx() {
    local installed_packages

    if ! installed_packages="$(run_as_target_user pipx list --short 2>/dev/null)"; then
        die "could not inspect pipx packages for ${TARGET_USER}"
    fi

    if grep -Eq '^tldr[[:space:]]' <<<"$installed_packages"; then
        info "tldr already installed via pipx, skipping"
        return
    fi

    run_quiet_command "pipx tldr installation" run_as_target_user pipx install tldr ||
        die "failed installing tldr via pipx"
    run_quiet_command "pipx PATH configuration" run_as_target_user pipx ensurepath ||
        die "failed configuring the pipx application path"

    if ! installed_packages="$(run_as_target_user pipx list --short 2>/dev/null)"; then
        die "could not verify pipx packages for ${TARGET_USER}"
    fi
    grep -Eq '^tldr[[:space:]]' <<<"$installed_packages" ||
        die "tldr installation could not be verified"
    ok "tldr installed via pipx"
}
