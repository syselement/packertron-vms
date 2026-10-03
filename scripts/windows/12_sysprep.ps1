# Last provisioner: check what sysprep depends on, remove what must not reach a
# clone, then generalize. The builder shuts the VM down and converts it once
# this returns.
#
# sysprep runs with /quit rather than /shutdown because proxmox-iso has no
# shutdown_command - it stops the VM itself after the last provisioner. That
# also means a failed generalize is reported here, by name, instead of as a
# build that times out waiting for a shutdown that never comes.
#
# Docs:
#   Sysprep    https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-command-line-options
#   Proxmox    https://pve.proxmox.com/pve-docs/chapter-qm.html (Cloudbase-Init and Sysprep)
#   WINDOWS.md ../../templates/proxmox/WINDOWS.md, the build chain
#
# Run: Packer invokes this; it is not meant to be run by hand.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Unattend = 'C:\Windows\Panther\unattend.xml'
$SysprepDir = Join-Path $env:SystemRoot 'System32\Sysprep'
$SucceededTag = Join-Path $SysprepDir 'Sysprep_succeeded.tag'

function Assert-SysprepInput {
    $required = @(
        $Unattend,
        'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\Scripts\cloudbase-init.exe',
        'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf',
        'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init-unattend.conf',
        (Join-Path $env:SystemRoot 'Setup\Scripts\SetupComplete.cmd')
    )
    foreach ($path in $required) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "$path is missing; sysprep would produce a template whose clones never configure themselves"
        }
    }
}

# Windows 11 only. The package is installed per user but not provisioned for
# all users, which sysprep refuses to generalize past - the Proxmox
# documentation names it specifically.
function Remove-OneDriveSync {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $package = Get-AppxPackage -AllUsers -Name 'Microsoft.OneDriveSync' -ErrorAction SilentlyContinue
    if ($package -and $PSCmdlet.ShouldProcess('Microsoft.OneDriveSync', 'Remove-AppxPackage -AllUsers')) {
        Write-Output 'Removing Microsoft.OneDriveSync, which blocks sysprep'
        $package | Remove-AppxPackage -AllUsers
    }
}

# The answer file's AutoLogon is limited to one logon, after which Windows
# clears it; this makes sure the build password is not left in plain text
# under Winlogon for every clone to inherit.
function Clear-AutoLogon {
    $winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-ItemProperty -Path $winlogon -Name 'AutoAdminLogon' -Value '0'
    Remove-ItemProperty -Path $winlogon -Name 'DefaultPassword' -ErrorAction SilentlyContinue
}

# Fast Startup hibernates the kernel instead of shutting down, and it needs
# hibernation to do it. Left on, the builder's shutdown could leave a kernel
# image the clone resumes from, skipping the specialize pass cloudbase-init
# hangs off. Also drops hiberfil.sys, several GB, from the template.
function Disable-Hibernation {
    & powercfg.exe /hibernate off
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg /hibernate off failed with exit code $LASTEXITCODE"
    }
}

# Backstop for the answer file's PreventDeviceEncryption: sysprep will not
# generalize an encrypted OS volume, and a template must not carry one anyway,
# since every clone would share its keys. Server has no BitLocker cmdlets
# unless the feature is installed, and then nothing can have encrypted it.
function Disable-OsVolumeEncryption {
    if (-not (Get-Command -Name 'Get-BitLockerVolume' -ErrorAction SilentlyContinue)) {
        return
    }
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive
    if ($volume.VolumeStatus -eq 'FullyDecrypted') {
        return
    }

    Write-Output "Decrypting $env:SystemDrive ($($volume.VolumeStatus), $($volume.EncryptionPercentage)%)"
    Disable-BitLocker -MountPoint $env:SystemDrive | Out-Null
    $deadline = (Get-Date).AddMinutes(60)
    while ((Get-BitLockerVolume -MountPoint $env:SystemDrive).VolumeStatus -ne 'FullyDecrypted') {
        if ((Get-Date) -gt $deadline) {
            throw "$env:SystemDrive is still not decrypted after 60 minutes"
        }
        Start-Sleep -Seconds 15
    }
    Write-Output "$env:SystemDrive is decrypted"
}

# Generalizing while servicing still wants a reboot bakes a half-applied update
# into every clone, or reboots the VM under sysprep.
function Assert-NoPendingReboot {
    $pending = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    ) | Where-Object { Test-Path -LiteralPath $_ }
    if ($pending) {
        throw "A reboot is still pending ($($pending -join ', ')); refusing to generalize"
    }
}

function Invoke-Sysprep {
    Remove-Item -LiteralPath $SucceededTag -Force -ErrorAction SilentlyContinue
    Write-Output 'Running sysprep /generalize /oobe'
    $process = Start-Process -FilePath (Join-Path $SysprepDir 'sysprep.exe') -Wait -PassThru -ArgumentList @(
        '/generalize', '/oobe', '/quit', '/quiet', "/unattend:$Unattend"
    )
    # sysprep reports failure through its log, not always its exit code; the
    # tag file is the documented sign it finished.
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $SucceededTag)) {
        $log = Join-Path $SysprepDir 'Panther\setuperr.log'
        if (Test-Path -LiteralPath $log) {
            Write-Output "--- last lines of $log ---"
            Get-Content -LiteralPath $log -Tail 30 | Write-Output
        }
        throw "sysprep did not complete (exit code $($process.ExitCode)); see $log"
    }
}

Assert-SysprepInput
Remove-OneDriveSync
Clear-AutoLogon
Disable-Hibernation
Disable-OsVolumeEncryption
Assert-NoPendingReboot
Invoke-Sysprep
Write-Output 'Generalized; the builder shuts the VM down and converts it next'
