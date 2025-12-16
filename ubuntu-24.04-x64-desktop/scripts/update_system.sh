#!/bin/bash -eux

# Source: https://github.com/ynlamy/packer-ubuntuserver24_04

echo "Updating the system..."
apt -qq -y update &> /dev/null
apt -qq -y dist-upgrade &> /dev/null

echo "Installing packages..."
apt -qq -y install locate open-vm-tools net-tools unzip &> /dev/null
systemctl enable open-vm-tools
systemctl start open-vm-tools

echo "Setting up locate database..."
updatedb
echo "System update completed."
