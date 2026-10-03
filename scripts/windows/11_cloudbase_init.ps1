# Install cloudbase-init, pinned and verified, and put this repository's
# configuration in place. It does not run here: it runs on each clone, after
# sysprep, and reads the Proxmox cloud-init drive.
#
# Expects the two .conf files rendered from scripts/windows/cloudbase-init/ in
# C:\Windows\Temp\ beforehand, which the template's file provisioners do.
#
# Docs:
#   cloudbase-init  https://cloudbase-init.readthedocs.io/en/latest/
#   Releases        https://github.com/cloudbase/cloudbase-init/releases
#   WINDOWS.md      ../../templates/proxmox/WINDOWS.md, the clone-time model
#
# Run: Packer invokes this; it is not meant to be run by hand.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Bump all three together. The hash is of the release asset itself, computed
# when this version was pinned.
$Version = '1.1.8'
$MsiUrl = "https://github.com/cloudbase/cloudbase-init/releases/download/$Version/CloudbaseInitSetup_$($Version -replace '\.', '_')_x64.msi"
$MsiSha256 = '0E7FA42E0CBC0CE7657F85730B0C6CC7AFC4087A3639DF0FF51A721A0BE19BD5'

$InstallDir = 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init'
$ConfDir = Join-Path $InstallDir 'conf'
$StagedConfDir = 'C:\Windows\Temp'
$ConfFiles = @('cloudbase-init.conf', 'cloudbase-init-unattend.conf')

# Returns the MSI's path and nothing else: anything this function writes to
# the output stream would become part of the return value.
function Get-VerifiedInstaller {
    $msi = Join-Path $env:TEMP "CloudbaseInitSetup_$Version.msi"
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $MsiUrl -OutFile $msi -UseBasicParsing

    $actual = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
    if ($actual -ne $MsiSha256) {
        Remove-Item -LiteralPath $msi -Force
        throw "cloudbase-init checksum mismatch: expected $MsiSha256, got $actual"
    }
    # The hash already pins the exact file; the signature says who built it.
    $signature = Get-AuthenticodeSignature -FilePath $msi
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Cloudbase Solutions') {
        Remove-Item -LiteralPath $msi -Force
        throw "cloudbase-init signature is $($signature.Status), signed by '$($signature.SignerCertificate.Subject)'"
    }
    return $msi
}

# RUN_SERVICE_AS_LOCAL_SYSTEM: without it the MSI creates a second local
# account in Administrators just to run the service.
function Install-CloudbaseInit {
    param([string]$Msi)

    $process = Start-Process -FilePath 'msiexec.exe' -Wait -PassThru -ArgumentList @(
        '/i', "`"$Msi`"", '/qn', '/norestart', '/l*v', 'C:\Windows\Temp\cloudbase-init-install.log',
        'RUN_SERVICE_AS_LOCAL_SYSTEM=1'
    )
    if ($process.ExitCode -notin 0, 3010) {
        throw "cloudbase-init install failed with exit code $($process.ExitCode); see C:\Windows\Temp\cloudbase-init-install.log"
    }
}

# Replaces the files the MSI generated at install time.
function Install-Configuration {
    foreach ($name in $ConfFiles) {
        $source = Join-Path $StagedConfDir $name
        if (-not (Test-Path -LiteralPath $source)) {
            throw "$source is missing; the template uploads it before running this script"
        }
        Copy-Item -LiteralPath $source -Destination (Join-Path $ConfDir $name) -Force
        Remove-Item -LiteralPath $source -Force
    }
}

# The MSI installs the service to start at boot and does not start it. It must
# not run during the build: it would replace the password Packer logs in with -
# and on Windows 10 and 11 rename the account too - so the next provisioner
# could not connect. It is left Manual rather than Automatic because a clone's
# first boot is still inside Windows Setup: started then, it renamed the
# account and Setup reverted the rename, leaving an Administrator whose
# password nobody knew. SetupComplete.cmd starts it once Setup has finished.
function Register-ServiceStartAfterSetup {
    $service = Get-Service -Name 'cloudbase-init'
    if ($service.Status -ne 'Stopped') {
        Write-Output 'WARNING: cloudbase-init was running; stopping it'
        Stop-Service -Name 'cloudbase-init' -Force
    }
    Set-Service -Name 'cloudbase-init' -StartupType Manual

    # Windows runs this once, after Setup completes and before the logon
    # screen. It does not run on images activated with an OEM key, which the
    # evaluation media these templates use are not.
    $scripts = Join-Path $env:SystemRoot 'Setup\Scripts'
    $setupComplete = Join-Path $scripts 'SetupComplete.cmd'
    if ((Test-Path -LiteralPath $setupComplete) -and
        -not (Select-String -LiteralPath $setupComplete -Pattern 'packertron-vms' -Quiet)) {
        throw "$setupComplete already exists and is not this repository's; refusing to overwrite it"
    }
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null
    Set-Content -LiteralPath $setupComplete -Encoding ascii -Value @(
        '@rem packertron-vms: start cloudbase-init once Windows Setup has finished.'
        '@rem Written by scripts/windows/11_cloudbase_init.ps1.'
        'sc.exe config cloudbase-init start= auto'
        'sc.exe start cloudbase-init'
    )
}

# cloudbase-init writes the clone's SSH keys to <home>\.ssh\authorized_keys.
# Windows OpenSSH ignores that file for any member of Administrators - the
# stock sshd_config sends them to administrators_authorized_keys instead - and
# the clone's user is an administrator, so the keys deploy/ passes would never
# work. Commenting the Match block out lets the per-user file apply. sshd is
# not restarted: the change takes effect when a clone first boots.
function Enable-PerUserAuthorizedKey {
    $config = 'C:\ProgramData\ssh\sshd_config'
    if (-not (Test-Path -LiteralPath $config)) {
        throw "$config is missing; OpenSSH Server should have created it at first logon"
    }
    $lines = Get-Content -LiteralPath $config
    $updated = $lines | ForEach-Object {
        if ($_ -match '^\s*Match Group administrators\s*$' -or
            $_ -match '^\s*AuthorizedKeysFile\s+__PROGRAMDATA__/ssh/administrators_authorized_keys\s*$') {
            "#$_"
        } else {
            $_
        }
    }
    if (Compare-Object -ReferenceObject $lines -DifferenceObject $updated) {
        Set-Content -LiteralPath $config -Value $updated -Encoding ascii
        Write-Output "Per-user authorized_keys enabled for administrators in $config"
    }
}

Write-Output "Downloading cloudbase-init $Version"
$installer = Get-VerifiedInstaller
Write-Output "Verified $installer"
try {
    Install-CloudbaseInit -Msi $installer
} finally {
    Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
}
Install-Configuration
Register-ServiceStartAfterSetup
Enable-PerUserAuthorizedKey
Write-Output "cloudbase-init $Version installed and configured"
