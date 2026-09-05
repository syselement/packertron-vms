#!/usr/bin/env bash

# Shared download helpers for 02-provision-system.sh and
# 03-customize-system.sh.
#
# Depends on a warn() helper from the sourcing script.
#
# Behavior is the union of the two implementations these replaced: curl's own
# --retry, plus an outer attempt loop that reports each failure, plus stall
# detection so a connection that goes quiet is abandoned rather than hanging
# until --max-time. Output stays silent so progress meters do not end up in
# the log files.

fetch_file() {
    local url="$1"
    local destination_file="$2"
    local attempt
    local attempts=3

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        if curl \
            --fail \
            --show-error \
            --silent \
            --location \
            --connect-timeout 10 \
            --max-time 180 \
            --speed-limit 1024 \
            --speed-time 30 \
            --retry 2 \
            --retry-delay 2 \
            --output "$destination_file" \
            "$url"; then
            return 0
        fi

        ((attempt < attempts)) || break
        warn "download failed (${attempt}/${attempts}): ${url}"
        sleep 2
    done

    return 1
}

# Fetches only the requested byte range, used to read Debian package metadata
# without transferring the whole archive.
fetch_file_range() {
    local url="$1"
    local byte_range="$2"
    local destination_file="$3"

    curl \
        --fail \
        --show-error \
        --silent \
        --location \
        --connect-timeout 10 \
        --max-time 30 \
        --speed-limit 1024 \
        --speed-time 30 \
        --retry 2 \
        --retry-delay 2 \
        --range "$byte_range" \
        --max-filesize 65536 \
        --output "$destination_file" \
        "$url"
}
