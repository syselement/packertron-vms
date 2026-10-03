# Wait until Windows has finished servicing the updates just installed, then
# report whether it still wants a reboot.
#
# sshd starts while the "Working on updates" screen is still up after a
# restart, so Packer reconnects and moves on while the servicing stack
# (TiWorker) is still applying the update. On Windows 11 25H2
# TrustedInstaller then restarted the VM by itself a minute after boot, two
# seconds into sysprep, which failed with 0x80010108 and dropped the session.
#
# Docs:
#   Updates     https://learn.microsoft.com/en-us/windows/deployment/update/how-windows-update-works
#   WINDOWS.md  ../../templates/proxmox/WINDOWS.md, the build chain
#
# Run: Packer invokes this; it is not meant to be run by hand.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$TimeoutMinutes = 60
# TiWorker can exit and start again between servicing stages, so one idle
# sample is not enough.
$QuietSeconds = 60

function Wait-ServicingIdle {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $quietSince = $null
    while ($true) {
        if (Get-Process -Name 'TiWorker' -ErrorAction SilentlyContinue) {
            $quietSince = $null
        } elseif (-not $quietSince) {
            $quietSince = Get-Date
        } elseif (((Get-Date) - $quietSince).TotalSeconds -ge $QuietSeconds) {
            return
        }
        if ((Get-Date) -gt $deadline) {
            throw "Windows servicing (TiWorker) still busy after $TimeoutMinutes minutes"
        }
        Start-Sleep -Seconds 10
    }
}

Write-Output 'Waiting for Windows servicing to finish'
Wait-ServicingIdle
$pending = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
) | Where-Object { Test-Path -LiteralPath $_ }
if ($pending) {
    Write-Output "Servicing idle; a reboot is pending ($($pending -join ', '))"
} else {
    Write-Output 'Servicing idle; no reboot pending'
}
