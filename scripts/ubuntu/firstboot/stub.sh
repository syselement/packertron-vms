#!/usr/bin/env bash
#
# Fetch the provisioning repository and hand off to the runner it carries.
# cloud-init writes this file to /usr/local/sbin/packertron-firstboot; it is
# the only part of the first-boot path that has to be embedded in a seed, so
# it is kept small and everything else lives in run.sh beside it.
#
# Settings come from /etc/packertron/firstboot.conf, which is read as
# KEY=VALUE and never sourced: the file is written by whoever deploys the
# machine, and sourcing it would make it arbitrary root code.
#
# Docs:
#   cloud-init  https://cloudinit.readthedocs.io/en/latest/
#   README.md   ../README.md, the first-boot runner and its settings
#
# Run:
#   The packertron-firstboot.service unit invokes this; not run by hand.
#   Lint it with: ../../check-templates.sh shell

set -Eeuo pipefail

CONF_FILE=/etc/packertron/firstboot.conf
LOG_FILE=/var/log/packertron-firstboot.log
RUNNER_PATH=scripts/ubuntu/firstboot/run.sh

# Last assignment wins, quotes are optional, and anything else in the file is
# ignored. Never source: this must not be able to execute code as root.
conf_value() {
    local key="$1" value=""

    [[ -r "$CONF_FILE" ]] || return 0
    value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$CONF_FILE" | tail -n 1)"
    value="${value%\"}" && value="${value#\"}"
    value="${value%\'}" && value="${value#\'}"
    printf '%s' "$value"
}

touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

PACKERTRON_REPO_URL="$(conf_value REPO_URL)"
PACKERTRON_REPO_BRANCH="$(conf_value REPO_BRANCH)"
PACKERTRON_REPO_DIR="$(conf_value REPO_DIR)"
PACKERTRON_TARGET_USER="$(conf_value TARGET_USER)"
PACKERTRON_STEPS="$(conf_value STEPS)"
: "${PACKERTRON_REPO_URL:=https://github.com/syselement/packertron-vms.git}"
: "${PACKERTRON_REPO_BRANCH:=main}"
: "${PACKERTRON_REPO_DIR:=/opt/packertron-vms}"
export PACKERTRON_REPO_URL PACKERTRON_REPO_BRANCH PACKERTRON_REPO_DIR
export PACKERTRON_TARGET_USER PACKERTRON_STEPS

# Checked here because this is where they reach git. A URL from the conf file
# that begins with a dash would otherwise be read as an option.
[[ "$PACKERTRON_REPO_URL" =~ ^https://[A-Za-z0-9._~:/?#@!$\&\'\(\)*+,\;=%-]+$ ]] ||
    {
        echo "ERROR: refusing a non-https repository URL: $PACKERTRON_REPO_URL" >&2
        exit 1
    }
[[ "$PACKERTRON_REPO_BRANCH" =~ ^[A-Za-z0-9._/-]+$ && "$PACKERTRON_REPO_BRANCH" != -* ]] ||
    {
        echo "ERROR: invalid repository branch: $PACKERTRON_REPO_BRANCH" >&2
        exit 1
    }

command -v git >/dev/null 2>&1 ||
    {
        echo "ERROR: git is not installed; cannot fetch the provisioning repository" >&2
        exit 1
    }

echo "Waiting for GitHub connectivity..."
reachable=false
for attempt in $(seq 1 30); do
    if git ls-remote "$PACKERTRON_REPO_URL" HEAD >/dev/null 2>&1; then
        reachable=true
        break
    fi
    echo "GitHub unavailable; retry ${attempt}/30"
    sleep 10
done
[[ "$reachable" == true ]] || {
    echo "ERROR: GitHub remained unreachable" >&2
    exit 1
}

if [[ -d "$PACKERTRON_REPO_DIR/.git" ]]; then
    echo "Updating managed repository checkout"
    git -C "$PACKERTRON_REPO_DIR" fetch --prune origin
else
    # A leftover non-repository directory would make git clone fail identically
    # on every retry, wedging the bootstrap forever.
    [[ ! -e "$PACKERTRON_REPO_DIR" ]] || rm -rf -- "$PACKERTRON_REPO_DIR"
    echo "Cloning managed repository checkout"
    install -d -m 0755 "$(dirname "$PACKERTRON_REPO_DIR")"
    git clone --branch "$PACKERTRON_REPO_BRANCH" "$PACKERTRON_REPO_URL" "$PACKERTRON_REPO_DIR"
fi

# Run from a copy on tmpfs, never from the checkout: the runner moves the
# checkout between revisions, and Bash re-reads a script file as it executes.
install -m 0700 "$PACKERTRON_REPO_DIR/$RUNNER_PATH" /run/packertron-firstboot-run
exec /run/packertron-firstboot-run
