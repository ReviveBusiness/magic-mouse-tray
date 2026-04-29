# Phase E — Empirical evidence plan (no-assumptions audit)

**Status:** awaiting user approval before any state change.
**Goal:** prove every claim that goes into the PRD update with measured data, separating fact from inference.

---

## A. What is actually proven (measured)

| # | Claim | Evidence | File |
|---|---|---|---|
| F1 | v1 Magic Mouse battery = 100% via standard HID Feature 0x47 | Tray log line `OK ... vid&...&pid&030d ... battery=100% (unified Feature 0x47)` at 09:33:47 | `~/AppData/Roaming/MagicMouseTray/debug.log` |
| F2 | v1 mouse user-perceptible scroll WORKS in current configuration | User-reported 2026-04-28 morning | (verbal) |
| F3 | v3 Magic Mouse battery readout fails today (Feature 0x47 err=87) | Tray log line `FEATURE_BLOCKED ... err=87` every poll cycle | tray debug.log |
| F4 | v3 mouse user-perceptible scroll WORKS in current configuration | User-reported 2026-04-27 evening | (verbal) |
| F5 | `applewirelessmouse` service status = Running, StartType = Manual | bt-stack-snapshot.txt | `bt-stack-snapshot.txt` |
| F6 | v3 BTHENUM HID PDO has NO LowerFilters | bt-stack-snapshot.txt | `bt-stack-snapshot.txt` |
| F7 | v1 BTHENUM HID PDO has NO LowerFilters | bt-stack-snapshot.txt | `bt-stack-snapshot.txt` |
| F8 | Keyboard BTHENUM HID PDO has LowerFilters = `applewirelessmouse` | bt-stack-snapshot.txt | `bt-stack-snapshot.txt` |
| F9 | v1 SDP cache descriptor declares Mouse TLC + Feature 0x47 (UP=0x06) + Vendor 0xFF02 | descriptor decode | `multi-device-cache-comparison.md` |
| F10 | v3 SDP cache descriptor declares Mouse TLC + Vendor 0xFF00 (RID=0x90) + Vendor 0xFF02 — **NO Feature 0x47** | descriptor decode | `multi-device-cache-comparison.md` |
| F11 | Keyboard SDP cache descriptor declares Keyboard TLC + Consumer TLC + Feature 0x47 + vendor pages | descriptor decode | `multi-device-cache-comparison.md` |
| F12 | AirPods Pro = pure audio profile (A2DP/HFP/AVRCP/GATT/AAP); no HID | bthport-discovery + battery-probe | `multi-device-analysis.md` |
| F13 | BTHENUM Disable+Enable PnP recycle reliably flips filter binding state | exp-a-recycle | `exp-a-recycle/finding.md` |
| F14 | Post-recycle State A persists ≥65 min idle | persistence-monitor.log | `exp-a-recycle/persistence-monitor.log` |
| F15 | Win32 PnP/WMI APIs do NOT surface battery for any of the 3 BT HID devices | bt-battery-probe.txt | `bt-battery-probe.txt` |
| F16 | mm-tray.exe (PID 24340) holds long-lived HID handle on v3 mouse | running process + log polling | `debug.log` |

## B. What we have been assuming (NOT yet measured)

