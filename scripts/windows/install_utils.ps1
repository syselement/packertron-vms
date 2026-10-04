# Install Chocolatey, a few utilities through it, and the latest UniGetUI, on
# Windows 10, Windows 11 or Windows Server 2025.
#
# Both installers are downloaded to a file and run only once their Authenticode
# signature checks out as their publisher's; UniGetUI's must also match the
# SHA-256 digest GitHub publishes for the release asset.
#
# Docs:
#   Chocolatey install  https://docs.chocolatey.org/en-us/choco/setup/
#   UniGetUI releases   https://github.com/Devolutions/UniGetUI/releases
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

$InstallerUrl = 'https://community.chocolatey.org/install.ps1'
$Utilities = @(
    '7zip'
    'brave'
    'firefox'
    'notepadplusplus.install'
    'powershell-core'
    'sublimetext4'
)
$UniGetUiRepository = 'Devolutions/UniGetUI'
# The installer's Inno Setup AppId, from UniGetUI.iss.
$UniGetUiUninstallKey = '{889610CC-4337-4BDB-AC3B-4F21806C0BDE}_is1'

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
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $installer -UseBasicParsing

        Assert-Signer -Path $installer -Organization 'Chocolatey Software, Inc'

        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        & $installer
    } finally {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    }

    # The installer updates the machine PATH, not this session's.
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
}

# 2026.3.0 and 2026.3.0.0 are the same release: the tag has three parts, the
# installer stamps four. $null when the text is not a version.
function ConvertTo-FullVersion {
    param([string]$Text)

    $parsed = $null
    if (-not [version]::TryParse($Text, [ref]$parsed)) {
        return $null
    }
    [version]::new($parsed.Major, $parsed.Minor, [math]::Max($parsed.Build, 0), [math]::Max($parsed.Revision, 0))
}

function Get-UniGetUiInstalledVersion {
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall') {
        $key = Join-Path $root $UniGetUiUninstallKey
        if (Test-Path -LiteralPath $key) {
            return (Get-ItemProperty -LiteralPath $key).PSObject.Properties['DisplayVersion'].Value
        }
    }
}

function Install-UniGetUi {
    $assetName = 'UniGetUI.Installer.x64.exe'

    $release = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/$UniGetUiRepository/releases/latest"
    $version = $release.tag_name -replace '^v', ''
    $wanted = ConvertTo-FullVersion $version
    if (-not $wanted) {
        throw "unexpected UniGetUI release tag: $($release.tag_name)"
    }
    if ((ConvertTo-FullVersion (Get-UniGetUiInstalledVersion)) -eq $wanted) {
        Write-Step "UniGetUI $version is already installed"
        return
    }

    $asset = @($release.assets | Where-Object { $_.name -eq $assetName })
    if ($asset.Count -ne 1) {
        throw "UniGetUI $($release.tag_name) has no single $assetName asset"
    }
    # Read through PSObject: strict mode throws on a property the API left out.
    $digest = $asset[0].PSObject.Properties['digest']
    if (-not $digest -or $digest.Value -notmatch '^sha256:([0-9a-fA-F]{64})$') {
        throw "GitHub published no SHA-256 digest for $assetName; refusing to install UniGetUI $($release.tag_name)"
    }
    $expectedHash = $Matches[1]

    Write-Step "Installing UniGetUI $version"
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) $assetName
    try {
        Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $installer -UseBasicParsing
        $actualHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
        if ($actualHash -ne $expectedHash) {
            throw "$assetName SHA-256 is $actualHash, GitHub published $expectedHash"
        }
        Assert-Signer -Path $installer -Organization 'Devolutions Inc'

        # /ALLUSERS: the installer defaults to a per-user install.
        $process = Start-Process -FilePath $installer -Wait -PassThru -ArgumentList @(
            '/SP-', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/ALLUSERS', '/NoAutoStart'
        )
        # 100: installed, but adding UniGetUI to PATH failed.
        if ($process.ExitCode -eq 100) {
            Write-Warning 'UniGetUI installed, but its PATH entry could not be added'
        } elseif ($process.ExitCode -ne 0) {
            throw "UniGetUI installer failed with exit code $($process.ExitCode)"
        }
    } finally {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
    }
}

# Windows PowerShell 5.1 may still default to TLS 1.0, which both download
# sites refuse.
[System.Net.ServicePointManager]::SecurityProtocol =
    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

Install-Chocolatey

Write-Step 'Installing utilities'
& choco install -y --limit-output --no-progress @Utilities
# 1641 and 3010: installed, reboot required or already started.
if ($LASTEXITCODE -notin 0, 1641, 3010) {
    throw "choco install failed with exit code $LASTEXITCODE"
}

Install-UniGetUi
Write-Step 'Utilities installation complete'
