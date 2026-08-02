#!/usr/bin/env bats

@test "Ubuntu README documents every provisioning entry path" {
    local readme="$BATS_TEST_DIRNAME/../README.md"

    grep -Fq 'Ubuntu Desktop and Ubuntu Server' "$readme"
    grep -Fq '### Packer template build' "$readme"
    grep -Fq '### Vagrant-provisioned workstation' "$readme"
    grep -Fq '### Autoinstall / bare-metal first boot' "$readme"
    grep -Fq '90-bootstrap-baremetal.sh' "$readme"
    grep -Fq 'autoinstall-noscripts.yaml' "$readme"
    grep -Fq 'intentional negative control' "$readme"
}

@test "autoinstall validation comments reference the actual YAML file" {
    local filename

    for filename in \
        autoinstall-desktop.yaml \
        autoinstall-server.yaml \
        autoinstall-noscripts.yaml; do
        grep -Fq -- "--config-file ${filename} --annotate" "$BATS_TEST_DIRNAME/../$filename"
        if grep -Fq -- '--config-file autoinstall.yaml' "$BATS_TEST_DIRNAME/../$filename"; then
            return 1
        fi
    done
}
