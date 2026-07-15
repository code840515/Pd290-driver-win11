[CmdletBinding()]
param(
    [string] $PrinterName = 'Pd290-Win11',
    [switch] $SetDefaultPrinter,
    [switch] $PrintTestPage,
    [switch] $ConfirmAllChanges
)

$ErrorActionPreference = 'Stop'
$driverName = 'Pd290-Win11'
$driverVersion = [version]'2.0.0.2'
$serviceName = 'PU290WinUsbRelay'
$spoolFile = Join-Path $env:ProgramData 'PU290Relay\spool\PU290.prn'
$dataDirectory = Join-Path $env:ProgramData 'PU290Relay'
$statePath = Join-Path $dataDirectory 'install-state.clixml'
$serviceDirectory = Join-Path $env:ProgramFiles 'PU290Relay'
$serviceExecutable = Join-Path $serviceDirectory 'PU290Relay.exe'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run Windows PowerShell as Administrator.'
    }
}

Assert-Administrator
if (-not $ConfirmAllChanges) {
    throw 'Re-run with -ConfirmAllChanges to trust the test certificate, install both driver packages, replace the matching printer queue, and install the relay service.'
}

$required = @(
    (Join-Path $PSScriptRoot 'WinUSB-Relay\Pd290-WinUSB-Test.cer'),
    (Join-Path $PSScriptRoot 'WinUSB-Relay\PL2305-WinUSB.inf'),
    (Join-Path $PSScriptRoot 'WinUSB-Relay\PL2305-WinUSB.cat'),
    (Join-Path $PSScriptRoot 'Printer-Driver\Pd290.inf'),
    (Join-Path $PSScriptRoot 'Printer-Driver\Pd290.cat'),
    (Join-Path $PSScriptRoot 'Pd290Relay\Pd290Relay.exe')
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file is missing: $path" }
}

$device = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object InstanceId -Like 'USB\VID_067B&PID_2305\*' |
    Select-Object -First 1
if (-not $device) {
    throw 'PL2305 was not detected. Power on the Pd290 and reconnect its USB cable.'
}

& (Join-Path $PSScriptRoot 'Trust-Pd290-Certificate.ps1') -ConfirmCertificateTrust

foreach ($catalog in @(
    (Join-Path $PSScriptRoot 'WinUSB-Relay\PL2305-WinUSB.cat'),
    (Join-Path $PSScriptRoot 'Printer-Driver\Pd290.cat')
)) {
    $signature = Get-AuthenticodeSignature -LiteralPath $catalog
    if ($signature.Status -ne 'Valid') {
        throw "Catalog is not trusted: $catalog - $($signature.Status)"
    }
}

$printerInf = Join-Path $PSScriptRoot 'Printer-Driver\Pd290.inf'
& pnputil.exe /add-driver $printerInf
if ($LASTEXITCODE -ne 0) { throw "PnPUtil could not stage the Pd290 driver: $LASTEXITCODE" }

$package = Get-WindowsDriver -Online -All |
    Where-Object {
        (Split-Path -Leaf $_.OriginalFileName) -ieq 'Pd290.inf' -and
        [version]$_.Version -eq $driverVersion
    } |
    Select-Object -First 1
if (-not $package) { throw 'The staged Pd290-Win11 2.0.0.2 package was not found.' }
$publishedInf = Join-Path $env:WINDIR "INF\$($package.Driver)"

$existingQueue = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
$createdQueue = -not [bool]$existingQueue
$previousPort = if ($existingQueue) { $existingQueue.PortName } else { $null }
$wasDefault = if ($existingQueue) {
    [bool](Get-CimInstance Win32_Printer | Where-Object Name -eq $PrinterName | Select-Object -ExpandProperty Default -First 1)
} else { $false }

if ($existingQueue) {
    foreach ($job in @(Get-PrintJob -PrinterName $PrinterName -ErrorAction SilentlyContinue)) {
        Remove-PrintJob -PrinterName $PrinterName -ID $job.ID -ErrorAction Stop
    }
    Remove-Printer -Name $PrinterName -ErrorAction Stop
}

