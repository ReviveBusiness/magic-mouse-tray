using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace MagicMouseTray;

// Reads battery % from Apple Magic Mouse via HID Input Report 0x90.
// Uses SetupDi enumeration + HidD_GetInputReport P/Invoke — same approach
// confirmed in M1 feasibility test (84% returned on MM2024-BT-COL02).
//
// COL02 is the battery collection; COL01 (pointer) is Windows-owned (err=5).
// We enumerate all HID interfaces and try each — COL02 succeeds, COL01 fails,
// so the first successful read is the battery read.
public static class MouseBatteryReader
{
    // Known Magic Mouse device definitions (VID/PID as they appear in device paths).
    // BT paths use format: VID&XXXXXXXPID&XXXX
    // USB paths use format: VID_XXXX&PID_XXXX
    static readonly (string VidPattern, string PidPattern, string Name)[] KnownMice =
    [
        ("0001004C", "PID&0323", "Magic Mouse 2024"),  // BT, VID=Apple BT 0x004C, confirmed M1
        ("VID_05AC",  "PID_0323", "Magic Mouse 2024"),  // USB
        ("000205AC", "PID&030D", "Magic Mouse v1"),    // BT, VID=Apple USB-IF 0x05AC, PnP confirmed
        ("000205AC", "PID&0269", "Magic Mouse v2"),    // BT, PID unconfirmed — test in M2
    ];

    const byte BatteryReportId = 0x90;

    // Returns (battery %, device name) or (-1, "") if no mouse found/connected.
    public static (int Percent, string DeviceName) GetBatteryLevel()
    {
        var hidGuid = new Guid("4d1e55b2-f16f-11cf-88cb-001111000030");
        var devs = SetupDiGetClassDevs(ref hidGuid, null, IntPtr.Zero,
            DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);

        if (devs == IntPtr.Zero || devs == INVALID_HANDLE_VALUE)
            return (-1, string.Empty);

        try
        {
            uint index = 0;
            while (true)
            {
                var iface = new SP_DEVICE_INTERFACE_DATA();
                iface.cbSize = (uint)Marshal.SizeOf<SP_DEVICE_INTERFACE_DATA>();

                if (!SetupDiEnumDeviceInterfaces(devs, IntPtr.Zero, ref hidGuid, index++, ref iface))
                    break;

                var detail = new SP_DEVICE_INTERFACE_DETAIL_DATA();
                detail.cbSize = IntPtr.Size == 8 ? 8u : 6u;
                SetupDiGetDeviceInterfaceDetail(devs, ref iface, ref detail, 512,
                    out _, IntPtr.Zero);

                if (string.IsNullOrEmpty(detail.DevicePath))
                    continue;

                string? name = MatchMouse(detail.DevicePath);
                if (name is null)
                    continue;

                int pct = TryReadBattery(detail.DevicePath);
                if (pct >= 0)
                    return (pct, name);
            }
        }
        finally
        {
            SetupDiDestroyDeviceInfoList(devs);
        }

        Logger.Log("NO_MOUSE_FOUND no Apple Magic Mouse HID interface responded to 0x90");
        return (-1, string.Empty);
    }

    // Returns device name if the path matches a known Magic Mouse, null otherwise.
    static string? MatchMouse(string path)
    {
        foreach (var (vid, pid, name) in KnownMice)
        {
            if (path.Contains(vid, StringComparison.OrdinalIgnoreCase) &&
                path.Contains(pid, StringComparison.OrdinalIgnoreCase))
                return name;
        }
        return null;
    }

    // Opens the HID device at path and reads Input Report 0x90.
    // Returns battery % (0-100) or -1 on failure.
    static int TryReadBattery(string devicePath)
    {
        using var handle = CreateFile(
            devicePath,
            GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            IntPtr.Zero,
            OPEN_EXISTING,
            0,
            IntPtr.Zero);

        if (handle.IsInvalid)
        {
            Logger.Log($"OPEN_FAILED path={devicePath} err={Marshal.GetLastWin32Error()}");
            return -1;
        }

        var buf = new byte[3];
        buf[0] = BatteryReportId;

        if (!HidD_GetInputReport(handle, buf, buf.Length))
        {
            Logger.Log($"READ_FAILED path={devicePath} err={Marshal.GetLastWin32Error()}");
            return -1;
        }

        if (buf[0] != BatteryReportId)
        {
            Logger.Log($"WRONG_REPORT path={devicePath} got=0x{buf[0]:X2}");
            return -1;
        }

        int pct = buf[2];
        if (pct is < 0 or > 100)
        {
            Logger.Log($"INVALID_PCT path={devicePath} val={pct}");
            return -1;
        }

        Logger.Log($"OK path={devicePath} battery={pct}%");
        return pct;
    }

    // --- P/Invoke ---

    const uint GENERIC_READ = 0x80000000;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_READ = 0x00000001;
    const uint FILE_SHARE_WRITE = 0x00000002;
    const uint OPEN_EXISTING = 3;
    const uint DIGCF_PRESENT = 0x02;
    const uint DIGCF_DEVICEINTERFACE = 0x10;
    static readonly IntPtr INVALID_HANDLE_VALUE = new(-1);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern SafeFileHandle CreateFile(string lpFileName, uint dwDesiredAccess,
        uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("hid.dll", SetLastError = true)]
    static extern bool HidD_GetInputReport(SafeFileHandle HidDeviceObject,
        byte[] ReportBuffer, int ReportBufferLength);

    [DllImport("setupapi.dll", SetLastError = true)]
    static extern IntPtr SetupDiGetClassDevs(ref Guid ClassGuid, string? Enumerator,
        IntPtr hwndParent, uint Flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    static extern bool SetupDiEnumDeviceInterfaces(IntPtr DeviceInfoSet,
        IntPtr DeviceInfoData, ref Guid InterfaceClassGuid, uint MemberIndex,
        ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Auto)]
    static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr DeviceInfoSet,
        ref SP_DEVICE_INTERFACE_DATA DeviceInterfaceData,
        ref SP_DEVICE_INTERFACE_DETAIL_DATA DeviceInterfaceDetailData,
        uint DeviceInterfaceDetailDataSize, out uint RequiredSize,
        IntPtr DeviceInfoData);

    [DllImport("setupapi.dll")]
    static extern bool SetupDiDestroyDeviceInfoList(IntPtr DeviceInfoSet);

    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA
    {
        public uint cbSize;
        public Guid InterfaceClassGuid;
        public uint Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    struct SP_DEVICE_INTERFACE_DETAIL_DATA
    {
        public uint cbSize;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 512)]
        public string DevicePath;
    }
}
