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

# The Dpkg::Options are not redundant with DEBIAN_FRONTEND: that governs
# debconf, while dpkg's own "Configuration file '...' - what would you like to
# do about it?" prompt is separate. Without these, a run started from a
# terminal (the documented way to run 02 and 03) blocks indefinitely on any
# locally modified conffile. confdef takes the package default where one
# exists, confold keeps the local file otherwise.
run_apt_get() {
    DEBIAN_FRONTEND=noninteractive apt-get \
        -o DPkg::Lock::Timeout=300 \
        -o Acquire::Retries=3 \
        -o Acquire::http::Timeout=30 \
        -o Acquire::https::Timeout=30 \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        "$@"
}
