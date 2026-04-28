// SPDX-License-Identifier: MIT
// SelfHealManager.cs — Phase 4-Ω detection + recycle trigger logic.
//
// Detects the split-mode degradation (filter inert) and triggers a PnP recycle
// of the BTHENUM HID device via the SelfHealRequest helper. Cooldowns prevent
// recycle loops if degradation reproduces immediately.
//
// Detection signal (already produced by MouseBatteryReader.GetBatteryLevel):
//   pct ==  -2  -> unified mode (filter active, scroll synth working)  -> healthy, do nothing
//   pct >=   0  -> split mode (filter inert, battery readable)         -> trigger recycle
//   pct ==  -1  -> mouse disconnected                                  -> do nothing
//
// State machine:
//   Healthy        -- pct=-2 observed at least once recently
//   DegradedNoticed -- pct>=0 observed once; arming
//   Recycling       -- recycle request dispatched; waiting for next poll
//   Failed          -- post-recycle poll still shows pct>=0; cooldown 30 min before retry
//
// Cooldown prevents recycle storms; max one recycle attempt per 5 min.

namespace MagicMouseTray;

internal sealed class SelfHealManager
{
    enum State { Healthy, DegradedNoticed, Recycling, Failed }

    static readonly TimeSpan CooldownAfterSuccess = TimeSpan.FromMinutes(5);
    static readonly TimeSpan CooldownAfterFailure = TimeSpan.FromMinutes(30);
    static readonly TimeSpan WaitForRecycleSettle = TimeSpan.FromSeconds(45);

    State _state = State.Healthy;
    DateTime _cooldownUntil = DateTime.MinValue;
    DateTime _lastRecycleAttempt = DateTime.MinValue;
    int _consecutiveSplitObservations = 0;

    readonly AdaptivePoller _poller;
    readonly Config _config;

    internal SelfHealManager(AdaptivePoller poller, Config config)
    {
        _poller = poller;
        _config = config;
        _poller.BatteryChanged += OnBatteryObserved;
    }

    void OnBatteryObserved(int pct, string name)
    {
        // -1 = disconnected, ignore for self-heal purposes
        if (pct == -1)
        {
            _state = State.Healthy;
            _consecutiveSplitObservations = 0;
            return;
        }

        // -2 = unified mode (filter active) — healthy state
        if (pct == -2)
        {
            if (_state == State.Recycling)
            {
                Logger.Log("SELFHEAL recycle SUCCEEDED — device returned to unified mode");
                _state = State.Healthy;
                _cooldownUntil = DateTime.UtcNow + CooldownAfterSuccess;
            }
            else if (_state != State.Healthy)
            {
                _state = State.Healthy;
            }
            _consecutiveSplitObservations = 0;
            return;
        }

        // pct >= 0 = split mode (filter inert)
        _consecutiveSplitObservations++;
        Logger.Log($"SELFHEAL split mode observed (consecutive={_consecutiveSplitObservations}) state={_state}");

        // If we just attempted a recycle and we're STILL in split, give up for a while
        if (_state == State.Recycling)
        {
            Logger.Log("SELFHEAL recycle FAILED — still split after attempt; cooldown 30 min");
            _state = State.Failed;
            _cooldownUntil = DateTime.UtcNow + CooldownAfterFailure;
            return;
        }

        // Respect cooldown
        if (DateTime.UtcNow < _cooldownUntil)
        {
            Logger.Log($"SELFHEAL split observed but cooldown active until {_cooldownUntil:o}");
            return;
        }

        // Don't recycle on first observation; wait for at least 2 consecutive
        // observations to avoid false positives from transient PnP glitches.
        if (_consecutiveSplitObservations < 2)
        {
            _state = State.DegradedNoticed;
            Logger.Log("SELFHEAL armed; will trigger recycle if next poll also shows split");
            return;
        }

        // Trigger recycle
        Logger.Log($"SELFHEAL triggering BTHENUM recycle for device {name}");
        _state = State.Recycling;
        _lastRecycleAttempt = DateTime.UtcNow;

        var ok = SelfHealRequest.RequestRecycle();
        if (!ok)
        {
            Logger.Log("SELFHEAL recycle request FAILED to dispatch");
            _state = State.Failed;
            _cooldownUntil = DateTime.UtcNow + CooldownAfterFailure;
            return;
        }

        // Schedule a follow-up poll in ~45 sec to verify the recycle worked
        _ = ScheduleVerificationPoll();
    }

    async Task ScheduleVerificationPoll()
    {
        await Task.Delay(WaitForRecycleSettle);
        Logger.Log("SELFHEAL post-recycle verification poll");
        _poller.RefreshNow();
    }

    public void Dispose()
    {
        _poller.BatteryChanged -= OnBatteryObserved;
    }
}
