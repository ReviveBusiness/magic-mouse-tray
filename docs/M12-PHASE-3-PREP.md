# M12 Phase 3 Prep - Build/Sign/DV-CHECK Route Reference

## BLUF

Three new routes added to `scripts/mm-task-runner.ps1` for Phase 3 driver agent use:
BUILD dispatches EWDK msbuild via the admin task queue; SIGN invokes signtool;
DV-CHECK configures Driver Verifier. All routes are ASCII-safe, PS 5.1 compatible,
and follow the existing nonce/result.txt protocol.

---

## Protocol recap

All routes use the same filesystem queue pattern:

| File | Role |
|------|------|
| `C:\mm-dev-queue\request.txt` | WSL writes route args (ASCII, pipe-delimited) |
| `C:\mm-dev-queue\result.txt` | Runner writes `EXITCODE|NONCE` on completion |
| `C:\mm-dev-queue\running.lock` | Concurrency guard (stale after 30 min) |
| `C:\mm-dev-task.log` | Per-run log (timestamped) |

WSL dispatch sequence:
1. Write request.txt
2. `schtasks /run /tn MM-Dev-Cycle`
3. Poll result.txt for matching nonce (recommended: 5s interval, 300s timeout)
4. Read route-specific log file for detail

---

## BUILD route

### Request format

```
BUILD|<nonce>|<config>|<platform>[|<sln-path>]
```

| Field | Values | Default |
|-------|--------|---------|
| nonce | any unique string (e.g. hex timestamp) | required |
| config | Release, Debug | Release |
| platform | x64 | x64 |
| sln-path | full Windows path to .sln | `\\wsl.localhost\Ubuntu\home\lesley\projects\Personal\magic-mouse-tray\driver\M12.sln` |

### Result

`result.txt` contains `EXITCODE|NONCE` where EXITCODE is the msbuild exit code (0 = success).

### Log file

`C:\mm-dev-queue\build-<nonce>.log` - full msbuild output (stdout + stderr combined).

### Pre-conditions

- EWDK ISO must be mounted at `F:\`
- `F:\LaunchBuildEnv.cmd` must exist
- Solution file must be accessible from Windows (WSL path via `\\wsl.localhost\...` works)

### Example (from WSL)

```bash
NONCE="$(date +%s%N | head -c 12)"
SLN="\\\\wsl.localhost\\Ubuntu\\home\\lesley\\projects\\Personal\\magic-mouse-tray\\driver-test\\HelloWorld.sln"
printf "BUILD|%s|Release|x64|%s" "$NONCE" "$SLN" > /mnt/c/mm-dev-queue/request.txt
/mnt/c/Windows/System32/schtasks.exe /run /tn MM-Dev-Cycle
# poll result.txt for $NONCE, then:
cat "/mnt/c/mm-dev-queue/build-${NONCE}.log"
```

---

## SIGN route

### Request format

```
SIGN|<nonce>|<sys-path>|<cat-path>|<pfx-path>|<pfx-pass-env-var>
```

| Field | Description |
|-------|-------------|
| nonce | unique string |
| sys-path | full Windows path to .sys file to sign |
| cat-path | full Windows path to .cat file to sign |
| pfx-path | full Windows path to .pfx certificate file |
| pfx-pass-env-var | name of Windows env var holding PFX password (avoids plaintext in request.txt) |

### Result

`result.txt` contains `EXITCODE|NONCE` (0 = both files signed successfully).

### Log file

`C:\mm-dev-queue\sign-<nonce>.log` - signtool output for both signing operations.

### Pre-conditions

- signtool at `F:\Program Files\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe`
- PFX file accessible from Windows side
- If pfx-pass-env-var is set, that env var must exist in the SYSTEM environment

### Example

```bash
NONCE="sign-$(date +%s)"
SYS="C:\\build\\M12.sys"
CAT="C:\\build\\M12.cat"
PFX="C:\\certs\\M12-test.pfx"
printf "SIGN|%s|%s|%s|%s|M12_PFX_PASS" "$NONCE" "$SYS" "$CAT" "$PFX" > /mnt/c/mm-dev-queue/request.txt
/mnt/c/Windows/System32/schtasks.exe /run /tn MM-Dev-Cycle
```

---

## DV-CHECK route

### Request format

```
DV-CHECK|<nonce>|<driver-name>
```

| Field | Description |
|-------|-------------|
| nonce | unique string |
| driver-name | driver filename only, e.g. `M12.sys` (no path) |

### Result

`result.txt` contains `EXITCODE|NONCE`.

| Exit code | Meaning |
|-----------|---------|
| 0 | Driver Verifier configured for driver-name; reboot required to activate |
| 2 | Missing driver-name arg |
| 99 | Exception during verifier invocation |

### Log file

`C:\mm-dev-queue\dv-<nonce>.log` - output of `verifier /flags` command + `verifier /query`.

### DV flags configured

`0x49bb` = special pool + force IRQL checking + low-resources simulation + IRP logging +
I/O verification + deadlock detection + DMA verification + security checks + IRP logging.
Source: M12-PRODUCTION-HYGIENE-FOR-V1.3.md Section 4.

### Important

DV-CHECK configures the verifier settings. The verifier only activates after a system reboot.
After rebooting, run the DV soak (VG-8): 1000 IOCTL cycles + 100 pair/unpair cycles,
then check `verifier /query` for any flags fired.

### Example

```bash
NONCE="dv-$(date +%s)"
printf "DV-CHECK|%s|M12.sys" "$NONCE" > /mnt/c/mm-dev-queue/request.txt
/mnt/c/Windows/System32/schtasks.exe /run /tn MM-Dev-Cycle
```

---

## HelloWorld build-test scaffold

Location: `driver-test/HelloWorld.sln`

Purpose: smoke-test the BUILD pipeline without the full M12 solution. Binds to
`USB\VID_FFFF&PID_FFFF` (non-existent device - build only, never install).

Files:
- `driver-test/HelloWorld.c` - DriverEntry returning STATUS_SUCCESS via WdfDriverCreate
- `driver-test/HelloWorld.inf` - INF binding to non-existent USB VID/PID
- `driver-test/HelloWorld.vcxproj` - KMDF driver msbuild project (EWDK toolset)
- `driver-test/HelloWorld.sln` - Solution file

Expected build output: `driver-test/build/Release/x64/HelloWorld.sys`

### Dispatch command (from WSL)

```bash
NONCE="hw-$(date +%s)"
SLN="\\\\wsl.localhost\\Ubuntu\\home\\lesley\\projects\\Personal\\magic-mouse-tray\\driver-test\\HelloWorld.sln"
printf "BUILD|%s|Release|x64|%s" "$NONCE" "$SLN" > /mnt/c/mm-dev-queue/request.txt
/mnt/c/Windows/System32/schtasks.exe /run /tn MM-Dev-Cycle
# Poll for result:
for i in $(seq 1 60); do
    sleep 5
    if grep -q "^0|$NONCE$" /mnt/c/mm-dev-queue/result.txt 2>/dev/null; then
        echo "BUILD SUCCESS"
        break
    elif grep -q "|$NONCE$" /mnt/c/mm-dev-queue/result.txt 2>/dev/null; then
        echo "BUILD FAILED:"
        cat "/mnt/c/mm-dev-queue/build-${NONCE}.log"
        break
    fi
done
```

---

## Activity Log

| Date | Update |
|------|--------|
| 2026-04-28 | Added BUILD, SIGN, DV-CHECK routes to mm-task-runner.ps1; created HelloWorld scaffold in driver-test/ |
