#!/usr/bin/env bats
# ShellCheck cannot infer function calls made through sourced code and Bats.
# shellcheck disable=SC1091,SC2329

setup() {
    CLEANUP_SCRIPT="$BATS_TEST_DIRNAME/../01-cleanup-system.sh"

    # shellcheck source=../01-cleanup-system.sh
    source "$CLEANUP_SCRIPT"

    unset PACKER_BUILD_NAME PACKER_BUILDER_TYPE PACKERTRON_ALLOW_CLEANUP

    log() {
        printf 'LOG: %s\n' "$*"
    }
}

@test "cleanup refuses to run outside a template build" {
    run require_template_build

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"refusing to run outside a template build"* ]]
}

@test "a Packer build satisfies the template guard" {
    PACKER_BUILD_NAME="ubuntu-test"

    run require_template_build

    [[ "$status" -eq 0 ]]
}

@test "the guard can be overridden explicitly" {
    PACKERTRON_ALLOW_CLEANUP="true"

    run require_template_build

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"explicitly allowed"* ]]
}

@test "a failed machine-id reset is fatal" {
    truncate() {
        return 1
    }

    run reset_machine_id

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failed truncating /etc/machine-id"* ]]
}

@test "a failed cloud-init clean is fatal" {
    command() {
        [[ "$2" == "cloud-init" ]]
    }
    cloud-init() {
        return 1
    }

    run reset_cloud_init

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failed cleaning cloud-init state"* ]]
}

@test "cloud-init reset is skipped when cloud-init is absent" {
    command() {
        return 1
    }

    run reset_cloud_init

    [[ "$status" -eq 0 ]]
}

@test "journal vacuuming stays best effort" {
    journalctl() {
        return 1
    }

    run vacuum_journal

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"journal rotate skipped"* ]]
    [[ "$output" == *"journal vacuum skipped"* ]]
}

@test "the standalone APT wrapper matches the shared one in lib/apt.sh" {
    # 01-cleanup-system.sh cannot source lib/apt.sh, because Packer's shell
    # provisioner uploads it without the lib directory. Catch the two copies
    # drifting apart instead.
    local apt_record="$BATS_TEST_TMPDIR/apt-record"
    local library_record="$BATS_TEST_TMPDIR/library-record"

    apt-get() {
        printf '%s\n' "$@" >"$apt_record"
    }

    run_apt_get -y clean

    # shellcheck source=../lib/apt.sh
    source "$BATS_TEST_DIRNAME/../lib/apt.sh"
    apt-get() {
        printf '%s\n' "$@" >"$library_record"
    }

    run_apt_get -y clean

    diff "$apt_record" "$library_record"
}

@test "APT operations request noninteractive conffile handling" {
    local apt_record="$BATS_TEST_TMPDIR/apt-record"

    apt-get() {
        printf '%s\n' "$@" >"$apt_record"
    }

    run_apt_get -y autoremove --purge

    grep -Fxq 'Dpkg::Options::=--force-confdef' "$apt_record"
    grep -Fxq 'Dpkg::Options::=--force-confold' "$apt_record"
    grep -Fxq 'DPkg::Lock::Timeout=300' "$apt_record"
}
