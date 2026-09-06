# Build settings for the Windows 11 Proxmox template.
#
# STATUS: this template does not build and is excluded from CI. It still
# reads its credentials from a KeePass database two directories up
# (../../seclab.kdbx) that is not part of this repository, and copies in a CA
# certificate from ../../pki that is not here either, so `packer validate`
# cannot run on it. See README notes in ../kali for the shape the conversion
# took there.
#
# This file previously held the single word "placeholder", which is not valid
# HCL: any packer command run in this directory failed to parse before it
# could report the real problems above.
#
# When it is converted, node settings belong in ../proxmox.pkrvars.hcl with
# every other Proxmox template, and credentials in the environment.
