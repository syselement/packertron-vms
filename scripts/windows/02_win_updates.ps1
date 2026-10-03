# Install Windows Updates via the PSWindowsUpdate module, driven by a scheduled task so the run survives the reboots it triggers.
# Run by the win-srv-2025 Packer build as a provisioner, twice.
#
# Docs:
#   PSWindowsUpdate  https://www.powershellgallery.com/packages/PSWindowsUpdate
#   Source           https://github.com/eaksel/packer-Win2022/blob/main/scripts/win-update.ps1
#                    https://github.com/hashicorp/best-practices/blob/master/packer/scripts/windows/install_windows_updates.ps1 (deprecated)
#
# Run: Packer invokes this; it is not meant to be run by hand.

# Silence progress bars in PowerShell, which can sometimes feed back strange XML data to the Packer output.
$ProgressPreference = "SilentlyContinue"

Write-Output "***** Starting PSWindowsUpdate Installation"

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -ErrorAction Stop
try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
} catch {
    Write-Output "***** Unable to set PSGallery as Trusted; continuing"
}
Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -ErrorAction Stop

if (Get-ChildItem "C:\Program Files\WindowsPowerShell\Modules\PSWindowsUpdate") {
    Write-Output "***** PSWindowsUpdate installed successfully"
}

Write-Output "***** Starting Windows Update Installation"

Try
{
    Import-Module PSWindowsUpdate -ErrorAction Stop
}
Catch
{
    Write-Error "***** Unable to Import PSWindowsUpdate"
    exit 1
}

if (Test-Path C:\Windows\Temp\PSWindowsUpdate.log) {
    Remove-Item -Path C:\Windows\Temp\PSWindowsUpdate.log
}

try {
    # *>&1 sends errors into the log too, so a failure prints its reason
    # below rather than only a task result code.
    $updateCommand = {& { Import-Module PSWindowsUpdate -ErrorAction Stop; Get-WUInstall -AcceptAll -Install -IgnoreReboot } *>&1 | Out-File C:\Windows\Temp\PSWindowsUpdate.log}
    $TaskName = "PackerUpdate"

    $User = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Scheduler = New-Object -ComObject Schedule.Service

    $Task = $Scheduler.NewTask(0)

    $RegistrationInfo = $Task.RegistrationInfo
    $RegistrationInfo.Description = $TaskName
    $RegistrationInfo.Author = $User.Name

    $Settings = $Task.Settings
    $Settings.Enabled = $True
    $Settings.StartWhenAvailable = $True
    $Settings.Hidden = $False

    $Action = $Task.Actions.Create(0)
    $Action.Path = "powershell"
    # Packer's own session runs with -ExecutionPolicy Bypass, but this task
    # starts a fresh powershell. Client Windows defaults to Restricted, which
    # refuses to load PSWindowsUpdate, so without this the task exits 1 before
    # it writes anything; Server's RemoteSigned default hid that. Scoped to
    # this one process, as Packer's is.
    $Action.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command $updateCommand"

    $Task.Principal.RunLevel = 1

    $Scheduler.Connect()
    $RootFolder = $Scheduler.GetFolder("\")
    $RootFolder.RegisterTaskDefinition($TaskName, $Task, 6, "SYSTEM", $Null, 1) | Out-Null
    $started = Get-Date
    $RootFolder.GetTask($TaskName).Run(0) | Out-Null

    Write-Output "***** The Windows Update log will be displayed below this message. No additional output indicates no updates were needed."
    # A task that was just started is queued before it runs, and neither
    # state is "has run". Waiting only while GetRunningTasks lists it can end
    # before the task starts; the task is then deleted and the restart that
    # follows kills the update. So wait until it has run since $started and is
    # no longer queued (2) or running (4).
    do {
        Start-Sleep -Seconds 5
        if ((Test-Path C:\Windows\Temp\PSWindowsUpdate.log) -and $null -eq $script:reader) {
            $script:stream = New-Object System.IO.FileStream -ArgumentList "C:\Windows\Temp\PSWindowsUpdate.log", "Open", "Read", "ReadWrite"
            $script:reader = New-Object System.IO.StreamReader $stream
        }
        if ($null -ne $script:reader) {
            while ($null -ne ($line = $script:reader.ReadLine())) {
                Write-Output $line
            }
        }
        $current = $RootFolder.GetTask($TaskName)
        $hasRun = $current.LastRunTime -ge $started.AddSeconds(-1)
        if (-not $hasRun -and $current.State -notin 2, 4 -and (Get-Date) -gt $started.AddMinutes(5)) {
            Write-Output "***** WARNING: the update task had not started after 5 minutes"
            break
        }
    } while ($current.State -in 2, 4 -or -not $hasRun)

    # The last lines can land after the final read inside the loop.
    if ($null -ne $script:reader) {
        while ($null -ne ($line = $script:reader.ReadLine())) {
            Write-Output $line
        }
    }

    # Without this a task that failed before writing its log looks exactly like
    # "no updates needed". Reported, not fatal: a build should not fail on a
    # Windows Update outage.
    $lastResult = $RootFolder.GetTask($TaskName).LastTaskResult
    if (-not (Test-Path C:\Windows\Temp\PSWindowsUpdate.log)) {
        Write-Output ("***** WARNING: the update task wrote no log (task result 0x{0:X8})" -f $lastResult)
    } elseif ($lastResult -ne 0) {
        Write-Output ("***** WARNING: the update task ended with result 0x{0:X8}" -f $lastResult)
    }
    # PSWindowsUpdate reports a failed download or install as a row, not an
    # error, so the task still succeeds; without this an unpatched image passes.
    $failed = @(Select-String -LiteralPath C:\Windows\Temp\PSWindowsUpdate.log -Pattern '\sFailed\s' -ErrorAction SilentlyContinue)
    if ($failed.Count) {
        Write-Output "***** WARNING: $($failed.Count) update(s) failed:"
        $failed | ForEach-Object { Write-Output "*****   $($_.Line.Trim())" }
    }
} finally {
    if ($null -ne $RootFolder) {
        $RootFolder.DeleteTask($TaskName,0)
    }
    if ($null -ne $Scheduler) {
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($Scheduler) | Out-Null
    }
    if ($null -ne $script:reader) {
        $script:reader.Close()
        $script:stream.Dispose()
    }
}
Write-Output "***** Ended Windows Update Installation"
