# BTHPORT Descriptor Cache Patch — Safety Review

**Date:** 2026-04-27
**Reviewer:** Windows Registry & Security Auditor (Claude Sonnet 4.6)
**Scope:** Phase 4 of M13 — patching `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\<mac_lowercase>\CachedServices\00010000` (REG_BINARY) to inject a vendor battery TLC (UP=0xFF00 U=0x0014, Report 0x90), then forcing PnP re-enumeration via `Disable-PnpDevice` + `Enable-PnpDevice` on the BTHENUM parent.
**References:** M13 test plan, registry-diff-2026-04-27.md, windows-audit-2026-04-27.md, applewirelessmouse.sys rev-eng findings
**Mode:** Read-only audit — no registry mutations performed.

---

## Findings (ordered by severity)

---

### FINDING 1 — SEVERITY: HIGH
#### In-memory descriptor state survives registry restore; rollback is not atomic

**The problem.** The M13 rollback plan states: snapshot the registry before patching, auto-rollback if `mm-accept-test` fails. This is correct for registry state, but BTHPORT keeps the parsed descriptor in non-paged pool (kernel memory) after it reads the cache at device start time. If the test sequence is:

1. Write patched blob to registry
2. Disable+Enable BTHENUM (forces BTHPORT to re-read cache → loads patched descriptor into kernel pool)
3. `mm-accept-test` fails
4. Restore snapshot (writes original blob back to registry)
5. — BTHPORT memory still holds the patched descriptor until the next device-start cycle —

The registry is back to clean, but the running driver has the modified in-memory structure. Any attempt to read battery state in this window will use the patched descriptor. The device must be disabled+enabled a **second** time after the registry restore to force BTHPORT to re-parse the original blob. The current plan only calls for one disable+enable cycle (the test trigger) and does not call for a second disable+enable in the rollback path.

**Blast radius if ignored:** After a failed patch attempt, the accept test runs against patched-descriptor-in-memory but restored registry. A pass on the accept test in this state would be a false positive — the device appears healthy only until the next reboot or BT reconnect, at which point BTHPORT re-reads the original (unpatched) registry blob and the COL02 collection disappears. Conversely, a fail followed by registry restore leaves the device in a state where `HID\..._COL02` is still in the PnP tree (from the patched enumerate) but the descriptor it advertises no longer matches what the cache will produce on next device start. This can manifest as Code 43 on the COL02 node after reboot.

**Required mitigation:** Extend the rollback procedure to always perform a second Disable+Enable after registry restore. Update `mm-bthport-patch.ps1` to include a `Restore-AndReload` function that: (a) writes original blob, (b) disables BTHENUM HID device, (c) enables it, (d) waits for device stable, (e) only then reruns accept test to confirm clean state.

---

### FINDING 2 — SEVERITY: HIGH
#### SDP TLV length bytes must be patched in three places; patch tool must not assume blob is fixed-size

**The problem.** The v3 `CachedServices\00010000` blob is a well-formed SDP `ServiceAttributeResponse`. The outer structure is:

```
36 01 5c  <- SDP Data Element Sequence, 2-byte length = 0x015c (348 bytes total content)
  09 00 00  <- Attribute 0x0000 (ServiceRecordHandle)
  ...
  09 02 06  <- Attribute 0x0206 (HIDDescriptorList)
    35 ??   <- Sequence containing the descriptor class descriptor
      08 22  <- ClassDescriptorType = 0x22 (Report Descriptor)
      25 87  <- string of length 135 (the embedded HID descriptor bytes)
        [135 bytes of HID descriptor]
```

When we insert a vendor TLC (e.g., 9 bytes of HID descriptor items for UP=0xFF00, U=0x0014, Report ID 0x90, 1 byte value), the following length fields in the blob must ALL be updated:
1. Outer SDP sequence length at bytes [1:3] (`36 01 5c` → e.g., `36 01 65`)
2. The HIDDescriptorList sequence length byte
3. The embedded descriptor string length byte (`25 87` → `25 90`)

If any one of these is wrong, BTHPORT will parse a malformed SDP record. Behavior in that case is driver-dependent (see Finding 3), but the worst case is that BTHPORT treats the entire blob as invalid and fails device enumeration.

The plan says "updates SDP TLV length bytes" — that's correct intent, but the implementation in `mm-bthport-patch.ps1` must be verified to update ALL three length fields and must handle variable-length SDP encoding (1-byte vs 2-byte length depending on content size). The current v3 descriptor uses 2-byte length at the outer sequence (`36 01 5c`) but 1-byte lengths at inner sequences. Adding content that pushes any inner sequence past 127 bytes would require a length encoding change from `35 NN` (1-byte) to `36 NN NN` (2-byte), shifting all subsequent offsets. The patch tool must be aware of this boundary.

