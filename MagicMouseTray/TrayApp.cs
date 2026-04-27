// SPDX-License-Identifier: MIT
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MagicMouseTray;

// Manages the system tray icon, right-click menu, and battery change display.
// All UI updates are marshaled to the WPF dispatcher (NotifyIcon requires STA thread).
internal sealed class TrayApp : IDisposable
{
    readonly NotifyIcon _tray;
    readonly Config _config;
    readonly AdaptivePoller _poller;
    readonly ToolStripMenuItem[] _thresholdItems;
    readonly ToolStripMenuItem _startupItem;

    int _lastPct = -1;
    string _lastName = string.Empty;

    // Tracks which alert boundaries have already fired this drain cycle.
    // Boundaries: [user threshold, 10%]. Cleared when battery returns above threshold or disconnects.
    readonly HashSet<int> _firedBoundaries = new();

    // Persistent critical alert shown at 1%; auto-closed when mouse plugs in (pct=-1).
    CriticalAlert? _criticalAlert;

    readonly DriverStatus _driverStatus;

    Icon? _currentIcon;

    // Cached base image (loaded once from embedded resource)
    static Bitmap? _mouseOutline;   // magic-mouse.png — white fill, black border
    static readonly object _bitmapLock = new();

    internal TrayApp(Config config)
    {
        _config = config;
        (_thresholdItems, _startupItem) = (null!, null!); // assigned by BuildMenu

        _driverStatus = DriverHealthChecker.GetStatus();
        var menu = BuildMenu(out _thresholdItems, out _startupItem);

        _currentIcon = MakeIcon(-1, false, _driverStatus != DriverStatus.Ok);
        _tray = new NotifyIcon
        {
            Icon = _currentIcon,
            ContextMenuStrip = menu,
            Visible = true,
            Text = "Magic Mouse Battery — starting..."
        };

        _poller = new AdaptivePoller();
        _poller.BatteryChanged += OnBatteryChanged;
        _poller.Start();
    }

