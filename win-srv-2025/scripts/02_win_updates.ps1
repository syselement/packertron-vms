# Install Windows Updates using PSWindowsUpdate module and a scheduled task.
# Adapted from various sources listed below.
#
# Source: https://github.com/hashicorp/best-practices/blob/master/packer/scripts/windows/install_windows_updates.ps1 - deprecated repo
# Source: https://github.com/eaksel/packer-Win2022/blob/main/scripts/win-update.ps1
#

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
    $updateCommand = {Import-Module PSWindowsUpdate; Get-WUInstall -AcceptAll -Install -IgnoreReboot | Out-File C:\Windows\Temp\PSWindowsUpdate.log}
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
    $Action.Arguments = "-Command $updateCommand"

    $Task.Principal.RunLevel = 1

    $Scheduler.Connect()
    $RootFolder = $Scheduler.GetFolder("\")
    $RootFolder.RegisterTaskDefinition($TaskName, $Task, 6, "SYSTEM", $Null, 1) | Out-Null
    $RootFolder.GetTask($TaskName).Run(0) | Out-Null

    Write-Output "***** The Windows Update log will be displayed below this message. No additional output indicates no updates were needed."
    do {
        sleep 1
        if ((Test-Path C:\Windows\Temp\PSWindowsUpdate.log) -and $null -eq $script:reader) {
            $script:stream = New-Object System.IO.FileStream -ArgumentList "C:\Windows\Temp\PSWindowsUpdate.log", "Open", "Read", "ReadWrite"
            $script:reader = New-Object System.IO.StreamReader $stream
        }
        if ($null -ne $script:reader) {
            while ($null -ne ($line = $script:reader.ReadLine())) {
                Write-Output $line
            }
        }
    } while ($Scheduler.GetRunningTasks(0) | Where-Object {$_.Name -eq $TaskName})
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
