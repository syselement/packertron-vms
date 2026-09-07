# Download and silently install VMware Tools, then reboot.
# Run by the win-srv-2025 Packer build as a provisioner.
#
# Docs:
#   VMware Tools  https://packages.vmware.com/tools/releases/latest/windows/x64/
#   Source        https://github.com/eaksel/packer-Win2022/blob/main/scripts/vmware-tools.ps1
#
# Run: Packer invokes this; it is not meant to be run by hand.

$ProgressPreference = "SilentlyContinue"

$webclient = New-Object System.Net.WebClient
$version_url = "https://packages.vmware.com/tools/releases/latest/windows/x64/"
$raw_package = $webclient.DownloadString($version_url)
$raw_package -match "VMware-tools[\w-\d\.]*\.exe"
$package = $Matches.0

$url = "https://packages.vmware.com/tools/releases/latest/windows/x64/$package"
$exe = "$Env:TEMP\$package"

Write-Output "***** Downloading VMware Tools"
$webclient.DownloadFile($url, $exe)

$parameters = '/S /v "/qn REBOOT=R ADDLOCAL=ALL"'

Write-Output "***** Installing VMware Tools"
Start-Process $exe $parameters -Wait

Write-Output "***** Deleting $exe"
Remove-Item $exe