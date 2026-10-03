# First-boot check: confirm sysprep completed, then remove the startup shortcut so this runs once and never again.
# Staged into the image by the win-srv-2025 Packer build.
#
# Docs:
#   Sysprep state  https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep-process-overview
#   PowerShell     https://learn.microsoft.com/en-us/powershell/
#
# Run: launched by 04_startup.cmd from the Startup folder on first boot.

# Define the registry path
# Run only when sysprep has completed successfully
$regPath = "HKLM:\SYSTEM\Setup\Status\SysprepStatus"

# Verify the startup.cmd file after successful execution
$filePath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\startup.cmd"

# Query the CleanupState and GeneralizationState from the registry to determine if sysprep has completed
$cleanupState = Get-ItemProperty -Path $regPath -Name CleanupState | Select-Object -ExpandProperty CleanupState
$generalizationState = Get-ItemProperty -Path $regPath -Name GeneralizationState | Select-Object -ExpandProperty GeneralizationState

# Check if CleanupState is 2 and GeneralizationState is 7
if ($cleanupState -eq 2 -and $generalizationState -eq 7) {
   Write-Output "CleanupState is 2 and GeneralizationState is 7. Running commands..."

   # Enabling a few other options via registry settings.
   if (!(Test-Path -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
      New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "Advanced"
   }

   # Setting view options
   Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1
   Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0
   Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideDrivesWithNoMedia" -Value 0
   Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSyncProviderNotifications" -Value 0

   # Setting default explorer view to This PC
   Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1

   # Setting Dark theme
   Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0
   Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0

   # Hide Edge first run experience
   if (!(Test-Path "HKLM:\Software\Policies\Microsoft\Edge")) {
      New-Item -Path "HKLM:\Software\Policies\Microsoft\" -Name "Edge" -Force
   }
   New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HideFirstRunExperience" -Value 1 -PropertyType DWORD -Force

   # Configure basic telemetry settings
   if (!(Test-Path "HKLM:\Software\Policies\Microsoft\Windows\DataCollection")) {
      New-Item -Path "HKLM:\Software\Policies\Microsoft\Windows" -Name "DataCollection" -Force
   }
   New-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -PropertyType DWORD -Force

   # Disable password expiration for Administrator.  CAUTION: Typically, you'll override this setting with a group policy once the machine is added to a domain.
   Set-LocalUser Administrator -PasswordNeverExpires $true

   # Set to the highperformance profile
   powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

   # Enable SSH rule in the firewall
   netsh advfirewall firewall set rule name="Allow SSH" new action=allow

   Write-Output "Commands executed successfully."
}
else {
   Write-Output "Conditions not met. CleanupState: $cleanupState, GeneralizationState: $generalizationState"
}

# Verify if the firewall rule was added and enabled. If it has, there's no need to keep the startup.cmd file or this one.
$firewallRuleName = "Allow SSH"
$ruleExists = Get-NetFirewallRule -DisplayName $firewallRuleName

if ($ruleExists) {
   #Check action
   if ($ruleExists.Action -eq 'Allow') {
      Write-Output "Firewall rule '$firewallRuleName' exists and is set to allow"
      Remove-Item -Path $filePath
      Remove-Item -Path "C:\tmp\startup.ps1"
   }
   else {
      Write-Output "Firewall rule '$firewallRuleName' exists but is not set to Allow."
   }
}
else {
   Write-Output "Firewall rule '$firewallRuleName' does not exist. "
}