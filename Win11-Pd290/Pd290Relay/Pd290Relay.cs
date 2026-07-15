using System;
using System.IO;
using System.IO.Pipes;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.ServiceProcess;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace PU290Relay
{
    internal static class Program
    {
        private const int ListenPort = 29100;

        private static int Main(string[] args)
        {
            if (args.Length > 0 && string.Equals(args[0], "--probe", StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    using (var device = Pl2305Device.Open())
                    {
                        Console.WriteLine("WinUSB device ready: {0}", device.Description);
                    }
                    return 0;
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine(ex.ToString());
                    return 1;
                }
            }

            if (args.Length > 0 && string.Equals(args[0], "--console", StringComparison.OrdinalIgnoreCase))
            {
                using (var server = new FileRelayServer())
                {
                    Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e)
                    {
                        e.Cancel = true;
                        server.Stop();
                    };
                    server.Run();
                }
                return 0;
            }

            ServiceBase.Run(new RelayWindowsService(ListenPort));
            return 0;
        }
    }

    internal sealed class RelayWindowsService : ServiceBase
    {
        private readonly FileRelayServer server;
        private Thread worker;

        public RelayWindowsService(int port)
        {
            ServiceName = "PU290WinUsbRelay";
            CanStop = true;
            AutoLog = false;
            server = new FileRelayServer();
        }

        protected override void OnStart(string[] args)
        {
            worker = new Thread(server.Run);
            worker.IsBackground = true;
            worker.Name = "PU290 WinUSB relay";
            worker.Start();
        }

        protected override void OnStop()
        {
            server.Stop();
            if (worker != null && worker.IsAlive)
            {
                worker.Join(10000);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) server.Dispose();
            base.Dispose(disposing);
        }
    }

    internal sealed class FileRelayServer : IDisposable
    {
        private readonly ManualResetEvent stopped = new ManualResetEvent(false);
        private readonly string spoolDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PU290Relay", "spool");

        private string SpoolFile { get { return Path.Combine(spoolDirectory, "PU290.prn"); } }

        public void Run()
        {
            Directory.CreateDirectory(spoolDirectory);
            Log.Write("File relay watching " + SpoolFile);
            while (!stopped.WaitOne(0))
            {
                if (File.Exists(SpoolFile) && TryProcessJob()) continue;
                stopped.WaitOne(250);
            }
            Log.Write("File relay stopped");
        }

        private bool TryProcessJob()
        {
            FileStream input;
            try
            {
                input = new FileStream(SpoolFile, FileMode.Open, FileAccess.Read, FileShare.None);
            }
            catch (IOException)
            {
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                return false;
            }

            long total = 0;
            bool completed = false;
            try
            {
                using (input)
                using (var device = Pl2305Device.Open())
                {
                    byte[] buffer = new byte[4096];
                    int count;
                    while ((count = input.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        device.Write(buffer, count);
                        total += count;
                    }
                }
                completed = true;
                Log.Write("File job completed, bytes=" + total);
            }
            catch (Exception ex)
            {
                Log.Write("File job failed after bytes=" + total + ": " + ex);
            }

            try
            {
                if (completed)
                {
                    File.Delete(SpoolFile);
                }
                else if (File.Exists(SpoolFile))
                {
                    string failed = Path.Combine(spoolDirectory,
                        "PU290-failed-" + DateTime.Now.ToString("yyyyMMdd-HHmmssfff") + ".prn");
                    File.Move(SpoolFile, failed);
                    Log.Write("Failed job preserved as " + failed);
                }
            }
            catch (Exception ex)
            {
                Log.Write("Unable to finalize spool file: " + ex);
            }
            return true;
        }

        public void Stop() { stopped.Set(); }

        public void Dispose()
        {
            Stop();
            stopped.Dispose();
        }
    }

    internal sealed class PipeRelayServer : IDisposable
    {
        private const string PipeName = "PU290WinUsb";
        private readonly ManualResetEvent stopped = new ManualResetEvent(false);
        private readonly object sync = new object();
        private NamedPipeServerStream activePipe;

        private static PipeSecurity CreatePipeSecurity()
        {
            var security = new PipeSecurity();
            security.AddAccessRule(new PipeAccessRule(
                new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                PipeAccessRights.FullControl, AccessControlType.Allow));
            security.AddAccessRule(new PipeAccessRule(
                new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
                PipeAccessRights.FullControl, AccessControlType.Allow));
            security.AddAccessRule(new PipeAccessRule(
                new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null),
                PipeAccessRights.ReadWrite, AccessControlType.Allow));
            security.AddAccessRule(new PipeAccessRule(
                new SecurityIdentifier("S-1-5-80-3951239711-1671533544-1416304335-3763227691-3930497994"),
                PipeAccessRights.FullControl, AccessControlType.Allow));
            return security;
        }

        public void Run()
        {
            Log.Write("Named pipe relay waiting on \\\\.\\pipe\\" + PipeName);
            while (!stopped.WaitOne(0))
            {
                NamedPipeServerStream pipe = null;
                try
                {
                    pipe = new NamedPipeServerStream(PipeName, PipeDirection.In, 1,
                        PipeTransmissionMode.Byte, PipeOptions.None, 4096, 4096, CreatePipeSecurity());
                    lock (sync) activePipe = pipe;
                    pipe.WaitForConnection();
                    if (stopped.WaitOne(0)) break;
                    RelayOneJob(pipe);
                }
                catch (ObjectDisposedException)
                {
                    if (!stopped.WaitOne(0)) Log.Write("Named pipe was unexpectedly closed");
                }
                catch (Exception ex)
                {
                    if (!stopped.WaitOne(0)) Log.Write("Named pipe server error: " + ex);
                }
                finally
                {
                    lock (sync)
                    {
                        if (object.ReferenceEquals(activePipe, pipe)) activePipe = null;
                    }
                    if (pipe != null) pipe.Dispose();
                }
            }
            Log.Write("Named pipe relay stopped");
        }

        private static void RelayOneJob(Stream input)
        {
            long total = 0;
            Log.Write("Spooler connected to named pipe");
            try
            {
                using (var device = Pl2305Device.Open())
                {
                    byte[] buffer = new byte[4096];
                    int count;
                    while ((count = input.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        device.Write(buffer, count);
                        total += count;
                    }
                }
                Log.Write("Named pipe job completed, bytes=" + total);
            }
            catch (Exception ex)
            {
                Log.Write("Named pipe job failed after bytes=" + total + ": " + ex);
                throw;
            }
        }

        public void Stop()
        {
            stopped.Set();
            lock (sync)
            {
                if (activePipe != null) activePipe.Dispose();
            }
        }

        public void Dispose()
        {
            Stop();
            stopped.Dispose();
        }
    }

    internal sealed class RelayServer : IDisposable
    {
        private readonly int port;
        private readonly ManualResetEvent stopped = new ManualResetEvent(false);
        private TcpListener listener;

        public RelayServer(int port)
        {
            this.port = port;
        }

        public void Run()
        {
            try
            {
                listener = new TcpListener(IPAddress.Any, port);
                listener.Start(5);
                Log.Write("Relay listening on local interfaces, port " + port);

                while (!stopped.WaitOne(0))
                {
                    TcpClient client;
                    try
                    {
                        client = listener.AcceptTcpClient();
                    }
                    catch (SocketException)
                    {
                        if (stopped.WaitOne(0)) break;
                        throw;
                    }
                    catch (ObjectDisposedException)
                    {
                        if (stopped.WaitOne(0)) break;
                        throw;
                    }

                    using (client)
                    {
                        if (!IsLocalClient(client))
                        {
                            Log.Write("Rejected non-local connection from " + client.Client.RemoteEndPoint);
                            try { client.Client.LingerState = new LingerOption(true, 0); } catch { }
                            continue;
                        }
                        RelayOneJob(client);
                    }
                }
            }
            catch (Exception ex)
            {
                Log.Write("Server error: " + ex);
            }
            finally
            {
                if (listener != null) listener.Stop();
                Log.Write("Relay stopped");
            }
        }

        private static bool IsLocalClient(TcpClient client)
        {
            var endpoint = client.Client.RemoteEndPoint as IPEndPoint;
            if (endpoint == null) return false;
            if (IPAddress.IsLoopback(endpoint.Address)) return true;

            try
            {
                IPAddress remote = endpoint.Address;
                foreach (IPAddress local in Dns.GetHostAddresses(Dns.GetHostName()))
                {
                    if (remote.Equals(local)) return true;
                    if (remote.IsIPv4MappedToIPv6 && remote.MapToIPv4().Equals(local)) return true;
                    if (local.IsIPv4MappedToIPv6 && local.MapToIPv4().Equals(remote)) return true;
                }
            }
            catch { }
            return false;
        }

        private static void RelayOneJob(TcpClient client)
        {
            long total = 0;
            string remote = client.Client.RemoteEndPoint == null ? "unknown" : client.Client.RemoteEndPoint.ToString();
            Log.Write("Connection accepted from " + remote);

            try
            {
                client.NoDelay = true;
                using (var device = Pl2305Device.Open())
                using (NetworkStream input = client.GetStream())
                {
                    byte[] buffer = new byte[4096];
                    int count;
                    while ((count = input.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        device.Write(buffer, count);
                        total += count;
                    }
                }
                Log.Write("Job completed, bytes=" + total);
            }
            catch (Exception ex)
            {
                Log.Write("Job failed after bytes=" + total + ": " + ex);
                try
                {
                    client.Client.LingerState = new LingerOption(true, 0);
                }
                catch { }
            }
        }

        public void Stop()
        {
            stopped.Set();
            TcpListener current = listener;
            if (current != null) current.Stop();
        }

        public void Dispose()
        {
            Stop();
            stopped.Dispose();
        }
    }

    internal sealed class Pl2305Device : IDisposable
    {
        private static readonly Guid DeviceInterfaceGuid = new Guid("D14692B4-3AFD-4F6C-AB91-F2B456CF7F77");
        private SafeFileHandle fileHandle;
        private IntPtr winUsbHandle;
        private byte bulkOutPipe;

        public string Description { get; private set; }

        private Pl2305Device() { }

        public static Pl2305Device Open()
        {
            var result = new Pl2305Device();
            try
            {
                string path = NativeMethods.GetDevicePath(DeviceInterfaceGuid);
                result.fileHandle = NativeMethods.CreateFile(
                    path,
                    NativeMethods.GENERIC_READ | NativeMethods.GENERIC_WRITE,
                    NativeMethods.FILE_SHARE_READ | NativeMethods.FILE_SHARE_WRITE,
                    IntPtr.Zero,
                    NativeMethods.OPEN_EXISTING,
                    NativeMethods.FILE_ATTRIBUTE_NORMAL | NativeMethods.FILE_FLAG_OVERLAPPED,
                    IntPtr.Zero);

                if (result.fileHandle.IsInvalid)
                    throw NativeMethods.Win32Exception("CreateFile");

                if (!NativeMethods.WinUsb_Initialize(result.fileHandle, out result.winUsbHandle))
                    throw NativeMethods.Win32Exception("WinUsb_Initialize");

                NativeMethods.USB_INTERFACE_DESCRIPTOR descriptor;
                if (!NativeMethods.WinUsb_QueryInterfaceSettings(result.winUsbHandle, 0, out descriptor))
                    throw NativeMethods.Win32Exception("WinUsb_QueryInterfaceSettings");

                bool found = false;
                ushort maxPacket = 0;
                for (byte i = 0; i < descriptor.bNumEndpoints; i++)
                {
                    NativeMethods.WINUSB_PIPE_INFORMATION pipe;
                    if (!NativeMethods.WinUsb_QueryPipe(result.winUsbHandle, 0, i, out pipe))
                        throw NativeMethods.Win32Exception("WinUsb_QueryPipe");

                    if (!found && pipe.PipeType == NativeMethods.UsbdPipeType.Bulk && (pipe.PipeId & 0x80) == 0)
                    {
                        result.bulkOutPipe = pipe.PipeId;
                        maxPacket = pipe.MaximumPacketSize;
                        found = true;
                    }
                }
                if (!found) throw new IOException("The PL2305 interface has no Bulk OUT endpoint.");

                uint timeout = 5000;
                NativeMethods.WinUsb_SetPipePolicy(result.winUsbHandle, result.bulkOutPipe,
                    NativeMethods.PIPE_TRANSFER_TIMEOUT, 4, ref timeout);
                uint autoClear = 1;
                NativeMethods.WinUsb_SetPipePolicy(result.winUsbHandle, result.bulkOutPipe,
                    NativeMethods.AUTO_CLEAR_STALL, 4, ref autoClear);

                result.Description = string.Format("{0}, Bulk OUT 0x{1:X2}, max packet {2}", path, result.bulkOutPipe, maxPacket);
                return result;
            }
            catch
            {
                result.Dispose();
                throw;
            }
        }

        public void Write(byte[] buffer, int count)
        {
            int offset = 0;
            while (offset < count)
            {
                int chunkSize = Math.Min(4096, count - offset);
                byte[] chunk;
                if (offset == 0 && chunkSize == buffer.Length)
                {
                    chunk = buffer;
                }
                else
                {
                    chunk = new byte[chunkSize];
                    Buffer.BlockCopy(buffer, offset, chunk, 0, chunkSize);
                }

                uint written;
                bool ok = NativeMethods.WinUsb_WritePipe(winUsbHandle, bulkOutPipe, chunk,
                    (uint)chunkSize, out written, IntPtr.Zero);
                if (!ok) throw NativeMethods.Win32Exception("WinUsb_WritePipe");
                if (written == 0) throw new IOException("WinUsb_WritePipe returned zero bytes.");
                offset += (int)written;
            }
        }

        public void Dispose()
        {
            if (winUsbHandle != IntPtr.Zero)
            {
                NativeMethods.WinUsb_Free(winUsbHandle);
                winUsbHandle = IntPtr.Zero;
            }
            if (fileHandle != null)
            {
                fileHandle.Dispose();
                fileHandle = null;
            }
        }
    }

    internal static class NativeMethods
    {
        internal const uint GENERIC_READ = 0x80000000;
        internal const uint GENERIC_WRITE = 0x40000000;
        internal const uint FILE_SHARE_READ = 0x00000001;
        internal const uint FILE_SHARE_WRITE = 0x00000002;
        internal const uint OPEN_EXISTING = 3;
        internal const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
        internal const uint FILE_FLAG_OVERLAPPED = 0x40000000;
        internal const uint CM_GET_DEVICE_INTERFACE_LIST_PRESENT = 0;
        internal const uint PIPE_TRANSFER_TIMEOUT = 3;
        internal const uint AUTO_CLEAR_STALL = 2;

        internal enum UsbdPipeType { Control, Isochronous, Bulk, Interrupt }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        internal struct USB_INTERFACE_DESCRIPTOR
        {
            internal byte bLength;
            internal byte bDescriptorType;
            internal byte bInterfaceNumber;
            internal byte bAlternateSetting;
            internal byte bNumEndpoints;
            internal byte bInterfaceClass;
            internal byte bInterfaceSubClass;
            internal byte bInterfaceProtocol;
            internal byte iInterface;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct WINUSB_PIPE_INFORMATION
        {
            internal UsbdPipeType PipeType;
            internal byte PipeId;
            internal ushort MaximumPacketSize;
            internal byte Interval;
        }

        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode, EntryPoint = "CM_Get_Device_Interface_List_SizeW")]
        internal static extern int CM_Get_Device_Interface_List_Size(out uint length, ref Guid interfaceClassGuid,
            string deviceId, uint flags);

        [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode, EntryPoint = "CM_Get_Device_Interface_ListW")]
        internal static extern int CM_Get_Device_Interface_List(ref Guid interfaceClassGuid, string deviceId,
            [Out] char[] buffer, uint bufferLength, uint flags);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern SafeFileHandle CreateFile(string fileName, uint desiredAccess, uint shareMode,
            IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

        [DllImport("winusb.dll", SetLastError = true)]
        internal static extern bool WinUsb_Initialize(SafeFileHandle deviceHandle, out IntPtr interfaceHandle);

        [DllImport("winusb.dll", SetLastError = true)]
        internal static extern bool WinUsb_QueryInterfaceSettings(IntPtr interfaceHandle, byte alternateSettingNumber,
            out USB_INTERFACE_DESCRIPTOR descriptor);

        [DllImport("winusb.dll", SetLastError = true)]
        internal static extern bool WinUsb_QueryPipe(IntPtr interfaceHandle, byte alternateInterfaceNumber,
            byte pipeIndex, out WINUSB_PIPE_INFORMATION pipeInformation);

        [DllImport("winusb.dll", SetLastError = true)]
        internal static extern bool WinUsb_SetPipePolicy(IntPtr interfaceHandle, byte pipeId, uint policyType,
            uint valueLength, ref uint value);

        [DllImport("winusb.dll", SetLastError = true)]
        internal static extern bool WinUsb_WritePipe(IntPtr interfaceHandle, byte pipeId, byte[] buffer,
            uint bufferLength, out uint lengthTransferred, IntPtr overlapped);

        [DllImport("winusb.dll", SetLastError = true)]
        internal static extern bool WinUsb_Free(IntPtr interfaceHandle);

        internal static string GetDevicePath(Guid interfaceGuid)
        {
            uint length;
            int result = CM_Get_Device_Interface_List_Size(out length, ref interfaceGuid, null,
                CM_GET_DEVICE_INTERFACE_LIST_PRESENT);
            if (result != 0 || length <= 1)
                throw new IOException("The PL2305 WinUSB interface was not found. CM result=" + result);

            char[] buffer = new char[length];
            result = CM_Get_Device_Interface_List(ref interfaceGuid, null, buffer, length,
                CM_GET_DEVICE_INTERFACE_LIST_PRESENT);
            if (result != 0)
                throw new IOException("Unable to enumerate the PL2305 WinUSB interface. CM result=" + result);

            string all = new string(buffer);
            int end = all.IndexOf('\0');
            if (end < 1) throw new IOException("The PL2305 WinUSB device path was empty.");
            return all.Substring(0, end);
        }

        internal static Exception Win32Exception(string operation)
        {
            int error = Marshal.GetLastWin32Error();
            return new System.ComponentModel.Win32Exception(error, operation + " failed");
        }
    }

    internal static class Log
    {
        private static readonly object Sync = new object();
        private static readonly string DirectoryPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PU290Relay");
        private static readonly string LogPath = Path.Combine(DirectoryPath, "relay.log");

        internal static void Write(string message)
        {
            try
            {
                lock (Sync)
                {
                    Directory.CreateDirectory(DirectoryPath);
                    if (File.Exists(LogPath) && new FileInfo(LogPath).Length > 1024 * 1024)
                    {
                        File.Copy(LogPath, LogPath + ".old", true);
                        File.Delete(LogPath);
                    }
                    File.AppendAllText(LogPath,
                        DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + " " + message + Environment.NewLine);
                }
            }
            catch { }
        }
    }
}
