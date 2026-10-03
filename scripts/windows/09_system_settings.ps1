# Apply the machine-wide settings every Windows template starts from: no Edge
# first-run wizard, the lowest diagnostic-data level, the High performance
# power plan, and an Administrator password that does not expire.
#
# Per-user settings - dark mode and the Explorer view - live in the answer
# file's Default-hive block instead, so every new profile starts with them.
#
# Docs:
#   Edge policy    https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies#hidefirstrunexperience
#   Telemetry      https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization
#   powercfg       https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options
#   WINDOWS.md     ../../templates/proxmox/WINDOWS.md, the build chain
#
# Run: Packer invokes this; it is not meant to be run by hand.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-PolicyValue {
    param([string]$Path, [string]$Name, [int]$Value)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

Write-Output 'Hiding the Edge first-run experience'
Write-PolicyValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HideFirstRunExperience' -Value 1

# 0 is "Security" on Enterprise and Server, the editions these templates
# build; Windows Update keeps working at that level.
Write-Output 'Setting diagnostic data to the lowest level'
Write-PolicyValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0

# High performance never sleeps the VM and never parks its cores. SCHEME_MIN
# is powercfg's alias for that plan on every edition.
Write-Output 'Activating the High performance power plan'
& powercfg.exe /setactive SCHEME_MIN
if ($LASTEXITCODE -ne 0) {
    throw "powercfg /setactive SCHEME_MIN failed with exit code $LASTEXITCODE"
}

# Local password policy expires it after 42 days otherwise, and a lab clone
# that forces a change at the console is a clone nobody can script against.
# A clone's account is this one, renamed on Windows 10 and 11.
Write-Output 'Setting the Administrator password to never expire'
Get-LocalUser | Where-Object { $_.SID.Value -like 'S-1-5-*-500' } |
    Set-LocalUser -PasswordNeverExpires $true
