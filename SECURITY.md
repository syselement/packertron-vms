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
- Require the `Template checks` and `Ubuntu static checks` workflows to pass
  before merging to `main`.

## Reporting

This is a personal lab project. Open an issue, or contact the repository owner
directly for anything you would rather not file publicly.
