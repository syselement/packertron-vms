# Ubuntu Provisioning Scripts

## Scope

- Work only inside `scripts/ubuntu/` unless explicitly instructed otherwise.
- Do not modify Kali, Windows, Packer, Vagrant, VMware, or repository-wide files.
- Preserve compatibility with the existing `packertron-vms` workflows.
- Prefer small, reviewable changes over complete rewrites.
- Preserve existing behavior unless the requested task explicitly changes it.
- Do not rename or move scripts without explicit approval.

## Target Systems

- Support Ubuntu Desktop and Ubuntu Server.
- Detect the operating system and release using `/etc/os-release`.
- Clearly separate Desktop-only functionality from Server-compatible functionality.
- Do not assume an interactive shell, graphical session, or logged-in desktop user.
- Account for execution by Packer, cloud-init, autoinstall, Vagrant, or manual provisioning.
- Do not add support for other distributions unless explicitly requested.

## Existing Script Order

Preserve the intended execution order:

1. `00-update-system.sh`
2. `01-cleanup-system.sh`
3. `02-provision-system.sh`
4. `03-customize-system.sh`
5. `90-bootstrap-baremetal.sh`, where applicable

Do not introduce hidden dependencies between scripts. If one script depends on
another, document the dependency clearly.

## Bash Standards

- Use Bash explicitly rather than POSIX `sh`.
- New executable scripts must begin with:

  ```bash
  #!/usr/bin/env bash
  set -Eeuo pipefail
  ```

- Do not add `set -Eeuo pipefail` blindly to an existing script without first
  checking whether its current logic is compatible.
- Quote variable expansions unless intentional word splitting is required.
- Use arrays for package lists and command arguments.
- Use `printf` instead of `echo` where output behavior matters.
- Use `local` variables inside functions.
- Prefer `[[ ... ]]` for Bash conditionals.
- Prefer arithmetic contexts for numeric comparisons.
- Avoid `eval`.
- Do not parse the output of `ls`.
- Avoid unnecessary subshells and pipelines.
- Avoid temporary files when a pipe or variable is sufficient.
- When temporary files are required, use `mktemp` and clean them with `trap`.
- Use descriptive function and variable names.
- Keep functions focused on one responsibility.
- Preserve the current formatting style unless a formatting refactor is
  explicitly requested.

## Error Handling

- Fail with an actionable error message.
- Send error messages to standard error.
- Return meaningful non-zero exit statuses.
- Do not hide failures with broad constructs such as:

  ```bash
  command || true
  ```

  unless the failure is expected and documented.
- Check failures at boundaries such as downloads, repository configuration,
  package installation, file writes, and service changes.
- When using traps, preserve the original exit status.
- Avoid leaving the system in a partially configured state where practical.

A preferred error helper is:

```bash
die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}
```

## Idempotency

- Scripts must be safe to run repeatedly.
- Check the current state before changing it.
- Do not duplicate configuration entries.
- Do not repeatedly append aliases, environment variables, repositories, or
  shell initialization blocks.
- Check whether packages, Flatpaks, Snaps, repositories, keyrings, groups,
  services, directories, files, and configuration entries already exist.
- Prefer declarative file generation when the complete file is owned by this
  project.
- Use explicit markers when managing only part of an existing file.
- Handle partially completed previous runs where practical.
- Avoid unnecessary package-manager refreshes inside individual functions.
- Do not reinstall software that is already correctly installed.
- Avoid enabling or restarting services when their state does not need to
  change.

## Privilege Handling

- Do not run Codex itself with `sudo`.
- Do not execute complete provisioning scripts on the development workstation.
- Validation commands must not modify the host system.
- Use `sudo` only for commands that require elevated privileges.
- Do not wrap an entire script in `sudo` unless explicitly required.
- Do not use redundant constructions such as:

  ```bash
  sudo sh -c "sudo command"
  ```

- Preserve the invoking user's home directory when user-level configuration is
  required.
- Do not assume that `$HOME` belongs to the intended desktop user while running
  under `sudo`.
- Resolve the target non-root user explicitly when necessary.
- Do not write user-owned files as root without correcting ownership.

## Safety Restrictions