| # | Assumption | Where it appears in our docs | What we'd need to confirm |
|---|---|---|---|
| A1 | v1 scroll depends on `applewirelessmouse` driver being loaded into kernel (via keyboard's stale ref) | `multi-device-analysis.md` "global hook" theory | E1: Stop service, retry scroll |
| A2 | The tray's "Apple driver traps Feature 0x47" log message accurately describes what's happening on v3 | `MouseBatteryReader.cs` log text | E6: source audit + bench test |
| A3 | err=87 on v3 means "filter trapped" (vs. "report ID not in descriptor") | tray log + PRD-184 narrative | E5 — already inferable but worth recording: descriptor F10 says no 0x47, so err=87 IS just "doesn't exist" — **claim is mis-attributed** |
| A4 | Phase 4-Ω recycle restores BOTH scroll AND battery on v3 | Phase 4-Ω plan | E4: recycle, observe both signals |
| A5 | Keyboard battery would be readable via HidD_GetFeature(0x47) — descriptor declares it | descriptor decode | E3: actually call HidD_GetFeature on keyboard |
| A6 | v3 mouse Feature 0x90 is readable when filter is bound | PRD-184 narrative | E5b: filter bound, attempt 0x90 read |
| A7 | Filter binding to v3 stack = scroll synth + battery translation; no binding = no synth no battery | PRD-184 state machine | E2: Stop service, retry v3 scroll |

## C. Empirical tests to run (rollback included)

Each test is reversible. Run in order; halt if any unexpected state change.

### E1 — v1 mouse: Stop-Service test
- **Goal:** Determine source of v1 scroll synthesis.
- **Steps:**
  1. Capture pre-state: bt-stack-snapshot, tray log tail.
  2. `Stop-Service applewirelessmouse -Force`.
  3. Wait 5 sec.
  4. User: try scrolling v1 mouse in Notepad. Does it scroll? Y/N.
  5. Capture state during stopped: bt-stack-snapshot.
  6. `Start-Service applewirelessmouse`.
  7. Verify post-state matches pre-state.
- **Rollback:** Start-Service.
- **Expected discriminator:**
  - Scroll fails → driver does global synth.
  - Scroll persists → not driver dependency; Windows or per-device path.
- **Risk:** stopped service may briefly de-bind keyboard's filter. Restart returns it.

### E2 — v3 mouse: Stop-Service test
- **Goal:** Same question for v3 mouse (currently no filter on stack but scroll works).
- **Steps:** Same as E1, with user testing v3 mouse instead of v1.
- **Expected discriminator:** Same logic.
- **Run combined with E1** if user is willing — single Stop / both-mouse test / Start.

### E3 — Keyboard battery: direct HidD_GetFeature(0x47) read
- **Goal:** Confirm A5 (keyboard descriptor's Feature 0x47 is readable).
- **Method options:**
  - **E3a:** Tiny console exe that takes a HID device interface path + report ID and writes the result. Avoids tray's exclusive-handle issue.
  - **E3b:** Stop the tray briefly, run the existing `mm-hid-feature-read.ps1`, restart tray. Filter the script to keyboard COL01 path only (skip COL02/03 to avoid the consumer-control wedge).
- **Risk:** E3b requires tray exit/restart; minor. E3a needs ~50 LOC of C#.
- **Recommend E3b** — fastest path with existing tooling.

### E4 — v3 mouse: BTHENUM recycle + battery follow-through
- **Goal:** Confirm A4 (recycle puts filter on v3 stack AND battery becomes readable).
- **Steps:**
  1. Capture pre-state: bt-stack-snapshot (expect no LowerFilter on v3), tray log shows err=87.
  2. Run `mm-state-flip.ps1 -Mode AppleFilter` via the queue (existing recycle path).
  3. Wait 30 sec for PnP settle.
  4. Capture post-state: bt-stack-snapshot. Expect v3 BTHENUM PDO now has LowerFilter=`applewirelessmouse`.
  5. Wait for next tray poll (5 min) OR force RefreshNow via tray IPC.
  6. Read tray log: does it now log `OK ... vid&...&pid&0323 ... battery=N% (unified Feature 0x90)` or similar? Or err?
- **Rollback:** Recycle again to revert to State A if user wants the previous state.
- **Expected discriminator:**
  - Battery returns → A4 confirmed; Phase 4-Ω is the right architecture.
  - Battery does NOT return → A4 wrong; need different translation path (cache patch, custom KMDF, userland daemon).

### E5 — Filter-bound vs filter-unbound Feature 0x47 + 0x90 reads on v3
- **Goal:** Disambiguate A2/A3 (does the filter trap 0x47 or just doesn't expose it?).
- **Method:**
  - With filter bound: stop tray, run probe, try Feature 0x47 (expect err=87 since descriptor doesn't declare it OR a real value if filter exposes it) and 0x90 (expect data).
  - With filter unbound: same, expect 0x47 err=87 (correct interpretation = "report not declared") and 0x90 err.
- **Discriminator:** Whether "Apple driver traps" claim in tray log is accurate or should be reworded.

### E6 — Source code audit of MouseBatteryReader log strings
- **Goal:** Verify the diagnostic messages in the tray match measured reality.
- **Method:** read `MouseBatteryReader.cs`. List every log line + its trigger condition. Cross-reference with measured F1/F3.
- **No state change.**

### E7 — applewirelessmouse DriverEntry side-effects
- **Goal:** Understand WHAT the loaded driver actually does (registers hooks? WMI providers? PnP filter callbacks?).
- **Method:**
  - Method A: Run sysinternals `loadord` / `kdmp` to inspect kernel callbacks installed by the driver.
  - Method B: Boot ETW trace (`Microsoft-Windows-Kernel-Power`, `Microsoft-Windows-Kernel-PnP`, `Microsoft-Windows-DriverFrameworks-UserMode`) capturing driver init.
  - Method C: Static analysis of `applewirelessmouse.sys` (78 KB) — strings, imports, exported callbacks. Less invasive.
- **No state change.** Method C first; A/B only if C is inconclusive.

### E8 — Tray's running handle reproducer
- **Goal:** Confirm F16 (tray blocks our standalone probe).
- **Method:** Stop mm-tray.exe → run `mm-hid-feature-read.ps1` → confirm reads succeed → restart tray.
- **Rollback:** Restart tray (existing startup-repair.ps1).

---

## D. Proposed run order

1. **E6** — read source. No state change. Tells us what the tray's claims actually mean.
2. **E7 (Method C)** — static-inspect `applewirelessmouse.sys` strings/imports. No state change.
3. **E8 + E3b** — stop tray briefly, run keyboard + v1 + v3 Feature reads via the standalone probe. Restart tray.
4. **E1 + E2 combined** — single Stop-Service of `applewirelessmouse`, user tries scrolling v1 and v3, restart service.
5. **E4** — recycle v3 BTHENUM, observe filter bind + tray battery on v3.
6. **E5** — by this point have most of the data; finalize the trap-vs-not-declared question.

Tests 1–3 are no-state-change or quick-bounce; should all run in <5 minutes total.
Tests 4–6 are state-changing; do them sequentially with snapshots.

## E. Decision points after data collection

After Phase E, we'll know:
- Whether v3 needs filter on stack to surface battery (A4 / E4).
- Whether v1+v3 scroll depends on the loaded service vs. per-stack binding (E1 + E2).
- Whether Phase 4-Ω alone delivers user goal "scroll + battery on v3" or whether we need additional pieces.
- What the keyboard battery state actually is.
- What the tray's diagnostic messages should be reworded to.

## F. Files this will produce

```
.ai/test-runs/2026-04-27-154930-T-V3-AF/
├── phase-e/
│   ├── E1-v1-stop-service.txt          # E1 results
│   ├── E2-v3-stop-service.txt          # E2 results
│   ├── E3-keyboard-feature-read.txt    # keyboard battery byte
│   ├── E4-v3-recycle-followthrough.md  # full cycle including tray battery observation
│   ├── E5-filter-bound-vs-unbound.md
│   ├── E6-tray-log-string-audit.md
│   ├── E7c-applewirelessmouse-sys-static.txt
│   └── E8-handle-block-reproducer.txt
└── PHASE-E-FINDINGS.md                 # consolidated findings, BLUF for PRD update
```

## G. Approval needed

**Approve to proceed?** Y/N — and any changes to test order or scope.

If approved I'll execute E6 + E7c (read-only) immediately and pause before E1 (first state-changing step).

---

# Phase E.2 — Passive proofs for the post-research headlines (2026-04-28 PM)

After the NotebookLM 150-source synthesis (`docs/research-findings.md`), four headlines need empirical anchoring **before** any state-changing test. Every test in this section is **PASSIVE** — no PnP changes, no service starts/stops, no registry writes, no device disables. We collect data, then decide whether intrusive tests are still needed.

## H. Headlines and their passive proofs

| # | Headline | How we prove it without state change |
|---|---|---|
| H1 | v3 battery is on **Input 0x90 byte 1** of vendor TLC (UP=0xFF00, U=0x14) | E9 + E14 + E15 + E16 |
| H2 | The Apple filter previously mutated v3's HID descriptor; HidBth still serves the mutated copy | E9 + E12 (compare runtime to SDP cache; verify vendor TLC is NOT enumerated as a child PDO) |
| H3 | v1 mouse + Apple Keyboard battery on standard Feature 0x47 byte 1 | Already proven for v1 (tray log F1). E10 captures runtime descriptor + cap walk for keyboard. |
| H4 | AirPods Pro battery is in BLE Advertisement (0x004C, 0x07 prefix, byte 6 nibbles) | **E11** — passive WinRT BluetoothLEAdvertisementWatcher capture |
| H5 | Polling cadence: faster than 15-min poll causes scroll stutter | E13 — analyse tray's debug.log for cadence + cross-check with reported scroll-stutter symptoms |
| H6 | INF v6.2.0.0 binds filter to v3 PID 0x0323; binding lost because v3 was paired before the INF arrived | E17 — registry sweep for the v3's per-device install record + INF install date vs first-pair date |

## I. Passive tests to add (E9 → E17)

### E9 — v3 LIVE HID descriptor capture (passive read)
- **Goal:** prove H1+H2 by comparing the runtime descriptor (what HidBth currently serves) against the SDP cache (what we already decoded).
- **Method:** open the v3 mouse HID interface with `dwDesiredAccess=0` (no I/O perms — same trick `MouseBatteryReader` uses), call `HidD_GetPreparsedData`, walk the preparsed bytes, dump the FULL descriptor (every Main/Global/Local item with its bSize/bType/bTag).
- **Risk:** none — read-only. The tray already does this every poll; we're just dumping the result.
- **Output:** `descriptor-runtime-v3.txt` (decoded items) + `descriptor-runtime-v3.bin` (raw bytes).
- **Discriminator:**
  - Runtime descriptor has Feature 0x47 in Mouse TLC AND vendor 0xFF00 TLC missing → mutation confirmed.
  - Runtime == SDP cache → mutation hypothesis disproven; need different explanation for tray's err=87.

### E10 — v1 mouse + keyboard runtime descriptors (passive)
- **Goal:** prove H3 (v1 + keyboard battery is real Feature 0x47) by capturing live descriptors.
- **Method:** same as E9, but for v1 mouse and keyboard COL01 paths (the latter may wedge on `\kbd` suffix; if so, fall back to the SDP cache descriptor only).
- **Output:** `descriptor-runtime-v1.txt`, `descriptor-runtime-keyboard.txt`.

### E11 — BLE Advertisement passive capture (NEW — H4)
- **Goal:** prove AirPods Pro battery is exposed in BLE manufacturer data without ANY connection.
- **Method:** WinRT `Windows.Devices.Bluetooth.Advertisement.BluetoothLEAdvertisementWatcher` running for ~60 seconds. Filter: AD Type 0xFF (Manufacturer Specific Data), Company ID 0x004C, prefix byte 0x07. Capture all matching packets with raw bytes + RSSI + timestamp. Decode bytes 6 (left/right pod nibbles) and 7 (case nibble + flags).
- **Risk:** none — passive listener, no connection. May see neighbour Apple devices too (filter by RSSI to identify user's own AirPods).
- **Output:** `ble-advertisement-capture.json` — array of `{timestamp, rssi, mac, raw_hex, decoded_pods, decoded_case, charging_flags}` records.
- **Discriminator:**
  - Stable nibbles for some advertisements + match to user's iPhone display → AirPods battery confirmed in BLE adv.
  - No 0x004C 0x07 packets at all → maybe AirPods only broadcast when in/near case lid event; need different timing.

### E12 — v3 mouse PnP child enumeration (passive)
- **Goal:** prove H2 — the vendor 0xFF00 TLC is NOT currently enumerated as a separate HID child PDO of the v3 BTHENUM device. (The previous mutation stripped it.)
- **Method:** `Get-PnpDevice` walk from BTHENUM v3 PDO down all children. Tabulate which TLCs are present.
- **Risk:** none — read-only PnP query.
- **Output:** `v3-pnp-tree.txt`.
- **Discriminator:**
  - Only Mouse TLC child enumerated → mutation took the vendor TLCs away.
  - Mouse + vendor 0xFF00 + vendor 0xFF02 children all enumerated → descriptor is whole; tray's open is wrong path; not a mutation issue.

### E13 — Tray polling cadence forensics (passive)
- **Goal:** prove H5 — quantify the actual poll cadence and outcomes from existing log.
- **Method:** parse `~/AppData/Roaming/MagicMouseTray/debug.log` for `POLL_SCHEDULED` and `BATTERY_INACCESSIBLE`/`OK ... battery` lines. Compute interval distribution per device.
- **Output:** `poll-cadence-stats.md` — table of (device, count, mean interval, min/max, outcome ratio).

### E14 — Cross-check WinMagicBattery source (passive, OSS reference)
- **Goal:** independent confirmation of byte offsets for v3.
- **Method:** clone `https://github.com/hank1101444/WinMagicBattery` (or browse via WebFetch). Read the C# code that parses Feature 0x90. Note exact byte offset.
- **Output:** `oss-reference-winmagicbattery.md` — extracts of the relevant code with our annotation.

### E15 — Cross-check mac-precision-touchpad (passive, OSS reference)
- **Goal:** alternative implementation for comparison.
- **Method:** browse `https://github.com/imbushuo/mac-precision-touchpad`. Note any v3 PID handling and battery byte layout.
- **Output:** `oss-reference-mac-precision-touchpad.md`.

### E16 — Linux hid-magicmouse.c source reference (passive)
- **Goal:** canonical reference for v3 byte layout (Linux kernel).
- **Method:** WebFetch `https://github.com/torvalds/linux/blob/master/drivers/hid/hid-magicmouse.c` — search for `0x0323`, `BTHENUM`, `magic_mouse_battery`, etc. Note the report ID and byte offsets the kernel uses.
- **Output:** `oss-reference-linux-hid-magicmouse.md`.

### E17 — INF install date vs v3 first-pair date (passive)
- **Goal:** prove H6 — v3 was paired BEFORE INF arrived, so PnP never applied LowerFilters to v3's PDO.
- **Method:**
  - INF install date: `Get-WindowsDriver -Online | Where-Object OriginalFileName -like '*applewirelessmouse*' | Select-Object Date`. Already partial in `bt-stack-snapshot`.
  - v3 first-pair date: BTHPORT cache `LastConnected` and `FingerprintTimestamp` for MAC `d0c050cc8c4d`. Already captured in `bthport-discovery-d0c050cc8c4d.txt`.
  - PnP install date: Setup API key timestamp on the v3 BTHENUM PDO.
- **Risk:** none.
- **Output:** `v3-pair-vs-inf-timeline.md`.
- **Discriminator:** if v3 first-pair predates INF install, H6 confirmed and the fix is `pnputil /add-driver /install` (or just disable+enable v3 once filter is unbound and let INF re-evaluate).

## J. Updated execution order

Run **all of E9–E17 first** (passive). No state change. They give us the data to verify (or invalidate) each headline. THEN, only if needed, proceed to the intrusive tests:

```
1. E6  ✅ done (source audit)
2. E7c ✅ done (driver static analysis)
3. E9  — v3 runtime descriptor dump (passive)
4. E10 — v1 + keyboard runtime descriptor dump
5. E11 — BLE advertisement capture (60 sec passive)
6. E12 — v3 PnP child tree
7. E13 — poll cadence forensics
8. E14 — WinMagicBattery source check
9. E15 — mac-precision-touchpad source check
10. E16 — Linux hid-magicmouse.c source check
11. E17 — INF install date vs v3 pair date

CHECKPOINT — review findings; decide if intrusive tests still needed
12. (intrusive) E1+E2 if H1/H2/H3 still ambiguous after passive — keyboard cleanup MOP + reboot
13. (intrusive) E4 — recycle v3 PnP if H2 confirms mutated descriptor
14. (intrusive) E5 — confirm filter-bound vs unbound 0x90 read paths
```

## K. Files E.2 will produce

```
.ai/test-runs/2026-04-27-154930-T-V3-AF/
├── descriptor-runtime-v3.{txt,bin}
├── descriptor-runtime-v1.{txt,bin}
├── descriptor-runtime-keyboard.{txt,bin}    # may be partial if kbdhid wedges
├── ble-advertisement-capture.json
├── v3-pnp-tree.txt
├── poll-cadence-stats.md
├── oss-reference-winmagicbattery.md
├── oss-reference-mac-precision-touchpad.md
├── oss-reference-linux-hid-magicmouse.md
└── v3-pair-vs-inf-timeline.md
```

## L. Decision after E.2

After all passive data is in, we'll know:

- **H1**: byte offsets for every device, confirmed against ≥3 independent sources.
- **H2**: whether HidBth's runtime descriptor for v3 differs from the SDP cache, with the diff measured byte-by-byte.
- **H3**: keyboard battery byte location confirmed (descriptor + OSS pattern match).
- **H4**: AirPods Pro live battery readings via BLE adv, with timestamps and RSSI.
- **H5**: actual poll cadence measured against industry "15-min default" reference.
- **H6**: timeline confirmation that v3 paired before INF.

If H2 is confirmed (runtime != cache, vendor TLC missing from PnP tree), the intrusive E4 test (Disable+Enable v3) becomes a **single-shot proof** with a known-good predicted outcome. If H2 is **not** confirmed, we need a different fix theory and probably more passive analysis.
