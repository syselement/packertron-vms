#!/usr/bin/env bash

# Shared APT invocation.
#
# Used by the scripts that are staged as a complete directory:
# 02-provision-system.sh and 03-customize-system.sh (Vagrant copies
# scripts/ubuntu wholesale, and the autoinstall first-boot runner checks the
# repository out).
#
# 00-update-system.sh deliberately keeps its own copy of this wrapper rather
# than sourcing this file: Packer's shell provisioner uploads that script on
# its own, with no lib/ directory beside it, so it has to stay self-contained.
# tests/update-system.bats asserts the two stay in step.

run_apt_get() {
    DEBIAN_FRONTEND=noninteractive apt-get \
        -o DPkg::Lock::Timeout=300 \
        -o Acquire::Retries=3 \
        -o Acquire::http::Timeout=30 \
        -o Acquire::https::Timeout=30 \
        "$@"
}
