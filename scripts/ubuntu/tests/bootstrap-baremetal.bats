#!/usr/bin/env bats

setup() {
    BOOTSTRAP_SCRIPT="$BATS_TEST_DIRNAME/../90-bootstrap-baremetal.sh"
    TEST_REVISION="0123456789abcdef0123456789abcdef01234567"

    # shellcheck disable=SC1090
    source "$BOOTSTRAP_SCRIPT"

    SCRIPT_DIR="$BATS_TEST_TMPDIR/scripts"
    STATE_DIR="$BATS_TEST_TMPDIR/state"
    BOOTSTRAP_REVISION="$TEST_REVISION"
    mkdir -p "$SCRIPT_DIR" "$STATE_DIR"
}

@test "bootstrap step markers are bound to one repository revision" {
    local execution_record="$BATS_TEST_TMPDIR/executions"

    cat >"$SCRIPT_DIR/test-step.sh" <<EOF
#!/usr/bin/env bash
printf 'run\n' >>'$execution_record'
EOF

    run run_step "test-step" "test-step.sh"
    [[ "$status" -eq 0 ]]
    [[ "$(<"$STATE_DIR/test-step.done")" == "$TEST_REVISION" ]]

    run run_step "test-step" "test-step.sh"
    [[ "$status" -eq 0 ]]
    [[ "$(wc -l <"$execution_record")" -eq 1 ]]

    BOOTSTRAP_REVISION="abcdef0123456789abcdef0123456789abcdef01"
    run run_step "test-step" "test-step.sh"
    [[ "$status" -eq 0 ]]
    [[ "$(wc -l <"$execution_record")" -eq 2 ]]
    [[ "$(<"$STATE_DIR/test-step.done")" == "$BOOTSTRAP_REVISION" ]]
}

@test "existing log and lock directories keep their mode" {
    local existing="$BATS_TEST_TMPDIR/existing-dir"

    # /var/log ships group-writable for rsyslog and /run/lock sticky. Creating
    # them with "install -d -m" would silently reset both.
    mkdir -p "$existing"
    chmod 1777 "$existing"

    ensure_directory "$existing"

    [[ "$(stat -c '%a' "$existing")" == "1777" ]]
}

@test "a missing directory is still created" {
    local missing="$BATS_TEST_TMPDIR/missing-dir"

    ensure_directory "$missing"

    [[ -d "$missing" ]]
}

@test "the target user is passed through to each bootstrap step" {
    local environment_record="$BATS_TEST_TMPDIR/step-environment"

    cat >"$SCRIPT_DIR/test-step.sh" <<EOF
#!/usr/bin/env bash
printf 'TARGET_USER=%s REBOOT_AT_END=%s\n' "\${TARGET_USER:-unset}" "\${REBOOT_AT_END:-unset}" >'$environment_record'
EOF
    chmod +x "$SCRIPT_DIR/test-step.sh"

    TARGET_USER="someone" run_step "test-step" "test-step.sh"

    [[ "$(<"$environment_record")" == "TARGET_USER=someone REBOOT_AT_END=false" ]]
}

@test "an unset target user is not forced onto the step" {
    local environment_record="$BATS_TEST_TMPDIR/step-environment"

    cat >"$SCRIPT_DIR/test-step.sh" <<EOF
#!/usr/bin/env bash
printf 'TARGET_USER=%s\n' "\${TARGET_USER:-unset}" >'$environment_record'
EOF
    chmod +x "$SCRIPT_DIR/test-step.sh"

    unset TARGET_USER
    run_step "test-step" "test-step.sh"

    [[ "$(<"$environment_record")" == "TARGET_USER=unset" ]]
}

@test "failed reboot scheduling does not mark bootstrap complete" {
    # shellcheck disable=SC2329
    schedule_reboot() {
        return 1
    }

    run finalize_bootstrap

    [[ "$status" -ne 0 ]]
    [[ ! -e "$STATE_DIR/complete" ]]
}

@test "successful reboot scheduling records revision completion" {
    schedule_reboot() {
        return 0
    }

    run finalize_bootstrap

    [[ "$status" -eq 0 ]]
    [[ "$(<"$STATE_DIR/complete")" == "$TEST_REVISION" ]]
}

@test "autoinstall enables a retrying revision-bound service that removes itself on success" {
    local autoinstall_file

    for autoinstall_file in autoinstall-desktop.yaml autoinstall-server.yaml; do
        autoinstall_file="$BATS_TEST_DIRNAME/../$autoinstall_file"

        grep -Fq 'After=network-online.target cloud-final.service' "$autoinstall_file"
        run grep -Fq 'ConditionPathExists=!/var/lib/packertron-bootstrap/complete' "$autoinstall_file"
        [[ "$status" -ne 0 ]]
        grep -Fq 'Restart=on-failure' "$autoinstall_file"
        grep -Fq 'ExecStartPost=/usr/bin/systemctl disable packertron-firstboot.service' "$autoinstall_file"
        grep -Fq 'ExecStartPost=/usr/bin/rm -f /etc/systemd/system/packertron-firstboot.service' "$autoinstall_file"
        grep -Fq 'ExecStartPost=/usr/bin/systemctl daemon-reload' "$autoinstall_file"
        # shellcheck disable=SC2016
        grep -Fq 'PACKERTRON_BOOTSTRAP_REVISION="$REPO_COMMIT" \' "$autoinstall_file"
        # The target user must be passed explicitly: there is no SUDO_USER
        # under systemd, and discovery fails once a second account exists.
        # shellcheck disable=SC2016
        grep -Fq 'TARGET_USER="$INSTALL_USER" exec \' "$autoinstall_file"
        # shellcheck disable=SC2016
        grep -Fq 'git -C "$REPO_DIR" checkout --detach "$REPO_COMMIT"' "$autoinstall_file"
        grep -Fq -- '- [systemctl, start, --no-block, packertron-firstboot.service]' "$autoinstall_file"
        ! grep -Fq -- '- ["/usr/local/sbin/packertron-firstboot"]' "$autoinstall_file"
    done
}
