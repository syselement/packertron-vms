#!/usr/bin/env bats

# Covers scripts/proxmox/stage-isos.sh end to end, against fixture templates.
# curl and ssh are stubs on PATH: curl serves files from FIXTURES by URL
# basename, and ssh runs the remote command here, so nothing leaves the
# machine and the --node path is exercised with its real quoting.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../stage-isos.sh"
    FIXTURES="$BATS_TEST_TMPDIR/fixtures"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    export PACKERTRON_TEMPLATES_DIR="$BATS_TEST_TMPDIR/templates"
    export PACKERTRON_ISO_DIR="$BATS_TEST_TMPDIR/iso dir"
    export CURL_LOG="$BATS_TEST_TMPDIR/curl.log"
    export SSH_LOG="$BATS_TEST_TMPDIR/ssh.log"
    export FIXTURES
    mkdir -p "$FIXTURES" "$STUBS" "$PACKERTRON_TEMPLATES_DIR"

    cat >"$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
output=""
url=""
while (($# > 0)); do
    case "$1" in
        --output) output="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
printf '%s\n' "$url" >>"$CURL_LOG"
source_file="$FIXTURES/${url##*/}"
[[ -f "$source_file" ]] || exit 22
if [[ -n "$output" ]]; then cp "$source_file" "$output"; else cat "$source_file"; fi
STUB
    cat >"$STUBS/ssh" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "--" ]] && shift
printf '%s\n' "$1" >>"$SSH_LOG"
shift
exec bash -c "$*"
STUB
    chmod +x "$STUBS/curl" "$STUBS/ssh"
    export PATH="$STUBS:$PATH"

    printf 'linux installer\n' >"$FIXTURES/linux.iso"
    printf 'windows installer\n' >"$FIXTURES/windows.iso"
    printf 'virtio drivers\n' >"$FIXTURES/virtio.iso"
    LINUX_SHA="$(sha256sum "$FIXTURES/linux.iso" | cut -d ' ' -f 1)"
    WINDOWS_SHA="$(sha256sum "$FIXTURES/windows.iso" | cut -d ' ' -f 1)"
    VIRTIO_SHA="$(sha256sum "$FIXTURES/virtio.iso" | cut -d ' ' -f 1)"
    printf '%s *other.iso\n%s *linux.iso\n' "$WINDOWS_SHA" "$LINUX_SHA" >"$FIXTURES/SHA256SUMS"

    write_template linux \
        'local:iso/linux.iso' 'https://example.invalid/linux/linux.iso' \
        'file:https://example.invalid/linux/SHA256SUMS'
    write_template windows \
        'local:iso/windows.iso' 'https://example.invalid/windows.iso' "sha256:${WINDOWS_SHA}" \
        '' 'https://example.invalid/virtio.iso' "sha256:${VIRTIO_SHA}"
}

# write_template <name> <iso_file> <iso> <checksum> [<virtio_iso_file> <virtio_iso> <virtio_checksum>]
write_template() {
    local dir="$PACKERTRON_TEMPLATES_DIR/$1"

    mkdir -p "$dir"
    {
        printf 'variable "iso_file" {\n  type    = string\n  default = "%s"\n}\n\n' "$2"
        printf 'variable "iso" {\n  type        = string\n  description = "x"\n  default     = "%s"\n}\n\n' "$3"
        printf 'variable "checksum" {\n  type    = string\n  default = "%s"\n}\n' "$4"
        if (($# > 4)); then
            printf 'variable "virtio_iso_file" {\n  default = "%s"\n}\n' "$5"
            printf 'variable "virtio_iso" {\n  default = "%s"\n}\n' "$6"
            printf 'variable "virtio_checksum" {\n  default = "%s"\n}\n' "$7"
        fi
    } >"$dir/$1.pkr.hcl"
}

@test "a missing ISO is downloaded and checked against its SHA256SUMS line" {
    run "$SCRIPT" linux

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"staged  local:iso/linux.iso (checksum matches)"* ]]
    [[ "$(<"$PACKERTRON_ISO_DIR/linux.iso")" == "linux installer" ]]
    [[ ! -e "$PACKERTRON_ISO_DIR/linux.iso.partial" ]]
}

