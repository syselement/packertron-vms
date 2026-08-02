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
