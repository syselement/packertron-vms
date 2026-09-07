# Security

This repository builds lab VM templates. Read this before pointing anything it produces at a network you do not control.

## The images ship a known password

Every autoinstall seed - `scripts/ubuntu/autoinstall-*.yaml` and each
`templates/*/*/http/user-data` - commits a SHA-512 crypt hash for the initial
user, and the plaintext is documented in the file next to it.

- This is not an accident and it cannot be avoided for an unattended install: subiquity needs the hash at install time, before the machine exists and before anything is available to fetch a secret from.
- Treat that credential as public.

It follows that:

- Every machine built from this repository starts with the **same** console password.
- The same seeds grant that user `NOPASSWD: ALL` sudo, permanently.
- SSH password authentication is disabled (`allow-pw: false`) and a fixed
  ed25519 public key is authorized, so remote access depends on holding the
  matching private key - but console and GDM login do not.
- Because of that, the Proxmox build authenticates through the **SSH agent**
  (`ssh_agent_auth`), not a password and not a key file. No passphrase-less
  copy of a personal key has to exist on disk for a build to run.

**Change the password on any machine that will be reachable by anyone else.**

`.gitleaks.toml` allowlists the crypt-hash pattern only, never the files, so a real credential committed to those same seeds is still reported.

## Credentials belong in the environment

Nothing that authenticates to real infrastructure is committed. A value lands in one of three places, decided by what it is:

| Kind | Where | Committed |
| --- | --- | --- |
| API token, SSH password | environment, `PKR_VAR_*` | **never** |
| Node name, storage pools, bridge | `templates/proxmox/proxmox.pkrvars.hcl` | no - only the `.example` |
| ISO URL, checksum, sizing | the template's `.pkr.hcl` / `.auto.pkrvars.hcl` | yes |

```bash
export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
export PKR_VAR_proxmox_api_token_secret="..."
export PKR_VAR_ssh_password="..."
```

- Use an API **token** scoped to template creation, not a root password.
- Keep `insecure_skip_tls_verify` at its default of `false` unless the node presents a self-signed certificate you have deliberately chosen to accept.

- The middle row is not secret, but it describes one person's network, so it is not shared either.
- `.gitignore` excludes `proxmox.pkrvars.hcl` and any `*.local.pkrvars.hcl`, along with `*.tfvars`, `.env`, `*.kdbx` and private keys.
- Only `proxmox.pkrvars.hcl.example` is tracked.

A token in the environment cannot be committed by a mistake in a `.gitignore` rule, which is why the split is drawn there rather than at "sensitive files".

## Per-machine identity in a cloned image

Anything that identifies *a machine* rather than *an image* has to be removed before a template is cloned, or every clone shares it.

`scripts/ubuntu/01-cleanup-system.sh` runs in every build and handles the two
that matter everywhere: it truncates `/etc/machine-id` and clears
`/var/lib/cloud`, so a clone is treated as a new instance and reads the
cloud-init drive attached to it.

The Proxmox template's own build block does the rest, as a final step after `01`:

- **SSH host keys** are deleted, and a one-shot unit regenerates them before
  `ssh.service` starts on the clone. Shipped in the image, they let any clone
  impersonate any other with no warning to a client that has connected before.
- **`/etc/netplan/00-installer-config*.yaml`**, which subiquity pins to the
  *build* VM's MAC address, is removed. A clone gets a new MAC, so the stanza
  matches nothing and configures nothing; leaving it behind only hides the fact
  that cloud-init's `50-cloud-init.yaml` is doing all the work.
- **`/var/lib/systemd/random-seed`** is removed so clones do not start from a shared seed.

It also fails the build if subiquity's cloud-init pinning survived the install,
or if `manage_etc_hosts` was not set, rather than shipping a template whose
clones silently ignore their cloud-init drive or answer to a name that resolves
nowhere.

**This applies to the Proxmox template only.**

- The VMware templates keep their host keys, because subiquity leaves cloud-init pinned there and nothing would regenerate them: an image with no host keys cannot start `sshd`.
- Treat a VMware image built from this repository as one machine, not a template to clone widely - or unpin cloud-init there first, the same way `templates/proxmox/ubuntu-24.04-server/http/user-data` does.

## Supply chain

- GitHub Actions are pinned to commit SHAs, not tags, with the version in a trailing comment. Dependabot proposes the updates.
- `changelog-ci` is the only job with `contents: write`, granted at job level; the workflow default is `contents: read`.
- Every other workflow checks out with `persist-credentials: false`.
- ISO checksums are verified on every build, either as a literal `sha256:` or via the distribution's signed `SHA256SUMS`.

## Recommended repository settings

Not settable from a file - enable these in the GitHub UI:

- Secret scanning, **and** push protection.
- Dependabot alerts.
- A branch ruleset on `main` with **Restrict deletions**, **Block force pushes** and **Require status checks to pass**.

Required status checks match the *job* context, not the workflow name, so the two to add are:

- `Ubuntu static checks`
- `Template checks complete`

`Template checks complete` is an aggregate job that depends on the others.

- Require it rather than the individual jobs: `packer` is a matrix and emits one context per template, so requiring those directly breaks the ruleset whenever a
  template is added or renamed, and a removed entry leaves a required check that can never report again.

Do **not** require `Changelog CI`. It has no `pull_request` trigger, so it would never report and no PR could merge.

### Letting the release through the ruleset

- `Changelog CI` pushes the version bump and tag straight to `main`.
- A ruleset enforces **Require status checks to pass** on direct pushes too, and the release commit is created on the runner, so it has no check runs and never can have.

The push is rejected:

```
remote: - 2 of 2 required status checks are expected.
```

- A push authenticated with the default `GITHUB_TOKEN` acts as `github-actions[bot]`, which is not a repository admin and so cannot bypass the rule.

The workflow therefore uses a `RELEASE_TOKEN` secret:

1. **Create a fine-grained PAT** — Settings → Developer settings → Personal access tokens → Fine-grained tokens.
   - Scope it to this repository only, with **Repository permissions → Contents: Read and write**. Nothing else.
   - Give it the shortest expiry you are willing to renew.
2. **Store it** as repository secret `RELEASE_TOKEN`.
3. **Allow the bypass** — in the `main` ruleset, *Bypass list* → *Add bypass* → **Repository admin**.

- The token is a real credential: it can write to this repository.
- Rotate it on expiry, and revoke it immediately if it leaks.
- If the secret is absent the workflow falls back to `GITHUB_TOKEN`, so a fork still runs and simply fails at the push step rather than at checkout.

- A tag can outlive a rejected push.
- `git push --follow-tags` sends tags and the branch separately, so a blocked release leaves an orphan tag pointing at a commit that is not on `main`; the next run then treats it as the last release and skips the bump.
- Check with `git ls-remote --tags origin` after any failed release, and delete the stray tag with `git push origin :refs/tags/vX.Y.Z`.

## Reporting

This is a personal lab project. Open an issue, or contact the repository owner directly for anything you would rather not file publicly.
