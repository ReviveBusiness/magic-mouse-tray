# M12 CRD Config Integration Note -- For v1.3

**To:** M12 v1.3 design agent
**From:** ai/m12-empirical-and-crd session (2026-04-28)
**Action:** MUST fold into M12-DESIGN-SPEC.md before v1.3 is approved

This note describes what changed and exactly which sections of M12-DESIGN-SPEC.md
need updating to incorporate the K8s-CRD-style registry config schema.

---

## A. Summary of schema deliverable

`docs/M12-CONFIG-SCHEMA.md` defines a two-level registry config:

1. `HKLM\...\Services\M12\Parameters\` -- global driver tunables (DebugLevel, PoolTag)
2. `HKLM\...\Services\M12\Devices\VID_<V>&PID_<P>\` -- per-device config (battery,
   scroll, feature flags)

Per-device config is keyed by PID string. Adding a new Magic Mouse variant requires
only a new registry subkey -- no driver rebuild.

---

## B. Design changes required for v1.3

### B1. DEVICE_CONTEXT -- extend for per-device config

Current v1.2 DEVICE_CONTEXT has only two tunables (`BatteryOffset`, `FirstBootPolicy`).
v1.3 must add all schema fields:

```c
typedef struct _DEVICE_CONTEXT {
    WDFDEVICE      Device;
    WDFIOTARGET    IoTarget;
    WDFQUEUE       IoctlQueue;
    WDFQUEUE       ReadQueue;

    USHORT         Vid;
    USHORT         Pid;

    // Shadow buffer
    KSPIN_LOCK     ShadowLock;
    SHADOW_BUFFER  Shadow;

    // --- NEW in v1.3: from registry schema ---
    UCHAR          BatteryReportId;       // default 0x27
    UCHAR          BatteryReportLength;   // default 46
    ULONG          BatteryOffset;         // default 0 (was 1 in v1.2 -- CHANGE)
    BOOLEAN        UseLookupTable;        // default FALSE
    UCHAR          LookupTable[66];       // populated if UseLookupTable=TRUE
    ULONG          FeatureFlags;          // default 0x03
    ULONG          ShadowBufferSize;      // default 46
    UCHAR          FirstBootPolicy;       // default 0
    ULONG          MaxStalenessMs;        // default 0 (disabled)
    WCHAR          DeviceName[64];        // display name from registry
} DEVICE_CONTEXT, *PDEVICE_CONTEXT;
```

### B2. ReadRegistryTunables() -- add per-device config path

Current implementation reads only `Parameters\BATTERY_OFFSET` and `Parameters\FirstBootPolicy`.
v1.3 must:
1. Open `Devices\VID_<V>&PID_<P>\` subkey (constructed from Ctx->Vid and Ctx->Pid).
2. Read all schema fields with validation.
3. Fall back to compiled-in defaults if subkey missing.

See M12-CONFIG-SCHEMA.md Section 8 (Driver Validation Logic) for pseudocode.

### B3. BATTERY_OFFSET default change

**v1.2 default: 1** (reads Shadow.Payload[1], the second payload byte)
**v1.3 default: 0** (reads Shadow.Payload[0], the first payload byte)

Rationale: structural analysis in M12-RID27-EMPIRICAL-PASS2-2026-04-28.md Section 2d
shows that the first payload byte is the more likely battery location per Ghidra analysis
of applewirelessmouse.sys.

Update in:
- Section 6 (Translation algorithm): change `BATTERY_OFFSET (REG_DWORD, default = 1)` to `default = 0`
- Section 7 (Battery synthesis): update shadow buffer pseudocode comment
- Section 10a (DEVICE_CONTEXT): update `BatteryOffset` default comment
- Section 11 (Failure modes): F16 boundary check: `must be < BatteryReportLength` (no integer change needed)
- Section 12 (Open questions): OQ-A -- update default from 1 to 0

### B4. Registry path -- add Devices\ hierarchy

Current v1.2 registry path: `Services\M12\Parameters\BATTERY_OFFSET`
v1.3 registry path for battery offset: `Services\M12\Devices\VID_004C&PID_0323\BatteryByteOffset`

The `Parameters\` path becomes global-only. Per-device tunables move to `Devices\<PID>\`.

Update in:
- Section 6: Change the registry path block
- Section 4 (INF Design): Add `[AddReg_M12_Devices_v3]`, `[AddReg_M12_Devices_v1]`,
  `[AddReg_M12_Parameters]` sections (see M12-CONFIG-SCHEMA.md Section 6a for INF templates)
- Section 4f (Strings): Add string tokens for each device name

### B5. New section to add: "Registry Configuration Schema"

Add a new Section 14 (or renumber) to M12-DESIGN-SPEC.md:

Title: "14. Registry Configuration Schema (K8s-CRD-style per-device config)"

Content: summarize M12-CONFIG-SCHEMA.md Sections 2-4, 7, 9, with cross-reference
to the full schema doc. Include:
- Registry path structure (Section 2)
- All field definitions with types, defaults, validation (Section 4)
- Known device table (Section 5)
- INF integration note (Section 6 -- brief, link to schema doc)
- New failure modes NF-1 through NF-6 (Section 9) -- add to the existing F-table in Section 11

### B6. Dynamic shadow buffer (NF-4 from schema doc)

Current design: `SHADOW_BUFFER.Payload[46]` is a fixed-size array.
This is safe for v1.3 since all current devices use a 46-byte payload.

However, the schema defines `ShadowBufferSize` as a registry tunable.
If an operator sets `ShadowBufferSize > 46`, the fixed array overflows.

**v1.3 action**: Add a runtime check. If ShadowBufferSize (from registry) != 46,
clamp to 46 and DbgPrint a warning. Document that larger payloads require M12 v2.0
(dynamic allocation, which is a larger structural change).

The `SHADOW_BUFFER` struct change (replace fixed array with pointer) is deferred to
a future milestone that targets future Magic Mouse variants.

---

## C. Sections of M12-DESIGN-SPEC.md to update

| Section | Update type | Detail |
|---------|-------------|--------|
| Sec 1 (BLUF) | Sentence addition | Add: "Per-device config is registry-driven (K8s-CRD-style Devices\ subkeys); future variants supported without driver rebuild." |
| Sec 4 (INF Design) | Add subsection | AddReg sections for Parameters\ and Devices\VID_004C&PID_0323\, VID_004C&PID_030D\ |
| Sec 6 (Translation) | Registry path change | Change from Parameters\BATTERY_OFFSET to Devices\<PID>\BatteryByteOffset; change default from 1 to 0 |
| Sec 7 (Battery synthesis) | DEVICE_CONTEXT update | Expand with all new fields from B1 above |
| Sec 9 (Function sigs) | Add ReadDeviceConfig() | Signature: `NTSTATUS ReadDeviceConfig(WDFDEVICE, PDEVICE_CONTEXT)` |
| Sec 10a (DEVICE_CONTEXT) | Full struct update | Replace 2-tunable struct with full 12-field struct from B1 |
| Sec 11 (Failure modes) | Add NF-1..NF-6 | 6 new rows in failure mode table |
| Sec 12 (Open questions) | OQ-A update | Change default from 1 to 0; add note about ETW being blocked |
| Sec 13 (References) | Add 2 entries | M12-CONFIG-SCHEMA.md + M12-RID27-EMPIRICAL-PASS2-2026-04-28.md |
| Sec NEW (Schema) | New section | Add Section 14: Registry Configuration Schema (see B5) |
| Version header | Bump to v1.3 | "v1.3 (2026-04-28): K8s-CRD-style per-device registry config + BATTERY_OFFSET default correction (1->0) + ETW empirical confirmation blocked (deferred to Phase 3 LogShadowBuffer)" |

---

## D. No new failure modes that block Phase 3

All new failure modes (NF-1..NF-6) are handled by:
- Runtime validation + clamping (NF-1, NF-2, NF-3, NF-6)
- Dynamic allocation deferral (NF-4)
- Diagnostic mode documentation (NF-5)

None of NF-1..NF-6 require Phase 3 to be gated. They are all operator-error scenarios
that the driver handles gracefully with DbgPrint warnings.

The BATTERY_OFFSET empirical question (OQ-A) remains open and is STILL the
sole Phase 3 gate from the prior open question list. The default changes from 1 to 0
based on structural analysis (MEDIUM confidence); empirical confirmation via
LogShadowBuffer() is still required.

---

## E. Schema completeness summary

| Device | Supported | Byte offset known | Notes |
|--------|-----------|-------------------|-------|
| Magic Mouse 1 (0x030D) | YES | NO (shared with v3, PENDING Phase 3) | |
| Magic Mouse 1 trackpad-PID (0x0310) | YES | NO | |
| Magic Mouse 2 (0x0269) | YES (hypothetical) | NO | Not user-owned; untested |
| Magic Mouse 2024 / v3 (0x0323) | YES | NO (PENDING Phase 3) | PRIMARY target |
| Magic Mouse v4 (future) | SCHEMA READY | N/A | New subkey only; static array capped at 46 until v2.0 |

---

## F. Schema failure modes that need Design attention (new)

Only NF-4 (dynamic shadow buffer for larger payloads) requires a non-trivial design
change. The v1.3 design decision is to DEFER NF-4 via a runtime cap at 46 bytes,
document the cap, and label it as a v2.0 concern. This decision must appear in
M12-DESIGN-SPEC.md v1.3 Section 11 (or Section 14).

The other NF entries (NF-1, 2, 3, 5, 6) are handled by existing defensive patterns
already in the v1.2 driver code -- no new code required.

---

Document version: 1.0
Session: ai/m12-empirical-and-crd
Date: 2026-04-28
