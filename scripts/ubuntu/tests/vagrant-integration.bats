#!/usr/bin/env bats

@test "Ubuntu Vagrant provisioners stage the complete script bundle" {
    local repository_root
    local vagrantfile
    local -a vagrantfiles=(
        "ubuntu-24.04-x64-desktop/Vagrantfile"
        "ubuntu-26.04-x64-desktop/Vagrantfile"
    )

    repository_root="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

    for vagrantfile in "${vagrantfiles[@]}"; do
        vagrantfile="$repository_root/$vagrantfile"

        grep -Fq 'source: "../scripts/ubuntu"' "$vagrantfile"
        grep -Fq 'destination: "/var/tmp/packertron-ubuntu"' "$vagrantfile"
        grep -Fq 'inline: "bash /var/tmp/packertron-ubuntu/02-provision-system.sh"' "$vagrantfile"
        grep -Fq 'inline: "bash /var/tmp/packertron-ubuntu/03-customize-system.sh"' "$vagrantfile"
        ! grep -Fq 'path: "../scripts/ubuntu/' "$vagrantfile"
    done
}
