# Multi-device Apple BT HID analysis (v1 mouse + v3 mouse + Keyboard + AirPods)

**Captured:** 2026-04-28 morning
**Trigger:** User paired Magic Mouse v1 (PID 0x030D) + about to pair AirPods Pro for cross-device characterization.

---

## TL;DR

Apple changed the **battery reporting architecture** between Magic Mouse v1 and v3:

| Device | Battery channel | Windows native readout | Needs `applewirelessmouse`? |
|---|---|---|---|
| **Magic Mouse v1** (PID 0x030D) | **Standard HID Feature 0x47** (UP=0x06 Battery Strength) | YES | NO — for battery |
| **Magic Mouse v3** (PID 0x0323) | **Vendor TLC** (UP=0xFF00, U=0x14, ReportID 0x90) | NO | YES — to translate proprietary report |
| **Apple Keyboard** (PID 0x0239) | Standard HID Feature 0x47 | YES | NO |

**Implication:** The mutually-exclusive scroll-vs-battery problem is **specific to the v3 Magic Mouse** because Apple stopped declaring a standard battery report there. v1 mouse + Apple Keyboard both publish battery on the standard HID feature page that Windows reads natively.

The user's reported steady-state ("scroll works, battery N/A") on the v3 is the inevitable result of Windows + HidBth meeting a descriptor that has no standard battery report at all.

---

## Live BT stack state (snapshot 2026-04-28 09:43)

Three BTHENUM HIDClass children currently enumerated:

```
[OK] VID&000205AC_PID&0239 (Keyboard)        Service=HidBth  LowerFilters=applewirelessmouse  ← STALE
[OK] VID&0001004C_PID&0323 (v3 Magic Mouse)  Service=HidBth  no filters
[OK] VID&000205AC_PID&030D (v1 Magic Mouse)  Service=HidBth  no filters
```

`applewirelessmouse` service status: **Running** (Manual start). Only loaded because the keyboard's LowerFilter pulled it in — neither mouse currently has it on the stack.

DevParam shared by both Apple mice (but NOT keyboard):
- `SelectiveSuspendEnabled = 0` (disabled)
- `AllowIdleIrpInD3 = 1`
- `EnhancedPowerManagementEnabled = 1`
- `DeviceResetNotificationEnabled = 1`

Differences:
- v3 mouse has `ConnectionCount = 2` (recycled)
- v1 mouse has no ConnectionCount written (newly active)
- Keyboard has `ConnectionCount = 26` and a longer-lived pairing.

---

## SDP cache + HID Report Descriptor — apples-to-apples

Source: BTHPORT cache `…\Devices\<mac>\CachedServices\00010000`, attribute 0x0206.

| MAC | Device | Cache | Desc len | Mouse TLC | Wheel | UP=0xFF00 Vendor | Battery (UP=FF00,U=14) | Keyboard TLC | Consumer TLC |
|---|---|---|---|---|---|---|---|---|---|
| `04f13eeede10` | v1 Magic Mouse | 337B | 98 | YES | NO | NO | NO | NO | NO |
| `d0c050cc8c4d` | v3 Magic Mouse | 351B | 135 | YES | NO | YES | YES | NO | NO |
| `e806884b0741` | Apple Keyboard | 454B | 224 | NO | NO | NO | NO | YES | YES |

### v1 Magic Mouse descriptor (98 bytes)
- Mouse TLC, ReportID 0x10: 2 buttons + X/Y (16-bit). **No Wheel.**
- **Standard HID battery Feature**, ReportID 0x47, UP=0x06 (Generic Device Controls), Usage=0x20 (Battery Strength), 0–100, 1 byte, Feature flags 0xa2.
- Vendor 0xFF02 Feature 0x55 (touchpad mode), 64 bytes — same as v3.

### v3 Magic Mouse descriptor (135 bytes)
- Mouse TLC, ReportID 0x12: 2 buttons + X/Y (16-bit). **No Wheel.**
- Vendor 0xFF00, Usage 0x14 (Apple proprietary battery), ReportID 0x90, 0–255, 8 byte, Feature flags 0xa2 — **NOT a standard HID battery report**.
- Vendor 0xFF02 Feature 0x55 (touchpad mode), 64 bytes.
- **No Feature 0x47.**