@test "a literal sha256 checksum is used as written, and an empty virtio_iso_file is skipped" {
    run "$SCRIPT" windows

    [[ "$status" -eq 0 ]]
    [[ "$(<"$PACKERTRON_ISO_DIR/windows.iso")" == "windows installer" ]]
    [[ ! -e "$PACKERTRON_ISO_DIR/virtio.iso" ]]
    ! grep -q 'virtio.iso' "$CURL_LOG"
}

@test "a staged virtio ISO is handled like the installer" {
    write_template windows \
        'local:iso/windows.iso' 'https://example.invalid/windows.iso' "sha256:${WINDOWS_SHA}" \
        'local:iso/virtio.iso' 'https://example.invalid/virtio.iso' "sha256:${VIRTIO_SHA}"

    run "$SCRIPT" windows

    [[ "$status" -eq 0 ]]
    [[ "$(<"$PACKERTRON_ISO_DIR/virtio.iso")" == "virtio drivers" ]]
}

@test "an ISO already staged and matching is not downloaded again" {
    mkdir -p "$PACKERTRON_ISO_DIR"
    cp "$FIXTURES/windows.iso" "$PACKERTRON_ISO_DIR/windows.iso"

    run "$SCRIPT" windows

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"already staged, checksum matches"* ]]
    ! grep -q 'windows.iso' "$CURL_LOG" 2>/dev/null
}

@test "an ISO already staged with the wrong checksum is reported and left alone" {
    mkdir -p "$PACKERTRON_ISO_DIR"
    printf 'something else\n' >"$PACKERTRON_ISO_DIR/windows.iso"

    run "$SCRIPT" windows

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"is on the node but its sha256 is"* ]]
    [[ "$(<"$PACKERTRON_ISO_DIR/windows.iso")" == "something else" ]]
}

@test "a download that fails its checksum leaves nothing behind" {
    printf 'tampered installer\n' >"$FIXTURES/windows.iso"

    run "$SCRIPT" windows

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"nothing staged"* ]]
    [[ ! -e "$PACKERTRON_ISO_DIR/windows.iso" ]]
    [[ ! -e "$PACKERTRON_ISO_DIR/windows.iso.partial" ]]
}

@test "a SHA256SUMS that does not list the ISO stops before any download" {
    printf '%s *other.iso\n' "$WINDOWS_SHA" >"$FIXTURES/SHA256SUMS"

    run "$SCRIPT" linux

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"lists no linux.iso"* ]]
    ! grep -q 'linux.iso' "$CURL_LOG"
}

@test "one failing template does not stop the others" {
    mkdir -p "$PACKERTRON_ISO_DIR"
    printf 'something else\n' >"$PACKERTRON_ISO_DIR/windows.iso"

    run "$SCRIPT"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"1 template(s) not staged"* ]]
    [[ -f "$PACKERTRON_ISO_DIR/linux.iso" ]]
}

@test "a dry run downloads nothing" {
    run "$SCRIPT" --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"would stage local:iso/linux.iso"* ]]
    [[ "$output" == *"would stage local:iso/windows.iso"* ]]
    [[ ! -e "$PACKERTRON_ISO_DIR" ]]
    ! grep -q '\.iso$' "$CURL_LOG"
}

@test "an unknown template is an error" {
    run "$SCRIPT" nonexistent

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"no template named nonexistent"* ]]
}

@test "--node runs the staging on the node, quoting a path with spaces" {
    run "$SCRIPT" --node root@pve02 linux

    [[ "$status" -eq 0 ]]
    [[ "$(<"$SSH_LOG")" == "root@pve02" ]]
    [[ "$(<"$PACKERTRON_ISO_DIR/linux.iso")" == "linux installer" ]]
}
