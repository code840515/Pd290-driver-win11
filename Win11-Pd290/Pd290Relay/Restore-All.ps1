[CmdletBinding()]
param(
    [switch] $ConfirmRestoreAll
)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmRestoreAll) {
    throw 'Re-run with -ConfirmRestoreAll to remove the relay, restore usbprint.inf, and remove the Pd290 test certificate.'
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator.'
}

& (Join-Path $PSScriptRoot 'Uninstall-Relay.ps1') -ConfirmUninstall
& (Join-Path (Split-Path $PSScriptRoot -Parent) 'WinUSB-Relay\Restore-UsbPrint.ps1') -ConfirmRestore
& (Join-Path (Split-Path $PSScriptRoot -Parent) 'WinUSB-Relay\Remove-TestCertificate.ps1') -ConfirmCertificateRemoval

Write-Host 'Full rollback completed. Power-cycle the printer and reconnect USB.'