    ContextMenuStrip BuildMenu(
        out ToolStripMenuItem[] thresholdItems,
        out ToolStripMenuItem startupItem)
    {
        var menu = new ContextMenuStrip();

        // --- Low Battery Threshold submenu ---
        var thresholdMenu = new ToolStripMenuItem("Low Battery Threshold");
        thresholdItems = new[] { 10, 15, 20, 25 }.Select(t =>
        {
            var item = new ToolStripMenuItem($"{t}%")
            {
                Tag = t,
                Checked = t == _config.Threshold
            };
            item.Click += (_, _) => OnThresholdClick(t);
            return item;
        }).ToArray();
        thresholdMenu.DropDownItems.AddRange(thresholdItems);
        menu.Items.Add(thresholdMenu);

        // --- Start with Windows ---
        startupItem = new ToolStripMenuItem("Start with Windows")
        {
            Checked = _config.StartWithWindows
        };
        startupItem.Click += (_, _) =>
        {
            _config.SetStartWithWindows(!_config.StartWithWindows);
            _startupItem.Checked = _config.StartWithWindows;
        };
        menu.Items.Add(startupItem);

        menu.Items.Add(new ToolStripSeparator());

        // --- Driver warning (shown when scroll driver is missing, unbound, or unknown model) ---
        if (_driverStatus != DriverStatus.Ok)
        {
            var (label, url) = _driverStatus switch
            {
                DriverStatus.UnknownAppleMouse =>
                    ("⚠ Unknown mouse model — check for app update",
                     "https://github.com/ReviveBusiness/magic-mouse-tray/releases"),
                DriverStatus.NotBound =>
                    ("⚠ Driver not bound — scroll fix needed",
                     "https://github.com/ReviveBusiness/magic-mouse-tray#scroll-not-working"),
                _ =>
                    ("⚠ Install Apple Driver (scroll fix)",
                     "https://github.com/tealtadpole/MagicMouse2DriversWin11x64"),
            };
            var driverItem = new ToolStripMenuItem(label) { ForeColor = System.Drawing.Color.OrangeRed };
            driverItem.Click += (_, _) =>
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url)
                    { UseShellExecute = true });
            menu.Items.Add(driverItem);
            menu.Items.Add(new ToolStripSeparator());
        }

        // --- Refresh Now ---
        var refresh = new ToolStripMenuItem("Refresh Now");
        refresh.Click += (_, _) => _poller.RefreshNow();
        menu.Items.Add(refresh);

        // --- Test Notification (debug only) ---
        var testToast = new ToolStripMenuItem("Test Notification");
        testToast.Click += (_, _) =>
        {
            var dev = _lastName.Length > 0 ? _lastName : "Magic Mouse";
            ToastNotifier.Show(_lastPct >= 0 ? _lastPct : 15, dev);
        };
        menu.Items.Add(testToast);

        menu.Items.Add(new ToolStripSeparator());

        // --- Quit ---
        var quit = new ToolStripMenuItem("Quit");
        quit.Click += (_, _) =>
        {
            Dispose();
            System.Windows.Application.Current.Shutdown();
        };
        menu.Items.Add(quit);

        return menu;
    }

    void OnThresholdClick(int value)
    {
        _config.SetThreshold(value);
        foreach (var item in _thresholdItems)
            item.Checked = (int)item.Tag! == _config.Threshold;
    }

    void OnBatteryChanged(int pct, string name)
    {
        // Marshal to WPF/STA thread — NotifyIcon was created there
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            _lastPct = pct;
            if (!string.IsNullOrEmpty(name)) _lastName = name;

            bool isLow = pct >= 0 && pct < _config.Threshold;
            var device = _lastName.Length > 0 ? _lastName : "Magic Mouse";

            // Cascading alerts: fire at user threshold, then again at 10% critical boundary.
            // _firedBoundaries resets when battery recovers above threshold or disconnects.
            if (pct < 0 || pct >= _config.Threshold)
            {
                _firedBoundaries.Clear();
            }
            else
            {
                var boundaries = _config.Threshold > 10
                    ? new[] { _config.Threshold, 10 }
                    : new[] { _config.Threshold };

                foreach (var boundary in boundaries)
                {
                    if (pct < boundary && _firedBoundaries.Add(boundary))
                    {
                        ToastNotifier.Show(pct, device);
                        break; // one toast per poll cycle
                    }
                }
            }

            // Persistent critical alert at 1% — auto-closes when mouse plugs in (pct=-1)
            if (pct == 1 && _criticalAlert == null)
            {
                _criticalAlert = new CriticalAlert(pct, device);
                _criticalAlert.FormClosed += (_, _) => _criticalAlert = null;
                _criticalAlert.Show();
                Logger.Log($"CRITICAL_ALERT_SHOWN pct={pct}");
            }
            else if (pct < 0 && _criticalAlert != null)
            {
                _criticalAlert.Close();
                Logger.Log("CRITICAL_ALERT_CLOSED reason=charging");
            }

            // Update icon (badge dot in corner when driver not OK)
            var newIcon = MakeIcon(pct, isLow, _driverStatus != DriverStatus.Ok);
            var oldIcon = _currentIcon;
            _tray.Icon = newIcon;
            _currentIcon = newIcon;
            oldIcon?.Dispose();

            // Update tooltip (max 63 chars — Windows limit).
            // pct=-1 means disconnected (no Apple Magic Mouse path responded).
            // pct=-2 means inaccessible (path found, Apple driver in unified-mode trapping
            // Feature Report 0x47 behind mouhid exclusivity — see PRD-184 / MouseBatteryReader).
            var interval = AdaptivePoller.GetInterval(pct);
            var pctStr = pct switch {
                >= 0 => $"{pct}%",
                -2   => "battery N/A",
                _    => "disconnected",
            };
            var baseTip = $"{device} - {pctStr} · Next: {FormatInterval(interval)}";
            var tip = _driverStatus != DriverStatus.Ok ? $"⚠ Driver | {baseTip}" : baseTip;
            _tray.Text = tip.Length > 63 ? tip[..63] : tip;

            Logger.Log($"TRAY_UPDATE pct={pct} isLow={isLow} tooltip=\"{_tray.Text}\"");
        });
    }

    static string FormatInterval(TimeSpan t)
        => t.TotalHours >= 1 ? $"{(int)t.TotalHours}h" : $"{(int)t.TotalMinutes}m";

    public void Dispose()
    {
        _poller.BatteryChanged -= OnBatteryChanged;
        _poller.Dispose();
        _criticalAlert?.Close();
        _tray.Visible = false;
        _tray.Dispose();
        _currentIcon?.Dispose();
    }

    // --- Icon generation ---
    // Loads the Magic Mouse outline PNG from embedded resources and tints it by battery level.
    // White interior pixels become the tier color; black border pixels stay black.
    // Falls back to the simple battery-bar if the resource is missing.
    //
    // Tint colors (applied via ColorMatrix — white→color, black stays black):
    //   disconnected (-1)  → gray
    //   below threshold    → orange-red
    //   >50%               → green
    //   ≥20%               → yellow
    //   ≥10%               → orange
    //   <10%               → red

    [DllImport("user32.dll")]
    static extern bool DestroyIcon(IntPtr hIcon);

    static Bitmap? LoadEmbedded(string name)
    {
        try
        {
            var stream = Assembly.GetExecutingAssembly()
                .GetManifestResourceStream($"MagicMouseTray.{name}");
            return stream is null ? null : new Bitmap(stream);
        }
        catch { return null; }
    }

    static Bitmap? GetOutline()
    {
        if (_mouseOutline != null) return _mouseOutline;
        lock (_bitmapLock)
        {
            _mouseOutline ??= LoadEmbedded("magic-mouse.png");
            return _mouseOutline;
        }
    }

    static Icon MakeIcon(int pct, bool isLow, bool driverMissing = false)
    {
        using var bmp = new Bitmap(16, 16, PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp);
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.Clear(Color.Transparent);

        var (r, gv, b) = TintColor(pct, isLow);
        var baseImg = GetOutline();

        if (baseImg != null)
        {
            // ColorMatrix: white→tint color, black stays black, alpha preserved
            using var ia = new ImageAttributes();
            ia.SetColorMatrix(new ColorMatrix(new float[][]
            {
                new float[] { r,   0f,  0f, 0f, 0f },
                new float[] { 0f, gv,   0f, 0f, 0f },
                new float[] { 0f,  0f,  b,  0f, 0f },
                new float[] { 0f,  0f,  0f, 1f, 0f },
                new float[] { 0f,  0f,  0f, 0f, 1f },
            }));
            g.DrawImage(baseImg,
                new Rectangle(0, 0, 16, 16),
                0, 0, baseImg.Width, baseImg.Height,
                GraphicsUnit.Pixel, ia);
        }
        else
        {
            // Fallback: simple colored rectangle if resource missing
            using var fb = new SolidBrush(Color.FromArgb(
                (int)(r * 255), (int)(gv * 255), (int)(b * 255)));
            g.FillRectangle(fb, 1, 1, 14, 14);
        }

        // Driver-missing badge: 3×3 yellow dot in top-right corner
        if (driverMissing)
        {
            using var dot = new SolidBrush(Color.FromArgb(255, 220, 30));
            g.FillRectangle(dot, 13, 0, 3, 3);
        }

        var hIcon = bmp.GetHicon();
        var icon = (Icon)Icon.FromHandle(hIcon).Clone();
        DestroyIcon(hIcon);
        return icon;
    }

    static (float R, float G, float B) TintColor(int pct, bool isLow) => (pct, isLow) switch
    {
        (-1, _)       => (0.65f, 0.65f, 0.65f),  // gray — disconnected
        (_, true)     => (1.0f,  0.25f, 0.05f),  // orange-red — below threshold
        ( > 50, _)    => (0.25f, 1.0f,  0.25f),  // green
        ( >= 20, _)   => (1.0f,  1.0f,  0.1f),   // yellow
        ( >= 10, _)   => (1.0f,  0.55f, 0.0f),   // orange
        _             => (1.0f,  0.15f, 0.15f),  // red — critical
    };
}
