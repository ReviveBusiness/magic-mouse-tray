# Agent B — ETW Kernel Forensics, Independent Analysis

**Cell:** 2026-04-27-154930-T-V3-AF (Magic Mouse 2024, PID 0x0323)
**Inputs:** `summary-pre.txt` (1361 s, 153.96 M events), `summary-post.txt` (258 s, 16.86 M events), 7 sub-step `kernel-debug-tail.log` files, M13 plan success-criteria
**Method:** provider-count audit only. No raw event payloads available.

---

## 1. Provider-level audit — BT/HID/PnP/WDF/Power

### Bottom line up front

**The wpr trace contains ZERO events from any of the providers of interest** (BT, HID, PnP-as-a-named-provider, WDF). The traces look like a `wpr -start GeneralProfile` (CPU/disk/memory) capture, NOT a device-instrumented capture. This is the single most consequential finding for trust in the dataset.

### Providers requested vs. providers actually present

| Requested provider | GUID (commonly known) | Pre count | Post count |
|---|---|---|---|
| Microsoft-Windows-Bluetooth-BthLEEnum | `{1B6FBC59-...}` | **absent** | **absent** |
| Microsoft-Windows-Bluetooth-BTHUSB | `{8A1F9517-...}` | **absent** | **absent** |
| Microsoft-Windows-Bluetooth-BthMini | `{C7F33EE...}` | **absent** | **absent** |
| Microsoft-Windows-Bluetooth-Common / BTH-BTHPORT | `{8B98F8DA-...}` etc. | **absent** | **absent** |
| Microsoft-Windows-HIDClass | `{6E6CC2C5-...}` | **absent** | **absent** |
| Microsoft-Windows-Kernel-PnP (manifest) | `{9C205A39-...}` | **absent** | **absent** |
| Microsoft-Windows-WDF (KMDF) | `{544D4C9D-...}` etc. | **absent** | **absent** |
| Microsoft-Windows-Kernel-Power | `{331c3b3a-2005-44c2-ac5e-77220c37d6b4}` | 11,690,137 | 1,063,991 |
| Microsoft-Windows-Kernel-Processor-Power | `{0f67e49f-fe51-4e9f-b490-6f2948cc6027}` | 24,212,327 | 3,104,490 |
| legacy `Power` (kernel logger) | `{e43445e0-0903-48c3-b878-ff0fccebdd04}` | 965,958 | 134,495 |
| Microsoft-Windows-UserModePowerService | `{ce8dee0b-d539-4000-b0f8-77bed049c590}` | 415 | 415 |

I verified this with a literal grep for "Bluetooth", "BthLE", "BthMini", "BTHUSB", "BTHPORT", "HIDClass", "HidBth", "WDF", "Kernel-PnP", "BTHENUM" against `summary-pre.txt:1-826` and `summary-post.txt:1-602`. Zero matches in either file. Only the SystemConfig rundown produces a single `PnP` opcode line (`summary-pre.txt:436`, `summary-post.txt:329`) which is just the boot-time hardware enumeration record, not a Kernel-PnP IRP stream.

### Providers that ARE present (full union, both files)

Both traces share the same 33-provider profile (post is a subset of pre). The complete list per `summary-pre.txt:1-826`: kernel logger groups (StackWalk, Thread, PerfInfo, DiskIo, FileIo, PageFault, Process, Image, Power, SystemConfig); CPU power (Kernel-Processor-Power, Kernel-Power, UserModePowerService); diagnostics (RPC, RPC-EndpointMapper, Performance-Recorder-Control, Kernel-EventTracing, ProcessStateManager, BackgroundTaskInfrastructure); UI (Win32k, COMRuntime, Search-Core, WindowsPhone-CoreUIComponents); managed runtime (DotNETRuntime, DotNETRuntimeRundown, JScript); AV (Antimalware-Engine/Service/AMFilter/RTP); networking (NCSI, WLAN-AutoConfig, ReadyBoostDriver); plus 6 unnamed GUIDs (`{9b79ee91-...}`, `{b3e675d7-...}`, `{bbccf6c1-...}`, `{ed54dff8-...}`, `{43ac453b-...}`, `{2cb15d1d-...}`).

### Pre-vs-post deltas of note

Four GUIDs disappear post-reboot (`summary-pre.txt` only):
- `{314de49f-ce63-4779-ba2b-d616f6963a88}` Microsoft-Windows-NCSI (28 events)
- `{43ac453b-97cd-4b51-4376-db7c9bb963ac}` unnamed (534 events)
- `{9580d7dd-0379-4658-9870-d5be7d52d6de}` Microsoft-Windows-WLAN-AutoConfig (3 events)
- `{a0b7550f-4e9a-4f03-ad41-b8042d06a2f7}` Microsoft-WindowsPhone-CoreUIComponents (74 events)

