#!/usr/bin/env bash

# Persistent rollback support for project-managed APT source and key files.
# The caller must set APT_TRANSACTION_DIR to an absolute, script-specific path.

apt_transaction_validate_directory() {
    [[ "${APT_TRANSACTION_DIR:-}" == /* ]] || {
        printf 'ERROR: APT_TRANSACTION_DIR must be an absolute path\n' >&2
        return 1
    }
    [[ "$APT_TRANSACTION_DIR" != "/" && "$APT_TRANSACTION_DIR" != "/tmp" && "$APT_TRANSACTION_DIR" != "/var" ]] || {
        printf 'ERROR: refusing unsafe APT transaction directory: %s\n' "$APT_TRANSACTION_DIR" >&2
        return 1
    }
}

apt_transaction_record_key() {
    local destination_file="$1"
    local digest

    [[ "$destination_file" == /* ]] || {
        printf 'ERROR: managed APT path must be absolute: %s\n' "$destination_file" >&2
        return 1
    }

    digest="$(printf '%s' "$destination_file" | sha256sum)"
    printf '%s\n' "${digest%% *}"
}

apt_transaction_publish_record() {
    local destination_file="$1"
    local record_key="$2"
    local path_file="$APT_TRANSACTION_DIR/records/${record_key}.path"
    local temporary_path_file="${path_file}.tmp"

    printf '%s\n' "$destination_file" >"$temporary_path_file"
    chmod 0600 "$temporary_path_file"
    mv -f -- "$temporary_path_file" "$path_file"
}

apt_transaction_record_file() {
    local destination_file="$1"
    local record_key
    local record_prefix

    [[ -d "$APT_TRANSACTION_DIR/records" ]] || return 0

    record_key="$(apt_transaction_record_key "$destination_file")" || return
    record_prefix="$APT_TRANSACTION_DIR/records/$record_key"
    [[ -f "${record_prefix}.path" ]] && return 0

    if [[ -e "$destination_file" || -L "$destination_file" ]]; then
        cp -a -- "$destination_file" "${record_prefix}.backup"
    else
        : >"${record_prefix}.absent"
        chmod 0600 "${record_prefix}.absent"
    fi

    apt_transaction_publish_record "$destination_file" "$record_key"
}

apt_transaction_record_created_file() {
    local destination_file="$1"
    local record_key
    local record_prefix

    [[ -d "$APT_TRANSACTION_DIR/records" ]] || return 0

    record_key="$(apt_transaction_record_key "$destination_file")" || return
    record_prefix="$APT_TRANSACTION_DIR/records/$record_key"
    [[ -f "${record_prefix}.path" ]] && return 0

    : >"${record_prefix}.absent"
    chmod 0600 "${record_prefix}.absent"
    apt_transaction_publish_record "$destination_file" "$record_key"
}

apt_transaction_rollback() {
    local backup_file
    local destination_file
    local path_file
    local record_prefix
    local -a path_files=()

    apt_transaction_validate_directory || return
    [[ -d "$APT_TRANSACTION_DIR/records" ]] || return 0

    shopt -s nullglob
    path_files=("$APT_TRANSACTION_DIR"/records/*.path)
    shopt -u nullglob

    for path_file in "${path_files[@]}"; do
        destination_file="$(<"$path_file")"
        [[ "$destination_file" == /* ]] || {
            printf 'ERROR: invalid APT rollback path: %s\n' "$destination_file" >&2
            return 1
        }

        record_prefix="${path_file%.path}"
        backup_file="${record_prefix}.backup"
        if [[ -e "$backup_file" || -L "$backup_file" ]]; then
            install -d -m 0755 "$(dirname -- "$destination_file")"
            rm -f -- "${destination_file}.packertron-restore"
            cp -a -- "$backup_file" "${destination_file}.packertron-restore"
            mv -Tf -- "${destination_file}.packertron-restore" "$destination_file"
        elif [[ -f "${record_prefix}.absent" ]]; then
            rm -f -- "$destination_file"
        fi
    done

    rm -rf -- "$APT_TRANSACTION_DIR"
    printf 'Recovered the previous project-managed APT repository state\n'
}

apt_transaction_recover() {
    apt_transaction_validate_directory || return
    [[ ! -d "$APT_TRANSACTION_DIR" ]] || apt_transaction_rollback
}

apt_transaction_begin() {
    apt_transaction_validate_directory || return
    [[ ! -d "$APT_TRANSACTION_DIR" ]] || apt_transaction_rollback
    install -d -m 0700 "$APT_TRANSACTION_DIR/records"
}

apt_transaction_commit() {
    apt_transaction_validate_directory || return
    [[ ! -d "$APT_TRANSACTION_DIR" ]] || rm -rf -- "$APT_TRANSACTION_DIR"
}
