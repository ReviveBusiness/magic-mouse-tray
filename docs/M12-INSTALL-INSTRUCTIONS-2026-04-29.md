---
created: 2026-04-29
modified: 2026-04-29
type: install-instructions
audience: Lesley (morning review)
risk: HIGH — kernel driver install can BSOD or break Bluetooth stack
---

# M12 Driver Morning Install — 2026-04-29

> **STATUS**: Pending cycle-2 review verdict. **Do NOT install yet** unless reviewer convergence is achieved overnight.

## Pre-flight (read before running anything)

### Why this is risky
M12 is a KMDF lower filter on the BTHENUM stack. It intercepts Bluetooth Request Blocks (BRBs) carrying SDP descriptors and HID payloads. A bug in the IRP completion path can BSOD the system. A bug in the BRB length validation can corrupt nonpaged pool. **Have your Dell USB mouse plugged in before installing** (recovery cursor when Magic Mouse v3 is broken).

### What's been verified before reaching you
- ✅ Compiles cleanly (Release/x64, EWDK 10.0.26100.0)
- ✅ 5-reviewer adversarial code review (KMDF/IRP, HID/Desc, Security, Arch/Style, NotebookLM corpus)
- ✅ Static style + AI-tells gate (`scripts/check-style.sh`)
- ✅ PREfast static analysis (`/p:RunCodeAnalysis=true`)
- ✅ Signed by `CN=MagicMouseFix` (already in `LocalMachine\TrustedPublisher` on this machine)
- ✅ Catalog produced by Inf2Cat
- ✅ Both `.sys` and `.cat` verified by `signtool verify /pa`

### What has NOT been verified
- ❌ **Driver Verifier 0x49bb runtime check** — requires the driver to be installed; can't run statically
- ❌ Behavior on a real Magic Mouse v3 — first install IS the test
- ❌ Recursive TLV SDP parser — current code uses byte-pattern matching (deferred per cycle-1 review; works for current 113-byte descriptor pattern but fragile if Apple's descriptor changes shape)
- ❌ Channel race resilience under high BT load (tested only by code review)

## Recovery plan (read FIRST)

If anything goes wrong:

1. **Boot to Safe Mode** (Shift + Restart → Troubleshoot → Advanced → Startup Settings → F4)
2. Open elevated cmd
3. Remove M12: `pnputil /enum-drivers | findstr /i M12` then `pnputil /delete-driver oemNN.inf /uninstall /force`
4. Restore Apple driver: copy from backup at `D:\Backups\AppleWirelessMouse-RECOVERY\`
   ```
   pnputil /add-driver D:\Backups\AppleWirelessMouse-RECOVERY\applewirelessmouse.inf /install
   ```
5. Re-pair Magic Mouse v3 from Bluetooth settings
6. Reboot normally

## Install (only after you've read the cycle-2 review verdict)

### 1. Backup state (one-shot, idempotent)
```powershell
# Already done in prior session — verify backup exists:
ls D:\Backups\AppleWirelessMouse-RECOVERY\*.sys
# Should show applewirelessmouse.sys + .inf
```

### 2. Confirm staged bundle
```powershell
ls D:\mm3-driver\MagicMouse*
# Should show: MagicMouseDriver.sys, .inf, .cat
```

### 3. Verify signatures (read-only check, harmless)
```powershell
$st = 'F:\Program Files\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe'
& $st verify /pa /v 'D:\mm3-driver\MagicMouseDriver.sys'
& $st verify /pa /v 'D:\mm3-driver\MagicMouseDriver.cat'
# Both should report "Successfully verified" with chain ending at MagicMouseFix
```

### 4. Remove the existing Apple driver from the stack (required — coexistence rejected by design)
```powershell
# Find the Apple oem*.inf
pnputil /enum-drivers | Select-String -Pattern "applewirelessmouse" -Context 1,1
# Note the oemNN.inf number, then:
pnputil /delete-driver oemNN.inf /uninstall /force
```

### 5. Install M12 driver
```powershell
pnputil /add-driver D:\mm3-driver\MagicMouseDriver.inf /install
```
Expected result: `Driver package added successfully` + `Driver installed on N matching device(s)` (where N = number of paired Magic Mouse v3 instances).

### 6. Re-pair Magic Mouse v3
- Bluetooth settings → remove Magic Mouse if present → put mouse in pairing mode → re-pair
- This forces BTHENUM to re-enumerate so M12 binds as lower filter on the fresh PDO

### 7. Smoke test
- ✅ Cursor moves
- ✅ Scroll works (Force Touch trackpad gestures don't apply, but scroll does)
- ✅ Tray app shows battery percentage (within 60s of pairing — tray polls)
- ✅ No event log errors at `Windows Logs/System` filtered by source `Microsoft-Windows-Kernel-PnP`

If any of the above fails:
- Cursor stuck or no scroll → **uninstall M12 immediately** (step 4 in reverse)
- BSOD on next boot → boot Safe Mode, recovery plan above
- Tray battery shows 0% or "unknown" → may be transient; check tray logs at `%APPDATA%\MagicMouseTray\` for errors

## Cycle-1 review summary (cycle-2 pending)

See `REVIEW-VERDICTS-M12-DRIVER-2026-04-29.md` for full reviewer output. Key install-blockers fixed this cycle:

- SDP length-fixup offset bug (writes were at -3,-5; corrected to -5,-7)
- Dead `HidDescriptor_Handle` function with raw `UserBuffer` deref deleted
- BRB length validation at offset 0x10 before any write at offset 0x84
- BRB pointer recovery via per-request context (replaces fragile WDF assumption)
- CLOSE_CHANNEL race fixed (handle clear deferred to completion routine)
- WDFSPINLOCK added to DEVICE_CONTEXT (parallel queue race fix)
- DriverVer bumped to 01/01/2027 for PnP rank
- Stale doc strings updated

Known follow-ups (not blocking install):
- SDP scanner is byte-pattern matching, not recursive TLV. Works for current descriptor shape. Replace with proper SDP TLV parser in next cycle.
- Driver Verifier 0x49bb cycle test deferred to post-install validation
- VID format (`0001004C` vs `00010005AC`) — the current INF uses `0001004C`, which is correct for BTHENUM (Apple BT SIG company ID 0x004C). One reviewer mandated the USB-VID-style `00010005AC`; that would not bind on BTHENUM and is wrong.

## Files at this stage

| File | Path | Purpose |
|---|---|---|
| Driver binary | `D:\mm3-driver\MagicMouseDriver.sys` | Signed, runs in kernel |
| INF | `D:\mm3-driver\MagicMouseDriver.inf` | PnP install metadata |
| Catalog | `D:\mm3-driver\MagicMouseDriver.cat` | Signature catalog (signtool /verify) |
| Cert | (in cert store) `LocalMachine\My` thumbprint `B902C2864315E2DE359450024768CE7D01715C38` | Used to sign |
| Source | `~/.claude/worktrees/ai-m12-script-tests/driver/` | Branch `ai/m12-script-tests` |

## When to escalate to Lesley

- Any reviewer in cycle 2 returns REJECT (don't install)
- BSOD or device disappear on first install
- pnputil errors on `/add-driver` or `/install`
- Tray app reports `DriverStatus.NotInstalled` after re-pair
