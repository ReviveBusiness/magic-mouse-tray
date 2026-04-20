using Microsoft.Win32;

namespace MagicMouseTray;

// Checks whether the AppleWirelessMouse64 driver service is registered.
// Without it, the mouse connects but scroll doesn't work.
internal static class DriverHealthChecker
{
    const string ServiceKey = @"SYSTEM\CurrentControlSet\Services\AppleWirelessMouse";

    internal static bool IsDriverInstalled()
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(ServiceKey, writable: false);
            var ok = key != null;
            Logger.Log($"DRIVER_CHECK installed={ok}");
            return ok;
        }
        catch (Exception ex)
        {
            Logger.Log($"DRIVER_CHECK_FAILED err={ex.Message}");
            return false;
        }
    }
}
