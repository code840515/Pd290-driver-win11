[CmdletBinding()]
param(
    [switch] $ConfirmRestore
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator.'
}

if (-not $ConfirmRestore) {
    throw 'Re-run with -ConfirmRestore to remove the experimental WinUSB package and return to usbprint.inf.'
}

$packages = @(Get-WindowsDriver -Online -All |
    Where-Object { (Split-Path -Leaf $_.OriginalFileName) -ieq 'PL2305-WinUSB.inf' })

foreach ($package in $packages) {
    Write-Host "Removing $($package.Driver)..."
    & pnputil.exe /delete-driver $package.Driver /uninstall /force
    if ($LASTEXITCODE -ne 0) {
        throw "PnPUtil failed while removing $($package.Driver); exit code $LASTEXITCODE"
    }
}

& pnputil.exe /scan-devices
Write-Host 'Restore command completed. Unplug USB, power-cycle the printer, and reconnect it.'
Write-Host 'The device should return as Microsoft USB Printing Support using usbprint.inf.'
