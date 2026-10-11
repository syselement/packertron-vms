:: Block inbound SSH, then shut down the generalized image. 12_sysprep.ps1 has
:: already run sysprep in the last provisioner; on the box's first boot,
:: 04_startup.ps1 opens SSH again once that boot has finished.
:: Supplied to the win-srv-2025 VMware build as a floppy file.
::
:: Docs:
::   shutdown   https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/shutdown
::   README.md  templates/vmware/win-srv-2025/README.md
::
:: Run: invoked as the build's shutdown_command; not meant to be run by hand.

netsh advfirewall firewall set rule name="Allow SSH" new action=block

shutdown /s /t 5 /f /d p:4:1 /c "Packer: the image is generalized"
