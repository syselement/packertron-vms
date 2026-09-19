#!/usr/bin/env bats

# Covers scripts/ubuntu/firstboot/run.sh, the revision pinning and retry logic
# that used to be embedded in the autoinstall seeds where no test could reach
# it. The fixtures are real git repositories: the code under test is almost
# entirely git behaviour, and stubbing git would test the stub.

setup() {
    ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    WORKTREE="$BATS_TEST_TMPDIR/work"

    git init -q --bare -b main "$ORIGIN"
    git init -q -b main "$WORKTREE"
    git -C "$WORKTREE" config user.email tests@example.invalid
    git -C "$WORKTREE" config user.name tests
    printf 'one\n' >"$WORKTREE/file"
    git -C "$WORKTREE" add -A
    git -C "$WORKTREE" commit -qm one
    git -C "$WORKTREE" remote add origin "$ORIGIN"
    git -C "$WORKTREE" push -q origin main

    export PACKERTRON_REPO_DIR="$BATS_TEST_TMPDIR/repo"
    export PACKERTRON_STATE_DIR="$BATS_TEST_TMPDIR/state"
    export PACKERTRON_REPO_BRANCH=main
    git clone -q "$ORIGIN" "$PACKERTRON_REPO_DIR"

    HEAD_COMMIT="$(git -C "$PACKERTRON_REPO_DIR" rev-parse --verify origin/main)"
    MISSING_COMMIT="0123456789abcdef0123456789abcdef01234567"

    # shellcheck disable=SC1090
    source "$BATS_TEST_DIRNAME/../firstboot/run.sh"

    install -d -m 0700 "$STATE_DIR"
}

# Push a second commit so origin/main moves ahead of $HEAD_COMMIT.
advance_branch() {
    printf 'two\n' >"$WORKTREE/file"
    git -C "$WORKTREE" commit -qam two
    git -C "$WORKTREE" push -q origin main
    git -C "$PACKERTRON_REPO_DIR" fetch -q --prune origin
    git -C "$PACKERTRON_REPO_DIR" rev-parse --verify origin/main
}

@test "with no pin recorded the branch head is chosen and written down" {
    run resolve_revision

    [[ "$status" -eq 0 ]]
    [[ "$output" == "$HEAD_COMMIT" ]]
    [[ "$(<"$REVISION_FILE")" == "$HEAD_COMMIT" ]]
}

@test "an existing pin is reused rather than re-resolved" {
    printf '%s\n' "$HEAD_COMMIT" >"$REVISION_FILE"
    advance_branch >/dev/null

    run resolve_revision

    [[ "$status" -eq 0 ]]
    # The branch has moved, but a pinned run must stay coherent.
    [[ "$output" == "$HEAD_COMMIT" ]]
}

@test "a malformed recorded revision is fatal rather than passed to git" {
    printf '%s\n' '--upload-pack=evil' >"$REVISION_FILE"

    run resolve_revision

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"invalid recorded bootstrap revision"* ]]
}

@test "a pinned revision that no longer exists falls back to the branch head" {
    printf '%s\n' "$MISSING_COMMIT" >"$REVISION_FILE"

    run resolve_revision

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"$HEAD_COMMIT" ]]
    [[ "$(<"$REVISION_FILE")" == "$HEAD_COMMIT" ]]
}

@test "attempts are counted against the revision they were made for" {
    [[ "$(recorded_attempts "$HEAD_COMMIT")" -eq 0 ]]

    record_attempt "$HEAD_COMMIT" 2
    [[ "$(recorded_attempts "$HEAD_COMMIT")" -eq 2 ]]

    # A different revision starts its own count.
    [[ "$(recorded_attempts "$MISSING_COMMIT")" -eq 0 ]]
}

@test "the branch head is adopted once a pinned revision exhausts its attempts" {
    local moved
    moved="$(advance_branch)"

    run revision_after_attempt_ceiling "$HEAD_COMMIT" "$MAX_PINNED_ATTEMPTS"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"$moved" ]]
    [[ "$(<"$REVISION_FILE")" == "$moved" ]]
}

@test "a failing revision that is still the branch head is kept, with a warning" {
    run revision_after_attempt_ceiling "$HEAD_COMMIT" "$MAX_PINNED_ATTEMPTS"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"$HEAD_COMMIT" ]]
    [[ "$output" == *"push a fix to recover"* ]]
}

@test "a revision below the attempt ceiling is left alone" {
    advance_branch >/dev/null

    run revision_after_attempt_ceiling "$HEAD_COMMIT" 1

    [[ "$status" -eq 0 ]]
    [[ "$output" == "$HEAD_COMMIT" ]]
    [[ ! -e "$REVISION_FILE" ]]
}

@test "completion counts only when it matches the revision now pinned" {
    printf '%s\n' "$HEAD_COMMIT" >"$REVISION_FILE"
    printf '%s\n' "$HEAD_COMMIT" >"$STATE_DIR/complete"
    run bootstrap_already_complete
    [[ "$status" -eq 0 ]]

    # A newly pinned revision must provision again, not be treated as done.
    printf '%s\n' "$MISSING_COMMIT" >"$REVISION_FILE"
    run bootstrap_already_complete
    [[ "$status" -ne 0 ]]
}

@test "an absent completion marker is not treated as completion" {
    printf '%s\n' "$HEAD_COMMIT" >"$REVISION_FILE"

    run bootstrap_already_complete

    [[ "$status" -ne 0 ]]
}
