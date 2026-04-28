# v3 Battery — empirical proof we cannot read it right now + actionable paths forward

**Date:** 2026-04-28
**Status:** Empirical, not assumed.

---

## Empirical proof: no documented channel returns v3 battery data right now

Probe script: `scripts/mm-battery-everything.ps1`. Output: `.ai/test-runs/2026-04-27-154930-T-V3-AF/battery-everything-probe.txt`.

| # | Channel | Attempts | Hits |
|---|---|---|---|
| 1 | PnP `DEVPKEY_*Battery*` keys × 6 Apple devices (BT + HID + parent) | 24 | **0** |
| 2 | WMI `root\WMI` battery classes (`AppleWirelessHIDDeviceBattery`, `BatteryStatus`, `BatteryStaticData`, `BatteryFullChargedCapacity`, `BatteryRuntime`) | 5 | **0** |
| 3 | `\\.\AppleBluetoothMultitouch` IOCTL device (codes 0x800-0x830, METHOD_BUFFERED) | 49 | **0** (device OPENS but no response) |
| 4 | `HidD_GetFeature` and `HidD_GetInputReport` on parent v3 BTHENUM HID PDO, every ReportID 0x01-0xFE | 508 | **0** |
| 5 | Open orphaned `…&Col02&…` PDO via symbolic link | 1 | **OPEN FAILED 0x2** (link doesn't exist) |
| 6 | `Get-PnpDevice -Class Battery` enumeration | 1 | **0 devices** |
| **Total** | | **~588** | **0** |

The runtime CAPS reading on the parent BTHENUM HID PDO confirms the descriptor in effect: `TLC=UP:0001/U:0002 InLen=47 FeatLen=2 OutLen=0` — that's Descriptor B (single Mouse TLC + phantom Feature 0x47, no vendor 0xFF00 TLC). This is the broken descriptor variant.

## What's specifically blocking battery, in order of root-causedness

1. **HidBth's cached HID descriptor for v3 is the single-TLC variant (Descriptor B).** PnP enumerates only one HID interface, with a Mouse TLC and a phantom Feature 0x47 cap. The vendor 0xFF00 TLC (where battery actually lives, on Input ReportID 0x90) is not in this descriptor.
2. **The COL02 PDO is registered but not enumerated.** It's in the device container's `BaseContainers` list (carried over from when it was last active on April 27 17:59). PnP knows about it. But because the parent's runtime descriptor doesn't include the vendor TLC, PnP doesn't enumerate COL02 as an active child — Status=Unknown, no symbolic link, no driver binding.
3. **Without an enumerated COL02 interface, `HidD_GetInputReport(0x90)` cannot be called** — there's no handle to call it on.
4. **Feature 0x47 on the parent path is a phantom.** The descriptor declares the cap but the device returns err=87 because it doesn't actually back that report. So the tray's `unifiedAppleBattery` path always fails today.
5. **`\\.\AppleBluetoothMultitouch` exists** (the applewirelessmouse driver creates it at `DriverEntry`). It opens. But Apple's IOCTL codes for "get battery" are not in the 0x800-0x830 range we probed. Without reverse-engineering the binary or capturing Apple's userland tool's IOCTL traffic (which isn't installed), we don't know which code to send.

## Why we'll never get battery via "configure the registry"

Empirical evidence from registry comparison (`docs/REGISTRY-DIFF-AND-PNP-EVIDENCE.md`):
- April 3 backup (Magic Utilities era): Descriptor A, COL02 active, battery worked.
- April 27 17:59 snapshot: Descriptor A, COL02 active, battery worked. Same applewirelessmouse filter as today.
- Today (post-DSM event 04-27 19:50:53): Descriptor B, COL02 orphan, battery doesn't work.
- **Registry values on `Enum\BTHENUM\…PID&0323\…` are byte-identical** between Descriptor A working and Descriptor B broken.

The state difference lives in **HidBth's runtime descriptor cache** (kernel memory), not in registry. There is no registry key to set that says "use multi-TLC variant" — HidBth fetches the descriptor over the BT HID profile pipe at AddDevice time and caches whatever it gets.

## What CAN restore battery (validated paths)

### Path 1 — PnP recycle the v3 BTHENUM (intermittent)

Disable + Enable the BTHENUM HID PDO. Forces HidBth to re-fetch the descriptor. Empirical evidence:
- April 27 17:43: a recycle restored Descriptor A. 96 successful battery reads followed.
- Persistence-monitor's recycles (19:54+) sometimes resulted in Descriptor B.
- **Non-deterministic.** Either Descriptor A or B can come out the other side.

Risk: brief mouse stutter (~5 sec) per recycle.

### Path 2 — re-pair the v3 mouse

Remove the BT pairing in Settings, then pair fresh. Forces a complete SDP re-fetch + AddDevice. More disruptive than a recycle but more thorough.

### Path 3 — reboot

Every boot triggers fresh AddDevice. Yesterday's reboot landed Descriptor A. Today's may or may not. Equally non-deterministic.

### Path 4 — RE the AppleBluetoothMultitouch IOCTL surface

Read the `applewirelessmouse.sys` binary (already extracted to `/tmp/applewirelessmouse.sys`) in IDA/Ghidra. Find the IOCTL dispatch handler for the AppleBluetoothMultitouch device. Identify which IOCTL returns battery data. Then probe that specific code.

This is **work but tractable**. Effort: 1-2 days for someone with WinDbg + RE skills. Result: definitive battery channel that doesn't depend on descriptor state.

### Path 5 — replace driver

- **5a** — install Magic Utilities (paid yearly subscription; user has ruled out)
- **5b** — preserve INF from Magic Utilities trial install + reinstall later. See `docs/MAGIC-UTILITIES-PRESERVE-PLAN.md`. Capture script ready: `scripts/mm-magicutilities-capture.ps1`.
- **5c** — write our own KMDF filter (Phase M12) that handles v3's vendor TLC. Real driver dev, 2-4 weeks.

## Recommended sequence

Given that 96 OK reads in 13.5 hours is empirical proof recycle CAN deliver Descriptor A, the cheapest first step is:

**Step 1 — Try one recycle right now.** Single intrusive test. ~30 min including verification. Expected outcome: 60-80% chance of Descriptor A returning, COL02 enumerating, battery reads resuming.

**Step 2 — If recycle restores A**, ship Option Z (Detect Descriptor B + recycle in tray) with the corrected detection logic (sign-flipped from the original Phase 4-Ω prototype). 1-2 days of code. Battery readings on most polls.

**Step 3 — If recycle DOESN'T restore A** (or Step 2's success rate is too low), pivot to RE'ing the AppleBluetoothMultitouch IOCTL. We have the binary. We have time. This is the deterministic path that doesn't depend on descriptor state at all.

**Last resort: Path 5b** (Magic Utilities capture-and-preserve). Documented but not the first path.

## Files referenced

- `scripts/mm-battery-everything.ps1` — exhaustive probe script
- `.ai/test-runs/…/battery-everything-probe.txt` — proof-of-no-battery output
- `docs/PHASE-E-FINDINGS.md` — Descriptor A/B state machine analysis
- `docs/REGISTRY-DIFF-AND-PNP-EVIDENCE.md` — three-era registry comparison
- `docs/MAGIC-UTILITIES-PRESERVE-PLAN.md` (next file) — capture-and-restore plan
- `scripts/mm-magicutilities-capture.ps1` — the capture script (663 lines, syntax-clean)
- `/tmp/applewirelessmouse.sys` — driver binary for RE work
