# M13 — Empirical Baseline & BTHPORT Descriptor Cache Investigation

**Status:** plan v1.1 — Phase 1 executed, reg-diff verification baked in as MOP gate
**Owner:** PRD-184
**Estimated effort:** 1.5h prep + ~4h execution
**Pre-flight gate:** see `.ai/playbooks/autonomous-agent-team.md` checklist sections A-E.
**v1.0 → v1.1 (2026-04-27):** Phase 1 ran; reg-diff verification gate added; orchestrator + bundle script added; cleanup script B1 (COL01 health check) + B2 (RAWPDO `\\` pattern) bugs fixed. See `.ai/test-runs/m13-phase0/phase1-report.md`.

## Why M13

The autonomous overnight session (2026-04-27) produced two deliverables and one critical empirical finding:

1. SDP-scanner filter approach committed (`5ff866a`) — viable but requires fresh re-pair after install for HidBth to fetch a new descriptor.
2. Registry diff agent confirmed the HidBth descriptor cache location: `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<mac>\CachedServices\00010000` (REG_BINARY). The cached descriptor survives driver install/uninstall and is not modified by filter drivers.
3. The Apr 3 "MagicUtilities working" backup showed MU did NOT use a lower filter for v3 — MU claimed the hardware ID via INF as the function driver (same approach Apple's `applewirelessmouse.inf` uses today).

These three facts open a path that may eliminate the kernel filter entirely: patch the BTHPORT cache to declare COL02 (vendor battery), let Apple's existing `applewirelessmouse.sys` continue to provide scroll synthesis, force AddDevice via disable+enable BTHENUM. If it works, PRD-184 collapses from "build a kernel driver" to "registry patch + tray." If it doesn't, we revert and proceed with the SDP-scanner filter that's already on `main`.

M13 baselines the empirical state of both Magic Mouse models the user owns, decodes the cached descriptors, runs the registry-patch hypothesis under controlled conditions, and produces a yes/no decision with evidence.

## Success criteria

End of M13, we can answer with concrete evidence:

1. **Q1**: Does the v3 BTHPORT cached descriptor already declare COL02 (UP=0xFF00 U=0x0014)?
2. **Q2**: Does the v3 cached descriptor declare any wheel/AC-Pan usages?
3. **Q3**: With `applewirelessmouse` as function driver, what subset of the cached descriptor reaches HidClass?
4. **Q4**: With `applewirelessmouse` removed (NoFilter mode), does battery work? (re-validate from earlier session)
5. **Q5**: Does patching the cached descriptor to add COL02 + reload (disable+enable) result in HidBth presenting both COL01 (with Apple's scroll synthesis) and COL02 (vendor battery readable)?
6. **Q6**: Does the v1 mouse exhibit the same architecture or a different one?
7. **Q7**: Can we deliver scroll+battery on v3 without writing a kernel driver?

Q7 is the bottom-line question. Yes/no determines whether PRD-184 ships as a registry-patch + tray (and the existing SDP-scanner filter becomes vestigial) or as the kernel driver.

## Phase structure

### Phase 1 — Clean state baseline (~30 min, your admin shell)

Goal: remove orphan registry/PnP residue from MU + overnight experiments without touching the working scroll path. Produce a known-clean reference state and a fresh registry export.

Steps (each verified before next):

0. **MOP gate — pre-flight (admin PS, Phase 0):** `mm-pause-windows-update.ps1` (7d) + `mm-driver-fingerprints` capture
1. Pre-flight registry export → `D:\Users\Lesley\Documents\Backups\<ts>-pre-cleanup.reg`
2. Remove dead `MagicMouseDriver` service key (no `.sys` exists, orphan)
3. Remove stale USB MI_01 `LowerFilters=MagicMouse` (would Code-39 if mouse plugged via USB-C)
4. Remove `MAGICMOUSERAWPDO` orphan PnP node (`{7D55502A-...}`)
5. Clean `C:\Temp` scatter (~270 MB) keeping only `MagicMouseTray.exe`
6. Remove orphan `oem*.inf` packages from our overnight experiments (the Windows audit at `.ai/cleanup-audit/windows-audit-2026-04-27.md` enumerates these)
7. Verify scroll still works (move pointer, 2-finger gesture)
8. Post-cleanup registry export → `D:\Users\Lesley\Documents\Backups\<ts>-post-cleanup.reg`
9. **MOP gate — reg-diff verification:** `./scripts/mm-reg-diff.sh --auto` produces a markdown audit report at `.ai/test-runs/<phase>/reg-diff-<ts>.md` showing (a) sections added/removed, (b) value-level diffs with hex(7)/hex(1) decoded inline, (c) full diff totals. Report must show ONLY the expected mutations (MagicMouse* / RAWPDO sections in CCS+CS001) — any unexpected drift halts the phase.
10. `mm-snapshot-state.sh` for in-repo record

Exact command sequences:
- Admin PS one-shot orchestrator (steps 0+2-4+6-7 with per-step verify): `scripts/mm-phase01-run.ps1`
- WSL close-out bundle (steps 1, 8, 9, 10 — runs reg export + diff + snapshot in sequence): `scripts/mm-phase1-closeout.sh`

**Phase-1 success criteria:** scroll works · `LowerFilters=applewirelessmouse` on BTHENUM HID device · parent HID PDO (Class=Mouse, Status=OK, no COL suffix) enumerated · no MU residue per Windows audit's safe-to-delete list · post-cleanup registry export saved · **reg-diff report shows only expected mutations**.

**Halt conditions:**
- scroll stops working after any cleanup step → STOP, restore from pre-cleanup export, do not proceed.
- reg-diff report shows unexpected sections added/removed or value-level changes outside the MagicMouse/RAWPDO/applewirelessmouse filter → STOP, investigate before declaring Phase 1 done.

### Phase 2 — Empirical baseline (both mice, both states, ~2h)

Goal: capture HID enumeration + battery readability + scroll behavior under all combinations of (mouse model × driver state × test phase).

#### Test matrix

| ID | Mouse | Driver state | Test sequence | Expected scroll | Expected battery |
|---|---|---|---|---|---|
| T-V3-AF | v3 (PID 0x0323) | AppleFilter (current) | test → unpair → repair → test → reboot → test | ✓ | ✗ (per overnight finding) |
| T-V3-NF | v3 (PID 0x0323) | NoFilter | flip → test → unpair → repair → test → reboot → test | ✗ (per overnight finding) | ✓ (per overnight finding) |
| T-V1-AF | v1 (PID 0x030D) | AppleFilter | pair → test → unpair → repair → test → reboot → test | ? | ? |
| T-V1-NF | v1 (PID 0x030D) | NoFilter | flip → test → unpair → repair → test → reboot → test | ? | ? |

The "?" cells are the empirical gaps M13 fills.

#### Per-test-cell capture

Test orchestrator (`scripts/mm-test-matrix.sh`) auto-starts on enter:
- Procmon recording filtered to `BTHPORT.SYS`, `HidBth.sys`, `applewirelessmouse.sys`
- ETW Bluetooth + HidClass + Kernel-PnP providers via `wpr.exe` start
- DebugView (kernel debug log) tail
- Per-cell working dir: `.ai/test-runs/<ts>-<cell-id>/`

Per-test-cell capture data:
- HID caps probe (`mm-hid-probe.ps1` output)
- mm-accept-test.sh JSON (8 checks)
- mm-snapshot-state tarball
- Tray debug.log tail
- Procmon `.PML` (closed at cell end)
- ETW `.etl` (closed at cell end)
- DebugView log slice
- Quick subjective notes from human (scroll smooth? click registers? gesture continuous?)

#### "Test" step definition

At each "test" point in the sequence, the human:
1. Moves the pointer corner-to-corner across the screen — verifies pointer responsiveness
2. Performs 2-finger vertical scroll gesture for ≥3 seconds — verifies wheel events
3. Performs 2-finger horizontal swipe — verifies AC-Pan
4. Clicks left + right
5. Tray app should poll within 30s; screenshot/log the tooltip

Test orchestrator prompts the human with these instructions and records observations.

#### Phase-2 success criteria

All cells executed. All capture data archived. No data loss.

#### Halt conditions

- v3 mouse becomes completely unresponsive in any cell — stop, flip to AppleFilter, validate scroll restored
- BTHENUM device shows error code in Device Manager — stop, capture state, do not proceed
- Phase-2 elapsed time exceeds 2h 30min — stop, reassess scope

### Phase 3 — Decode cached descriptors (~1h, read-only)

Goal: empirically read the BTHPORT cached descriptor for both mice and decode the HID descriptor structure.

Steps:

1. Build `scripts/mm-bthport-read.ps1`:
   - Read `HKLM\...\BTHPORT\Parameters\Devices\<mac>\CachedServices\00010000` REG_BINARY
   - Parse outer SDP TLV: `36 LL` SEQUENCE of length LL (or `35 LL` if 1-byte len)
   - Walk attribute records, find attribute 0x0206 (HIDDescriptorList)
   - Inside that, find `08 22 25 NN` framing
   - Extract NN bytes as the embedded HID descriptor
   - Pretty-print TLCs, Report IDs, value caps, button caps using HID descriptor item parser

2. Run against v3 mac (`d0c050cc8c4d`) — produce decoded descriptor in `.ai/test-runs/v3-cached-descriptor.md` + binary fixture in `tests/fixtures/v3-bthport-descriptor.bin`

3. Run against v1 mac (TBD; user provides) — produce same artefacts for v1

4. Compare against:
   - What `applewirelessmouse.sys` presents to HidClass (already known: COL01 mouse + scroll synthesis, no COL02)
   - What HidBth-only (NoFilter mode) presents (already known: COL01 mouse X/Y only, COL02 vendor battery)

5. Document: did the cached descriptor declare COL02 natively? If yes, then `applewirelessmouse` strips it during its function-driver-presents-descriptor flow. If no, then HidBth synthesizes COL02 from a different mechanism we haven't found.

#### Phase-3 success criteria

Both descriptors decoded, fixtures saved, comparison matrix produced. Q1, Q2, Q3 in success criteria answered.

### Phase 4 — Hypothesis test (varies by Phase 3 result)

Decision tree (pre-written so we don't drift):

#### Branch 4A — Cached descriptor already has COL02 (most likely)

Hypothesis: `applewirelessmouse.sys` strips COL02 because its INF only declares COL01-related capabilities. If we can configure the function-driver state to keep COL02 visible while still using Apple's scroll synthesis, we win.

Test:
1. Snapshot current state + reg export
2. Try removing `applewirelessmouse` and using `usbccgp`-equivalent generic HID stack (or just HidBth direct) to enumerate the device. Test if Apple's scroll-synth is REPLACEABLE by a userland gesture-to-wheel daemon (probably yes for non-time-critical scroll).
3. If userland synthesis is "good enough" UX-wise, we have a no-kernel-driver path.

#### Branch 4B — Cached descriptor missing COL02 but has scroll usages

Hypothesis: patching the cache to add COL02 should let HidBth present COL01 (with native scroll declared, Apple's filter still synthesizing actual wheel data) AND COL02 to HidClass.

Test:
1. Snapshot
2. Build `scripts/mm-bthport-patch.ps1` that adds COL02 vendor TLC to the cache blob, updates SDP TLV length bytes
3. Disable+enable BTHENUM
4. Run `mm-accept-test.sh` — must show 8/8 PASS
5. If pass: this is the path. Build a tray-side installer that does the patch.
6. Auto-rollback to snapshot if any check fails.

#### Branch 4C — Cached descriptor missing both COL02 and scroll usages

Hypothesis: only Apple's filter or our filter can deliver scroll. Battery is unobtainable without filter that doesn't strip COL02.

Action: keep our SDP-scanner filter (commit `5ff866a`) but additionally patch the cache to declare COL02. Re-validate post-install.

#### Phase-4 success criteria

Q5 and Q7 answered. Either we have a working scroll+battery configuration on v3 (any branch produces this) and a documented procedure to install it, OR we have empirical evidence that the kernel filter route is the only one and the SDP-scanner filter approach (already on `main`) needs to ship.

#### Halt conditions

- Branch 4B/4C patch corrupts cache and BTHENUM device fails to enumerate → restore from snapshot, abandon registry-patch approach, document why.
- BSOD on disable+enable → restore from registry export, capture crashdump, do not proceed.

## Telemetry / capture protocol

Per Phase, the test orchestrator opens these channels at start and closes at end:

| Channel | Tool | Output |
|---|---|---|
| Filesystem state | `mm-snapshot-state.sh` | tarball at start + end of phase |
| Registry export | `mm-reg-export.sh` | full HKLM\SYSTEM at start + end |
| **Registry diff (MOP gate)** | `mm-reg-diff.sh --auto` | `reg-diff-<ts>.md` audit report — required at end of every phase that mutates registry (Phase 1 cleanup, Phase 4 cache patch). Shows section adds/removes + value-level diffs with hex decoded inline. Filter `MagicMouse\|RAWPDO\|0323\|applewirelessmouse\|LowerFilters\|UpperFilters\|BTHPORT\|HidBth` by default. |
| Process activity | `Procmon.exe` | `.PML` filtered to BTHPORT/HidBth/applewirelessmouse |
| ETW kernel events | `wpr.exe` (Bluetooth, HidClass, Kernel-PnP) | `.etl` |
| Driver kernel debug | DebugView | tail of `C:\mm3-debug.log` |
| HID enumeration | `mm-hid-probe.ps1` | per-cell snapshot |
| Battery polling | tray app's debug.log | natural |
| Acceptance check | `mm-accept-test.sh` | JSON per cell |
| Subjective UX | human prompts in orchestrator | text notes |

All artefacts archived under `.ai/test-runs/<ts>/<phase>/<cell>/`.

## Pre-execution gates (G1)

Before Phase 1 runs, all of these must complete:

1. ✓ Plan written (this doc)
2. ☐ Three specialist reviewer agents complete + reports committed
3. ☐ Test orchestrator script + reg export script written
4. ☐ NLM corpus refreshed (registry-diff report + this M13 plan ingested as sources)
5. ☐ Targeted /peer-review query on registry-cache-patch viability run, verdict captured
6. ☐ User reviews all findings + approves Phase 1 execution

SMS to user when items 2-5 complete and items 1+6 are the only things left.

## Open questions / risks

- **Risk**: BTHPORT cache invalidation triggers we don't know about. Sleep/wake? Driver update via Windows Update? Solution: capture state across each transition during testing; document.
- **Risk**: Apple's filter behavior may differ between firmware versions of the Magic Mouse. Solution: run the same test suite on a system with a different mouse firmware (deferred — out of M13 scope; flag if observed).
- **Risk**: Patching the cache creates a "weird" descriptor that HidBth or HidClass rejects with no clean error. Solution: snapshot + auto-rollback; bound the patch attempt size.
- **Risk**: User testing fatigue — running 4 test cells × 6 sub-steps × multiple captures is ~3 hours of focused attention. Solution: orchestrator does the captures; human only does the physical mouse interaction; chunk into smaller sittings if needed.
- **Open**: do we need the v1 mouse paired throughout, or only at v1 test phases? (Probably only at v1 phases — minimizes BT interference.)

## Deliverables at end of M13

- 4 test-run dirs under `.ai/test-runs/` with full capture data
- Decoded v1 + v3 cached descriptor markdown reports
- Binary fixtures `tests/fixtures/v{1,3}-bthport-descriptor.bin`
- Yes/no answer to Q7 in this doc
- PRD-184 v1.18.x update with M13 results
- A merge candidate: either "ship registry-patch path" or "ship SDP-scanner filter (5ff866a)"
