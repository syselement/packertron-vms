#!/usr/bin/env bats

setup() {
    # shellcheck disable=SC1091
    source "$BATS_TEST_DIRNAME/../lib/download.sh"

    ATTEMPT_RECORD="$BATS_TEST_TMPDIR/attempts"
    : >"$ATTEMPT_RECORD"

    warn() {
        printf 'WARN: %s\n' "$*"
    }
}

@test "a download that succeeds first time is attempted once" {
    curl() {
        printf 'attempt\n' >>"$ATTEMPT_RECORD"
        return 0
    }

    run fetch_file "https://example.invalid/file" "$BATS_TEST_TMPDIR/out"

    [[ "$status" -eq 0 ]]
    [[ "$(wc -l <"$ATTEMPT_RECORD")" -eq 1 ]]
    [[ "$output" != *"download failed"* ]]
}

@test "a transient failure is retried and reported" {
    curl() {
        printf 'attempt\n' >>"$ATTEMPT_RECORD"
        [[ "$(wc -l <"$ATTEMPT_RECORD")" -ge 2 ]]
    }
    sleep() { :; }

    run fetch_file "https://example.invalid/file" "$BATS_TEST_TMPDIR/out"

    [[ "$status" -eq 0 ]]
    [[ "$(wc -l <"$ATTEMPT_RECORD")" -eq 2 ]]
    [[ "$output" == *"download failed (1/3)"* ]]
}

@test "a persistent failure gives up after three attempts without a trailing warning" {
    curl() {
        printf 'attempt\n' >>"$ATTEMPT_RECORD"
        return 1
    }
    sleep() { :; }

    run fetch_file "https://example.invalid/file" "$BATS_TEST_TMPDIR/out"

    [[ "$status" -ne 0 ]]
    [[ "$(wc -l <"$ATTEMPT_RECORD")" -eq 3 ]]
    [[ "$output" == *"download failed (1/3)"* ]]
    [[ "$output" == *"download failed (2/3)"* ]]
    # The final failure is the caller's to report, not a warning here.
    [[ "$output" != *"download failed (3/3)"* ]]
}

@test "range requests are capped and not retried by the outer loop" {
    local argument_record="$BATS_TEST_TMPDIR/arguments"

    curl() {
        printf '%s\n' "$@" >"$argument_record"
        printf 'attempt\n' >>"$ATTEMPT_RECORD"
        return 1
    }

    run fetch_file_range "https://example.invalid/pkg.deb" "0-65535" "$BATS_TEST_TMPDIR/out"

    [[ "$status" -ne 0 ]]
    [[ "$(wc -l <"$ATTEMPT_RECORD")" -eq 1 ]]
    grep -Fxq '0-65535' "$argument_record"
    grep -Fxq '65536' "$argument_record"
}