**Required mitigation:** Implement `mm-bthport-patch.ps1` with a proper SDP TLV recursive parser/re-serializer, not a fixed-offset patcher. Verify the output blob length arithmetic against the hex dumps in `registry-diff-2026-04-27.md` before writing to registry.

---

### FINDING 3 — SEVERITY: MEDIUM
#### BTHPORT does not verify a cryptographic signature on the cache, but malformed blobs have unpredictable parse-failure behavior

**What is known.** The CachedServices blob is written by BTHPORT.SYS at pairing time from the raw SDP `ServiceAttributeResponse` returned by the device. There is no checksum, HMAC, or DSA signature field in the SDP protocol or in BTHPORT's cache format — this is confirmed by the raw hex in the diff report (no prefix that would indicate a Windows-proprietary wrapper). BTHPORT reads the blob at device start and passes the embedded HID descriptor to HidBth via the `BRB_HCI_GET_LOCAL_BD_ADDR` + descriptor-list path.

**What is unknown.** How BTHPORT responds to a structurally malformed SDP record depends on internal error handling not visible in public documentation or the available rev-eng artifacts. Observed behaviors in similar driver-cache-patch scenarios across the Windows BT stack include:

- **Graceful degradation:** BTHPORT ignores the malformed attribute and uses defaults → device enumerates with reduced capability. Likely outcome for a malformed `HIDDescriptorList` attribute specifically.
- **Device node failure:** BTHPORT returns an error to PnP for AddDevice → BTHENUM device node goes to `CM_PROB_FAILED_ADD` (Code 31) or `CM_PROB_DEVICE_NOT_THERE` (Code 24). Recoverable via registry restore + disable/enable.
- **BSOD:** If BTHPORT or HidBth passes a malformed descriptor pointer to an unchecked consumer. The M13 test plan acknowledges this risk (halt condition: BSOD on disable+enable). This is low probability for a well-formed blob with wrong lengths but non-zero for a descriptor that passes SDP parsing but has an internally invalid HID item sequence (e.g., a Collection Open without a matching Collection Close).

