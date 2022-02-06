$Host.UI.RawUI.WindowTitle = "PowerShell v$($PSVersionTable.PSVersion) :: Windows PE v$([Environment]::OSVersion.Version)"
Clear-Host

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
trap {
    Write-Output "ERROR: $_"
    Write-Output (($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1')
    Write-Output (($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1')
    while ($true) {
        Start-Sleep -Seconds 3
    }
    Exit 1
}

function Write-Title($title) {
    Write-Output "#`n# $title`n#"
}

# NB this was rendered by http://patorjk.com/software/taag/#p=display&f=Standard&t=Windows%20PE
@'
 __        ___           _                     ____  _____
 \ \      / (_)_ __   __| | _____      _____  |  _ \| ____|
  \ \ /\ / /| | '_ \ / _` |/ _ \ \ /\ / / __| | |_) |  _|
   \ V  V / | | | | | (_| | (_) \ V  V /\__ \ |  __/| |___
    \_/\_/  |_|_| |_|\__,_|\___/ \_/\_/ |___/ |_|   |_____| {0}

'@ -f @((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ReleaseId)

Write-title Firmware
Get-ComputerInfo `
    -Property `
        BiosFirmwareType,
        BiosManufacturer,
        BiosVersion `
    | Format-List

Write-Title SMBIOS
$info = Get-WmiObject Win32_ComputerSystemProduct
New-Object PSObject -Property @{
    DmiSystemVendor = $info.Vendor
    DmiSystemProduct = $info.Name
    DmiSystemVersion = $info.Version
    DmiSystemSerial = $info.IdentifyingNumber
    DmiSystemUuid = $info.UUID
}

Write-Title DISKS
'list disk' | diskpart
Write-Output ''

Write-Title Network
ipconfig

Write-Output 'Mounting Artifacts Drive...'
$artifactsRemoteHost = '10.3.0.2'
$artifactsRemotePath = "\\$artifactsRemoteHost\artifacts"
# NB this uses net.exe because New-SmbMapping is quite unreliable.
$result = net.exe use S: $artifactsRemotePath
if ($result -ne 'The command completed successfully.') {
    throw "net.exe use failed with $result"
}
net use

# see https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-technical-reference
# see https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-command-line-options
Write-Output @'

To install Windows execute one of:

    s:\windows-server-2022.iso\sources\setup.exe /noreboot /unattend:s:\winpe\unattend-bios.xml
    s:\windows-server-2022.iso\sources\setup.exe /noreboot /unattend:s:\winpe\unattend-uefi.xml

Then restart the computer:

    Restart-Computer
'@
