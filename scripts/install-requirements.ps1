# Report, and optionally install, the Windows host tooling this repository
# needs. Checks by default and changes nothing; installing is an explicit flag.
#
# Windows builds the VMware templates. The repository's own check suite is Bash
# and Linux-only - scripts/check-templates.sh needs cloud-init, which does not
# exist on Windows - so run that side under WSL with
# scripts/install-requirements.sh.
#
# Docs:
#   Packer     https://developer.hashicorp.com/packer/install
#   Vagrant    https://developer.hashicorp.com/vagrant/install
#   WSL        https://learn.microsoft.com/en-us/windows/wsl/install
#   README.md  what the Proxmox and VMware paths each need
#
# Run:
#   powershell -ExecutionPolicy Bypass -File scripts\install-requirements.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\install-requirements.ps1 -Install

[CmdletBinding()]
param(
    # Install what is missing. Without it this script only reports.
    [switch] $Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# id is the winget package identifier; choco is the Chocolatey fallback, used
# only when winget is unavailable.
$Tools = @(
    @{ Name = 'packer';   Command = 'packer';   Id = 'HashiCorp.Packer';  Choco = 'packer'
       Purpose = 'builds and validates every template' }
    @{ Name = 'vagrant';  Command = 'vagrant';  Id = 'HashiCorp.Vagrant'; Choco = 'vagrant'
       Purpose = 'runs the VMware desktop boxes' }
    @{ Name = 'git';      Command = 'git';      Id = 'Git.Git';           Choco = 'git'
       Purpose = 'required by gitleaks and the release workflow' }
    @{ Name = 'gitleaks'; Command = 'gitleaks'; Id = 'Gitleaks.Gitleaks'; Choco = 'gitleaks'
       Purpose = 'scans the tree and history for committed secrets' }
)

function Test-Tool {
    param([string] $Command)
    return [bool] (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Get-ToolVersion {
    param([string] $Command)
    try {
        $output = & $Command --version 2>$null | Select-Object -First 1
        if ($output) { return $output.ToString().Trim() }
    } catch {
        # A tool that refuses --version is still installed; the name is enough.
    }
    return 'installed'
}

function Get-PackageManager {
    if (Test-Tool 'winget') { return 'winget' }
    if (Test-Tool 'choco') { return 'choco' }
    return $null
}

function Install-Tool {
    param([hashtable] $Tool, [string] $Manager)

    Write-Host ("   installing: {0}" -f $Tool.Name)
    $global:LASTEXITCODE = 0
    switch ($Manager) {
        'winget' {
            # --accept-*-agreements keeps it non-interactive; without them
            # winget stops on a prompt no one is there to answer.
            & winget install --exact --id $Tool.Id --silent `
                --accept-package-agreements --accept-source-agreements
        }
        'choco' { & choco install $Tool.Choco --yes --no-progress }
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning ("{0} did not install cleanly (exit {1})" -f $Tool.Name, $LASTEXITCODE)
    }
}

function Show-ManualSteps {
    Write-Host ''
    Write-Host '== manual'

    $vmware = Test-Path 'C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe'
    if (-not $vmware) {
        $vmware = Test-Path 'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
    }
    if ($vmware) {
        Write-Host '   ok      VMware Workstation found'
    } else {
        # Needs a Broadcom account, so it cannot be scripted.
        Write-Host '   MANUAL  VMware Workstation Pro: https://support.broadcom.com/group/ecx/free-downloads'
    }

    $plugin = $false
    if (Test-Tool 'vagrant') {
        # @() so no match gives an empty array rather than $null, whose .Count
        # throws under Set-StrictMode -Version Latest.
        $plugin = @(& vagrant plugin list 2>$null |
            Select-String 'vagrant-vmware-desktop').Count -gt 0
    }
    if ($plugin) {
        Write-Host '   ok      vagrant-vmware-desktop installed'
    } else {
        Write-Host '   MANUAL  vagrant plugin install vagrant-vmware-desktop'
        Write-Host '   MANUAL  Vagrant VMware Utility: https://developer.hashicorp.com/vagrant/docs/providers/vmware/vagrant-vmware-utility'
    }

    if (Test-Tool 'wsl') {
        Write-Host '   ok      WSL present - run scripts/install-requirements.sh inside it'
    } else {
        Write-Host '   MANUAL  wsl --install, then run scripts/install-requirements.sh inside it'
        Write-Host '           The seed and shell checks need cloud-init, shellcheck, shfmt and bats,'
        Write-Host '           none of which run natively on Windows.'
    }
}

$manager = Get-PackageManager

Write-Host 'packertron-vms host requirements (Windows)'

if ($Install) {
    if (-not $manager) {
        throw 'Neither winget nor Chocolatey is available. Install one, or install the tools by hand.'
    }
    Write-Host ''
    Write-Host ("== installing (via {0})" -f $manager)
    foreach ($tool in $Tools) {
        if (-not (Test-Tool $tool.Command)) { Install-Tool -Tool $tool -Manager $manager }
    }
    # winget and choco both extend PATH for new processes only.
    Write-Host ''
    Write-Host 'Open a new terminal so PATH picks up anything just installed.'
}

Write-Host ''
Write-Host '== tools'
$missing = 0
foreach ($tool in $Tools) {
    if (Test-Tool $tool.Command) {
        Write-Host ('   ok      {0,-10} {1}' -f $tool.Name, (Get-ToolVersion $tool.Command))
    } else {
        Write-Host ('   MISSING {0,-10} {1}' -f $tool.Name, $tool.Purpose)
        $missing++
    }
}

Show-ManualSteps

Write-Host ''
if ($missing -gt 0) {
    Write-Host ("{0} tool(s) missing. Install them with:" -f $missing)
    Write-Host '  powershell -ExecutionPolicy Bypass -File scripts\install-requirements.ps1 -Install'
    exit 1
}

Write-Host 'all tooling present'
Write-Host ''
Write-Host 'Next:'
Write-Host '  cd templates\vmware\ubuntu-24.04-desktop'
Write-Host '  packer init . ; packer validate . ; packer build .'
exit 0
