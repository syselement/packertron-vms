:: Block inbound SSH, then sysprep and shut down. This is the last thing that
:: runs in the image, so the box is packaged generalized.
:: Supplied to the win-srv-2025 build as a floppy file.
::
:: Docs:
::   Sysprep  https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-command-line-options
::
:: Run: invoked as the build's shutdown_command; not meant to be run by hand.

:: Block SSH on first boot
netsh advfirewall firewall set rule name="Allow SSH" new action=block

:: Sysprep and shutdown
C:/windows/system32/sysprep/sysprep.exe /generalize /oobe /unattend:C:/Windows/Panther/unattend.xml /quiet /shutdown