Do not perform or introduce any of the following without explicit approval:

- rebooting or shutting down
- partitioning, formatting, or mounting storage
- modifying the bootloader
- changing kernel command-line parameters
- changing SSH configuration
- changing firewall rules
- changing network configuration
- changing DNS configuration
- modifying `sudoers`
- creating or deleting users
- changing authentication or PAM configuration
- changing the display manager
- removing packages
- purging configuration files
- disabling security services
- enabling remote access
- replacing system configuration files wholesale

Warn clearly before adding destructive or difficult-to-reverse operations.

## Package Management

Keep package managers separated by purpose:

- APT for Ubuntu repository packages
- Flatpak for selected desktop applications
- Snap only when intentionally selected
- Homebrew only for packages deliberately managed through Linuxbrew
- Manual installers only when no suitable managed package exists

Additional requirements:

- Store package names in Bash arrays.
- Avoid installing the same application through multiple package managers.
- Use noninteractive APT execution where appropriate.
- Do not set `DEBIAN_FRONTEND=noninteractive` globally for the user's shell.
- Account for APT and dpkg lock contention.
- Avoid running `apt update` repeatedly in multiple functions.
- Prefer `apt-get` for automation where stable machine-oriented behavior is
  useful.
- Do not use deprecated `apt-key`.
- Store repository keys under `/etc/apt/keyrings`.
- Use repository-specific `signed-by=` configuration.
- Use HTTPS repository URLs where available.
- Do not trust downloaded signing keys without validating their source.
- Do not add unsupported third-party repositories without explicit approval.

Example package array:

```bash
readonly COMMON_PACKAGES=(
    aptitude
    bash-completion
    bat
    git
    jq
)
```

Example installation pattern:

```bash
install_apt_packages() {
    local -a packages=("$@")

    ((${#packages[@]} > 0)) || return 0

    sudo apt-get install -y --no-install-recommends "${packages[@]}"
}
```

## Downloads and External Installers

- Do not use unverified `curl | bash` or `wget | sh` patterns.
- Download installers to a temporary file first.
- Use `curl` with:

  ```bash
  curl --fail --show-error --location
  ```

- Validate checksums or signatures when the publisher provides them.
- Pin versions when reproducibility is important.
- Do not download from unofficial mirrors without explicit approval.
- Do not execute downloaded files before validating them.
- Clean up temporary files after use.

Preferred pattern:

```bash
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

curl \
    --fail \
    --show-error \
    --location \
    --output "$tmp_file" \
    "$download_url"
```

## Desktop and Server Detection

- Detect Ubuntu using `/etc/os-release`.
- Do not identify Ubuntu Desktop solely from `$XDG_CURRENT_DESKTOP`,
  `$DESKTOP_SESSION`, or the presence of a graphical session.
- Prefer installed Ubuntu desktop metapackages as the primary signal.
- Treat display-server and session variables only as supplemental signals.
- Keep Desktop-only packages and customization out of Ubuntu Server paths.
- Functions should expose explicit results that other scripts can consume.

Example result values:

```text
ubuntu
ubuntu-desktop
ubuntu-server
unsupported
```

## Files and Configuration

- Create parent directories explicitly.
- Use restrictive permissions where appropriate.
- Preserve ownership and permissions when modifying existing files.
- Use `install` when it improves ownership and mode handling.
- Write complete generated files atomically where practical.
- Do not modify shell startup files with repeated unguarded appends.
- Use managed blocks for project-owned shell configuration.

Example managed block:

```text
# BEGIN PACKERTRON MANAGED BLOCK
...
# END PACKERTRON MANAGED BLOCK
```

- Back up important configuration files before replacing them.
- Do not create backups repeatedly on every run.
- Validate generated configuration before activating it when a validation
  command exists.

## Services and systemd

- Check whether a unit exists before enabling or starting it.
- Distinguish between system and user services.
- Do not assume systemd is available inside containers or image-build chroots.
- Avoid restarting services unnecessarily.
- Use `systemctl is-enabled` and `systemctl is-active` where appropriate.
- Run `systemctl daemon-reload` only after unit files change.
- Do not mask, disable, or replace system services without explicit approval.
- Report service changes that require VM-level validation.

