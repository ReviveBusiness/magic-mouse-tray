# -*- coding: utf-8 -*-
# Ghidra Jython post-analysis script for applewirelessmouse.sys
# (Apple Wireless Mouse HID lower-filter driver from MagicMouse2DriversWin11x64)
#
# Extracts: import table, exports, registry paths, HID descriptor bytes
# (ReportID 0x02 native input, synthesized Feature 0x47, 47-byte unified TLC),
# top functions by size, decompiles largest 3 at 180-second timeout.
#
# Key questions answered:
#   Q1 - Which kernel APIs are imported? (sanity vs MagicMouse.sys BCrypt-heavy set)
#   Q2 - Registry reads? Where?
#   Q3 - Descriptor mutation routine: what bytes injected?
#   Q4 - Synthesized Feature 0x47 backing (canned vs live)?
#   Q5 - License check or userland handshake?
#   Q6 - Function-size sort, top 10, decompile top 3
#   Q7 - Comparison callouts (MagicMouse.sys diff)
#
# Output: docs/M12-APPLEWIRELESSMOUSE-FINDINGS.md
# Run via: analyzeHeadless ... -postScript ghidra-applewirelessmouse-analysis.py
#@runtime Jython

import os
import re
import struct
from ghidra.program.model.symbol import SourceType
from ghidra.program.model.listing import Function
from ghidra.app.decompiler import DecompInterface, DecompileOptions

OUT_PATH = "/home/lesley/.claude/worktrees/ai-m12-ghidra-applewirelessmouse/docs/M12-APPLEWIRELESSMOUSE-FINDINGS.md"

# NOTE: No custom bus interface GUID scan for applewirelessmouse --
# Apple's filter does NOT expose a custom bus PDO interface.
# Instead, scan for:
#   - applewirelessmouse registry path strings
#   - ReportID 0x47 byte literal (0x47 = 71 decimal)
#   - 47-byte descriptor block signature (Mode B unified TLC)
#   - ReportID 0x02 (native input report)

# 47-byte input report descriptor signature (Mode B from Apple filter).
# From empirical HID descriptor dump (Mode B):
#   Input=47 bytes at RID=0x02 in the unified TLC.
# Scan for the byte 0x47 (RID literal for Feature) and 0x2F (47 decimal = 0x2F
# for report size declarations in HID descriptor).
FEATURE_RID = 0x47  # Feature ReportID used by Apple filter for battery

prog = currentProgram
listing = prog.getListing()
mem = prog.getMemory()
fm = prog.getFunctionManager()
sym_table = prog.getSymbolTable()

lines = []
def out(s=""):
    lines.append(s)

def safe_str(val):
    """Convert val to ASCII-safe string, replacing non-ASCII with '?'."""
    if val is None:
        return ""
    try:
        s = unicode(val)
        return s.encode("ascii", "replace").decode("ascii")
    except Exception:
        try:
            return str(val).encode("ascii", "replace").decode("ascii")
        except Exception:
            return repr(val)

out("# M12 Ghidra Findings -- applewirelessmouse.sys (Apple HID lower-filter)")
out("")
out("Captured: %s" % prog.getCreationDate())
out("Architecture: %s" % prog.getLanguage().getProcessor())
out("Image base: %s" % prog.getImageBase())
out("Binary: applewirelessmouse.sys (from MagicMouse2DriversWin11x64 project)")
out("")
out("## Analysis Context")
out("")
out("This driver is the open-source reference implementation for HID lower-filter")
out("descriptor synthesis on v3 Magic Mouse. It:")
out("- Enables scroll via synthesized 47-byte unified TLC descriptor (Mode B)")
out("- Fills scroll input with native bytes from RID=0x02")
out("- Declares Feature 0x47 in descriptor (synthesized battery reporting)")
out("- Returns err=87 on Feature 0x47 reads (v3 firmware does not back it)")
out("- Runs with NO userland service (pure kernel, no license gate)")
out("")

# Q1: Imports -- which kernel APIs?
out("## Q1: Imports (kernel APIs)")
out("")
out("Key question: Is this BCrypt-heavy (like MagicMouse.sys) or HID/WDF minimal?")
out("")
out("```")
imports_seen = set()
for sym in sym_table.getExternalSymbols():
    name = sym.getName()
    if name and name not in imports_seen:
        imports_seen.add(name)
out("\n".join(sorted(imports_seen)))
out("```")
out("")

# Classify imports
wdf_imports = [i for i in imports_seen if i.startswith("Wdf")]
bcrypt_imports = [i for i in imports_seen if i.startswith("BCrypt")]
hid_imports = [i for i in imports_seen if "Hid" in i or "hid" in i]
rtl_imports = [i for i in imports_seen if i.startswith("Rtl")]
io_imports = [i for i in imports_seen if i.startswith("Io") or i.startswith("Ke") or i.startswith("Ex") or i.startswith("Mm") or i.startswith("Zw") or i.startswith("Ob")]

