# E18 — PnP event log narrative (passive)

**Source:** `pnp-eventlog.{txt,json}` — 138 events 2025-11-24 → 2026-04-28 from
`Microsoft-Windows-Kernel-PnP/Configuration` + `System` (UserPnp) for the four
device InstanceIDs the user supplied.

**Status:** All passive. Read-only `Get-WinEvent`. No state change.

---

## TL;DR — what the event log proves

1. **Magic Utilities WAS bound to your v3 mouse from 2026-03-18 to 2026-04-17** — the magicmouse INF (oem53.inf) v3.1.5.3 with `LowerFilters: MagicMouse`. Magic Utilities supports v3 PID 0x0323 in its INF.
2. **Apple's `applewirelessmouse` filter arrived on 2026-04-21** and started competing with Magic Utilities for v3 binding. The v3 mouse got rebound back-and-forth between the two filters at least 12 times between 2026-04-21 and 2026-04-27.
3. **Three different "Magic" filter names** have been present at various times: `MagicMouse`, `MagicMouseDriver`, `applewirelessmouse`. They are different services from different INF packages.
4. **The keyboard has NEVER had `applewirelessmouse` as a Lower Filter at runtime** — the PnP/Configuration log shows only `LowerFilters: ` (empty) since pair on 2025-11-24. The current registry ref must have been written by an INF AddReg directive (probably when applewirelessmouse INF was installed for v3) but the keyboard PDO has not been restarted since, so the ref never took effect. **Dangling registry-only orphan, exactly as suspected.**
5. **v1 mouse was DELETED (unpaired) on 2026-04-21 15:41** and re-paired this morning (2026-04-28 09:30) — with `applewirelessmouse` LowerFilter applied at 09:30:12. But the snapshot at 09:43 showed empty LowerFilters → some process stripped it between 09:30 and 09:43 (likely the user re-paired or did a manual reset).
6. **The Device Manager screenshots you sent show v1 mouse currently bound to `magicmouse.inf` v3.1.5.3** — but the most recent event-log entry for v1 shows `applewirelessmouse`. **Disagreement between the two views**. Either DM was captured at a different time, or PnP swapped the binding silently after the 09:30 event.

## Detailed timeline by device

### v3 Magic Mouse (PID 0x0323)
112 events. Driver/filter sequence:

