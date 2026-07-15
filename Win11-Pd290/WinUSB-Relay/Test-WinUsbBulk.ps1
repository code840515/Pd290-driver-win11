[CmdletBinding()]
param(
    [string] $FilePath
)

$ErrorActionPreference = 'Stop'
$deviceInterfaceGuid = [guid]'{D14692B4-3AFD-4F6C-AB91-F2B456CF7F77}'

if ([string]::IsNullOrWhiteSpace($FilePath)) {
    $packageRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
    $FilePath = Join-Path $packageRoot 'pd290-win10.prn'
}
if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
    throw "PRN file not found: $FilePath"
}

$source = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class Pl2305WinUsb
{
    public const uint GENERIC_READ = 0x80000000;
    public const uint GENERIC_WRITE = 0x40000000;
    public const uint FILE_SHARE_READ = 0x00000001;
    public const uint FILE_SHARE_WRITE = 0x00000002;
    public const uint OPEN_EXISTING = 3;
    public const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
    public const uint FILE_FLAG_OVERLAPPED = 0x40000000;
    public const uint CM_GET_DEVICE_INTERFACE_LIST_PRESENT = 0;
    public const uint PIPE_TRANSFER_TIMEOUT = 3;
    public const uint AUTO_CLEAR_STALL = 2;

    public enum UsbdPipeType
    {
        Control = 0,
        Isochronous = 1,
        Bulk = 2,
        Interrupt = 3
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct USB_INTERFACE_DESCRIPTOR
    {
        public byte bLength;
        public byte bDescriptorType;
        public byte bInterfaceNumber;
        public byte bAlternateSetting;
        public byte bNumEndpoints;
        public byte bInterfaceClass;
        public byte bInterfaceSubClass;
        public byte bInterfaceProtocol;
        public byte iInterface;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WINUSB_PIPE_INFORMATION
    {
        public UsbdPipeType PipeType;
        public byte PipeId;
        public ushort MaximumPacketSize;
        public byte Interval;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct WINUSB_SETUP_PACKET
    {
        public byte RequestType;
        public byte Request;
        public ushort Value;
        public ushort Index;
        public ushort Length;
    }

    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode, EntryPoint = "CM_Get_Device_Interface_List_SizeW")]
    public static extern int CM_Get_Device_Interface_List_Size(
        out uint length,
        ref Guid interfaceClassGuid,
        string deviceId,
        uint flags);

    [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode, EntryPoint = "CM_Get_Device_Interface_ListW")]
    public static extern int CM_Get_Device_Interface_List(
        ref Guid interfaceClassGuid,
        string deviceId,
        [Out] char[] buffer,
        uint bufferLength,
        uint flags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern SafeFileHandle CreateFile(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_Initialize(SafeFileHandle deviceHandle, out IntPtr interfaceHandle);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_QueryInterfaceSettings(
        IntPtr interfaceHandle,
        byte alternateSettingNumber,
        out USB_INTERFACE_DESCRIPTOR descriptor);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_QueryPipe(
        IntPtr interfaceHandle,
        byte alternateInterfaceNumber,
        byte pipeIndex,
        out WINUSB_PIPE_INFORMATION pipeInformation);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_SetPipePolicy(
        IntPtr interfaceHandle,
        byte pipeId,
        uint policyType,
        uint valueLength,
        ref uint value);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_ControlTransfer(
        IntPtr interfaceHandle,
        WINUSB_SETUP_PACKET setupPacket,
        [Out] byte[] buffer,
        uint bufferLength,
        out uint lengthTransferred,
        IntPtr overlapped);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_WritePipe(
        IntPtr interfaceHandle,
        byte pipeId,
        byte[] buffer,
        uint bufferLength,
        out uint lengthTransferred,
        IntPtr overlapped);

    [DllImport("winusb.dll", SetLastError = true)]
    public static extern bool WinUsb_Free(IntPtr interfaceHandle);
}
'@

if (-not ('Pl2305WinUsb' -as [type])) {
    Add-Type -TypeDefinition $source
}

$length = 0
$result = [Pl2305WinUsb]::CM_Get_Device_Interface_List_Size(
    [ref] $length,
    [ref] $deviceInterfaceGuid,
    $null,
    [Pl2305WinUsb]::CM_GET_DEVICE_INTERFACE_LIST_PRESENT)
if ($result -ne 0 -or $length -le 1) {
    throw "The PL2305 WinUSB device interface was not found. CM result=$result, length=$length"
}

$buffer = [char[]]::new($length)
$result = [Pl2305WinUsb]::CM_Get_Device_Interface_List(
    [ref] $deviceInterfaceGuid,
    $null,
    $buffer,
    $length,
    [Pl2305WinUsb]::CM_GET_DEVICE_INTERFACE_LIST_PRESENT)
if ($result -ne 0) {
    throw "Unable to enumerate the PL2305 WinUSB device interface. CM result=$result"
}

$devicePath = (-join $buffer).Split([char]0, [StringSplitOptions]::RemoveEmptyEntries) |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($devicePath)) {
    throw 'WinUSB returned an empty device path.'
}

$fileHandle = [Pl2305WinUsb]::CreateFile(
    $devicePath,
    [Pl2305WinUsb]::GENERIC_READ -bor [Pl2305WinUsb]::GENERIC_WRITE,
    [Pl2305WinUsb]::FILE_SHARE_READ -bor [Pl2305WinUsb]::FILE_SHARE_WRITE,
    [IntPtr]::Zero,
    [Pl2305WinUsb]::OPEN_EXISTING,
    [Pl2305WinUsb]::FILE_ATTRIBUTE_NORMAL -bor [Pl2305WinUsb]::FILE_FLAG_OVERLAPPED,
    [IntPtr]::Zero)
if ($fileHandle.IsInvalid) {
    $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "CreateFile failed. Win32 error: $code"
}

$winUsbHandle = [IntPtr]::Zero
try {
    if (-not [Pl2305WinUsb]::WinUsb_Initialize($fileHandle, [ref] $winUsbHandle)) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "WinUsb_Initialize failed. Win32 error: $code"
    }

    $descriptor = [Pl2305WinUsb+USB_INTERFACE_DESCRIPTOR]::new()
    if (-not [Pl2305WinUsb]::WinUsb_QueryInterfaceSettings($winUsbHandle, 0, [ref] $descriptor)) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "WinUsb_QueryInterfaceSettings failed. Win32 error: $code"
    }

    Write-Host ('Interface {0}: class=0x{1:X2}, subclass=0x{2:X2}, protocol=0x{3:X2}, endpoints={4}' -f
        $descriptor.bInterfaceNumber,
        $descriptor.bInterfaceClass,
        $descriptor.bInterfaceSubClass,
        $descriptor.bInterfaceProtocol,
        $descriptor.bNumEndpoints)

    $bulkOutPipe = $null
    for ($index = 0; $index -lt $descriptor.bNumEndpoints; $index++) {
        $pipe = [Pl2305WinUsb+WINUSB_PIPE_INFORMATION]::new()
        if (-not [Pl2305WinUsb]::WinUsb_QueryPipe($winUsbHandle, 0, $index, [ref] $pipe)) {
            $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "WinUsb_QueryPipe failed for index $index. Win32 error: $code"
        }

        $direction = if (($pipe.PipeId -band 0x80) -ne 0) { 'IN' } else { 'OUT' }
        Write-Host ('Pipe {0}: type={1}, id=0x{2:X2}, direction={3}, maxPacket={4}' -f
            $index, $pipe.PipeType, $pipe.PipeId, $direction, $pipe.MaximumPacketSize)

        if ($null -eq $bulkOutPipe -and
            $pipe.PipeType -eq [Pl2305WinUsb+UsbdPipeType]::Bulk -and
            ($pipe.PipeId -band 0x80) -eq 0) {
            $bulkOutPipe = $pipe
        }
    }

    if ($null -eq $bulkOutPipe) {
        throw 'The device has no Bulk OUT endpoint.'
    }

    # USB Printer Class GET_PORT_STATUS: bmRequestType=A1h, bRequest=1.
    $statusPacket = [Pl2305WinUsb+WINUSB_SETUP_PACKET]::new()
    $statusPacket.RequestType = 0xA1
    $statusPacket.Request = 1
    $statusPacket.Value = 0
    $statusPacket.Index = $descriptor.bInterfaceNumber
    $statusPacket.Length = 1
    $statusBuffer = [byte[]]::new(1)
    [uint32] $statusTransferred = 0
    $statusOk = [Pl2305WinUsb]::WinUsb_ControlTransfer(
        $winUsbHandle, $statusPacket, $statusBuffer, 1, [ref] $statusTransferred, [IntPtr]::Zero)
    $statusError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Host ('GET_PORT_STATUS: success={0}, bytes={1}, status=0x{2:X2}, error={3}' -f
        $statusOk, $statusTransferred, $statusBuffer[0], $statusError)

    $timeout = [uint32]5000
    [Pl2305WinUsb]::WinUsb_SetPipePolicy(
        $winUsbHandle,
        $bulkOutPipe.PipeId,
        [Pl2305WinUsb]::PIPE_TRANSFER_TIMEOUT,
        4,
        [ref] $timeout) | Out-Null
    $autoClear = [uint32]1
    [Pl2305WinUsb]::WinUsb_SetPipePolicy(
        $winUsbHandle,
        $bulkOutPipe.PipeId,
        [Pl2305WinUsb]::AUTO_CLEAR_STALL,
        4,
        [ref] $autoClear) | Out-Null

    $data = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $FilePath))
    $offset = 0
    $chunkSize = 4096
    while ($offset -lt $data.Length) {
        $count = [Math]::Min($chunkSize, $data.Length - $offset)
        $chunk = [byte[]]::new($count)
        [Array]::Copy($data, $offset, $chunk, 0, $count)
        [uint32] $written = 0
        $ok = [Pl2305WinUsb]::WinUsb_WritePipe(
            $winUsbHandle,
            $bulkOutPipe.PipeId,
            $chunk,
            $count,
            [ref] $written,
            [IntPtr]::Zero)
        if (-not $ok -or $written -ne $count) {
            $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Bulk OUT failed at offset ${offset}: requested=$count written=$written error=$code"
        }
        $offset += $written
        Write-Progress -Activity 'Writing Win10 PRN through WinUSB' -Status "$offset / $($data.Length) bytes" -PercentComplete (($offset * 100) / $data.Length)
    }
    Write-Progress -Activity 'Writing Win10 PRN through WinUSB' -Completed

    [pscustomobject]@{
        DevicePath      = $devicePath
        InterfaceClass  = ('0x{0:X2}' -f $descriptor.bInterfaceClass)
        InterfaceNumber = $descriptor.bInterfaceNumber
        BulkOutPipe     = ('0x{0:X2}' -f $bulkOutPipe.PipeId)
        BytesWritten    = $offset
        SourceFile      = (Resolve-Path -LiteralPath $FilePath).Path
    } | Format-List
}
finally {
    if ($winUsbHandle -ne [IntPtr]::Zero) {
        [Pl2305WinUsb]::WinUsb_Free($winUsbHandle) | Out-Null
    }
    $fileHandle.Dispose()
}
