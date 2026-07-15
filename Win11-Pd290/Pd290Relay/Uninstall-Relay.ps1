[CmdletBinding()]
param(
    [switch] $ConfirmUninstall
)

$ErrorActionPreference = 'Stop'
$serviceName = 'PU290WinUsbRelay'
$installDirectory = Join-Path $env:ProgramFiles 'PU290Relay'
$targetExecutable = Join-Path $installDirectory 'PU290Relay.exe'
$dataDirectory = Join-Path $env:ProgramData 'PU290Relay'
$statePath = Join-Path $dataDirectory 'install-state.clixml'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run Windows PowerShell as Administrator.'
}
if (-not $ConfirmUninstall) {
    throw 'Re-run with -ConfirmUninstall to remove the relay service and restore the previous printer port.'
}

$state = if (Test-Path -LiteralPath $statePath) { Import-Clixml -LiteralPath $statePath } else { $null }
if ($state) {
    $printer = Get-Printer -Name $state.PrinterName -ErrorAction SilentlyContinue
    $createdQueueProperty = $state.PSObject.Properties['CreatedQueue']
    if ($printer -and $createdQueueProperty -and [bool]$state.CreatedQueue) {
        foreach ($job in @(Get-PrintJob -PrinterName $state.PrinterName -ErrorAction SilentlyContinue)) {
            Remove-PrintJob -PrinterName $state.PrinterName -ID $job.ID -ErrorAction SilentlyContinue
        }
        Remove-Printer -Name $state.PrinterName -ErrorAction Stop
        Write-Host "Removed installer-created queue '$($state.PrinterName)'."
    } elseif ($printer -and $state.PreviousPort) {
        $previousPort = Get-PrinterPort -Name $state.PreviousPort -ErrorAction SilentlyContinue
        if ($previousPort) {
            Set-Printer -Name $state.PrinterName -PortName $state.PreviousPort
            Write-Host "Restored '$($state.PrinterName)' to '$($state.PreviousPort)'."
        }
    }
}

$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -ne 'Stopped') {
        Stop-Service -Name $serviceName -Force
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
    }
    & sc.exe delete $serviceName | Out-Host
}

if ($state) {
    $relayPort = Get-PrinterPort -Name $state.RelayPort -ErrorAction SilentlyContinue
    $portUsers = @(Get-Printer | Where-Object PortName -eq $state.RelayPort)
    if ($relayPort -and $portUsers.Count -eq 0) {
        Remove-PrinterPort -Name $state.RelayPort
    }
}

if (Test-Path -LiteralPath $targetExecutable -PathType Leaf) {
    Remove-Item -LiteralPath $targetExecutable -Force
}
if (Test-Path -LiteralPath $installDirectory -PathType Container) {
    Remove-Item -LiteralPath $installDirectory -Force -ErrorAction SilentlyContinue
}

Write-Host 'Relay removed. The WinUSB device binding and test certificate were intentionally left in place.'
Write-Host 'Use WinUSB-Relay\Restore-UsbPrint.ps1 and Remove-TestCertificate.ps1 only for a full rollback.'
