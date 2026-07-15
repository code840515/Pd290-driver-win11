[CmdletBinding()]
param(
    [string] $PortName,
    [string] $Text = 'PL2305 DIRECT TEST'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw '請以系統管理員身分開啟 Windows PowerShell，再執行本腳本。'
}

$portRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\USB Monitor\Ports'
$ports = Get-ChildItem -LiteralPath $portRoot -ErrorAction Stop | ForEach-Object {
    $properties = Get-ItemProperty -LiteralPath $_.PSPath
    [pscustomobject]@{
        Name       = $_.PSChildName
        DeviceId   = $properties.'Device Id'
        DevicePath = $properties.'Device Path'
    }
} | Where-Object { $_.DeviceId -match 'VID_067B&PID_2305' }

if ($PortName) {
    $port = $ports | Where-Object Name -eq $PortName | Select-Object -First 1
}
else {
    $port = $ports | Sort-Object Name -Descending | Select-Object -First 1
}

if (-not $port) {
    throw '找不到連接中的 PL2305（VID_067B/PID_2305）USB 列印連接埠。'
}

$source = @'
using System;
using System.Runtime.InteropServices;

public static class UsbPrinterNative
{
    public static readonly IntPtr InvalidHandleValue = new IntPtr(-1);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateFile(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool WriteFile(
        IntPtr handle,
        byte[] buffer,
        uint bytesToWrite,
        out uint bytesWritten,
        IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool FlushFileBuffers(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);
}
'@

if (-not ('UsbPrinterNative' -as [type])) {
    Add-Type -TypeDefinition $source
}

$spoolerWasRunning = (Get-Service -Name Spooler).Status -eq 'Running'
if ($spoolerWasRunning) {
    Write-Host '暫停 Print Spooler，以釋放 USB 裝置...'
    Stop-Service -Name Spooler -Force
}

try {
    Write-Host "直接開啟 $($port.Name): $($port.DevicePath)"
    $genericReadWrite = 0xC0000000
    $openExisting = 3
    $handle = [UsbPrinterNative]::CreateFile(
        $port.DevicePath,
        $genericReadWrite,
        3,
        [IntPtr]::Zero,
        $openExisting,
        0,
        [IntPtr]::Zero)

    if ($handle -eq [UsbPrinterNative]::InvalidHandleValue) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "無法直接開啟 PL2305。Win32 error: $code"
    }

    try {
        # ESC @ = initialize; CR/LF = print line; ESC d 4 = feed four lines.
        $payload = [Collections.Generic.List[byte]]::new()
        $payload.AddRange([byte[]](0x1b, 0x40))
        $payload.AddRange([Text.Encoding]::ASCII.GetBytes($Text))
        $payload.AddRange([byte[]](0x0d, 0x0a, 0x1b, 0x64, 0x04))

        [uint32] $written = 0
        $success = [UsbPrinterNative]::WriteFile(
            $handle,
            $payload.ToArray(),
            $payload.Count,
            [ref] $written,
            [IntPtr]::Zero)

        $writeError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $flushed = $false
        if ($success) {
            $flushed = [UsbPrinterNative]::FlushFileBuffers($handle)
        }

        [pscustomobject]@{
            Port           = $port.Name
            DeviceId       = $port.DeviceId
            OpenSucceeded  = $true
            WriteSucceeded = $success
            BytesRequested = $payload.Count
            BytesWritten   = $written
            FlushSucceeded = $flushed
            Win32Error     = $writeError
        } | Format-List

        if (-not $success -or $written -ne $payload.Count) {
            throw 'PL2305 已開啟，但測試資料沒有完整寫入。'
        }

        Write-Host '直接寫入完成。請確認印表機是否印出 PL2305 DIRECT TEST。' -ForegroundColor Green
    }
    finally {
        [UsbPrinterNative]::CloseHandle($handle) | Out-Null
    }
}
finally {
    if ($spoolerWasRunning) {
        Start-Service -Name Spooler
        Write-Host 'Print Spooler 已恢復。'
    }
}