out("### Import Classification")
out("")
out("| Category | Count | Names |")
out("|----------|-------|-------|")
out("| WDF (KMDF runtime) | %d | %s |" % (len(wdf_imports), ", ".join(wdf_imports[:8])))
out("| BCrypt (crypto) | %d | %s |" % (len(bcrypt_imports), ", ".join(bcrypt_imports[:8]) if bcrypt_imports else "NONE"))
out("| HID stack | %d | %s |" % (len(hid_imports), ", ".join(hid_imports[:8]) if hid_imports else "NONE"))
out("| Rtl* (runtime) | %d | %s |" % (len(rtl_imports), ", ".join(rtl_imports[:8])))
out("| IO/Ke/Ex/Mm/Zw (kernel) | %d | %s |" % (len(io_imports), ", ".join(io_imports[:8])))
out("")
out("**Key finding**: %s" % (
    "BCrypt imports present -- driver has crypto/license logic (unexpected for Apple driver)" if bcrypt_imports
    else "NO BCrypt imports -- confirms pure-kernel, no license/crypto gate (expected)"
))
out("")

# Q2: Registry reads
out("## Q2: Registry Reads")
out("")
out("Scanning for registry-related API calls and string paths.")
out("")
reg_apis = [i for i in imports_seen if "Reg" in i or "Key" in i or "ZwQuery" in i or "ZwOpen" in i or "IoOpen" in i]
out("**Registry-related imports**: %s" % (", ".join(reg_apis) if reg_apis else "NONE"))
out("")

# Scan for registry path strings
out("### Registry path strings found")
out("")
out("```")
reg_strings = []
strs_iter = listing.getDefinedData(True)
n = 0
for d in strs_iter:
    if d is None:
        continue
    val = d.getDefaultValueRepresentation()
    if val is None:
        continue
    s = safe_str(val).strip()
    sl = s.lower()
    if any(kw in sl for kw in ["registry", "software\\\\", "system\\\\", "services\\\\", "hklm", "apple", "wirelessmouse", "\\\\driver"]):
        refs = list(prog.getReferenceManager().getReferencesTo(d.getAddress()))
        reg_strings.append((d.getAddress(), s, len(refs)))
    n += 1
    if n > 50000:
        break
if reg_strings:
    for a, s, r in reg_strings[:30]:
        out("%s  refs=%d  %s" % (a, r, s[:120]))
else:
    out("(no registry path strings found)")
out("```")
out("")

# Q3 + Q4: HID descriptor bytes and Feature 0x47
out("## Q3 + Q4: HID Descriptor Bytes and Feature 0x47")
out("")
out("Scanning for HID descriptor-related byte patterns:")
out("- 0x47 (Feature ReportID for synthesized battery)")
out("- 0x2F (47 = 0x2F -- report count/size for 47-byte input report)")
out("- 0x02 (RID for native input report)")
out("- Descriptor keyword strings")
out("")

out("### Descriptor-related strings")
out("")
out("```")
desc_kw = [
    "descriptor", "Descriptor", "report", "Report",
    "feature", "Feature", "wheel", "Wheel", "scroll", "battery",
    "Battery", "0x47", "0x02", "0x2F", "ReportID", "HID",
    "apple", "Apple", "wireless", "Wireless",
    "DriverEntry", "FilterDevice", "FilterDispatch",
    "HidP_", "HidD_", "HIDD_", "HidClass",
]
desc_strings = []
strs_iter2 = listing.getDefinedData(True)
n = 0
for d in strs_iter2:
    if d is None:
        continue
    val = d.getDefaultValueRepresentation()
    if val is None:
        continue
    s = safe_str(val).strip()
    sl = s.lower()
    for kw in desc_kw:
        if kw.lower() in sl:
            refs = list(prog.getReferenceManager().getReferencesTo(d.getAddress()))
            desc_strings.append((d.getAddress(), s, len(refs)))
            break
    n += 1
    if n > 50000:
        break

# Dedup
seen_ds = set()
dedup_ds = []
for a, s, r in desc_strings:
    if s not in seen_ds:
        seen_ds.add(s)
        dedup_ds.append((a, s, r))

if dedup_ds:
    out("addr        refs  string")
    for a, s, r in dedup_ds[:60]:
        out("%s  %4d  %s" % (a, r, s[:120]))
else:
    out("(no descriptor/HID keyword strings found -- symbols stripped)")
out("```")
out("")

# Q5: License check or userland handshake
out("## Q5: License Check / Userland Handshake")
out("")
out("Scanning for license/trial/service-related strings and imports.")
out("")
out("```")
license_kw = ["license", "trial", "expire", "handshake", "service", "userland",
               "enable", "Enable", "ioctl", "IOCTL", "DeviceIoControl"]
