#!/usr/bin/env bats

# Covers scripts/proxmox/prepare-node.sh. pvesh, pveum and pvesm are stubs on
# PATH that keep a fake node's state under PVE_STATE and log every change to
# PVE_CALLS, so each test can assert both what changed and what did not.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../prepare-node.sh"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    export PVE_STATE="$BATS_TEST_TMPDIR/pve"
    export PVE_CALLS="$BATS_TEST_TMPDIR/calls"
    mkdir -p "$STUBS" "$PVE_STATE"/{roles,users,tokens,storage}
    : >"$PVE_STATE/acl"
    printf 'backup,iso,vztmpl' >"$PVE_STATE/storage/local"

    cat >"$STUBS/pvesh" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == get ]] || exit 2
path="$2"
case "$path" in
    /access/roles/*)
        file="$PVE_STATE/roles/${path#/access/roles/}"
        [[ -f "$file" ]] || exit 1
        tr ',' '\n' <"$file" | awk 'NF { printf "%s\"%s\":1", (n++ ? "," : "{"), $0 } END { print (n ? "}" : "{}") }'
        ;;
    /access/users/*/token/*)
        user="${path#/access/users/}"
        [[ -f "$PVE_STATE/tokens/${user%%/token/*}!${path##*/token/}" ]] || exit 1
        printf '{"privsep":0}\n'
        ;;
    /access/users/*)
        [[ -f "$PVE_STATE/users/${path#/access/users/}" ]] || exit 1
        printf '{"enable":1}\n'
        ;;
    /access/acl)
        printf '[%s]\n' "$(paste -sd, "$PVE_STATE/acl")"
        ;;
    /storage/*)
        file="$PVE_STATE/storage/${path#/storage/}"
        [[ -f "$file" ]] || exit 1
        printf '{"content":"%s","storage":"%s","type":"dir"}\n' "$(<"$file")" "${path#/storage/}"
        ;;
    *) exit 1 ;;
esac
STUB
    cat >"$STUBS/pveum" <<'STUB'
#!/usr/bin/env bash
printf 'pveum %s\n' "$*" >>"$PVE_CALLS"
case "$1 $2" in
    "role add" | "role modify") printf '%s' "$5" >"$PVE_STATE/roles/$3" ;;
    "user add") : >"$PVE_STATE/users/$3" ;;
    "acl modify")
        printf '{"path":"%s","propagate":1,"roleid":"%s","type":"user","ugid":"%s"}\n' "$3" "$7" "$5" >>"$PVE_STATE/acl"
        ;;
    "user token")
        : >"$PVE_STATE/tokens/$4!$5"
        printf 'value: 11111111-2222-3333-4444-555555555555\n'
        ;;
    *) exit 2 ;;
esac
STUB
    cat >"$STUBS/pvesm" <<'STUB'
#!/usr/bin/env bash
printf 'pvesm %s\n' "$*" >>"$PVE_CALLS"
[[ "$1" == set && "$3" == --content ]] || exit 2
printf '%s' "$4" >"$PVE_STATE/storage/$2"
STUB
    chmod +x "$STUBS"/*
    export PATH="$STUBS:$PATH"

    # shellcheck disable=SC1090
    source "$SCRIPT"
    require_root() { :; }
}

@test "a fresh node gets the role, user, ACL, token and snippets" {
    run main

    [[ "$status" -eq 0 ]]
    [[ "$(<"$PVE_STATE/roles/IACDeploy")" == *"VM.GuestAgent.Audit"* ]]
    [[ "$(<"$PVE_STATE/roles/IACDeploy")" != *"Sys."* ]]
    [[ -f "$PVE_STATE/users/automation@pve" ]]
    grep -q '"path":"/".*"roleid":"IACDeploy".*"ugid":"automation@pve"' "$PVE_STATE/acl"
    grep -q '^pveum user token add automation@pve deploy --privsep 0$' "$PVE_CALLS"
    [[ "$output" == *"value: 11111111-2222-3333-4444-555555555555"* ]]
    [[ "$output" == *"save the secret above now"* ]]
    [[ "$(<"$PVE_STATE/storage/local")" == "backup,iso,vztmpl,snippets" ]]
    ! grep -q 'vdi@pve' "$PVE_CALLS"
}

@test "a second run changes nothing" {
    main >/dev/null
    : >"$PVE_CALLS"

    run main

    [[ "$status" -eq 0 ]]
    [[ ! -s "$PVE_CALLS" ]]
    [[ "$output" == *"role IACDeploy already has exactly its privileges"* ]]
    [[ "$output" == *"user automation@pve exists"* ]]
    [[ "$output" == *"automation@pve already holds IACDeploy on /"* ]]
    [[ "$output" == *"its secret was shown once"* ]]
    [[ "$output" == *"storage local already carries snippets"* ]]
}

@test "a dry run reports every change and makes none" {
    run main --dry-run

    [[ "$status" -eq 0 ]]
    [[ ! -e "$PVE_CALLS" ]]
    [[ "$output" == *"would run: pveum role add IACDeploy --privs"* ]]
    [[ "$output" == *"would run: pveum user add automation@pve"* ]]
    [[ "$output" == *"would run: pveum user token add automation@pve deploy --privsep 0"* ]]
    [[ "$output" == *"would run: pvesm set local --content backup\\,iso\\,vztmpl\\,snippets"* ]]
    [[ ! -e "$PVE_STATE/roles/IACDeploy" ]]
}

@test "a drifted role is set back to exactly its privileges, showing the difference" {
    main >/dev/null
    printf 'Sys.AccessNetwork,VM.Audit' >"$PVE_STATE/roles/IACDeploy"
    : >"$PVE_CALLS"

    run main

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"role IACDeploy differs:"* ]]
    [[ "$output" == *"remove Sys.AccessNetwork"* ]]
    [[ "$output" == *"add    VM.Clone"* ]]
    grep -q '^pveum role modify IACDeploy --privs ' "$PVE_CALLS"
    [[ "$(<"$PVE_STATE/roles/IACDeploy")" != *"Sys.AccessNetwork"* ]]
    [[ "$(<"$PVE_STATE/roles/IACDeploy")" == *"VM.Clone"* ]]
}

@test "--with-vdi adds the cv4pve-vdi user, limited to /vms" {
    run main --with-vdi

    [[ "$status" -eq 0 ]]
    [[ "$(<"$PVE_STATE/roles/CV4PVEVDI")" == "VM.Audit,VM.Console,VM.GuestAgent.Audit,VM.PowerMgmt" ]]
    [[ -f "$PVE_STATE/users/vdi@pve" ]]
    grep -q '"path":"/vms".*"roleid":"CV4PVEVDI".*"ugid":"vdi@pve"' "$PVE_STATE/acl"
    [[ "$output" == *"pveum passwd vdi@pve"* ]]
}

@test "another snippet storage is used, and a missing one is an error" {
    printf 'images' >"$PVE_STATE/storage/vmstore"

    run main --storage vmstore
    [[ "$status" -eq 0 ]]
    [[ "$(<"$PVE_STATE/storage/vmstore")" == "images,snippets" ]]
    [[ "$(<"$PVE_STATE/storage/local")" == "backup,iso,vztmpl" ]]

    run main --storage nonexistent
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"storage nonexistent not found"* ]]
}

@test "piped to bash -s, as over SSH, the script runs" {
    run bash -s -- --dry-run <"$SCRIPT"

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"would run: pveum role add IACDeploy"* ]]
}

@test "without root and without --dry-run it refuses" {
    if ((EUID == 0)); then
        skip "the suite is running as root"
    fi

    run bash "$SCRIPT"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"run as root on the node, or with --dry-run"* ]]
    [[ ! -e "$PVE_CALLS" ]]
}