| Time (local) | Driver INF | LowerFilters | Notes |
|---|---|---|---|
| 2026-03-18 11:05 | (430 error) | — | First pair, "requires further installation" |
| 2026-03-18 11:05 | hidbth.inf | (empty) | Generic Microsoft fallback |
| 2026-03-18 11:37 | **oem53.inf** | **MagicMouse** | Magic Utilities INF v3.1.5.3 installed + bound |
| 2026-03-18 11:56 | oem53.inf | MagicMouse | (still Magic Utilities) |
| 2026-03-31 19:13 | oem53.inf | MagicMouse | |
| 2026-04-17 13:29–14:13 | (driver unparsed) | — | Several restart events |
| 2026-04-21 13:30–15:48 | (unparsed) | — | More restarts |
| 2026-04-21 15:50 | **oem0.inf** | **applewirelessmouse** | Apple INF arrives (v6.2.0.0 dated 2026-04-21) |
| 2026-04-21 23:33 | oem10.inf | MagicMouse | Magic Utilities reinstalled (different oem# = re-add) |
| 2026-04-21 23:48 | oem0.inf | applewirelessmouse | Apple back |
| 2026-04-26 22:13 | oem0.inf | applewirelessmouse | |
| 2026-04-27 03:35 | **oem10.inf** | **MagicMouseDriver** | Magic Utilities renamed service! |
| 2026-04-27 04:21–04:59 | oem52.inf / oem10.inf | MagicMouseDriver | Rapid alternation (8 swaps in 30 min) |
| 2026-04-27 06:17 | oem0.inf | applewirelessmouse | Apple wins last round |
| 2026-04-27 15:56 | oem0.inf | applewirelessmouse | LAST event in window |
| 2026-04-28 (today) | (per snapshot) | **(empty)** | Filter stripped — likely by exp-a-recycle yesterday eve or a reboot |

### v1 Magic Mouse (PID 0x030D)
15 events.

| Time | Driver INF | LowerFilters | Notes |
|---|---|---|---|
| 2026-03-18 11:37 | **oem53.inf** | **MagicMouse** | Magic Utilities INF (same as v3) |
| 2026-04-17 13:29 | (UserPnp svc add) applebmt | — | Apple Boot Camp service registered |
| 2026-04-17 14:11 | **oem52.inf** | **applewirelessmouse** | Apple INF v6.1.7700 dated 2019-08-08 |
| 2026-04-21 15:41 | (DELETED) | — | v1 was unpaired |
| 2026-04-28 09:30 (today) | (430 then) oem0.inf | applewirelessmouse | Re-paired this morning, applewirelessmouse v6.2.0.0 |

### Apple Keyboard (PID 0x0239)
7 events.

| Time | Driver INF | LowerFilters | Notes |
|---|---|---|---|
| 2025-11-24 08:35 | (DELETED) | — | Previous pairing removed |
| 2025-11-24 08:43 | (430) hidbth.inf | **(empty)** | Re-paired with Microsoft generic. **No filter.** |
| 2025-11-24 08:43 | keyboard.inf (HID child) | — | Standard Microsoft keyboard.inf for COL01 |

**The keyboard has never had `applewirelessmouse` as a runtime LowerFilter** per the Configuration log. The current registry ref (`LowerFilters=applewirelessmouse`) was added by some other path — most likely an INF AddReg side-effect when `applewirelessmouse.inf` was installed in 2026-04-21 (its install pass may have over-matched or written class-level reg). Since the keyboard PDO hasn't restarted since 2025-11-24, the ref has never actually been applied to its driver stack.

## Implications for our test plan

### Headlines re-graded after E18

| # | Headline | E18 evidence |
|---|---|---|
| H1 | v3 battery on Input 0x90 byte 1 of vendor TLC | E18 doesn't directly prove byte offset; OSS source-checks (E14–E16) still needed |
| H2 | Apple filter mutated descriptor; HidBth cached it | **PARTIALLY UNSEATED** — v3 has had filters bound and unbound MANY times. The "cached mutation" theory needs more thought; the runtime descriptor we see today reflects the LAST AddDevice (after applewirelessmouse was unbound). It IS plausibly mutated remnant, but we don't know which filter mutated it. E9 (runtime descriptor capture) still required to confirm. |
| H3 | v1 + keyboard standard 0x47 | Confirmed for v1 by tray log. Keyboard byte still inferential. |
| H4 | AirPods BLE adv | E11 still pending |
| H5 | Polling cadence | E13 still pending |
| H6 | v3 paired before INF arrived | **CONFIRMED + REFINED** — v3 paired 2026-03-18; applewirelessmouse INF v6.2.0.0 dated 2026-04-21. Magic Utilities INF was installed BEFORE pair (since v3 picked it up at 11:37 the same day as pair). The "paired before INF" gap is for applewirelessmouse, not for Magic Utilities. |

### NEW headline from E18

| # | Headline | Evidence |
|---|---|---|
| **H7** | **Magic Utilities is the right architecture** — it has been bound to BOTH v1 AND v3 in your driver history, with `LowerFilters: MagicMouse` on the BTHENUM HID PDO. When bound, v3 had a working filter. | E18 events 2026-03-18 11:37 onwards |
| **H8** | **The system has been in driver-thrash mode since 2026-04-21** — applewirelessmouse INF and Magic Utilities INF have been competing for v3 binding 12+ times. The current state (no filter on v3) is because the most recent intrusive test (exp-a-recycle on 2026-04-27 evening) stripped the filter, and no INF has rebound since. | event sequence above |
| **H9** | **Keyboard's `LowerFilters=applewirelessmouse` is a registry-only orphan**. The keyboard PDO has never started with that filter. Removing the registry ref does NOT require disabling the keyboard. | Configuration log silent on keyboard filter |

## Implication for "is Phase 4-Ω the right fix?"

**Possibly not.** Two simpler architectures emerge:

### Option X — install/restore Magic Utilities for v3
- Magic Utilities clearly handles v3 (we have evidence it was bound 2026-03-18 → 2026-04-17 with the MagicMouse filter on stack).
- It's the commercial, supported product mentioned in the research (paid but mature).
- Installing it would: (a) bind a known-good filter to v3, (b) replace applewirelessmouse, (c) presumably restore both scroll and battery on v3.
- This sidesteps the entire "DIY filter replacement" / Phase 4-Ω architecture.
- Cost: paid product subscription. Empirical proof needed: does Magic Utilities provide battery via its own UI for v3? (Per `magicutilities.net/magic-mouse/help/battery-alerts` it does.)

### Option Y — use applewirelessmouse but force PnP rebind
- Apple's INF v6.2.0.0 supports v3. INF is installed.
- The binding has been lost (probably from intrusive testing).
- Run `pnputil /add-driver oem0.inf /install` or trigger a PnP rescan.
- BTHENUM Disable+Enable on v3 with the filter unbound (current state) won't bind it — PnP only re-evaluates INF on add-device, not restart of an existing device.

### Option Z — userland-only via `HidD_GetInputReport(0x90)` on vendor TLC
- The research findings suggest this works WITHOUT any filter on v3 stack.
- IF the runtime descriptor still has the vendor TLC enumerated (E9/E12 will tell us), tray can read battery directly.
- Currently the vendor TLC is NOT in the live PnP tree → mutated descriptor or stripped TLC from a previous filter binding.
- A clean re-pair (unpair + repair v3) might restore the original descriptor.

## Updated test priority

1. ✅ **E18 done** — driver/filter timeline
2. **E9 next** — capture v3 runtime descriptor right now and compare to SDP cache. Critical to choose between options X/Y/Z.
3. **E12** — v3 PnP child enumeration (verify which TLCs are exposed).
4. **E11** — BLE adv for AirPods (still passive, still high-value).
5. **E14/E15/E16** — OSS source cross-checks for battery byte offsets.
6. **E13** — poll cadence forensics.
7. **E17** — INF date timeline (mostly answered now via E18; mainly need to confirm magicmouse INF date).
8. CHECKPOINT
9. (Intrusive) decide between options X / Y / Z based on data.
