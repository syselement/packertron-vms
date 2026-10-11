# Prepare a freshly installed Windows 10 or 11 on a real machine: the
# machine-wide settings the templates apply, a taskbar without search, Task
# View, news, Meet Now and pinned apps, optionally RDP and OpenSSH Server,
# then the utilities install_utils.ps1 installs through winget.
#
# Remote access stays off unless -EnableRemoteAccess is given: on a machine
# that leaves the lab, an RDP or SSH listener is a decision, not a default.
#
# Docs:
#   Edge policy          https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies#hidefirstrunexperience
#   Telemetry            https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization
#   OpenSSH for Windows  https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse
#   README.md            ../README.md, bare metal, the USB stick it runs from
#
# Run, from an elevated PowerShell, with install_utils.ps1 in the same folder:
#   powershell -NoProfile -ExecutionPolicy Bypass -File D:\setup-windows.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File D:\setup-windows.ps1 -EnableRemoteAccess

param(
    # Turn on RDP and OpenSSH Server, each with its firewall rule.
    [switch]$EnableRemoteAccess
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Step {
    param([string]$Message)
    Write-Output ('[{0:HH:mm}] {1}' -f (Get-Date), $Message)
}

function Write-PolicyValue {
    param([string]$Path, [string]$Name, [int]$Value)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Enable-RemoteDesktop {
    # Home has no RDP server; the setting would do nothing there.
    if ((Get-CimInstance -ClassName Win32_OperatingSystem).Caption -match 'Home') {
        Write-Warning 'Windows Home has no Remote Desktop server; skipping RDP'
        return
    }
    Write-Step 'Enabling Remote Desktop'
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
}

function Enable-OpenSshServer {
    # Windows 10 and 11 download the capability from Windows Update.
    $capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
    if ($capability.State -ne 'Installed') {
        Write-Step 'Installing OpenSSH Server'
        Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
    }
    if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
            -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
    }
    # Private and domain networks only, unlike the lab VMs: a laptop's Public
    # network is a coffee shop's.
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Private, Domain
    Set-Service -Name 'sshd' -StartupType Automatic
    Start-Service -Name 'sshd'
    Write-Step 'OpenSSH Server is running'
}

# Search box, Task View, News and Interests (Widgets on Windows 11), Meet
# Now and the default pinned apps: off for this account now, and for every
# account created later through the Default profile.
function Hide-TaskbarItem {
    Write-PolicyValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' -Name 'EnableFeeds' -Value 0
    Write-PolicyValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0
    Write-PolicyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'HideSCAMeetNow' -Value 1

    $userValues = @(
        @('Software\Microsoft\Windows\CurrentVersion\Search', 'SearchboxTaskbarMode')
        @('Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced', 'ShowTaskViewButton')
    )
    foreach ($value in $userValues) {
        Write-PolicyValue -Path "HKCU:\$($value[0])" -Name $value[1] -Value 0
    }
    # This account's pins; Explorer restarts with none.
    $taskband = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband'
    if (Test-Path -LiteralPath $taskband) {
        Remove-Item -LiteralPath $taskband -Recurse -Force
    }

    & reg.exe load 'HKU\PackertronDefault' "$env:SystemDrive\Users\Default\NTUSER.DAT" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "reg load of the Default profile failed with exit code $LASTEXITCODE"
    }
    try {
        foreach ($value in $userValues) {
            Write-PolicyValue -Path "Registry::HKEY_USERS\PackertronDefault\$($value[0])" -Name $value[1] -Value 0
        }
    } finally {
        # The registry provider holds the hive open until its handles are
        # collected, and reg unload refuses an open hive.
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        & reg.exe unload 'HKU\PackertronDefault' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "reg unload of the Default profile failed with exit code $LASTEXITCODE; it unloads at the next restart"
        }
    }

    # New accounts' pins: Replace with an empty list drops Windows' defaults.
    # An OEM's own layout is left alone.
    $layout = Join-Path $env:SystemDrive 'Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml'
    if ((Test-Path -LiteralPath $layout) -and -not (Select-String -LiteralPath $layout -Pattern 'packertron' -Quiet)) {
        Write-Warning "$layout is not this repository's; leaving the default pins of new accounts alone"
    } else {
        New-Item -ItemType Directory -Path (Split-Path $layout -Parent) -Force | Out-Null
        Set-Content -LiteralPath $layout -Encoding UTF8 -Value @(
            '<?xml version="1.0" encoding="utf-8"?>'
            '<!-- packertron-vms: no pinned apps on the taskbar of a new account. -->'
            '<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">'
            '  <CustomTaskbarLayoutCollection PinListPlacement="Replace">'
            '    <defaultlayout:TaskbarLayout>'
            '      <taskbar:TaskbarPinList>'
            '      </taskbar:TaskbarPinList>'
            '    </defaultlayout:TaskbarLayout>'
            '  </CustomTaskbarLayoutCollection>'
            '</LayoutModificationTemplate>'
        )
    }

    # Windows restarts Explorer on its own, which rereads the taskbar.
    Stop-Process -Name explorer -Force
}

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this from an elevated PowerShell (Run as administrator)'
}

# Beside this script, on the stick as in the repository.
$utilities = Join-Path $PSScriptRoot 'install_utils.ps1'
if (-not (Test-Path -LiteralPath $utilities)) {
    throw "install_utils.ps1 not found beside $PSCommandPath; copy it to the same folder"
}

Write-Step 'Hiding the Edge first-run experience'
Write-PolicyValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'HideFirstRunExperience' -Value 1

# 0 is "Security" on Enterprise and Education; Home and Pro treat it as 1,
# "Required", their lowest level.
Write-Step 'Setting diagnostic data to the lowest level'
Write-PolicyValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0

Write-Step 'Cleaning up the taskbar'
Hide-TaskbarItem

if ($EnableRemoteAccess) {
    Enable-RemoteDesktop
    Enable-OpenSshServer
}

Write-Step "Running $utilities"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $utilities
if ($LASTEXITCODE -ne 0) {
    throw "install_utils.ps1 failed with exit code $LASTEXITCODE"
}

Write-Step 'Done. Run Windows Update, then restart.'