### Apple Keyboard descriptor (224 bytes)
- Keyboard TLC + Consumer TLC + System Control TLC + 3 vendor TLCs.
- Standard HID battery Feature 0x47, UP=0x06.
- Standard input report 0x01 (8-modifier-bit + 6 keycodes — RFC 1188 keyboard).
- Multiple vendor inputs at UP=0xFF00..0xFF02.

---

## Why this matters for Phase 4 architecture

### Hypothesis (from descriptor evidence) — **needs empirical test**

**v1 mouse without Apple filter:**
- Mouse buttons + X/Y: works (standard mouse TLC, HidBth understands it).
- **Wheel: NO** — descriptor declares no Wheel either, so without `applewirelessmouse` synthesizing scroll from the touchpad surface, the v1 should ALSO give no scroll.
- **Battery: YES** — standard HID Feature 0x47 on UP=0x06 → Windows BatteryLevel reads this natively.

**v3 mouse without Apple filter:**
- Mouse buttons + X/Y: works.
- Wheel: NO.
- **Battery: NO** — descriptor's only battery channel is vendor (UP=0xFF00 RID=0x90), Windows native HID reader does not parse vendor pages without driver assistance.

If empirical testing confirms this, then:

1. **v1 mouse is a one-driver-fix-fits-both case** — Apple's filter is needed only for scroll, battery is free. A scroll-only userland daemon (Phase 4A) would give v1 users full functionality without the proprietary filter.

2. **v3 mouse is the harder case** — needs filter (or equivalent cache patch / userland daemon) for both scroll AND a way to surface battery. Phase 4-Ω restores both via the filter; Phase 4A would have to add a user-land battery probe that knows the vendor 0x90 report format.

3. **Keyboard is the easy case** — battery is standard, no scroll dependency. The `applewirelessmouse` LowerFilter on the keyboard is **vestigial** — most likely a leftover from a generic "all Apple HID gets the filter" install rule. Removing it should be safe.

### Anti-pattern caught (AP-18 candidate)

The `applewirelessmouse` INF rule attaches the LowerFilter to **all Apple BT HID devices**, not just the Magic Mouse. The keyboard inherited it. Without the filter the keyboard might still work fine (since its battery is standard), but the LowerFilter will fire AddDevice and chew CPU on every report. The user-visible cost is small but the architectural smell is real: install-time INF over-matching.

Phase 1 cleanup deleted the **service** but left the **LowerFilters reference** on the keyboard. With the service deleted, PnP would fail to load the filter at AddDevice (no driver behind the name), which generates a Code 39 / WHEA-Logger event for the keyboard at next reconnect. **Confirmed risk.**

Mitigation: Phase 4 cleanup MOP must remove the keyboard's LowerFilter reference _at the same time_ as the service. Or PnP-restart the keyboard to confirm whether the filter ref is actually used vs. ignored.

### State F (filter loaded with no v3 mouse referencing it)

The current snapshot shows `applewirelessmouse` service Running, but neither mouse has it on its stack — only the keyboard does. So:
- The driver DLL is loaded into the kernel.
- Its DriverEntry runs.
- AddDevice fires only against the keyboard's BTHENUM HID PDO.

This is the **first time we have a clean view of the filter's keyboard-only AddDevice path**. If `applewirelessmouse` does anything mouse-specific in DriverEntry (e.g., registering the WMI battery class, hooking Win32 input), those side effects exist with NO mouse client. Could explain some of the "filter looks inert but is actually doing something" observations from earlier sessions.

---

## Empirical results from 2026-04-28 09:55+ retest

### v1 mouse SCROLL: **WORKS** (without `applewirelessmouse` on its PnP filter stack)

User confirmed: v1 Magic Mouse scrolls in standard apps. Live filter chain still
shows no `applewirelessmouse` on the v1 BTHENUM HID PDO. The descriptor only
declares Mouse TLC + X/Y (16-bit) inputs — no Wheel input.

This contradicts the original hypothesis. Three plausible explanations:

