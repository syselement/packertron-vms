# Define the registry path
# Run only when sysprep has completed successfully
$regPath = "HKLM:\SYSTEM\Setup\Status\SysprepStatus"

# Remove the startup.cmd file 
$filePath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\startup.cmd"

# Query the CleanupState and GeneralizationState from the registry
$cleanupState = Get-ItemProperty -Path $regPath -Name CleanupState | Select-Object -ExpandProperty CleanupState
$generalizationState = Get-ItemProperty -Path $regPath -Name GeneralizationState | Select-Object -ExpandProperty GeneralizationState

# Check if CleanupState is 2 and GeneralizationState is 7
if ($cleanupState -eq 2 -and $generalizationState -eq 7) {
   Write-Host "CleanupState is 2 and GeneralizationState is 7. Running commands..."

   # Enabling a few other options via registry settings.
   if (!(Test-Path -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced")) {
      New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "Advanced"
   }

   # Setting view options
   Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" 1
   Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0
   Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideDrivesWithNoMedia" 0
   Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" 0

   # Setting default explorer view to This PC
   Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" 1

   # Setting Dark theme
   Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "AppsUseLightTheme" 0
   Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "SystemUsesLightTheme" 0

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

   Write-Host "Commands executed successfully."
}
else {
   Write-Host "Conditions not met. CleanupState: $cleanupState, GeneralizationState: $generalizationState"
}

# Verify if the firewall rule was added and enabled. If it has, there's no need to keep the startup.cmd file or this one.
$firewallRuleName = "Allow SSH"
$ruleExists = Get-NetFirewallRule -DisplayName $firewallRuleName

if ($ruleExists) {
   #Check action
   if ($ruleExists.Action -eq 'Allow') {
      write-host "Firewall rule '$firewallRuleName' exists and is set to allow"
      remove-item $filePath
      remove-item "C:\tmp\startup.ps1"
   }
   else {
      write-host "Firewall rule '$firewallRuleName' exists but is not set to Allow."
   }
}
else {
   write-host "Firewall rule '$firewallRuleName' does not exist. "
}