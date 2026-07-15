[CmdletBinding()]
param(
    [switch] $ConfirmBindingChange
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator.'
}

if (-not $ConfirmBindingChange) {
    throw 'Re-run with -ConfirmBindingChange to replace USB Printing Support for VID_067B/PID_2305.'
}

$inf = Join-Path $PSScriptRoot 'PL2305-WinUSB.inf'
$catalog = Join-Path $PSScriptRoot 'PL2305-WinUSB.cat'
foreach ($path in $inf, $catalog) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required package file is missing: $path"
    }
}

$signature = Get-AuthenticodeSignature -LiteralPath $catalog
if ($signature.Status -ne 'Valid') {
    throw "Catalog signature is not trusted: $($signature.Status) - $($signature.StatusMessage)"
}

$devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object InstanceId -Like 'USB\VID_067B&PID_2305\*')
if ($devices.Count -eq 0) {
    throw 'PL2305 is not currently connected. Power on the printer and connect its USB cable.'
}

$backup = Join-Path $PSScriptRoot 'binding-before-winusb.txt'
@(
    "Captured: $(Get-Date -Format o)"
    $devices | Format-List Status, Class, FriendlyName, InstanceId | Out-String
    Get-CimInstance Win32_PnPSignedDriver |
        Where-Object DeviceID -Like 'USB\VID_067B&PID_2305\*' |
        Format-List DeviceName, DeviceID, DriverProviderName, InfName, DriverVersion |
        Out-String
) | Set-Content -LiteralPath $backup -Encoding UTF8

Write-Host 'Staging and installing the exact-match WinUSB binding...'
& pnputil.exe /add-driver $inf /install
if ($LASTEXITCODE -ne 0) {
    throw "PnPUtil failed with exit code $LASTEXITCODE"
}

& pnputil.exe /scan-devices
Start-Sleep -Seconds 2

Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object InstanceId -Like 'USB\VID_067B&PID_2305\*' |
    Format-List Status, Class, FriendlyName, InstanceId

Write-Host 'Binding command completed. If the device name did not change, unplug and reconnect USB once.'
