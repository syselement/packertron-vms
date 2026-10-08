# Install a few utilities and UniGetUI through winget, and Chocolatey for tools
# winget does not carry, on Windows 10, Windows 11 or Windows Server 2025.
#
# cloudbase-init runs this as SYSTEM, which has no winget command and which
# winget's PowerShell module does not support (microsoft/winget-cli#3935). So
# this installs App Installer, which carries winget.exe, for every account,
# with the Visual C++ runtime winget needs as SYSTEM, and runs winget.exe from
# its package directory.
#
# Every download is checked before it runs: App Installer against the SHA-256
# GitHub publishes, the Visual C++ and Chocolatey installers against their
# publisher's signature, and each winget package against the SHA-256 in its
# manifest.
#
# Docs:
#   winget install      https://learn.microsoft.com/en-us/windows/package-manager/winget/install
#   winget releases     https://github.com/microsoft/winget-cli/releases
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
    # The viewer and the server, which runs as a service with a firewall
    # exception for port 5900 and no password until one is set in its
    # service configuration. SECURITY.md has the warning.
    'GlavSoft.TightVNC'
    'Microsoft.PowerShell'
    'Mozilla.Firefox'
    'Notepad++.Notepad++'
    'SublimeHQ.SublimeText.4'
    'WireGuard.WireGuard'
)
# Microsoft.PowerShell lists its MSIX first, and SYSTEM cannot install an
# MSIX for anyone else; the MSI installs for every user.
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

# Downloads the release asset with this name, or the one this pattern matches,
# and checks it against the SHA-256 GitHub publishes for it.
function Save-GitHubAsset {
    param($Release, [string]$Pattern, [string]$Directory)

    $asset = @($Release.assets | Where-Object { $_.name -like $Pattern })
    if ($asset.Count -ne 1) {
        throw "$($Release.html_url) has no single asset matching $Pattern"
    }
    # Read through PSObject: strict mode throws on a property the API left out.
    $digest = $asset[0].PSObject.Properties['digest']
    if (-not $digest -or $digest.Value -notmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw "GitHub published no SHA-256 digest for $($asset[0].name); refusing to use it"
    }
    $expectedHash = $Matches[1]

    $path = Join-Path $Directory $asset[0].name
    Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $path -UseBasicParsing
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        throw "$($asset[0].name) SHA-256 is $actualHash, GitHub published $expectedHash"
    }
    $path
}

function Get-TemporaryDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    (New-Item -ItemType Directory -Path $path).FullName
}

# winget run as SYSTEM needs this runtime, which an evaluation image may lack.
# Microsoft publishes no checksum for the redistributable, so its signature is
# the check.
function Install-VCRuntime {
    $key = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64' -ErrorAction SilentlyContinue
    if ($key -and $key.PSObject.Properties['Installed'] -and $key.Installed -eq 1) {
        Write-Step "Visual C++ runtime $($key.Version) is already installed"
        return
    }

    Write-Step 'Installing the Visual C++ runtime'
    $directory = Get-TemporaryDirectory
    try {
        $installer = Join-Path $directory 'vc_redist.x64.exe'
        Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vc_redist.x64.exe' -OutFile $installer -UseBasicParsing
        Assert-Signer -Path $installer -Organization 'Microsoft Corporation'
        $process = Start-Process -FilePath $installer -Wait -PassThru -ArgumentList @('/install', '/quiet', '/norestart')
        # 1638: a newer version is already installed. 1641 and 3010: installed,
        # reboot required or already started.
        if ($process.ExitCode -notin 0, 1638, 1641, 3010) {
            throw "Visual C++ runtime installer failed with exit code $($process.ExitCode)"
        }
    } finally {
        Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The app execution alias for an administrator; for SYSTEM, which has none,
# the newest winget.exe in the App Installer package directories. $null when
# App Installer is missing.
function Get-WingetPath {
    $alias = Get-Command -Name 'winget.exe' -ErrorAction SilentlyContinue
    if ($alias) {
        return $alias.Source
    }
    $packaged = Resolve-Path -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object -Property { [version]($_.Path -split '_')[1] } |
        Select-Object -Last 1
    if ($packaged) {
        $packaged.Path
    }
}

# "v1.29.380" from winget --version. $null when winget is missing, or too old
# to run as this account.
function Get-WingetVersion {
    $winget = Get-WingetPath
    if (-not $winget) {
        return $null
    }
    try {
        $text = & $winget --version
    } catch {
        return $null
    }
    $parsed = $null
    if ($LASTEXITCODE -eq 0 -and [version]::TryParse(("$text".Trim() -replace '^v', ''), [ref]$parsed)) {
        $parsed
    }
}

# Provisions App Installer, which carries winget, with its x64 dependencies,
# for every account and every later one; a Windows 10 template carries an old
# one. The bundle is signed MSIX, which Windows checks as it adds it.
function Install-AppInstaller {
    $release = Invoke-RestMethod -UseBasicParsing -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    $wanted = [version]($release.tag_name -replace '^v', '')
    $installed = Get-WingetVersion
    if ($installed -and $installed -ge $wanted) {
        Write-Step "winget $installed is already installed"
        return
    }

    Write-Step "Installing winget $wanted"
    $directory = Get-TemporaryDirectory
    try {
        $bundle = Save-GitHubAsset -Release $release -Pattern 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' -Directory $directory
        $license = Save-GitHubAsset -Release $release -Pattern '*_License1.xml' -Directory $directory
        $dependencies = Save-GitHubAsset -Release $release -Pattern 'DesktopAppInstaller_Dependencies.zip' -Directory $directory
        Expand-Archive -LiteralPath $dependencies -DestinationPath (Join-Path $directory 'dependencies')
        $x64 = @(Get-ChildItem -Path (Join-Path $directory 'dependencies\x64') -Filter '*.appx' | ForEach-Object { $_.FullName })
        if ($x64.Count -eq 0) {
            throw "DesktopAppInstaller_Dependencies.zip of $($release.tag_name) has no x64 packages"
        }

        try {
            Add-AppxProvisionedPackage -Online -PackagePath $bundle -DependencyPackagePath $x64 -LicensePath $license | Out-Null
        } catch {
            # 0x80073D06: a newer version is already installed.
            if ($_.Exception.HResult -ne -2147009274) {
                throw
            }
        }
    } finally {
        Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
    }

    # A provisioned package reaches an account at its next logon. An
    # administrator running this, such as Vagrant's, needs it now.
    if (-not [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
        Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
    }
}

# Installs, upgrades when a newer version is out, or leaves a current one.
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

# Windows PowerShell 5.1 may still default to TLS 1.0, which GitHub and
# Chocolatey refuse.
[System.Net.ServicePointManager]::SecurityProtocol =
    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

Install-VCRuntime
Install-AppInstaller
$winget = Get-WingetPath
if (-not $winget) {
    throw 'winget.exe was not found after installing App Installer'
}
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