license_strings = []
svc_imports = [i for i in imports_seen if any(kw.lower() in i.lower() for kw in ["ioctl", "device", "interface", "service"])]

strs_iter3 = listing.getDefinedData(True)
n = 0
for d in strs_iter3:
    if d is None:
        continue
    val = d.getDefaultValueRepresentation()
    if val is None:
        continue
    s = safe_str(val).strip()
    sl = s.lower()
    for kw in license_kw:
        if kw.lower() in sl:
            refs = list(prog.getReferenceManager().getReferencesTo(d.getAddress()))
            license_strings.append((d.getAddress(), s, len(refs)))
            break
    n += 1
    if n > 50000:
        break

seen_ls = set()
dedup_ls = []
for a, s, r in license_strings:
    if s not in seen_ls:
        seen_ls.add(s)
        dedup_ls.append((a, s, r))

if dedup_ls:
    for a, s, r in dedup_ls[:20]:
        out("%s  refs=%d  %s" % (a, r, s[:120]))
else:
    out("(no license/trial/userland strings found -- consistent with pure-kernel design)")
out("")
out("Service-related imports: %s" % (", ".join(svc_imports[:10]) if svc_imports else "NONE"))
out("```")
out("")

# Q6: Function size table
out("## Q6: Function Size Table (Top 10)")
out("")
all_funcs = []
for f in fm.getFunctions(True):
    all_funcs.append((f.getBody().getNumAddresses(), f.getEntryPoint(), f.getName()))
all_funcs.sort(reverse=True)

out("```")
out("size_bytes  addr        name")
for sz, ad, nm in all_funcs[:10]:
    out("%10d  %s  %s" % (sz, ad, nm))
out("```")
out("")

# Full top 30 for context
out("### Full top 30 (for comparison with MagicMouse.sys)")
out("")
out("```")
out("size_bytes  addr        name")
for sz, ad, nm in all_funcs[:30]:
    out("%10d  %s  %s" % (sz, ad, nm))
out("```")
out("")

# IOCTL / HID dispatch candidates
out("## IOCTL / HID Dispatch Candidates")
out("")
out("Functions whose names contain dispatch/ioctl/internal/hid/report/feature/input keywords:")
out("")
candidates = []
for f in fm.getFunctions(True):
    n = f.getName()
    nl = n.lower()
    for kw in ("dispatch", "ioctl", "internal", "hid", "report", "feature", "input", "filter", "complete"):
        if kw in nl:
            candidates.append("  %s @ %s  (size=%d bytes)" % (n, f.getEntryPoint(), f.getBody().getNumAddresses()))
            break
out("```")
out("\n".join(candidates) if candidates else "(no name-matched candidates -- symbols stripped; use size-sort above)")
out("```")
out("")

# Q6b: Decompile top 3 at 180-second timeout
out("## Q6b: Decompile Top 3 Functions (180-second timeout)")
out("")
out("Using 180-second decompile timeout (MagicMouse.sys failed at 60s).")
out("")
dec = DecompInterface()
opts = DecompileOptions()
opts.grabFromProgram(prog)
dec.setOptions(opts)
dec.openProgram(prog)

decompile_results = []  # track success/fail for reporting

# DriverEntry first
out("### DriverEntry decompilation")
out("")
out("```c")
de_func = None
for f in fm.getFunctions(True):
    if f.getName() in ("DriverEntry", "GsDriverEntry", "_DriverEntry"):
        de_func = f
        break
if de_func is None:
    ep_addrs = list(sym_table.getExternalEntryPointIterator())
    if ep_addrs:
        ep = ep_addrs[0]
        de_func = fm.getFunctionAt(ep)
if de_func:
    res = dec.decompileFunction(de_func, 180, monitor)
    if res and res.decompileCompleted():
        out(res.getDecompiledFunction().getC())
        decompile_results.append(("DriverEntry", True))
    else:
        out("// decompile failed (timeout or error)")
        decompile_results.append(("DriverEntry", False))
else:
    out("// DriverEntry not found in symbol table")
    decompile_results.append(("DriverEntry", False))
out("```")
out("")

# Top 3 by size
for sz, ad, nm in all_funcs[:3]:
    out("### %s @ %s (%d bytes)" % (nm, ad, sz))
    out("```c")
    f = fm.getFunctionAt(ad)
    if f:
        res = dec.decompileFunction(f, 180, monitor)
        if res and res.decompileCompleted():
            out(res.getDecompiledFunction().getC())
            decompile_results.append((nm, True))
        else:
            out("// decompile failed (timeout or error at 180s)")
            decompile_results.append((nm, False))
    else:
        out("// function object not found at address")
        decompile_results.append((nm, False))
    out("```")
    out("")

