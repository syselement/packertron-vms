:: Block SSH on first boot
netsh advfirewall firewall set rule name="Allow SSH" new action=block

:: Sysprep and shutdown
C:/windows/system32/sysprep/sysprep.exe /generalize /oobe /unattend:C:/Windows/Panther/unattend.xml /quiet /shutdown