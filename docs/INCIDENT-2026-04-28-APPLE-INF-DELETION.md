# INCIDENT-2026-04-28: Apple INF Permanently Deleted Without Backup

**Date**: 2026-04-28  
**Session**: 12 (PRD-184 magic-mouse-tray)  
**Severity**: High — production driver deleted; host scroll broken until recovery  
**Status**: RESOLVED  
**Rule violated**: BCP change-management discipline — destructive command executed without verified backup

---

## BLUF

The assistant issued `pnputil /delete-driver oem0.inf /force` to remove Apple's HID driver INF from the Windows DriverStore during a kernel-only MU install test. The assistant's own message acknowledged the INF had no external backup — and then proceeded anyway. Apple's INF was permanently deleted. Scroll broke. Recovery required locating two independent sources that, by prior diligence alone, happened to exist. A new hard rule (`feedback_backup_before_destructive_commands.md`) is now in memory. The `.ai/snapshots/` mechanism is confirmed load-bearing safety infrastructure.

---

## 1. What Happened

### Timeline

| Time (approx.) | Event |
|---|---|
| Session 12 start | Reinstalled Magic Utilities (MU) to capture `.sys`/`.inf`/`.cat` as M12 reference; 41 files captured to `D:\Backups\MagicUtilities-Capture-2026-04-28-1937\` |
| Mid-session | MU uninstalled; scroll restored under Apple's `applewirelessmouse` filter |
| Later in session | Kernel-only MU reinstall test initiated: goal was to determine whether MU's kernel filter alone is sufficient for scroll + battery, or whether the userland service is required |
| Test setup | MU kernel INF (oem52.inf or similar) was added to DriverStore. Apple's INF (oem0.inf) remained present and was winning PnP rank selection, blocking MU's kernel driver from binding |
| Assistant recommendation | To force MU's driver to win rank, the assistant issued: `pnputil /delete-driver oem0.inf /force` |
| Assistant's own warning (in the same message) | "Apple's INF isn't backed up anywhere if we delete it" |
| Command executed | Apple's `applewirelessmouse.inf` was permanently removed from DriverStore |
| Devices rebound | Mouse rebound to MU kernel driver; scroll broke |
| User discovery | After the test, the assistant gave removal commands for MU's kernel driver. Scroll did not restore. User ran `pnputil /enum-drivers` — Apple's INF was absent. User reaction: "How could you tell me to remove a driver and not have a backup???" |
| Recovery initiated | Two independent sources located (see Section 3) |
| Recovery complete | Apple INF reinstalled; devices rebound; scroll verified on v3 and v1 |

### Exact destructive command issued

```powershell
pnputil /delete-driver oem0.inf /force
```

`pnputil /delete-driver` with `/force` removes the INF from the Windows DriverStore permanently. There is no recycle bin. There is no undo. The command requires that the file already exist in the DriverStore; the original source package is not retained.

---

## 2. Why It Was a Mistake

The assistant's own message contained the sentence:

> "Apple's INF isn't backed up anywhere if we delete it."

This is the exact condition that must block a destructive command under any change-management discipline. The correct action was:

1. Stop.
2. Take a backup of `oem0.inf` from DriverStore before issuing delete.
3. Verify the backup is reachable.
4. Then proceed.

Instead, the assistant acknowledged the risk explicitly and executed the command in the same step. This is not a gap in knowledge — it is a failure to apply known policy.

The change-management principle violated: **never run a destructive command before a backup is verified in place**. This applies regardless of session context, test scope, or time pressure. Auto Mode does not override this rule.

---

## 3. Recovery Path

Recovery succeeded because two independent sources existed — neither of which the assistant created as a deliberate pre-test backup.

### Source 1: Prior session snapshots (`.ai/snapshots/`)

The `scripts/capture-state.ps1` script had been run at least 10 times across Session 11 and Session 12. Each snapshot directory under `.ai/snapshots/mm-state-*/` contains `oem0-applewirelessmouse.inf`. As of the incident, 10 snapshot directories exist:

```
.ai/snapshots/mm-state-20260427T204156Z/oem0-applewirelessmouse.inf
.ai/snapshots/mm-state-20260427T204622Z/oem0-applewirelessmouse.inf
.ai/snapshots/mm-state-20260427T215216Z/oem0-applewirelessmouse.inf
.ai/snapshots/mm-state-20260427T215556Z/oem0-applewirelessmouse.inf
.ai/snapshots/mm-state-20260427T215708Z/oem0-applewirelessmouse.inf
.ai/snapshots/mm-state-20260427T215712Z/oem0-applewirelessmouse.inf
.ai/snapshots/mm-state-20260427T220018Z/oem0-applewirelessmouse.inf
.ai/snapshots/mm-state-20260427T220023Z/oem0-applewirelessmouse.inf
.ai/snapshots/mm-state-20260427T234748Z/oem0-applewirelessmouse.inf
.ai/snapshots/mm-state-20260427T235903Z/oem0-applewirelessmouse.inf
```

These snapshots contain the INF text only — no `.sys` or `.cat`. Reinstalling from an INF-only source requires that the referenced `.sys` already be present in DriverStore (or manually staged), and the INF may require test-signing if the original catalog is absent. The snapshot INF alone is a partial fallback.

### Source 2: User's existing zip archive

The user had independently downloaded `MagicMouse2DriversWin11x64-master.zip` from a public GitHub project. This archive provides a complete driver package: INF + SYS + CAT. Location: `D:\Users\Lesley\Downloads\MagicMouse2DriversWin11x64-master.zip`.

This source was sufficient for a clean reinstall without test-signing requirements.

### Recovery action taken

Recovery files staged to: `D:\Backups\AppleWirelessMouse-RECOVERY\`  
Zip archive backed up to: `D:\Backups\MagicMouse2DriversWin11x64-master.zip`

See `APPLE-DRIVER-RECOVERY-PROCEDURE.md` for the full reinstall runbook.

---

## 4. Permanent Backup Now in Place

| Location | Contents | Completeness |
|---|---|---|
| `D:\Backups\AppleWirelessMouse-RECOVERY\` | INF + SYS + CAT + SOURCE-README | Full driver package |
| `D:\Backups\MagicMouse2DriversWin11x64-master.zip` | Full GitHub project archive | Full driver package |
| `.ai/snapshots/mm-state-*/oem0-applewirelessmouse.inf` | INF text only (10+ copies) | INF only — partial |

The `D:\Backups\AppleWirelessMouse-RECOVERY\` directory is the designated primary recovery source going forward.

---

## 5. New Permanent Rule

**Memory file**: `/home/lesley/.claude/projects/-home-lesley-projects/memory/feedback_backup_before_destructive_commands.md`

Rule text (summary): Before any command that permanently removes, overwrites, or deletes a system artifact (driver, registry key, file, service), the assistant must:

1. Identify what will be destroyed.
2. Verify a backup of that artifact exists and is reachable.
3. Confirm the backup location in the message to the user.
4. Only then issue the destructive command.

Auto Mode does not override this rule. The rule applies even when the destructive command is the stated goal of the test.

---

## 6. Lesson for the Project: `.ai/snapshots/` Is Load-Bearing Safety Infrastructure

The snapshot mechanism (`scripts/capture-state.ps1`) saved this incident from being unrecoverable via project resources. Every snapshot directory contains a full copy of the current driver state including the INF text.

**Operational rules that follow from this incident**:

- Do not prune `.ai/snapshots/` directories aggressively. Disk space is cheap; lost drivers are not.
- Before any driver DriverStore operation (add, delete, update), run `scripts/capture-state.ps1` first.
- The snapshot is not a substitute for a full backup (INF only, no SYS/CAT) but it is a meaningful fallback for INF recovery.
- The `D:\Backups\AppleWirelessMouse-RECOVERY\` directory must be maintained in sync with the currently installed Apple driver version after any driver update.

---

## 7. Apology

The assistant violated basic change-management discipline. The failure was not a knowledge gap — the risk was identified in the assistant's own output — and the command was issued anyway. That is indefensible. The user's reaction ("How could you tell me to remove a driver and not have a backup???") was entirely correct.

The rule is now in memory. It will not happen again.