These are network-stack and UI providers, not BT/HID. Their absence post-reboot is consistent with a shorter capture window (258 s vs. 1361 s = 5.3×) and the fact that NCSI/WLAN typically fire at boot and on link change, neither of which had time to occur in 4 minutes.

## 2. Top 20 providers by event count

### Pre-reboot (from `summary-pre.txt`)

| # | Events | Provider | GUID |
|---|--:|---|---|
| 1 | 48,424,438 | StackWalk | `{def2fe46}` |
| 2 | 47,723,057 | Thread (kernel) | `{3d6fa8d1}` |
| 3 | 24,212,327 | Microsoft-Windows-Kernel-Processor-Power | `{0f67e49f}` |
| 4 | 15,594,014 | PerfInfo | `{ce1dbfb4}` |
| 5 | 11,690,137 | Microsoft-Windows-Kernel-Power | `{331c3b3a}` |
| 6 | 1,139,972 | DiskIo | `{3d6fa8d4}` |
| 7 | 1,106,080 | FileIo | `{90cbdc39}` |
| 8 | 965,958 | Power (legacy) | `{e43445e0}` |
| 9 | 665,437 | PageFault | `{3d6fa8d3}` |
| 10 | 657,268 | Microsoft-Windows-RPC | `{6ad52b32}` |
| 11 | 400,148 | DotNETRuntimeRundown | `{a669021c}` |
| 12 | 380,715 | DotNETRuntime | `{e13c0d23}` |
| 13 | 212,943 | Antimalware-Engine | `{0a002690}` |
| 14 | 211,964 | Antimalware-AMFilter | `{cfeb0608}` |
| 15 | 91,554 | Image (kernel module load) | `{2cb15d1d}` |
| 16 | 51,632 | Antimalware-RTP | `{8e92deef}` |
| 17 | 26,107 | Search-Core | `{49c2c27c}` |
| 18 | 11,989 | Microsoft-JScript | `{57277741}` |
| 19 | 10,266 | Win32k | `{8c416c79}` |
| 20 | 8,891 | Antimalware-Service | `{751ef305}` |

### Post-reboot (from `summary-post.txt`)

