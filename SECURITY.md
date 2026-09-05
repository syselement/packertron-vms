# Security

This repository builds lab VM templates. Read this before pointing anything it
produces at a network you do not control.

## The images ship a known password

Every autoinstall seed - `scripts/ubuntu/autoinstall-*.yaml` and each
`*/http/user-data` - commits a SHA-512 crypt hash for the initial user, and the
plaintext is documented in the file next to it.

This is not an accident and it cannot be avoided for an unattended install:
subiquity needs the hash at install time, before the machine exists and before
anything is available to fetch a secret from. Treat that credential as public.

It follows that:

- Every machine built from this repository starts with the **same** console
  password.
- The same seeds grant that user `NOPASSWD: ALL` sudo, permanently.
- SSH password authentication is disabled (`allow-pw: false`) and a fixed
  ed25519 public key is authorized, so remote access depends on holding the
  matching private key - but console and GDM login do not.

**Change the password on any machine that will be reachable by anyone else.**

`.gitleaks.toml` allowlists the crypt-hash pattern only, never the files, so a
real credential committed to those same seeds is still reported.

## Credentials belong in the environment

Nothing that authenticates to real infrastructure is committed. Proxmox
credentials are read from the environment:

```bash
export PKR_VAR_proxmox_api_token_id="packer@pve!templates"
export PKR_VAR_proxmox_api_token_secret="..."
```

Use an API **token** scoped to template creation, not a root password. Keep
`insecure_skip_tls_verify` at its default of `false` unless the node presents a
self-signed certificate you have deliberately chosen to accept.

The tracked `*.auto.pkrvars.hcl` and `*.pkrvars.hcl` files carry ISO URLs,
checksums and sizing only. Anything sensitive that must live in a file belongs
in a `*.local.pkrvars.hcl`, which `.gitignore` excludes along with `*.tfvars`,
`.env`, `*.kdbx` and private keys.

## Supply chain

- GitHub Actions are pinned to commit SHAs, not tags, with the version in a
  trailing comment. Dependabot proposes the updates.
- `changelog-ci` is the only job with `contents: write`, granted at job level;
  the workflow default is `contents: read`.
- Every other workflow checks out with `persist-credentials: false`.
- ISO checksums are verified on every build, either as a literal `sha256:` or
  via the distribution's signed `SHA256SUMS`.

## Recommended repository settings

Not settable from a file - enable these in the GitHub UI:

- Secret scanning, **and** push protection.
- Dependabot alerts.
- A branch ruleset on `main` with **Restrict deletions**, **Block force
  pushes** and **Require status checks to pass**.

Required status checks match the *job* context, not the workflow name, so the
two to add are:

- `Ubuntu static checks`
- `Template checks complete`

`Template checks complete` is an aggregate job that depends on the others.
Require it rather than the individual jobs: `packer` is a matrix and emits one
context per template, so requiring those directly breaks the ruleset whenever a
template is added or renamed, and a removed entry leaves a required check that
can never report again.

Do **not** require `Changelog CI`. It has no `pull_request` trigger, so it
would never report and no PR could merge.

### Letting the release through the ruleset

`Changelog CI` pushes the version bump and tag straight to `main`. A ruleset
enforces **Require status checks to pass** on direct pushes too, and the
release commit is created on the runner, so it has no check runs and never can
have. The push is rejected:

```
remote: - 2 of 2 required status checks are expected.
```

A push authenticated with the default `GITHUB_TOKEN` acts as
`github-actions[bot]`, which is not a repository admin and so cannot bypass the
rule. The workflow therefore uses a `RELEASE_TOKEN` secret:

1. **Create a fine-grained PAT** — Settings → Developer settings → Personal
   access tokens → Fine-grained tokens. Scope it to this repository only, with
   **Repository permissions → Contents: Read and write**. Nothing else. Give it
   the shortest expiry you are willing to renew.
2. **Store it** as repository secret `RELEASE_TOKEN`.
3. **Allow the bypass** — in the `main` ruleset, *Bypass list* → *Add bypass* →
   **Repository admin**.

The token is a real credential: it can write to this repository. Rotate it on
expiry, and revoke it immediately if it leaks. If the secret is absent the
workflow falls back to `GITHUB_TOKEN`, so a fork still runs and simply fails at
the push step rather than at checkout.

A tag can outlive a rejected push. `git push --follow-tags` sends tags and the
branch separately, so a blocked release leaves an orphan tag pointing at a
commit that is not on `main`; the next run then treats it as the last release
and skips the bump. Check with `git ls-remote --tags origin` after any failed
release, and delete the stray tag with
`git push origin :refs/tags/vX.Y.Z`.

## Reporting

This is a personal lab project. Open an issue, or contact the repository owner
directly for anything you would rather not file publicly.
