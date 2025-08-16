   # Install Chocolatey and some custom utilities using Choco

   Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Installing Chocolatey"
   Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
   
   Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Installing utilities..."
   choco install -y --limit-output --no-progress 7zip firefox notepadplusplus.install powershell-core sublimetext4

   Write-Host "$('[{0:HH:mm}]' -f (Get-Date)) Utilities installation complete!"