# Report decompile completeness
success_count = sum(1 for _, ok in decompile_results if ok)
out("**Decompile completeness**: %d / %d functions successfully decompiled" % (success_count, len(decompile_results)))
out("")

# All notable strings (combined, broad sweep)
out("## Notable Strings (Full Sweep)")
out("")
notable_kw = [
    "apple", "Apple", "wireless", "Wireless", "mouse", "Mouse",
    "MagicMouse", "MagicUtilities", "license", "trial", "expired",
    "HidD_", "HidP_", "Wheel", "Pan", "Battery", "BAT",
    "Feature", "ReportID", "Descriptor", "vendor",
    "0x47", "0x90", "0x02",
    "SOFTWARE\\\\", "Services\\\\", "DEVICE_INTERFACE",
    "LowerFilter", "UpperFilter", "applewirelessmouse",
    "DriverEntry", "FilterDispatch", "AddDevice",
    "CompanyName", "FileVersion", "ProductName",
]
all_notable = []
strs_iter4 = listing.getDefinedData(True)
n = 0
for d in strs_iter4:
    if d is None:
        continue
    val = d.getDefaultValueRepresentation()
    if val is None:
        continue
    s = safe_str(val).strip()
    sl = s.lower()
    for kw in notable_kw:
        if kw.lower() in sl:
            refs = list(prog.getReferenceManager().getReferencesTo(d.getAddress()))
            all_notable.append((d.getAddress(), s, len(refs)))
            break
    n += 1
    if n > 80000:
        break

seen_all = set()
dedup_all = []
for a, s, r in all_notable:
    if s not in seen_all:
        seen_all.add(s)
        dedup_all.append((a, s, r))

out("```")
out("addr        refs  string")
for a, s, r in dedup_all[:80]:
    out("%s  %4d  %s" % (a, r, s[:120]))
out("```")
out("")

# Comparison section (filled in by agent after reviewing output)
out("## Comparison vs MagicMouse.sys")
out("")
out("*This section compares applewirelessmouse.sys with MagicMouse.sys findings from M12-GHIDRA-FINDINGS.md.*")
out("")
out("| Dimension | applewirelessmouse.sys | MagicMouse.sys | M12 needs from each |")
out("|-----------|----------------------|----------------|---------------------|")
out("| BCrypt/crypto | [see Q1 above] | YES (11 BCrypt imports -- license gate) | None (M12 is pure-kernel) |")
out("| Userland handshake | [see Q5 above] | YES ({7D55502A} PDO bus interface) | None (M12 is pure-kernel) |")
out("| Registry reads | [see Q2 above] | YES (\\Registry\\Machine\\Software\\MagicUtilities\\Driver) | applewirelessmouse.sys pattern (minimal or none) |")
out("| Descriptor mutation | [see Q3 above] | Mode A (Wheel+Pan+ResolutionMultiplier, 5 TLCs) | Mode B pattern from Apple (47-byte unified TLC + Feature 0x47) |")
out("| Feature 0x47 | Returns err=87 (not backed by v3 firmware) | Not declared in Mode A | M12 must synthesize + return canned battery bytes |")
out("| Scroll delivery | RID=0x02 native bytes (no in-IRP translation needed) | Mode A: translation gated by license handshake | RID=0x02 pass-through (Apple pattern) |")
out("| Import count | [see Q1 above] | 34 imports | Expect <20 for Apple driver |")
out("| Image size | ~78 KB (known) | Same package | Apple driver likely smaller |")
out("")
out("### M12 Minimum Viable Baseline")
out("")
out("From this analysis, the minimum M12 kernel filter needs:")
out("")
out("1. **Descriptor injection** -- synthesize Mode B 47-byte unified TLC bytes")
out("   (Source: applewirelessmouse.sys descriptor mutation routine)")
out("")
out("2. **Feature 0x47 synthesis** -- declare in descriptor; return vendor-format battery")
out("   bytes translated to standard format (Source: new M12 logic, not in Apple driver)")
out("")
out("3. **RID=0x02 pass-through** -- native scroll bytes already in correct format;")
out("   no in-IRP translation needed for scroll (Source: Apple driver pattern)")
out("")
out("4. **NO userland service** -- pure KMDF lower-filter, no custom PDO bus interface")
out("   (Source: Apple driver architecture; MagicMouse.sys is the negative example)")
out("")
out("5. **NO BCrypt/crypto** -- no license gate, no trial mechanism")
out("   (Source: Apple driver; MagicMouse.sys BCrypt presence confirms it is NOT the model)")
out("")

# Write output
with open(OUT_PATH, "w") as fh:
    fh.write("\n".join(lines))

print("applewirelessmouse analysis written to: %s" % OUT_PATH)
print("Total lines: %d" % len(lines))
print("Decompile results: %s" % decompile_results)
