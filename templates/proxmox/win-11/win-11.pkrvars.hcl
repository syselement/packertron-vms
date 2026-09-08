# Build settings for the Windows 11 Proxmox template.
#
# STATUS: does not build, excluded from CI. It reads credentials from a KeePass
# database (../../seclab.kdbx) and a CA certificate from ../../pki, neither of
# which is in this repository, so packer validate cannot run on it.
#
# When converted, node settings belong in ../proxmox.pkrvars.hcl and
# credentials in the environment.
