// SPDX-License-Identifier: MIT
// Reads battery % from Apple Magic Mouse via HID Input Report 0x90 on COL02.
//
// COL02 (battery collection) is a separate child PDO under BTHENUM. It exists only when
// BTHENUM enumerates the device WITHOUT applewirelessmouse in LowerFilters — the filter
// strips the battery collection from the HID descriptor during enumeration (pair-first
// install sequence required; see M10 in PRD-184).
//
// COL01 (pointer) is exclusively held by mouhid. Zero-access handle (dwDesiredAccess=0)
// opens both COL01 and COL02 without err=5 conflict. HidP_GetCaps pre-check skips devices
// without a meaningful input report. HidD_GetInputReport is retried 3×50ms for BT timing.
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace MagicMouseTray;

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

        // Track if any path was found-but-inaccessible (Apple unified mode).
        // If we exit the loop without a successful read but with an inaccessible path,
        // we report -2 (battery N/A) instead of -1 (no mouse) so the tray shows the
        // accurate state.
        string? inaccessibleName = null;
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
                if (pct == -2)
                    inaccessibleName = name;  // remember; might find a working path later
            }
        }
        finally
        {
            SetupDiDestroyDeviceInfoList(devs);
        }

        if (inaccessibleName != null)
        {
            Logger.Log("BATTERY_INACCESSIBLE Apple driver in unified mode (see PRD-184)");
            return (-2, inaccessibleName);
        }

        Logger.Log("NO_MOUSE_FOUND no Apple Magic Mouse HID interface responded");
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
    // Vendor-defined battery TLC (legacy split path, applewirelessmouse.sys NOT in stack):
    //   UsagePage 0xFF00 / Usage 0x0014, Report 0x90 input, [reportId, flags, pct]
    // Apple unified path (applewirelessmouse.sys in LowerFilters, post-2026 driver behavior):
    //   UsagePage 0x0006 / Usage 0x0020 ("Battery Strength"), Report 0x47 feature, [reportId, pct]
    //   This path is INACCESSIBLE from userland — Apple's driver returns ERROR_INVALID_PARAMETER (87)
    //   on HidD_GetFeature even with correct buffer size. Documented empirically 2026-04-27.
    const ushort UP_VENDOR_BATTERY    = 0xFF00; const ushort USG_VENDOR_BATTERY    = 0x0014;
    const ushort UP_GENDEV_BATTERY    = 0x0006; const ushort USG_GENDEV_BATTSTRENG = 0x0020;

    static int TryReadBattery(string devicePath)
    {
        using var handle = CreateFile(
            devicePath,
            0,                              // zero access — opens mouhid-owned interfaces without err=5
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

        if (!HidD_GetPreparsedData(handle, out var preparsed)) return -1;
        bool splitVendorBattery = false;     // path has Report 0x90 vendor TLC
        bool unifiedAppleBattery = false;    // path has Feature 0x47 Battery Strength (Apple unified)
        byte unifiedReportId = 0;
        int featureLen = 0;
        try
        {
            var caps = new HIDP_CAPS();
            if (HidP_GetCaps(preparsed, ref caps) != HIDP_STATUS_SUCCESS) return -1;
            Logger.Log($"HIDP_CAPS path={devicePath} InLen={caps.InputReportByteLength} FeatLen={caps.FeatureReportByteLength} TLC=UP:{caps.UsagePage:X4}/U:{caps.Usage:X4}");
            featureLen = caps.FeatureReportByteLength;

            // Probe Feature value caps for Generic Device Battery Strength (Apple unified mode)
            if (caps.NumberFeatureValueCaps > 0)
            {
                var fcaps = new HIDP_VALUE_CAPS[caps.NumberFeatureValueCaps];
                ushort len = caps.NumberFeatureValueCaps;
                if (HidP_GetValueCaps(2 /* Feature */, fcaps, ref len, preparsed) == HIDP_STATUS_SUCCESS)
                {
                    for (int i = 0; i < len; i++)
                    {
                        if (fcaps[i].UsagePage == UP_GENDEV_BATTERY && fcaps[i].Usage == USG_GENDEV_BATTSTRENG)
                        {
                            unifiedAppleBattery = true;
                            unifiedReportId = fcaps[i].ReportID;
                            Logger.Log($"DETECT path={devicePath} unified-apple Feature=0x{unifiedReportId:X2} (Battery Strength)");
                            break;
                        }
                    }
                }
            }

            // Detect legacy split-COL02 vendor battery from CAPS UsagePage/Usage (input report)
            if (caps.UsagePage == UP_VENDOR_BATTERY && caps.Usage == USG_VENDOR_BATTERY && caps.InputReportByteLength >= 3)
            {
                splitVendorBattery = true;
                Logger.Log($"DETECT path={devicePath} split-vendor InputReport=0x{BatteryReportId:X2}");
            }
        }
        finally
        {
            HidD_FreePreparsedData(preparsed);
        }

        // Fast path: legacy split COL02 — works whenever Apple's filter is NOT in the stack
        if (splitVendorBattery)
        {
            var buf = new byte[3];
            for (int attempt = 0; attempt < 3; attempt++)
            {
                buf[0] = BatteryReportId;
                if (HidD_GetInputReport(handle, buf, buf.Length))
                {
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
                    Logger.Log($"OK path={devicePath} battery={pct}% (split)");
                    return pct;
                }
                if (attempt < 2) Thread.Sleep(50);
            }
            Logger.Log($"READ_FAILED path={devicePath} err={Marshal.GetLastWin32Error()} (split)");
            return -1;
        }

        // Slow path: Apple unified mode — try HidD_GetFeature on report 0x47.
        // Empirically this returns ERROR_INVALID_PARAMETER (87) on Apple driver 6.2.0.0,
        // but we attempt it anyway for completeness and in case future driver versions fix it.
        if (unifiedAppleBattery && featureLen > 0)
        {
            var fbuf = new byte[Math.Max(featureLen, 2)];
            fbuf[0] = unifiedReportId;
            if (HidD_GetFeature(handle, fbuf, fbuf.Length))
            {
                int pct = fbuf[1];
                if (pct is >= 0 and <= 100)
                {
                    Logger.Log($"OK path={devicePath} battery={pct}% (unified Feature 0x{unifiedReportId:X2})");
                    return pct;
                }
                Logger.Log($"INVALID_PCT path={devicePath} val={pct} (unified)");
                return -1;
            }
            int err = Marshal.GetLastWin32Error();
            Logger.Log($"FEATURE_BLOCKED path={devicePath} err={err} (Apple driver traps Feature 0x{unifiedReportId:X2}; needs custom KMDF filter — see PRD-184)");
            return -2;  // sentinel: known-inaccessible, distinguishable from -1 (not found)
        }

        // Neither pattern matched — not a recognized Apple Magic Mouse battery interface
        Logger.Log($"NO_BATTERY_TLC path={devicePath}");
        return -1;
    }

    // --- P/Invoke ---

    const uint FILE_SHARE_READ = 0x00000001;
    const uint FILE_SHARE_WRITE = 0x00000002;
    const uint OPEN_EXISTING = 3;
    const uint DIGCF_PRESENT = 0x02;
    const uint DIGCF_DEVICEINTERFACE = 0x10;
    const int HIDP_STATUS_SUCCESS = 0x00110000;
    static readonly IntPtr INVALID_HANDLE_VALUE = new(-1);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern SafeFileHandle CreateFile(string lpFileName, uint dwDesiredAccess,
        uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition,
        uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("hid.dll", SetLastError = true)]
    static extern bool HidD_GetInputReport(SafeFileHandle HidDeviceObject,
        byte[] ReportBuffer, int ReportBufferLength);

    [DllImport("hid.dll", SetLastError = true)]
    static extern bool HidD_GetFeature(SafeFileHandle HidDeviceObject,
        byte[] ReportBuffer, int ReportBufferLength);

    [DllImport("hid.dll")]
    static extern bool HidD_GetPreparsedData(SafeFileHandle HidDeviceObject,
        out IntPtr PreparsedData);

    [DllImport("hid.dll")]
    static extern bool HidD_FreePreparsedData(IntPtr PreparsedData);

    [DllImport("hid.dll")]
    static extern int HidP_GetCaps(IntPtr PreparsedData, ref HIDP_CAPS Capabilities);

    [DllImport("hid.dll")]
    static extern int HidP_GetValueCaps(int ReportType,
        [In, Out] HIDP_VALUE_CAPS[] ValueCaps,
        ref ushort ValueCapsLength, IntPtr PreparsedData);

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

    // HIDP_VALUE_CAPS — describes a single value field in a HID report.
    // Layout matches hidpi.h (Pack=4, total 96 bytes on x64). The Range/NotRange and
    // String/Designator/Data ranges share storage via union — we only need the first
    // members of each union (Usage, StringIndex, etc.). Padding fields preserve sizeof.
    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    struct HIDP_VALUE_CAPS
    {
        public ushort UsagePage;
        public byte ReportID;
        [MarshalAs(UnmanagedType.U1)] public bool IsAlias;
        public ushort BitField;
        public ushort LinkCollection;
        public ushort LinkUsage;
        public ushort LinkUsagePage;
        [MarshalAs(UnmanagedType.U1)] public bool IsRange;
        [MarshalAs(UnmanagedType.U1)] public bool IsStringRange;
        [MarshalAs(UnmanagedType.U1)] public bool IsDesignatorRange;
        [MarshalAs(UnmanagedType.U1)] public bool IsAbsolute;
        [MarshalAs(UnmanagedType.U1)] public bool HasNull;
        public byte Reserved;
        public ushort BitSize;
        public ushort ReportCount;
        public ushort Reserved1, Reserved2, Reserved3, Reserved4, Reserved5;
        public uint UnitsExp;
        public uint Units;
        public int LogicalMin, LogicalMax;
        public int PhysicalMin, PhysicalMax;
        // Range/NotRange union — when IsRange=false, Usage is in UsageMin slot
        public ushort Usage;       // [Range] UsageMin / [NotRange] Usage
        public ushort UsageMax;
        public ushort StringMin;
        public ushort StringMax;
        public ushort DesigMin;
        public ushort DesigMax;
        public ushort DataIdxMin;
        public ushort DataIdxMax;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct HIDP_CAPS
    {
        public ushort Usage;
        public ushort UsagePage;
        public ushort InputReportByteLength;
        public ushort OutputReportByteLength;
        public ushort FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)]
        public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps;
        public ushort NumberInputValueCaps;
        public ushort NumberInputDataIndices;
        public ushort NumberOutputButtonCaps;
        public ushort NumberOutputValueCaps;
        public ushort NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps;
        public ushort NumberFeatureValueCaps;
        public ushort NumberFeatureDataIndices;
    }
}