$registeredDriver = Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue
if ($registeredDriver) {
    $driverKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers\Version-3\$driverName"
    $installedVersion = if (Test-Path $driverKey) { [version](Get-ItemProperty $driverKey).DriverVersion } else { [version]'0.0.0.0' }
    if ($installedVersion -ne $driverVersion) {
        $otherQueues = @(Get-Printer | Where-Object DriverName -eq $driverName)
        if ($otherQueues.Count) { throw 'Another queue still uses an older Pd290 driver; remove that queue before deployment.' }
        Remove-PrinterDriver -Name $driverName -RemoveFromDriverStore -ErrorAction Stop
        $registeredDriver = $null
    }
}
if (-not $registeredDriver) {
    Add-PrinterDriver -Name $driverName -InfPath $publishedInf -ErrorAction Stop
}

& (Join-Path $PSScriptRoot 'WinUSB-Relay\Install-WinUsbBinding.ps1') -ConfirmBindingChange

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
    }
    & sc.exe delete $serviceName | Out-Host
    $deadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 500
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    } while ($service -and (Get-Date) -lt $deadline)
    if ($service) { throw "Windows did not finish deleting service '$serviceName'. Restart Windows and run the installer again." }
}

New-Item -ItemType Directory -Path $serviceDirectory -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path $spoolFile -Parent) -Force | Out-Null
Remove-Item -LiteralPath $spoolFile -Force -ErrorAction SilentlyContinue
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Pd290Relay\Pd290Relay.exe') -Destination $serviceExecutable -Force
New-Service -Name $serviceName -BinaryPathName ('"{0}"' -f $serviceExecutable) `
    -DisplayName 'Pd290 PL2305 WinUSB Print Relay' -StartupType Automatic `
    -Description 'Watches a local print file and relays completed jobs to the Pd290 PL2305 WinUSB Bulk OUT endpoint.' | Out-Null
& sc.exe failure $serviceName reset= 86400 actions= restart/5000/restart/15000/restart/60000 | Out-Host
Start-Service -Name $serviceName
(Get-Service -Name $serviceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))

if (-not (Get-PrinterPort -Name $spoolFile -ErrorAction SilentlyContinue)) {
    Add-PrinterPort -Name $spoolFile -ErrorAction Stop
}
Add-Printer -Name $PrinterName -DriverName $driverName -PortName $spoolFile -ErrorAction Stop
if ($SetDefaultPrinter -or $wasDefault) {
    (New-Object -ComObject WScript.Network).SetDefaultPrinter($PrinterName)
}

New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
[pscustomobject]@{
    InstalledAt  = Get-Date
    PrinterName  = $PrinterName
    PreviousPort = $previousPort
    RelayPort    = $spoolFile
    CreatedQueue = $createdQueue
} | Export-Clixml -LiteralPath $statePath -Force

if ($PrintTestPage) {
    & rundll32.exe printui.dll,PrintUIEntry /k /n "$PrinterName"
    Start-Sleep -Seconds 15
}

$driverRegistry = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Environments\Windows x64\Drivers\Version-3\$driverName"
$isolationEnabled = (([int]$driverRegistry.PrinterDriverAttributes -band 4) -ne 0)
if ([version]$driverRegistry.DriverVersion -ne $driverVersion) {
    throw "Unexpected printer driver version: $($driverRegistry.DriverVersion)"
}
if ($isolationEnabled) {
    throw 'The Pd290 driver is still configured for Driver Isolation. The Win11 fix was not applied.'
}
[pscustomobject]@{
    Printer          = (Get-Printer -Name $PrinterName).Name
    Port             = (Get-Printer -Name $PrinterName).PortName
    PrinterDriver    = $driverRegistry.DriverVersion
    IsolationMode    = if ($isolationEnabled) { 2 } else { 0 }
    WinUsbDevice     = (Get-PnpDevice -PresentOnly | Where-Object InstanceId -Like 'USB\VID_067B&PID_2305\*' | Select-Object -First 1).FriendlyName
    RelayService     = (Get-Service $serviceName).Status
    RemainingJobs    = @(Get-PrintJob -PrinterName $PrinterName -ErrorAction SilentlyContinue).Count
    RelayLog         = Join-Path $dataDirectory 'relay.log'
} | Format-List