## User Configuration

- Determine the intended non-root user explicitly.
- Do not assume the current effective user is the desktop user.
- Do not hard-code usernames or home paths.
- Use the target user's environment when running user-scoped commands.
- Preserve correct ownership for files under the target user's home directory.
- Do not overwrite existing user configuration without preserving or merging it.
- GNOME and desktop-session configuration may require execution in the user's
  graphical session; do not pretend such changes were validated when no session
  was available.

## Secrets

- Never add passwords, tokens, API keys, private keys, recovery codes, or
  credentials to the repository.
- Do not print secrets to logs.
- Do not place secrets directly in command-line arguments when a safer mechanism
  exists.
- Do not commit `.env` files containing real credentials.
- Use placeholders in examples.
- Apply restrictive permissions to sensitive files.
- Flag any existing secret-like material discovered during review.

## Logging and Output

- Keep output concise and actionable.
- Distinguish informational, warning, and error messages.
- Do not print misleading success messages before a command succeeds.
- Avoid excessive output from package managers unless needed for diagnostics.
- Do not suppress command output that is necessary to troubleshoot failures.

Example helpers:

```bash
log_info() {
    printf '[INFO] %s\n' "$*"
}

log_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}
```

## Testing and Validation

After modifying Bash files:

1. Run `bash -n` against every modified Bash script.
2. Run ShellCheck against every modified Bash script.
3. Run `shfmt -d` when `shfmt` is available.
4. Run applicable Bats tests.
5. Run `git diff --check`.
6. Review the complete Git diff.
7. Report any behavior that could not be tested safely.
8. Identify operations that require a disposable Ubuntu VM.

Suggested commands:

```bash
bash -n path/to/modified-script.sh
shellcheck path/to/modified-script.sh
shfmt -d -i 4 -ci path/to/modified-script.sh
git diff --check
git diff -- scripts/ubuntu
```

Do not run commands during validation that:

- install or remove packages
- modify repositories
- enable, disable, start, or stop services
- change user configuration
- modify networking
- modify the boot process
- reboot or shut down the machine
- change host firewall rules

Mock system-changing commands in tests where possible.

## VM Testing

Use a disposable Ubuntu VM for integration testing involving:

- APT package installation
- Flatpak or Snap installation
- systemd services
- GNOME configuration
- display-manager behavior
- networking
- Bluetooth
- libvirt
- kernel modules
- boot configuration
- reboot behavior
- bare-metal provisioning

Before VM testing:

- create a snapshot
- record the Ubuntu release
- record whether the VM is Desktop or Server
- record the exact command used
- preserve relevant logs

After VM testing:

- verify idempotency by running the relevant script twice
- confirm the second run makes no unnecessary changes
- inspect failed services
- inspect package-manager state
- revert the snapshot when required

## Change Management

For each task:

- inspect the relevant files before proposing changes
- explain the intended change briefly
- modify only files necessary for the task
- avoid unrelated formatting changes
- preserve backward compatibility unless explicitly instructed otherwise
- show the final diff
- summarize validation performed
- disclose assumptions and untested behavior
- do not commit changes unless explicitly requested
- do not push branches or tags unless explicitly requested

## Review Priorities

When reviewing changes, prioritize:

1. destructive behavior
2. security regressions
3. privilege-boundary errors
4. non-idempotent behavior
5. incomplete failure handling
6. package-manager correctness
7. Desktop and Server compatibility
8. quoting and word-splitting bugs
9. maintainability
10. formatting

Report findings with:

- severity
- file and line
- impact
- recommended fix

## Codex Working Rules

- Begin with an audit when the requested scope is broad.
- Do not modify files during an audit unless explicitly asked.
- For implementation tasks, make one bounded change at a time.
- Ask for approval before expanding the requested scope.
- Do not execute commands requiring `sudo`.
- Do not run the real provisioning workflow on the development host.
- Do not claim integration testing was completed unless it was actually run in
  a suitable disposable VM.
- At completion, provide:

  1. files changed
  2. behavior changed
  3. validation commands run
  4. validation results
  5. remaining risks
  6. VM tests still required
