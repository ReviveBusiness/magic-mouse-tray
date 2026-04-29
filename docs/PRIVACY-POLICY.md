# M12 Privacy Policy

**Status:** v1.0 (2026-04-28)
**Scope:** M12 KMDF lower filter driver (MagicMouseDriver.sys). Companion tray app is a separate component with a separate PRD and separate privacy documentation.

## BLUF

M12 collects nothing. All logging is local-only. Nothing is transmitted off-machine.

## What M12 logs (local only)

| Channel | What | Where | Retention |
|---|---|---|---|
| WPP ETW provider | Driver events (PnP, IOCTL, shadow buffer updates, errors) | Captured only when user runs `logman start M12 -p {8D3C1A92-B04E-4F18-9A23-7E5D4F892C12} -ets` | User-controlled; capture session only |
| DebugLevel=4 hex dumps | 46-byte RID=0x27 payloads (used for empirical offset confirmation) | WPP capture; OFF by default (DebugLevel default = 0) | User-controlled; requires explicit DebugLevel=4 registry write |
| Self-tuning learning state | Aggregate byte-position statistics (frame count + per-byte unique-value bitmaps) during first 5 min / 100 frames after install | In-driver memory (DEVICE_CONTEXT); result written to CRD config registry once at LEARNING mode exit; raw statistics discarded | Until next driver reinstall; CRD result persists until manually deleted |

## What M12 does NOT do

- No network connections of any kind
- No cloud upload or remote telemetry
- No anonymous usage telemetry to any vendor
- No analytics or instrumentation beyond local WPP
- No identifying information collected (no hostname, no user account, no hardware serial)
- No third-party SDKs or libraries with network access
- No crash reporting to external services

## How to disable all logging

Set DebugLevel to 0 (the default):

```
HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Parameters\DebugLevel = 0
```

WPP ETW capture is opt-in. The user must explicitly run `logman start ...` to capture anything. If no logman session is active, all WPP output is discarded by the OS.

DebugLevel=4 (hex dump mode) must also be explicitly set by the operator -- it is never the default.

## Self-tuning data specifics

During the first 5 minutes of use (or until 100 RID=0x27 input frames are captured), M12 maintains an aggregate statistical profile of which byte positions in the raw input report carry values consistent with a battery reading. This is a 3 KB in-memory bitmap (46 positions x 66 possible values). No raw frame data is retained; only the aggregate count of unique values per position.

At the end of learning, a single integer (the detected byte offset, 0-45) is written to:

```
HKLM\SYSTEM\CurrentControlSet\Services\MagicMouseM12\Devices\<HardwareKey>\BatteryByteOffset
```

The bitmap and per-frame statistics are discarded. No payload data, timestamps, or user-identifying information is stored anywhere.

## Companion tray app (separate)

The tray app (`MagicMouseTray.exe`) is a separate component governed by a separate PRD. Its privacy posture -- also local-only, no network, no telemetry -- is documented separately. The tray app reads battery percentage from M12 via `HidD_GetFeature` and writes only to a local debug log at `%APPDATA%\MagicMouseTray\debug.log`.

## License

M12 is MIT-licensed. See `LICENSE-M12` in the repository root. Source code is fully auditable.

## References

- `docs/M12-DESIGN-SPEC.md` Sec 6c (self-tuning algorithm), Sec 19 (WPP/ETW), Sec 25 (logging policy)
- `docs/M12-MOP.md` PRIVACY-1 sign-off checklist gate
