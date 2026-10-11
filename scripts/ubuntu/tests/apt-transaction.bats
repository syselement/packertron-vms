#!/usr/bin/env bats

setup() {
    APT_TRANSACTION_DIR="$BATS_TEST_TMPDIR/apt-transaction"

    # shellcheck disable=SC1091
    source "$BATS_TEST_DIRNAME/../lib/apt-transaction.sh"
}

@test "APT transaction rollback restores changed files and removes new files" {
    local existing_file="$BATS_TEST_TMPDIR/etc/apt/sources.list.d/existing.sources"
    local new_file="$BATS_TEST_TMPDIR/etc/apt/sources.list.d/new.sources"

    mkdir -p "$(dirname -- "$existing_file")"
    printf 'original repository\n' >"$existing_file"

    apt_transaction_begin
    apt_transaction_record_file "$existing_file"
    printf 'changed repository\n' >"$existing_file"
    printf 'new repository\n' >"$new_file"
    apt_transaction_record_created_file "$new_file"

    apt_transaction_rollback

    [[ "$(<"$existing_file")" == "original repository" ]]
    [[ ! -e "$new_file" ]]
    [[ ! -e "$APT_TRANSACTION_DIR" ]]
}

@test "next-run recovery rolls back an interrupted repository transaction" {
    local source_file="$BATS_TEST_TMPDIR/etc/apt/sources.list.d/vendor.sources"

    mkdir -p "$(dirname -- "$source_file")"
    printf 'working repository\n' >"$source_file"

    apt_transaction_begin
    apt_transaction_record_file "$source_file"
    printf 'interrupted repository update\n' >"$source_file"

    run apt_transaction_recover

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Recovered the previous project-managed APT repository state"* ]]
    [[ "$(<"$source_file")" == "working repository" ]]
}

@test "provisioning scripts recover before updates and roll back failed repository refreshes" {
    local script

    for script in 02-provision-system.sh 03-customize-system.sh; do
        script="$BATS_TEST_DIRNAME/../$script"

        # shellcheck disable=SC2016
        grep -Fq '. "$SCRIPT_DIR/lib/apt-transaction.sh"' "$script"
        grep -Fq 'apt_transaction_recover' "$script"
        grep -Fq 'apt_transaction_begin' "$script"
        grep -Fq 'apt_transaction_rollback' "$script"
        grep -Fq 'apt_transaction_commit' "$script"
        grep -Fq 'previous repository state restored' "$script"
    done
}

# The validator alone, never begin or rollback: if it ever regressed, those
# would go on to write or delete under the directory being refused.
@test "a transaction directory that is relative or system-wide is refused" {
    local unsafe

    for unsafe in "relative/apt-transaction" "/" "/tmp" "/var"; do
        APT_TRANSACTION_DIR="$unsafe"

        run apt_transaction_validate_directory

        [[ "$status" -ne 0 ]]
        [[ "$output" == *"APT_TRANSACTION_DIR must be an absolute path"* ||
            "$output" == *"refusing unsafe APT transaction directory"* ]]
    done
}

@test "recording outside a transaction changes nothing" {
    local source_file="$BATS_TEST_TMPDIR/etc/apt/sources.list.d/vendor.sources"

    mkdir -p "$(dirname -- "$source_file")"
    printf 'repository\n' >"$source_file"

    apt_transaction_record_file "$source_file"
    apt_transaction_record_created_file "$BATS_TEST_TMPDIR/new.sources"

    [[ ! -e "$APT_TRANSACTION_DIR" ]]
}

@test "the first record of a file wins, so rollback restores the original" {
    local source_file="$BATS_TEST_TMPDIR/etc/apt/sources.list.d/vendor.sources"

    mkdir -p "$(dirname -- "$source_file")"
    printf 'original\n' >"$source_file"

    apt_transaction_begin
    apt_transaction_record_file "$source_file"
    printf 'first change\n' >"$source_file"
    apt_transaction_record_file "$source_file"
    printf 'second change\n' >"$source_file"
    apt_transaction_rollback

    [[ "$(<"$source_file")" == "original" ]]
}

