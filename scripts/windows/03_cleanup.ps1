# Source: https://github.com/eaksel/packer-Win2022/blob/main/scripts/cleanup.ps1

# Clear the terminal screen
Clear-Host

## Stops the windows update service.
Get-Service -Name wuauserv | Stop-Service -Force -Verbose -ErrorAction SilentlyContinue

## Deletes the contents of windows software distribution.
Get-ChildItem "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

## Deletes all files and folders in user's Temp folder.
Get-ChildItem "C:\users\*\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

## Remove all files and folders in user's Temporary Internet Files.
Get-ChildItem "C:\users\*\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

## Deletes the contents of the Windows Temp folder.
Get-ChildItem "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue