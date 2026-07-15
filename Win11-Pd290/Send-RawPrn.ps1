[CmdletBinding()]
param(
    [string] $PrinterName = 'Pd290-Win11',
    [string] $FilePath
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($FilePath)) {
    $FilePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Pd290-win10.prn'
}

if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    throw "PRN file not found: $FilePath"
}

$existingJobs = @(Get-PrintJob -PrinterName $PrinterName -ErrorAction SilentlyContinue)
if ($existingJobs.Count -gt 0) {
    $existingJobs | Format-Table ID, DocumentName, JobStatus, Size -AutoSize
    throw 'The target printer still has queued jobs. Clear them before running this test.'
}

$source = @'
using System;
using System.Runtime.InteropServices;

public static class RawPrinterNative
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public class DOC_INFO_1
    {
        [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPWStr)] public string pDatatype;
    }

    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool OpenPrinter(string printerName, out IntPtr printer, IntPtr defaults);

    [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern int StartDocPrinter(IntPtr printer, int level, [In] DOC_INFO_1 info);

    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool StartPagePrinter(IntPtr printer);

    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool WritePrinter(IntPtr printer, byte[] bytes, int count, out int written);

    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool EndPagePrinter(IntPtr printer);

    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool EndDocPrinter(IntPtr printer);

    [DllImport("winspool.drv", SetLastError = true)]
    public static extern bool ClosePrinter(IntPtr printer);
}
'@

if (-not ('RawPrinterNative' -as [type])) {
    Add-Type -TypeDefinition $source
}

$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $FilePath))
$printer = [IntPtr]::Zero
$documentStarted = $false
$pageStarted = $false

if (-not [RawPrinterNative]::OpenPrinter($PrinterName, [ref] $printer, [IntPtr]::Zero)) {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "OpenPrinter failed. Win32 error: $code"
}

try {
    $info = [RawPrinterNative+DOC_INFO_1]::new()
    $info.pDocName = "RAW: $([IO.Path]::GetFileName($FilePath))"
    $info.pOutputFile = $null
    $info.pDatatype = 'RAW'

    $jobId = [RawPrinterNative]::StartDocPrinter($printer, 1, $info)
    if ($jobId -le 0) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "StartDocPrinter failed. Win32 error: $code"
    }
    $documentStarted = $true

    if (-not [RawPrinterNative]::StartPagePrinter($printer)) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "StartPagePrinter failed. Win32 error: $code"
    }
    $pageStarted = $true

    $offset = 0
    $chunkSize = 32768
    while ($offset -lt $bytes.Length) {
        $count = [Math]::Min($chunkSize, $bytes.Length - $offset)
        $chunk = [byte[]]::new($count)
        [Array]::Copy($bytes, $offset, $chunk, 0, $count)
        $written = 0
        if (-not [RawPrinterNative]::WritePrinter($printer, $chunk, $chunk.Length, [ref] $written)) {
            $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "WritePrinter failed at byte $offset. Win32 error: $code"
        }
        if ($written -ne $count) {
            throw "WritePrinter accepted only $written of $count bytes at offset $offset."
        }
        $offset += $written
    }

    [pscustomobject]@{
        Printer      = $PrinterName
        JobId        = $jobId
        Datatype     = 'RAW'
        SourceFile   = (Resolve-Path -LiteralPath $FilePath).Path
        BytesQueued  = $offset
    } | Format-List
}
finally {
    if ($pageStarted) {
        [RawPrinterNative]::EndPagePrinter($printer) | Out-Null
    }
    if ($documentStarted) {
        [RawPrinterNative]::EndDocPrinter($printer) | Out-Null
    }
    [RawPrinterNative]::ClosePrinter($printer) | Out-Null
}
