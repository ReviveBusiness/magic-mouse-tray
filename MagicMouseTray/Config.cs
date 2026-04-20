using System.IO;
using Microsoft.Win32;

namespace MagicMouseTray;

// Persists user settings to %APPDATA%\MagicMouseTray\config.ini.
// Start-with-Windows is stored in HKCU Run registry key (not Startup folder)
// because ProcessPath is available without install and needs no shortcut logic.
internal sealed class Config
{
    static readonly string ConfigPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "MagicMouseTray", "config.ini");

    const string RunKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    const string AppName = "MagicMouseTray";

    internal int Threshold { get; private set; } = 20;
    internal bool StartWithWindows { get; private set; }

    internal static Config Load()
    {
        var cfg = new Config();
        if (!File.Exists(ConfigPath)) return cfg;

        foreach (var line in File.ReadAllLines(ConfigPath))
        {
            var eq = line.IndexOf('=');
            if (eq < 0) continue;
            var key = line[..eq].Trim();
            var val = line[(eq + 1)..].Trim();

            if (key == "threshold" && int.TryParse(val, out int t) && IsValid(t))
                cfg.Threshold = t;
            else if (key == "start_with_windows" && bool.TryParse(val, out bool s))
                cfg.StartWithWindows = s;
        }
        return cfg;
    }

    internal void SetThreshold(int value)
    {
        if (!IsValid(value)) return;
        Threshold = value;
        Persist();
        Logger.Log($"CONFIG threshold={value}");
    }

    internal void SetStartWithWindows(bool value)
    {
        StartWithWindows = value;
        Persist();
        ApplyStartup(value);
        Logger.Log($"CONFIG start_with_windows={value}");
    }

    static bool IsValid(int t) => t is 10 or 15 or 20 or 25;

    void Persist()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(ConfigPath)!);
            File.WriteAllLines(ConfigPath, [
                $"threshold={Threshold}",
                $"start_with_windows={StartWithWindows.ToString().ToLower()}"
            ]);
        }
        catch { }
    }

    static void ApplyStartup(bool enable)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            if (key is null) return;
            if (enable)
                key.SetValue(AppName, Environment.ProcessPath ?? string.Empty);
            else
                key.DeleteValue(AppName, throwOnMissingValue: false);
        }
        catch { }
    }
}
