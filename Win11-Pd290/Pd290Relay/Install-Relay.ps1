[CmdletBinding()]
param(
    [string] $PrinterName = 'Pd290-Win11',
    [string] $PortName = (Join-Path $env:ProgramData 'PU290Relay\spool\PU290.prn'),
    [switch] $RecreateQueue,
    [switch] $ConfirmInstall
)

$ErrorActionPreference = 'Stop'
$serviceName = 'PU290WinUsbRelay'
$installDirectory = Join-Path $env:ProgramFiles 'PU290Relay'
$targetExecutable = Join-Path $installDirectory 'PU290Relay.exe'
$sourceExecutable = Join-Path $PSScriptRoot 'Pd290Relay.exe'
$dataDirectory = Join-Path $env:ProgramData 'PU290Relay'
$statePath = Join-Path $dataDirectory 'install-state.clixml'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run Windows PowerShell as Administrator.'
    }
}

Assert-Administrator
if (-not $ConfirmInstall) {
    throw 'Re-run with -ConfirmInstall to install the relay service and change the printer port.'
}
if (-not (Test-Path -LiteralPath $sourceExecutable -PathType Leaf)) {
    throw "Relay executable not found: $sourceExecutable. Run Build-Relay.ps1 first."
}

$catalog = Join-Path (Split-Path $PSScriptRoot -Parent) 'WinUSB-Relay\PL2305-WinUSB.cat'
$signature = Get-AuthenticodeSignature -LiteralPath $catalog
if ($signature.Status -ne 'Valid') {
    throw "The PL2305 WinUSB catalog is not trusted: $($signature.Status)"
}

$winUsbDevice = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like 'USB\VID_067B&PID_2305\*' -and $_.Class -eq 'USBDevice' } |
    Select-Object -First 1
if (-not $winUsbDevice) {
    throw 'The PL2305 is not connected or is not using the signed WinUSB binding.'
}

$printer = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
if (-not $printer) {
    $matches = @(Get-Printer | Where-Object Name -Like '*Pd290*')
    if ($matches.Count -ne 1) { throw "Printer not found: $PrinterName" }
    $printer = $matches[0]
    $PrinterName = $printer.Name
}
$driverName = $printer.DriverName
$wasDefault = [bool](Get-CimInstance Win32_Printer | Where-Object Name -eq $PrinterName | Select-Object -ExpandProperty Default -First 1)

foreach ($job in @(Get-PrintJob -PrinterName $PrinterName -ErrorAction SilentlyContinue)) {
    Remove-PrintJob -PrinterName $PrinterName -ID $job.ID -ErrorAction Stop
}

New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $PortName -Parent) -Force | Out-Null
Remove-Item -LiteralPath $PortName -Force -ErrorAction SilentlyContinue
$existingState = if (Test-Path -LiteralPath $statePath) { Import-Clixml -LiteralPath $statePath } else { $null }
$previousPort = if ($existingState -and $existingState.PrinterName -eq $PrinterName) {
    $existingState.PreviousPort
} else {
    $printer.PortName
}
[pscustomobject]@{
    InstalledAt  = Get-Date
    PrinterName  = $PrinterName
    PreviousPort = $previousPort
    RelayPort    = $PortName
    Recreated    = [bool]$RecreateQueue
} | Export-Clixml -LiteralPath $statePath -Force

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
    }
    & sc.exe delete $serviceName | Out-Host
    $deadline = (Get-Date).AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 300
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    } while ($service -and (Get-Date) -lt $deadline)
    if ($service) { throw "Timed out deleting existing service: $serviceName" }
}

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourceExecutable -Destination $targetExecutable -Force
New-Service -Name $serviceName -BinaryPathName ('"{0}"' -f $targetExecutable) `
    -DisplayName 'Pd290 PL2305 WinUSB Print Relay' -StartupType Automatic `
    -Description 'Watches a local print file and relays completed jobs to the Pd290 PL2305 WinUSB Bulk OUT endpoint.' | Out-Null
& sc.exe failure $serviceName reset= 86400 actions= restart/5000/restart/15000/restart/60000 | Out-Host
Start-Service -Name $serviceName
(Get-Service -Name $serviceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
Start-Sleep -Seconds 2

if (-not (Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue)) {
    Add-PrinterPort -Name $PortName -ErrorAction Stop
}

if ($RecreateQueue) {
    Remove-Printer -Name $PrinterName -ErrorAction Stop
    Add-Printer -Name $PrinterName -DriverName $driverName -PortName $PortName -ErrorAction Stop
    if ($wasDefault) { (New-Object -ComObject WScript.Network).SetDefaultPrinter($PrinterName) }
}
else {
    Set-Printer -Name $PrinterName -PortName $PortName -ErrorAction Stop
}

Write-Host 'Pd290 file relay installation completed.'
[pscustomobject]@{
    Service      = (Get-Service -Name $serviceName).Status
    Printer      = (Get-Printer -Name $PrinterName).Name
    PreviousPort = $previousPort
    CurrentPort  = (Get-Printer -Name $PrinterName).PortName
    SpoolFile    = $PortName
    Log          = Join-Path $dataDirectory 'relay.log'
} | Format-List