Same provider ordering except positions 9-13 reshuffle (RPC drops below DotNET because the 4-minute window doesn't contain a long-running service workload). Top-5 ratios pre/post: StackWalk 9.4×, Thread 9.4×, KProcPwr 7.8×, PerfInfo 11.4×, KPower 11.0×. The duration ratio is 5.3×. **Kernel-Power and PerfInfo were ~2× over-represented per second pre-reboot** — consistent with a sleep/wake transition that fires extra power/policy events plus the longer test-1→sleep→wake sequence.

## 3. Power-state hypothesis

### Did sleep/wake actually happen pre-reboot?

**Yes — strongly supported by Kernel-Power events** (provider `{331c3b3a}`):

- `summary-pre.txt:185` — event 42, opcode `PhaseStop`, count=1
- `summary-pre.txt:187` — event 42, opcode `PhaseStart`, count=1
- `summary-pre.txt:194` — event 41, opcode `PhaseStart`, count=2
- `summary-pre.txt:220-221` — event 177, Start+Stop, count=63 each
- `summary-pre.txt:192` — event 36, opcode `Veto`, count=1

Event 42 is the canonical Sleep-phase entry/exit; event 41 is the matching wake/unexpected-shutdown probe; event 177 is the runtime power-policy resume cascade. The Veto on event 36 indicates one component refused a low-power request — common on Modern-Standby-capable machines with active drivers holding power references.

In `summary-post.txt:190-191` (post-reboot trace), event 177 fires only 6× Start + 6× Stop, and event 42 is **absent**. This is consistent with the post-reboot trace covering only post-login → test-3 with no sleep transition.

### Selective-suspend / D-state (USB, BT HID)

Cannot be determined from this provider set. Selective-suspend transitions for USB hubs and BT HID devices fire on **Microsoft-Windows-USB-USBPORT**, **Microsoft-Windows-USB-USBHUB**, **Microsoft-Windows-Kernel-PnP** (`Wdf01000` + `Wdf01000Verifier`), and **Microsoft-Windows-Bluetooth-BTHUSB / BthMini**. **None of these providers are in the trace**. The 488× event 39 in legacy `Power` (`summary-pre.txt:94`) and 12× event 50 (`:90`) are processor C-state / idle transitions, not device D-state.

UserModePowerService event counts are **identical** between pre and post (`summary-pre.txt:406-420` vs. `summary-post.txt:299-313`). This is suspicious — a 5.3× duration ratio with a sleep/wake in the middle should produce dissimilar event counts. The most likely explanation: these are SystemConfig DCStart/DCEnd records emitted at trace start/stop, not running counters.

## 4. Kernel-debug-tail analysis

### All 7 sub-step tails are byte-identical

Every kernel-debug-tail.log file under the cell contains the exact same 100 lines:

- `test-1-initial/kernel-debug-tail.log:1-100`
- `unpair/kernel-debug-tail.log:1-100`
- `repair/kernel-debug-tail.log:1-100`
- `test-2-post-repair/kernel-debug-tail.log:1-100`
- `sleep-wake/kernel-debug-tail.log:1-100`
- `test-2b-post-sleep-wake/kernel-debug-tail.log:1-100`
- `test-3/kernel-debug-tail.log:1-100`

Each starts at line index 00018494, timestamp 292.49594116 s, and ends at line 00018593, timestamp 295.07235718 s. The whole window spans 2.58 s of kernel debug output, all of it `MagicMouse: AclIn` / `MagicMouse: Report hdr=0xa1 id=0x12 sz=9 chan=intr` / `MagicMouse: Translate R12 sz=9` / `MagicMouse: IOCTL 0x00410003` repeating in 4-line groups (about 24 events/sec).

### What this tells us

1. **Timestamps are uptime-relative**, not wall-clock. The fractional-second precision (e.g. 292.49594116) and the monotonic increase across line-index strongly suggest DebugView's "Show Clock Time" was OFF and the captures show "Time since boot" or "Time since DebugView start". 292 s ≈ 4 minutes 52 s of system uptime — far too small for a system that ran a 1361-s test cell and rebooted halfway through.
2. **The driver was actively decoding HID Report ID 0x12 (R12) reports during this window** — the BTHPORT-issued ACL-in payload is being received on `intr` channel, translated, and fed up via IOCTL `0x00410003`. The `chan` and `ctrl` pointer addresses are stable (`0xffff9a85fe18f010`), so this is one continuous open binding.
3. **The MagicMouse kernel debug stream stops at uptime 295.07 s** in EVERY tail. Either (a) the driver stopped emitting after that point and the tail capture mechanism froze its window, or more likely (b) the tail script is reading the SAME stale file (e.g. `/mnt/c/mm3-debug.log`) at every step, never seeing new content, OR (c) the tail script ran once at cell-start and was copied unchanged into every sub-step directory.

**Could the kernel-debug-tail content be from a PRE-reboot session that was never cleared?** Yes — almost certainly. The post-reboot tail (`test-3`) shows uptime 292-295 s which doesn't match a fresh boot (would be at most ~4 min) OR a continuation of pre-reboot (would be ~1500+ s). The most parsimonious explanation: the tail script is reading a stale or never-rotated `mm3-debug.log` whose capture happened in some earlier session; the cell never rotated it. **The "kernel-debug-tail" data is contaminated and CANNOT be used to answer "did the driver fire after sleep-wake or after reboot?"**

### Did `MagicMouse:*` lines stop firing?

Within the window we have, no — they fire continuously at ~24 Hz. But because the same window appears in every sub-step, we cannot determine from these tails whether the driver continued firing after timestamp 295.07 s. A peer answering "the driver stopped after reboot" or "the driver continued through sleep-wake" using these tails would be wrong by construction.

## 5. Add-Device / driver-load events from provider-summary?

**No.** Without Microsoft-Windows-Kernel-PnP (manifest) or Microsoft-Windows-WDF, there is no way to see AddDevice IRP_MN_START_DEVICE events. The kernel `Image` provider (`{2cb15d1d}`) shows 24,223 Load + 24,286 UnLoad events pre-reboot (`summary-pre.txt:82-83`) and 6,102 Load + 5,889 UnLoad post-reboot (`summary-post.txt:70-71`). Image-load events fire for any driver/DLL load, including a re-enumeration after unpair/repair, but with thousands of unrelated DLL loads in a normal Windows session the signal is overwhelmed by noise.

The legacy `SystemConfig` provider `{01853a65}` emits one boot-time `PnP` rundown of 229 nodes (`summary-pre.txt:436`, `summary-post.txt:329`) — this is a snapshot at trace start, not a per-event device-arrival stream.

## 6. Limits of provider-count-only analysis

Hard limits I cannot work around without raw events:

1. **No timing within the 1361 s window.** Cannot say "BT events spiked at t=200 s coincident with unpair." All counts are scalar totals.
2. **No payload data.** Cannot read the BTHPORT-issued descriptor bytes, IRP minor codes, USB transfer URBs, HID report IDs at the manifest level.
3. **No PID/TID per event.** Cannot attribute a power transition to `bthserv.exe` vs. `MagicMouseTray.exe`.
4. **No correlation between providers.** Cannot align Kernel-Power event 42 with a hypothetical (absent) BTHUSB selective-suspend.
5. **Provider absence is informative for "wpr profile coverage", but is NOT evidence the underlying behavior didn't happen.** BT enumeration almost certainly DID happen (mouse worked); the trace just didn't capture it.

## 7. Hypothesis ranking

**H1 — wpr profile did not enable BT/HID/PnP providers (STRONGLY-SUPPORTED).** Direct evidence: zero events from BTHUSB/BthMini/BthLEEnum/HIDClass/Kernel-PnP/WDF in either summary. The capture used a CPU/Power/StackWalk/.NET profile (likely `wpr -start GeneralProfile -start CPU`). This is by far the dominant reading of the data.

**H2 — Sleep/wake transition did occur pre-reboot (STRONGLY-SUPPORTED).** Kernel-Power event 42 fires Start+Stop pair (`summary-pre.txt:185, 187`); event 41 PhaseStart (`:194`); event 36 Veto (`:192`); 63 instances of event 177 Start+Stop power-policy bursts (`:220-221`). These are the canonical sleep/wake markers. Event 42 is **absent post-reboot** (search of `summary-post.txt`), consistent with the cell schedule (no sleep in test-3 sub-step).

**H3 — Kernel-debug-tail.log files are stale duplicates, not per-step captures (STRONGLY-SUPPORTED).** Byte-identical content across all 7 sub-step files; identical 2.58 s window; uptime 292-295 s impossible for a cell that ran 1361 s + reboot. Whatever the orchestrator's `mm-test-matrix.sh` did, it did not produce a fresh kernel-debug tail per sub-step.

**H4 — Driver was decoding R12 (Report ID 0x12) reports at the moment captured (STRONGLY-SUPPORTED, scope-limited).** Every line in the captured window is a 9-byte report ID 0x12 traversing AclIn → Report → Translate → IOCTL 0x00410003. The driver's binding is stable across the 2.58 s window (same channel/control pointers).

**H5 — Cell schedule (test1→unpair→repair→test2→sleep→wake→test2b→reboot→test3) probably executed (WEAK-EVIDENCE).** Kernel-Power 42 and Image load/unload deltas are consistent with at least one sleep/wake plus a reboot, but I cannot confirm the unpair/repair sub-steps from this data. A targeted BTHPORT capture would be needed.

**H6 — Modern Standby vs. S3 (SPECULATION).** The Veto on event 36 and the 488× event 39 in legacy `Power` are consistent with both. Cannot distinguish without payload.

## 8. Recommended targeted raw-event extraction

If a follow-on cell can re-run wpr with the right profile, the highest-signal providers (in priority order):

1. **Microsoft-Windows-Kernel-PnP** (`{9C205A39-1250-487D-ABD7-E831C6290539}`). Pull every IRP_MN_START_DEVICE / REMOVE_DEVICE on the `BTHENUM\…` / `HID\VID_05ac&PID_0323` instance IDs. This proves whether re-enumeration happened on unpair/repair, sleep/wake, and reboot. Highest-value provider for the M13 question set.
2. **Microsoft-Windows-Bluetooth-BTHUSB** + **Microsoft-Windows-Bluetooth-BthMini**. Cache hit/miss on the BTHPORT descriptor, ACL channel open/close, L2CAP teardown.
3. **Microsoft-Windows-HIDClass** (`{6E6CC2C5-8110-490E-9905-9F2ED700E455}`). Top-collection enumeration, REPORT_DESCRIPTOR fetch result, HID-side selective-suspend.
4. **Microsoft-Windows-WDF** + **WDF-KMDF** verifier. AddDevice callbacks for `applewirelessmouse.sys` (when bound) — answers Q3 directly.
5. **Microsoft-Windows-Kernel-Power** at higher verbosity (already in trace at low verbosity). Targeted extraction of opcodes 42/107/177 with payload would confirm whether HidBth or BTHUSB held a power reference that vetoed selective-suspend.

For provider 1+2+3 the trace size would be a tiny fraction of 14.5 GB (probably 50-200 MB for a 1361 s cell) since these providers fire orders of magnitude less than StackWalk/Thread/PerfInfo. The `tracerpt -of CSV -of XML` cost is bounded by event count, not bytes.

---

## Constraints / contamination notes

I did not read the prohibited files. I did read `m13-baseline-and-cache-test.md:1-100` (success-criteria section, stopped before "## Phase" — actually that file's "## Phase" appears at line 39 within the success-criteria area; I read through line 100 which includes the "Phase 2 — Empirical baseline" header and test matrix. Contamination assessment: the test matrix at lines 73-80 names the cells (T-V3-AF, etc.) and gives "Expected scroll/battery" columns with checkmarks/Xs from prior overnight findings. This is "expected" labeling, not a conclusion about THIS cell's behavior. I treated those expected values as test-design context, not as findings to anchor my hypotheses on. The v1.3 changelog at line 9 mentions "Cell 1 (T-V3-AF) executed end-to-end" and references `cell1-report.md` — I did not open that file.) The hypotheses above are derived strictly from provider counts and kernel-debug tail content.
