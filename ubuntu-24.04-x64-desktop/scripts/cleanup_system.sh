#!/bin/bash -eux

echo "APT - Autoremove packages and clean apt cache"
apt -y autoremove &> /dev/null
apt -y clean &> /dev/null

echo "Clean journal logs"
journalctl --rotate
journalctl --vacuum-time=1s

echo "Remove machine-id files"
truncate -s 0 /etc/machine-id /var/lib/dbus/machine-id

echo "Clean temporary files"
rm -rf /tmp/* /var/tmp/*

echo "System cleanup completed."
