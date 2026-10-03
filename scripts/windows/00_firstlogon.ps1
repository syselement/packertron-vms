# Bring a fresh Windows install to the point Packer can reach it: the full
# virtio-win guest tools, which carry the QEMU guest agent (how the Proxmox
# builder learns the VM's address), RDP, and OpenSSH Server (the communicator).
# Runs once, at the first autologon.
#
# The guest tools have to install here, before sshd exists. They reinstall the
# NetKVM driver, which resets the NIC: run from a provisioner, that reset cuts
# Packer's SSH session and the build fails with exit status 2300218.
#
# Its failures are invisible to Packer, which only sees SSH never answer. The
# transcript below is the place to look, from the Proxmox console.
#
# Docs:
#   OpenSSH for Windows  https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse
#   virtio-win           https://github.com/virtio-win/virtio-win-pkg-scripts/blob/master/README.md
#   Source               https://gitlab.com/badsectorlabs/ludus/-/blob/main/ludus-server/packer/scripts/install-virtio-drivers.ps1
#   WINDOWS.md           ../../templates/proxmox/WINDOWS.md, the build chain
#
# Run: the answer file's FirstLogonCommands runs this from the answer-file CD;
# it is not meant to be run by hand.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$LogPath = 'C:\Windows\Temp\packertron-firstlogon.log'

# The CD letters depend on how many optical drives the builder attached and
# in what order, so find the virtio CD by what is on it.
function Find-VirtioMedia {
    $drive = Get-PSDrive -PSProvider FileSystem |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.Root 'virtio-win-guest-tools.exe') } |
        Select-Object -First 1
    if (-not $drive) {
        throw 'virtio-win CD not found: no drive carries virtio-win-guest-tools.exe'
    }
    return $drive.Root
}

# The virtio-win folder name for this Windows. Only the editions these
# templates build are mapped; anything else fails rather than guessing.
function Get-VirtioOsFolder {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    # ProductType 1 is a workstation; 2 and 3 are domain controller and server.
    # Windows 11 starts at build 22000, so it has to be tested before 10.
    if ($os.ProductType -eq 1 -and [int]$os.BuildNumber -ge 22000) { return 'w11' }
    if ($os.ProductType -eq 1 -and [int]$os.BuildNumber -ge 10240) { return 'w10' }
    if ($os.ProductType -ne 1 -and [int]$os.BuildNumber -ge 26100) { return '2k25' }
    throw "No virtio-win folder mapped for '$($os.Caption)' build $($os.BuildNumber)"
}

# Trust each driver's signer before installing. Without it a driver from a
# publisher Windows has not seen raises a trust prompt that nobody is there to
# click, and the silent install stalls on it.
function Add-DriverSignersToTrustedPublisher {
    param([string]$VirtioRoot, [string]$OsFolder)

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('TrustedPublisher', 'LocalMachine')
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    try {
        Get-ChildItem -Path (Join-Path $VirtioRoot "*\$OsFolder\amd64") -Filter '*.cat' -Recurse |
            ForEach-Object {
                $signer = (Get-AuthenticodeSignature -FilePath $_.FullName).SignerCertificate
                if ($signer) {
                    $store.Add($signer)
                    Write-Output "Trusted $($signer.Subject) from $($_.Name)"
                }
            }
    } finally {
        $store.Close()
    }
}

function Install-VirtioGuestTool {
    param([string]$VirtioRoot)

    $installer = Join-Path $VirtioRoot 'virtio-win-guest-tools.exe'
    Write-Output "Installing $installer"
    $process = Start-Process -FilePath $installer -Wait -PassThru `
        -ArgumentList '/install', '/quiet', '/norestart', '/log', 'C:\Windows\Temp\virtio-guest-tools.log'
    # 3010: installed, reboot required - the windows-update provisioner's
    # restarts take care of that.
    if ($process.ExitCode -notin 0, 3010) {
        throw "virtio-win-guest-tools failed with exit code $($process.ExitCode); see C:\Windows\Temp\virtio-guest-tools*.log"
    }
    Set-Service -Name 'QEMU-GA' -StartupType Automatic
    Start-Service -Name 'QEMU-GA'
}

# The NetKVM reinstall above resets the NIC, and the OpenSSH download below
# needs it back with an address.
function Wait-Network {
    $deadline = (Get-Date).AddMinutes(3)
    while (-not (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)) {
        if ((Get-Date) -gt $deadline) {
            throw 'No IPv4 default route 3 minutes after the guest tools install'
        }
        Start-Sleep -Seconds 5
    }
}

function Enable-RemoteDesktop {
    Write-Output 'Enabling RDP'
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
}

# Last on purpose: Packer connects the moment port 22 answers, so everything
# above has to be finished by then.
function Enable-OpenSshServer {
    # Windows 11 downloads the capability from Windows Update, so this is the
    # step that needs the network. Server 2025 ships it and skips the install.
    $capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
    if ($capability.State -ne 'Installed') {
        Write-Output 'Installing the OpenSSH Server capability'
        Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
    }

    # The capability creates this rule on Windows 11; Server 2025 may not.
    if (-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
            -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow | Out-Null
    }
    # A new network is Public until someone says otherwise.
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Any

    Set-Service -Name 'sshd' -StartupType Automatic
    Start-Service -Name 'sshd'
    Write-Output 'OpenSSH Server is running'
}

Start-Transcript -Path $LogPath -Append | Out-Null
try {
    # Stops the "allow this PC to be discoverable" flyout on the console.
    New-Item -Path 'HKLM:\System\CurrentControlSet\Control\Network\NewNetworkWindowOff' -Force | Out-Null

    $virtioRoot = Find-VirtioMedia
    Add-DriverSignersToTrustedPublisher -VirtioRoot $virtioRoot -OsFolder (Get-VirtioOsFolder)
    Install-VirtioGuestTool -VirtioRoot $virtioRoot
    Wait-Network
    Enable-RemoteDesktop
    Enable-OpenSshServer
    Write-Output 'First logon complete'
} catch {
    Write-Output "ERROR: $_"
    exit 1
} finally {
    Stop-Transcript | Out-Null
}