**Consequence.** The patch cannot brick the BT stack permanently — the BT adapter itself (BTHPORT's lower layer) is separate from the device-specific cache. A corrupted cache entry for one MAC affects only that device's enumeration; the adapter itself continues to function and other paired devices are unaffected. A registry restore + Disable+Enable recovers the device in all non-BSOD cases.

**Required mitigation:** Validate the patched HID descriptor bytes independently (e.g., pass through a HID descriptor validator before inserting into the SDP blob). Ensure the appended TLC has matching Collection Open/Close tags. The proposed TLC (UP=0xFF00 U=0x0014 Report 0x90) already exists natively in the v3 descriptor — verify this before patching, because if COL02 is already present in the cache (the M13 Phase 3 decode may confirm this), the patch is unnecessary and the root cause is upstream in `applewirelessmouse.sys` stripping it.

---

### FINDING 4 — SEVERITY: MEDIUM
#### ACL — write access to HKLM\SYSTEM requires built-in Administrator, not just a standard admin token

**Who can write.** `HKLM\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Devices\` has default DACL of `SYSTEM: Full Control`, `Administrators: Full Control`. The `Administrators` group here means the local Administrators group with an **elevated** token — i.e., UAC-elevated shell or process running with high mandatory integrity level (MIL). A standard limited user account has Read access only.

**What happens if non-admin runs the patch tool.** `RegOpenKeyEx` with `KEY_SET_VALUE` will return `ERROR_ACCESS_DENIED` (5). In PowerShell: `Set-ItemProperty` will throw `Requested registry access is not allowed`. The patch tool should detect this and surface a clear error rather than silently writing nothing.

**Escalation surface.** The patch is a `REG_BINARY` write to an existing key the calling process has legitimate elevated access to. It does not create new services, does not modify `HKLM\SYSTEM\CurrentControlSet\Services\` service entries directly, and does not load or register a driver binary. There is no privilege escalation vector here beyond what already comes with an elevated admin token. The risk profile is equivalent to any other admin-level registry modification.

**For a distributable tool.** The tool must either: (a) require explicit UAC elevation at launch (manifest `requireAdministrator`), or (b) detect the non-elevated condition and re-launch itself with elevation via `Start-Process -Verb RunAs`. Option (a) is simpler and more predictable. The tool should never silently succeed with a partial write if elevation is missing.

**Required mitigation for M13 test:** Run `mm-bthport-patch.ps1` only from an elevated PowerShell session. Add a preflight check at line 1: `if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Must run elevated" }`.

---

### FINDING 5 — SEVERITY: MEDIUM
#### Concurrency — BTHPORT may hold the cached descriptor in a read context while we write; registry transactions are not coordinated with driver state

**The problem.** The registry write (`Set-ItemProperty` or `reg.exe import`) is not coordinated with BTHPORT's internal locking. BTHPORT reads the `CachedServices` blob at two points: (1) at device AddDevice/Start time, and (2) potentially during a reconnect after a BT link loss. If the mouse loses its BT link and reconnects while the patch tool is mid-write (between the old and new REG_BINARY values), BTHPORT could read a partial blob.

**Risk level.** Low-to-medium in practice. `RegSetValueEx` for a `REG_BINARY` is a single kernel call; it completes atomically from the registry's perspective (the registry kernel object provides its own internal locking). The write is atomic at the registry layer. The race window is: BTHPORT checks whether to re-read the cache exactly at the moment the value transitions. In practice, BTHPORT reads the cache at AddDevice time only — not continuously — so the race requires a spontaneous BT reconnect to coincide with the write, which is unlikely but not impossible if the mouse goes to sleep/wakes mid-patch.

**Required mitigation:** Ensure the mouse is in a stable connected state before patching. Add a pre-patch step: confirm BT connection is stable (ping via HID report or check device status), then patch, then immediately trigger the disable+enable. The window between patch write and disable+enable should be minimized. Do not patch while the mouse is mid-gesture.

---

### FINDING 6 — SEVERITY: MEDIUM
#### Cache invalidation triggers — sleep/wake and un-pair/re-pair are the two that matter

The diff report confirms the cache survives driver install/uninstall. Analysis of remaining triggers:

| Trigger | Cache behavior | Confidence |
|---|---|---|
| Sleep (S3) / Wake | Cache PERSISTS. BTHPORT re-reads cache on re-AddDevice after wake, using whatever is in registry. | High — confirmed by diff showing cache unchanged across multiple driver cycles which include sleeps. |
| Hibernate (S4) | Cache PERSISTS for same reason as S3. | High. |
| BT adapter disable/enable (Device Manager) | Cache PERSISTS. Adapter-level disable does not clear per-device cache. | High. |
| BT adapter SWAP (different USB dongle or PCIe card) | Cache PERSISTS under the same pairing MAC. The cache key is per-MAC, not per-adapter. A new adapter sees the same `Parameters\Devices\<mac>` entries. | High — cache path contains no adapter identifier. |
| Windows Update touching BTHPORT.SYS | Cache PERSISTS. Driver binary update does not reset the `Parameters\Devices\` subtree. This is consistent with the update design — BTHPORT migration code would need to explicitly clear the cache on schema change; no evidence of this exists. | Medium — relies on Microsoft not having added a schema-version migration in a recent update (see Finding 7). |
| User un-pairs and re-pairs via Settings UI | Cache IS REGENERATED. When the user removes the device from BT Settings and re-pairs, BTHPORT performs a fresh SDP query to the device and overwrites `CachedServices\00010000` with the live response from the mouse. This is the primary cache invalidation trigger and WILL erase the patch. | High — fundamental to BT pairing protocol. |
| System reboot (device remains paired) | Cache PERSISTS. Reboot does not trigger a re-pair; BTHPORT reads existing cache on next device start. | High. |

**Key operational implication:** Any end-user who un-pairs and re-pairs their mouse (e.g., to reconnect to a different machine, or after a BT glitch) will lose the patch. The patched cache value has a lifetime bounded by the pairing. This must be documented clearly in any M13 deliverable. A production-ready version of the patch tool would need a detection mechanism (e.g., checksum the cache on tray startup, re-patch if it no longer matches the expected patched state).

---

### FINDING 7 — SEVERITY: LOW
#### Cross-version compatibility — schema stability is not guaranteed but no breaking change is known

**Known schema.** The `CachedServices\00010000` format is a raw SDP `ServiceAttributeResponse` PDU, as specified in the Bluetooth SDP specification (Bluetooth Core Spec v5.x Part E). This is a published, stable standard. BTHPORT.SYS has stored this blob in this location since at least Windows Vista; the registry-diff data shows no schema change across three timestamps spanning months. The SDP TLV structure we are patching is defined by the Bluetooth SIG specification, not by a proprietary Microsoft format.

**Risk.** Microsoft could change how BTHPORT consumes the cache between Windows 11 builds without public notice. This is theoretically possible (internal migration code) but no evidence of it exists in the available data. The blob being byte-identical between the Apr 3 MU-era and Apr 27 AppleFilter-era, across likely at least one cumulative update cycle, supports stability.

**Cross-build risk for distribution.** A patching tool that hardcodes offsets into the SDP blob (rather than parsing TLV) would be fragile. A tool that properly parses SDP TLV (as recommended in Finding 2) is self-adapting to any valid blob and should work across all Windows 11 builds that implement the standard cache path.

---

### FINDING 8 — SEVERITY: LOW (ADVISORY)
#### Legal/policy — distributing an HKLM\SYSTEM modifier to end users carries shippability implications

**For M13 investigation:** No concern. Patching registry keys under `HKLM\SYSTEM\` during driver development and testing is a normal and legitimate activity. It does not violate Microsoft's terms of service for Windows.

**For a distributed tool.** Several considerations apply before shipping:

1. **Driver signing policy.** The patch itself is a registry write, not a driver load. It does not trigger Windows Driver Signing enforcement. No kernel code is executed by the patch tool itself. However, the downstream effect — causing BTHPORT to build a different HID descriptor stack than Apple's firmware declared — means the HID device stack operates on data that differs from the hardware's SDP response. This is not prohibited but it is unusual.

2. **Windows Defender / AV flagging.** Tools that write to `HKLM\SYSTEM\CurrentControlSet\Services\` or adjacent paths are a common signature for malware and rootkit installers. Microsoft Defender's behavior-based engine may flag `mm-bthport-patch.ps1` as suspicious, especially if it also calls `Disable-PnpDevice`/`Enable-PnpDevice`. The tool should be code-signed and ideally submitted to Microsoft for file reputation building before distribution.

3. **Support liability.** If the patch tool corrupts a user's BT pairing state and they are unable to restore it (e.g., registry export was not taken, or restore fails), there is a support burden. The snapshot + rollback mechanism in the M13 plan is the correct approach; any distributed version must make the backup mandatory (not optional).

4. **Microsoft Store / App certification.** A Windows Store app is prohibited from writing to `HKLM\SYSTEM\`. The tray application + patch approach would need to be distributed as a traditional Win32 installer, not a Store package.

**Recommendation:** Flag these items for pre-shipping review. They do not affect M13 investigation.

---

## Summary Table

| Finding | Severity | Blocks M13 Phase 4? | Fix before proceeding? |
|---|---|---|---|
| 1 — Rollback missing second Disable+Enable | HIGH | Yes | Yes — update `mm-bthport-patch.ps1` rollback path |
| 2 — Patch tool must parse SDP TLV, not fixed offsets | HIGH | Yes | Yes — verify implementation before first write |
| 3 — Malformed blob behavior; HID descriptor validation | MEDIUM | No (halt condition handles BSOD) | Recommended — add HID descriptor pre-validation |
| 4 — ACL: elevated token required | MEDIUM | No (M13 is admin-only manual test) | Preflight check in script |
| 5 — Concurrency with BT reconnect | MEDIUM | No (low probability in controlled test) | Ensure stable BT state before patching |
| 6 — Re-pair erases the patch | MEDIUM | No (empirical finding, not a blocker) | Document in M13 deliverables |
| 7 — Cross-build schema stability | LOW | No | Use TLV parser (covered by Finding 2 fix) |
| 8 — Distribution shippability | LOW (advisory) | No | Defer to post-M13 |

---

## Conditions for APPROVE-WITH-CONDITIONS

If proceeding with Phase 4 as designed, the following safeguards are required before the first registry write:

**Condition 1 (mandatory).** Update the rollback procedure in `mm-bthport-patch.ps1` to perform a second `Disable-PnpDevice` + `Enable-PnpDevice` cycle after registry restore. The second cycle ensures BTHPORT re-parses the restored blob and clears any in-memory patched state before the accept test reruns. The accept test for a "rollback succeeded" state must pass 8/8 on the restored-to-clean configuration.

**Condition 2 (mandatory).** Implement the SDP TLV patcher as a recursive parser, not a fixed-offset writer. Before writing the patched blob to registry, log the before/after byte lengths and verify: (a) outer sequence length field is consistent with actual blob size; (b) HIDDescriptorList inner sequence length is consistent; (c) descriptor string length byte matches the descriptor byte count; (d) all Collection Open tags in the appended TLC have a matching Collection Close. Print this verification to the test log before proceeding.

**Condition 3 (recommended).** Add an elevated-admin preflight check at the top of `mm-bthport-patch.ps1`. Fail loudly if not running elevated.

**Condition 4 (recommended).** Document in the M13 test log that re-pairing the mouse will erase the patch. Record whether the COL02 node status after the patch survives a reboot (it should, per Finding 6).

---

## VERDICT: APPROVE-WITH-CONDITIONS

Phase 4 may proceed once Conditions 1 and 2 above are implemented. The fundamental approach — patching the SDP cache blob, forcing PnP re-enumeration — is technically sound, uses normal admin-level registry access, and has a viable rollback path once the two-stage restore is added. The primary risk (in-memory state not flushed on rollback) is a correctness bug, not a safety-of-the-BT-stack issue, and it is straightforwardly mitigated. No evidence exists that BTHPORT verifies a signature or checksum on the cache, so the patch will be accepted by the driver. The BT adapter and other paired devices are not at risk. The worst-case unrecoverable failure scenario (BSOD producing a crashdump) is already an explicit halt condition in the test plan.