@test "rollback restores a file's mode and a symlink as a symlink" {
    local keyring="$BATS_TEST_TMPDIR/usr/share/keyrings/vendor.gpg"
    local link="$BATS_TEST_TMPDIR/etc/apt/trusted.gpg.d/vendor.gpg"

    mkdir -p "$(dirname -- "$keyring")" "$(dirname -- "$link")"
    printf 'key\n' >"$keyring"
    chmod 0640 "$keyring"
    ln -s "$keyring" "$link"

    apt_transaction_begin
    apt_transaction_record_file "$keyring"
    apt_transaction_record_file "$link"
    printf 'replaced key\n' >"$keyring.new"
    mv -f "$keyring.new" "$keyring"
    chmod 0644 "$keyring"
    rm -f "$link"
    printf 'not a link\n' >"$link"
    apt_transaction_rollback

    [[ "$(<"$keyring")" == "key" ]]
    [[ "$(stat -c '%a' "$keyring")" == "640" ]]
    [[ -L "$link" && "$(readlink "$link")" == "$keyring" ]]
}

@test "rollback recreates a directory removed during the transaction" {
    local source_dir="$BATS_TEST_TMPDIR/etc/apt/sources.list.d"

    mkdir -p "$source_dir"
    printf 'repository\n' >"$source_dir/vendor.sources"

    apt_transaction_begin
    apt_transaction_record_file "$source_dir/vendor.sources"
    rm -rf "$source_dir"
    apt_transaction_rollback

    [[ "$(<"$source_dir/vendor.sources")" == "repository" ]]
}

@test "commit keeps the new state, and a later recovery does nothing" {
    local source_file="$BATS_TEST_TMPDIR/etc/apt/sources.list.d/vendor.sources"

    mkdir -p "$(dirname -- "$source_file")"
    printf 'old\n' >"$source_file"

    apt_transaction_begin
    apt_transaction_record_file "$source_file"
    printf 'new\n' >"$source_file"
    apt_transaction_commit

    [[ ! -e "$APT_TRANSACTION_DIR" ]]

    run apt_transaction_recover

    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]]
    [[ "$(<"$source_file")" == "new" ]]
}

@test "beginning over an interrupted transaction rolls it back first" {
    local source_file="$BATS_TEST_TMPDIR/etc/apt/sources.list.d/vendor.sources"

    mkdir -p "$(dirname -- "$source_file")"
    printf 'working\n' >"$source_file"

    apt_transaction_begin
    apt_transaction_record_file "$source_file"
    printf 'half-written\n' >"$source_file"

    run apt_transaction_begin

    [[ "$status" -eq 0 ]]
    [[ "$(<"$source_file")" == "working" ]]
    [[ -d "$APT_TRANSACTION_DIR/records" ]]
    [[ -z "$(find "$APT_TRANSACTION_DIR/records" -type f)" ]]
}

@test "rollback refuses a record whose path is not absolute" {
    local source_file="$BATS_TEST_TMPDIR/etc/apt/sources.list.d/vendor.sources"

    mkdir -p "$(dirname -- "$source_file")"
    printf 'current\n' >"$source_file"

    apt_transaction_begin
    printf 'relative/path\n' >"$APT_TRANSACTION_DIR/records/tampered.path"

    run apt_transaction_rollback

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"invalid APT rollback path: relative/path"* ]]
    [[ "$(<"$source_file")" == "current" ]]
    [[ -d "$APT_TRANSACTION_DIR" ]]
}

@test "a relative managed path is refused before anything is recorded" {
    apt_transaction_begin

    run apt_transaction_record_file "etc/apt/sources.list.d/vendor.sources"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"managed APT path must be absolute"* ]]
    [[ -z "$(find "$APT_TRANSACTION_DIR/records" -type f)" ]]
}