1. **`applewirelessmouse` registers a global Win32 input hook on DriverEntry**.
   It's currently loaded into the kernel (Status=Running) because the keyboard's
   stale LowerFilter ref pulled it in. Once loaded, it could synthesize scroll
   for any Apple HID device it recognises, regardless of per-stack binding.
2. v1 mouse uses a different scroll mechanism — e.g., Windows's HidBth path has
   an Apple-specific code path for VID=0x05AC mice that interprets touch surface
   reports (Vendor 0xFF02 ReportID 0x55) as wheel events. Unverified.
3. The v1 sends an extra Vendor input report at runtime that Windows somehow
   recognises. The descriptor doesn't declare such an input, but BT HID can
   send unsolicited reports the host happens to know about.

**Test to disambiguate:** `Stop-Service applewirelessmouse` then try scrolling v1.
If scroll fails → theory 1 confirmed. If scroll persists → theories 2/3 in play.
NOT yet executed — user is in active test cycle.

### v1 mouse BATTERY: **not surfaced by Windows native** despite standard descriptor

User asked: "where can I see v1 battery?" Answer: **nowhere natively.**

The deep battery probe (`bt-battery-probe.txt`) confirmed:
- `DEVPKEY_Device_BatteryLevel` is empty on every BTHENUM and HID PDO node.
- WMI classes `AppleWirelessHIDDeviceBattery`, `BatteryStatus`, `Win32_Battery` are all empty.
- Settings → Bluetooth & devices won't show a percent for either Apple mouse.

Even though the v1 mouse declares standard HID Feature 0x47 (UP=0x06, U=0x20),
**Windows doesn't auto-poll Classic-BT HID Feature reports** for battery — that
behaviour only applies to BLE devices using HOGP+Battery Service (0x180F).

To surface v1 battery the tray app must call `HidD_GetFeature(handle, [0x47, ...], 2)`
itself. mm-tray already does this kind of read for v3 (vendor 0x90); a small
extension to also try the standard 0x47 report would give the v1 user a battery
reading. **Phase 4-Ω+v1-support task added.**

### AirPods Pro: out of scope

MAC `38c43a5f7a5f`, PID 0x2024. Pure audio device — A2DP (BthA2dp), HFP
(BthHFEnum), AVRCP, GATT (Find My), Apple AAP/UARP. **No HID profile.** No
relevance to the scroll/battery problem on the mouse stack. Cache value
`00000000` is a multi-language SDP service-name list, not a HID descriptor.

Battery for AirPods is exposed via Apple's proprietary AAP Server (BTHENUM
GUID `{74EC2172-0BAD-4D01-8F77-997B2BE0722A}`) which Windows can't decode
without third-party tooling. Not pursued.

### v3 mouse stale child PDOs

Snapshot showed orphan HID nodes from old USB Magic Mouse instances
(`HID\VID_05AC&PID_0323&MI_01\COL01..03\8&4FB45D0`) — Status=Unknown. These
are from the cabled-mouse phase before BT pairing. Not active, but cluttering
PnP. Cleanup candidate (low priority).

## Outstanding empirical tests

1. **`Stop-Service applewirelessmouse` + v1 scroll test** — disambiguates the global-hook hypothesis. Needs user approval (changes BT stack state).
2. **`HidD_GetFeature(0x47)` direct read on v1 mouse** — would prove the standard battery report is readable. Could be done from a small one-off test program or extension to mm-tray.
3. **Keyboard LowerFilter cleanup MOP** — task #26.

---

## Files

- `bthport-discovery-04f13eeede10.{txt,json}` — v1 mouse SDP cache
- `bthport-discovery-d0c050cc8c4d.{txt,json}` — v3 mouse SDP cache
- `bthport-discovery-e806884b0741.{txt,json}` — Apple Keyboard SDP cache
- `bthport-discovery-b2227a7a501b.{txt,json}` — HP ENVY printer (no cache)
- `bthport-discovery-index.txt` — summary
- `multi-device-cache-comparison.md` — descriptor diff
- `bt-stack-snapshot.{txt,json}` — live PnP filter chain
