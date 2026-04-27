#Requires -Version 5.1
# mm-wheel-counter.ps1
# Captures WM_MOUSEWHEEL events for N seconds via a Win32 low-level mouse hook.
# Emits a JSON file with event_count and per-event timestamps + deltas.
#
# Usage:
#   mm-wheel-counter.ps1 [-DurationSec <int>] [-OutputJson <path>]
#
# Exit 0 on success, 1 on hook-install failure.
# Prints one line to stdout: [wheel-counter] captured N events to <path>
#
# NOTE: ASCII-only source (AP-08). No smart quotes, no em-dashes.
# Admin is NOT required; WH_MOUSE_LL works from user space.

param(
    [int]$DurationSec = 3,
    [string]$OutputJson = "$env:TEMP\wheel-events.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Win32 declarations via Add-Type (ASCII strings only -- AP-08)
# ---------------------------------------------------------------------------

$hookCode = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

namespace WheelCapture {

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSLLHOOKSTRUCT {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    public class WheelEvent {
        public long t_ms;
        public int delta;
        public int x;
        public int y;
    }

    public class HookManager {
        private const int WH_MOUSE_LL = 14;
        private const int WM_MOUSEWHEEL = 0x020A;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern IntPtr GetModuleHandle(string lpModuleName);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

        [DllImport("user32.dll")]
        private static extern bool TranslateMessage([In] ref MSG lpMsg);

        [DllImport("user32.dll")]
        private static extern IntPtr DispatchMessage([In] ref MSG lpMsg);

        [DllImport("user32.dll")]
        private static extern bool PostThreadMessage(uint idThread, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [StructLayout(LayoutKind.Sequential)]
        private struct MSG {
            public IntPtr hwnd;
            public uint message;
            public IntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public POINT pt;
        }

        private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

        private IntPtr _hookId = IntPtr.Zero;
        private LowLevelMouseProc _proc;
        private uint _msgThreadId;
        private const uint WM_QUIT = 0x0012;

        public readonly List<WheelEvent> Events = new List<WheelEvent>();
        public bool HookInstalled { get; private set; }

        // Use Stopwatch for elapsed ms -- compatible with .NET Framework 4.x (PS5)
        private System.Diagnostics.Stopwatch _sw;

        public void Run(int durationMs) {
            _proc = HookCallback;
            _sw = System.Diagnostics.Stopwatch.StartNew();

            IntPtr hMod = GetModuleHandle(null);
            _hookId = SetWindowsHookEx(WH_MOUSE_LL, _proc, hMod, 0);

            if (_hookId == IntPtr.Zero) {
                HookInstalled = false;
                return;
            }

            HookInstalled = true;
            _msgThreadId = GetCurrentThreadId();

            // Timer to post WM_QUIT after duration
            System.Threading.Timer timer = new System.Threading.Timer(
                _ => PostThreadMessage(_msgThreadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero),
                null, durationMs, System.Threading.Timeout.Infinite
            );

            MSG msg;
            while (GetMessage(out msg, IntPtr.Zero, 0, 0)) {
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }

            timer.Dispose();
            UnhookWindowsHookEx(_hookId);
        }

        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
            if (nCode >= 0 && wParam.ToInt32() == WM_MOUSEWHEEL) {
                MSLLHOOKSTRUCT hookStruct = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                // delta is the high WORD of mouseData (signed short)
                short delta = (short)((hookStruct.mouseData >> 16) & 0xFFFF);
                long t_ms = _sw.ElapsedMilliseconds;
                Events.Add(new WheelEvent {
                    t_ms = t_ms,
                    delta = (int)delta,
                    x = hookStruct.pt.x,
                    y = hookStruct.pt.y
                });
            }
            return CallNextHookEx(_hookId, nCode, wParam, lParam);
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $hookCode -Language CSharp
} catch {
    Write-Error "[wheel-counter] Add-Type failed: $_"
    exit 1
}

# ---------------------------------------------------------------------------
# Run the hook
# ---------------------------------------------------------------------------

$mgr = New-Object WheelCapture.HookManager
$mgr.Run($DurationSec * 1000)

if (-not $mgr.HookInstalled) {
    Write-Error "[wheel-counter] SetWindowsHookEx failed -- hook not installed."
    exit 1
}

# ---------------------------------------------------------------------------
# Build JSON output
# ---------------------------------------------------------------------------

$capturedAt = [System.DateTimeOffset]::Now.ToString("yyyy-MM-ddTHH:mm:sszzz")
$eventCount = $mgr.Events.Count

# Build events array manually (avoid ConvertTo-Json quirks with nested objects)
$eventsJson = ($mgr.Events | ForEach-Object {
    '    {"t_ms": ' + $_.t_ms + ', "delta": ' + $_.delta + ', "x": ' + $_.x + ', "y": ' + $_.y + '}'
}) -join ",`n"

$json = @"
{
  "captured_at": "$capturedAt",
  "duration_sec": $DurationSec,
  "event_count": $eventCount,
  "events": [
$eventsJson
  ]
}
"@

# Write UTF-8 without BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($OutputJson, $json, $utf8NoBom)

Write-Host "[wheel-counter] captured $eventCount events to $OutputJson"
exit 0
