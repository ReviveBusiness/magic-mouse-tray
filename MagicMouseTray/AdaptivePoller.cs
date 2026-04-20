// SPDX-License-Identifier: MIT
namespace MagicMouseTray;

// Polls MouseBatteryReader at adaptive intervals based on battery level.
// Tiers: >50%=2h  |  20-50%=30m  |  10-20%=10m  |  <10% or disconnected=5m
//
// BatteryChanged is raised from a thread-pool thread — callers must marshal
// to the UI thread before touching WPF/NotifyIcon objects (done in M4 TrayApp).
internal sealed class AdaptivePoller : IDisposable
{
    // (percent, deviceName) — percent is -1 when mouse is disconnected
    internal event Action<int, string>? BatteryChanged;

    CancellationTokenSource _cts = new();
    Task? _pollTask;

    internal void Start() => _pollTask = PollLoop(_cts.Token);

    // Cancels the current wait and polls immediately.
    // Safe to call from any thread.
    internal void RefreshNow()
    {
        var old = Interlocked.Exchange(ref _cts, new CancellationTokenSource());
        old.Cancel();
        old.Dispose();
        _pollTask = PollLoop(_cts.Token);
    }

    public void Dispose()
    {
        _cts.Cancel();
        try { _pollTask?.Wait(TimeSpan.FromSeconds(5)); } catch { }
        _cts.Dispose();
    }

    async Task PollLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            var (pct, name) = MouseBatteryReader.GetBatteryLevel();

            // Fire always — pct=-1 means disconnected; callers handle both cases
            BatteryChanged?.Invoke(pct, name);

            var interval = GetInterval(pct);
            Logger.Log($"POLL_SCHEDULED pct={pct} next_in={interval}");

            try { await Task.Delay(interval, ct); }
            catch (TaskCanceledException) { break; }
        }
    }

    // Returns the polling interval for a given battery %.
    // pct=-1 (disconnected) falls into the <10 tier — recheck frequently.
    internal static TimeSpan GetInterval(int pct) => pct switch
    {
        > 50  => TimeSpan.FromHours(2),
        >= 20 => TimeSpan.FromMinutes(30),
        >= 10 => TimeSpan.FromMinutes(10),
        _     => TimeSpan.FromMinutes(5),
    };
}
