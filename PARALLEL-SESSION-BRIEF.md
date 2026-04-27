# Parallel Session Brief — InputHandler.c SDP Interception Rewrite

**Generated 2026-04-27 by Claude (Opus 4.7)**
**For**: a parallel agent or fresh Claude Code session

## Mission (one paragraph)

Rewrite `driver/InputHandler.c` so that Apple Magic Mouse 2024 (PID 0x0323) on
Bluetooth gets BOTH scroll AND a vendor battery TLC (UP=0xFF00 U=0x0014) on a
single connection. Approach: lower filter on BTHENUM intercepts every
`BRB_L2CA_ACL_TRANSFER` BRB, scans the buffer for the SDP HIDDescriptorList
attribute response, and replaces the embedded HID descriptor with our existing
`g_HidDescriptor[]` (which already contains 3 TLCs: Mouse+Wheel, Consumer
AC-Pan, Vendor Battery 0xFF00/0x14). This is the empirically-validated approach
Apple's `applewirelessmouse.sys` uses; we just preserve COL02 instead of
stripping it.

## Required reading (in this exact order)

1. `MORNING-BRIEFING-2026-04-27.md` (repo root) — overall state, three viable
   approaches, and which one we picked and why.
2. `Personal/prd/184-magic-mouse-windows-tray-battery-monitor.md` v1.17.0 work
   log entry — the corrected architecture finding.
3. `.ai/rev-eng/08f33d7e3ece/findings.md` — empirical signatures from Apple's
   driver. Confirms IOCTL_INTERNAL_BTH_SUBMIT_BRB hook + SDP attribute 0x0206
   pattern matching.
4. `.ai/rev-eng/08f33d7e3ece/contexts/brb-handler-candidates.txt` — line numbers
   in `disasm.txt` where Apple reads the BRB Type field at `[reg+0x16]`.
5. `driver/Driver.h` — current BRB constants, all verified.
6. `driver/HidDescriptor.c` — `g_HidDescriptor[]` is 113 bytes, 3 TLCs, already
   correct. Don't change it unless you find a bug.
7. `driver/InputHandler.c` — current state. The translation logic is wrong
   (writes Report 0x01 in 5-byte format that doesn't match COL01's 8-byte
   InLen). Replace it with the SDP-interception logic instead.

## Constraints (inviolable)

1. **Do not install your built driver yourself.** Build only. The user will
   review your code + commit log, then trigger install via
   `./scripts/mm-dev.sh full` from the main repo.
2. **Do not modify LowerFilters or run mm-state-flip.** Mouse must remain in
   its current AppleFilter state during your work.
3. **Do not push to origin.** Commit locally. The user reviews then pushes.
4. **Do not modify HidDescriptor.c, scripts/, or PRD docs.** Stay in
   `driver/` only. Specifically: only `driver/InputHandler.c` and
   `driver/Driver.h` (if you must adjust offsets).
5. **Commit every logical change separately.** If you discover an offset is
   wrong and fix it, that's one commit; the SDP scanner is another commit;
   tying it to descriptor injection is a third. Keep commits reviewable.
6. **Use the existing build harness.** From your worktree:
   `cd .. && ./scripts/mm-dev.sh build` to compile-check your changes via
   the scheduled task. Do not invoke `msbuild` directly.

## Work plan (do these in order)

### Step 1 — Confirm SDP attribute byte sequence

Look at `.ai/rev-eng/08f33d7e3ece/disasm.txt` around the function entry points
listed in `contexts/brb-handler-candidates.txt`. Find where Apple reads the
ACL buffer and compares against the SDP attribute ID. The actual on-the-wire
bytes for the HIDDescriptorList SDP response will look like:

```
35 LL                        ; SDP DataElement: SEQUENCE of length LL
    09 02 06                ; Attribute ID 0x0206 (HIDDescriptorList)
    35 LL                   ; SEQUENCE
        35 LL               ; SEQUENCE (each entry)
            08 22           ; UNSIGNED int 8-bit, value 0x22 = "report descriptor"
            25 NN ...       ; STRING NN bytes long, this is THE descriptor
```

The descriptor itself is the `25 NN ... <NN bytes>` payload.

### Step 2 — Implement SDP scan in InputHandler.c

Add a function `BOOLEAN ScanForSdpHidDescriptor(PUCHAR buf, ULONG bufSize, PULONG outOffset, PULONG outLen)`
that returns TRUE if the SDP HIDDescriptorList byte pattern is present in `buf`,
and outputs the offset of the embedded descriptor + its current length.

In `InputHandler_AclCompletion`, change the logic:
- Currently: only intercepts on tracked control/interrupt channels and tries
  to replace Report 0x12.
- New: ALWAYS scan the ACL buffer regardless of channel. If the scan finds an
  SDP HIDDescriptorList response, replace the embedded descriptor bytes with
  `g_HidDescriptor[]` (or update `outLen` if our descriptor is shorter — likely
  it isn't since it's 113 bytes vs typical Apple ~70 bytes).

### Step 3 — Remove the broken translation path

The current Report 0x12 → Report 0x01 translation in `InputHandler_AclCompletion`
is wrong (rejected by HidClass due to length mismatch). Comment it out and
replace with a pure pass-through. Once our descriptor injection works,
HidClass will see Report 0x12 packets as multi-touch input and our descriptor
defines what to do with them. Apple's filter does the same gesture-to-wheel
synthesis somewhere in `applewirelessmouse.sys` — search disasm for accesses
to BRB_L2CA_ACL_TRANSFER buffer where the byte at offset 0 is 0xA1 (BT HID
data prefix) — that's where their report translation lives. Mimic it.

### Step 4 — Build and report (don't install)

```bash
cd <main-repo-root>
./scripts/mm-dev.sh build
```

Read the resulting session log:

```bash
./scripts/mm-dev.sh log
```

If the build succeeds: stop. Document your changes in your final commit
message. The user will install + verify.

If the build fails: fix and rebuild. If you can't fix in 3 attempts, stop and
write a summary explaining what you couldn't resolve.

## What will end this session early (early-exit conditions)

1. The PRD or briefing files are missing/corrupt → stop, ask user.
2. Build succeeds 2+ times in a row with no test gating → stop, hand back.
3. You discover the SDP scanning approach can't work on this hardware (e.g.,
   live SDP traffic doesn't include the descriptor payload) → stop, document
   what you learned, suggest next architecture.
4. You hit a kernel API you can't use without admin or signing → stop, ask.

## What you DON'T need to do

- Validate runtime behavior (you can't — you don't have the mouse hardware).
- Test the descriptor injection actually fires (the user will, via DebugView).
- Modify the tray app, scripts, PRD docs, or briefing.
- Fix anything outside `driver/`.

## Reference checklist for your final commit message

- [ ] Which BRB completion-routine code path now fires the SDP scanner
- [ ] The exact byte pattern your scanner matches (cite Bluetooth SDP spec
      page if you used one)
- [ ] What happens if the buffer is via MDL vs direct Buffer pointer
- [ ] How length adjustment is propagated (irp->IoStatus.Information,
      BRB.BufferSize, etc.)
- [ ] Why you removed/kept the previous Report 0x12 translation logic
- [ ] What you tested and what you couldn't test

Good luck. The user expects a focused commit set, not a sprawling rewrite.
