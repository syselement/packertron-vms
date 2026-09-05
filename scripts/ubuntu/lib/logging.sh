#!/usr/bin/env bash
# The colour variables are assigned here and read by the sourcing script.
# shellcheck disable=SC2034

# Shared logging for 02-provision-system.sh and 03-customize-system.sh.
#
# One format for both scripts:
#
#   [2026-09-05 15:27:02] [provision-system] INFO  install baseline packages
#   [2026-09-05 15:27:02] [provision-system] OK    Docker service enabled
#
# The sourcing script sets SCRIPT_NAME, LOG_PREFIX and LOG_FILE before calling
# anything here.
#
# 00-update-system.sh and 01-cleanup-system.sh deliberately do not use this:
# Packer's shell provisioner uploads those two on their own, with no lib/
# directory beside them, and neither writes its own log file.

t_bold=""
t_dim=""
t_cyan=""
t_green=""
t_yellow=""
t_red=""
t_reset=""

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "[${SCRIPT_NAME}] ERROR must run as root (use: sudo bash $0)" >&2
        exit 1
    fi
}

# Console keeps ANSI colours, while the log file stores plain text. Call this
# before start_log_file: afterwards stdout is a pipe, so the terminal test can
# only ever answer false.
enable_colors() {
    if [[ -t 1 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR+x}" ]]; then
        t_bold=$'\e[1m'
        t_dim=$'\e[2m'
        t_cyan=$'\e[36m'
        t_green=$'\e[32m'
        t_yellow=$'\e[33m'
        t_red=$'\e[31m'
        t_reset=$'\e[0m'
    fi
}

# Strip ANSI escapes, then keep only the final state of a carriage-return
# redrawn line - dpkg and curl repaint progress with \r, so without this every
# intermediate percentage would be appended to the log.
#
# The `T keep` branch is what stops that second rule creating a new problem: a
# progress line ending in \r has nothing after the last one, so it collapses to
# an empty line rather than disappearing, and a single dpkg run leaves hundreds
# of them. `T` branches out for any line where no substitution happened - that
# is, any line with no \r at all - so only the collapsed remnants are deleted
# and the blank lines the scripts print between sections survive.
filter_log_output() {
    sed -u -r \
        -e 's/\x1B\[[0-9;]*[[:alpha:]]//g' \
        -e 's/.*\r//;T keep' \
        -e '/^$/d' \
        -e ':keep'
}

# Send output to both the console and the filtered log file.
start_log_file() {
    install -m 0600 /dev/null "$LOG_FILE"
    exec > >(tee >(filter_log_output >"$LOG_FILE")) 2>&1
}

_ts() { date +'%F %T'; }

log() {
    local level="$1"
    local level_color="$2"
    shift 2

    local message="$*"
    local ts

    ts="$(_ts)"
    printf '%s %s %s%-5s%s %s\n' \
        "[$ts]" \
        "$LOG_PREFIX" \
        "$level_color" \
        "$level" \
        "$t_reset" \
        "$message"
}

section() {
    printf '\n'
    log "STEP" "${t_cyan}${t_bold}" "==================== $* ===================="
}

info() { log "INFO" "$t_dim" "$@"; }
ok() { log "OK" "${t_green}${t_bold}" "$@"; }
warn() { log "WARN" "${t_yellow}${t_bold}" "$@"; }
error() { log "ERROR" "${t_red}${t_bold}" "$@"; }

manual_step() {
    printf '\n'
    printf '    %s\n' "------------------------------------------------------------"
    log "STEP" "${t_cyan}${t_bold}" "--- $* ---"
}
manual_line() { printf '    %s\n' "$*"; }
manual_item() { printf '    • %s\n' "$*"; }
manual_command() { printf '      $ %s\n' "$*"; }

die() {
    error "$*"
    exit 1
}
