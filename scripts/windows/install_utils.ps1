# Install a few utilities and UniGetUI through winget, and Chocolatey for tools
# winget does not carry, on Windows 10, Windows 11 or Windows Server 2025.
#
# winget checks each installer against the SHA-256 in its manifest, and the
# App Installer packages that carry winget are signed MSIX that Windows checks.
# The Chocolatey installer runs only once its Authenticode signature checks
# out as its publisher's.
#
# Docs:
#   winget install      https://learn.microsoft.com/en-us/windows/package-manager/winget/install
#   WinGet.Client       https://www.powershellgallery.com/packages/Microsoft.WinGet.Client
#   Chocolatey install  https://docs.chocolatey.org/en-us/choco/setup/
#   README.md           ../../deploy/README.md, first-boot provisioning
#
# Run:
#   deploy/ hands this to cloudbase-init as user-data on a Windows clone whose
#   entry sets provisioning_steps = "utils", and the VMware win-srv-2025
#   Vagrantfile runs it as a shell provisioner. By hand, from an elevated
#   PowerShell (Windows 10 and 11 block scripts by default):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\install_utils.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# The official winget-pkgs IDs.
$WingetPackages = @(
    '7zip.7zip'
    'Brave.Brave'
    'Devolutions.UniGetUI'
    'Microsoft.PowerShell'
    'Mozilla.Firefox'
    'Notepad++.Notepad++'
    'SublimeHQ.SublimeText.4'
)
# Microsoft.PowerShell lists its MSIX first, and an MSIX installed by SYSTEM
# is not registered for anyone else; the MSI installs for every user.
$WingetInstallerTypes = @{
    'Microsoft.PowerShell' = 'wix'
}
# Chocolatey IDs, for a tool winget does not carry. None needs it yet.
$ChocolateyPackages = @()
$ChocolateyInstallerUrl = 'https://community.chocolatey.org/install.ps1'

function Write-Step {
    param([string]$Message)
    Write-Output ('[{0:HH:mm}] {1}' -f (Get-Date), $Message)
}

function Assert-Signer {
    param([string]$Path, [string]$Organization)

    $signature = Get-AuthenticodeSignature -FilePath $Path
    if ($signature.Status -ne 'Valid') {
        throw "$Path signature is $($signature.Status): $($signature.StatusMessage)"
    }
    # The O= value, quoted when it holds a comma: O="Chocolatey Software, Inc".
    $subject = $signature.SignerCertificate.Subject
    $signer = if ($subject -match '(?:^|,\s*)O=(?:"([^"]*)"|([^,]*))') { "$($Matches[1])$($Matches[2])" }
    if ($signer -ne $Organization) {
        throw "$Path is signed by an unexpected publisher: $subject"
    }
}

function Install-Chocolatey {
    if (Get-Command -Name 'choco' -ErrorAction SilentlyContinue) {
        Write-Step 'Chocolatey is already installed'
        return
    }

    Write-Step 'Installing Chocolatey'
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) 'chocolatey-install.ps1'
    try {
        Invoke-WebRequest -Uri $ChocolateyInstallerUrl -OutFile $installer -UseBasicParsing

        Assert-Signer -Path $installer -Organization 'Chocolatey Software, Inc'

        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        & $installer
    } finally {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    }

    # The installer updates the machine PATH, not this session's.
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
}

# Microsoft's documented bootstrap: the WinGet.Client module installs App
# Installer and its dependencies for every user, or repairs an outdated one,
# which a Windows 10 template carries.
function Install-Winget {
    Write-Step 'Installing winget'
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    }
    if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
        Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope AllUsers -Force
    }
    Import-Module -Name Microsoft.WinGet.Client
    Repair-WinGetPackageManager -AllUsers -Latest | Out-Null
    # -AllUsers provisions App Installer for the next logon. An administrator
    # in this session, such as Vagrant's, needs it registered now as well.
    if (-not [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        Repair-WinGetPackageManager -Latest | Out-Null
    }
}

function Get-WingetPath {
    $command = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    # SYSTEM, which cloudbase-init runs as, has no app execution alias for
    # winget; the executable sits in the App Installer package directory.
    $candidate = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object -Property { [version]($_.Directory.Name -split '_')[1] } |
        Select-Object -Last 1
    if (-not $candidate) {
        throw 'winget.exe was not found after installing App Installer'
    }
    $candidate.FullName
}

# Installs, or upgrades when a newer version is out.
function Install-WingetPackage {
    param([string]$Winget, [string]$Id)

    $arguments = @(
        'install', '--id', $Id, '--exact', '--source', 'winget', '--scope', 'machine',
        '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements'
    )
    if ($WingetInstallerTypes.ContainsKey($Id)) {
        $arguments += @('--installer-type', $WingetInstallerTypes[$Id])
    }
    & $Winget @arguments
    # 0x8A15002B: installed, no newer version. 0x8A150061: already installed.
    # 0x8A150109: installed, reboot required to finish.
    if ($LASTEXITCODE -notin 0, -1978335189, -1978335135, -1978334967) {
        throw ('winget install {0} failed with exit code 0x{1:X8}' -f $Id, $LASTEXITCODE)
    }
}

# Windows PowerShell 5.1 may still default to TLS 1.0, which the PowerShell
# Gallery and Chocolatey refuse.
[System.Net.ServicePointManager]::SecurityProtocol =
    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

Install-Winget
$winget = Get-WingetPath
foreach ($id in $WingetPackages) {
    Write-Step "Installing $id"
    Install-WingetPackage -Winget $winget -Id $id
}

Install-Chocolatey
if ($ChocolateyPackages.Count -gt 0) {
    Write-Step 'Installing Chocolatey packages'
    & choco install -y --limit-output --no-progress @ChocolateyPackages
    # 1641 and 3010: installed, reboot required or already started.
    if ($LASTEXITCODE -notin 0, 1641, 3010) {
        throw "choco install failed with exit code $LASTEXITCODE"
    }
}

Write-Step 'Utilities installation complete'
