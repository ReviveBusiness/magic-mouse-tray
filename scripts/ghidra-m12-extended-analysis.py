# -*- coding: ascii -*-
# Ghidra Jython extended post-analysis script for MagicMouse.sys
# Extended from first-pass ghidra-m12-analysis.py with:
#   - 180-second decompile timeout (first-pass used 60s)
#   - Top 10 functions decompiled (first-pass did top 3)
#   - xref tracing FROM BCrypt imports (license check call sites)
#   - xref tracing FROM registry string at 0x1405acb30
#   - xref tracing FROM RawPdo string at 0x1405ad4a0
#   - HID descriptor byte pattern search (Mode A layout)
#   - IOCTL_HID_GET_REPORT_DESCRIPTOR constant search (0xB0193)
#   - WDF queue setup / EvtIoDeviceControl callback identification
#   - Full IOCTL code constant scan (32-bit values matching CTL_CODE shape)
#   - Data reference walk for all Unicode strings
#
# Output: docs/M12-GHIDRA-FINDINGS-EXTENDED.md in the repo
#@runtime Jython

import os
import struct
import jarray

from ghidra.program.model.symbol import SourceType
from ghidra.program.model.listing import Function
from ghidra.app.decompiler import DecompInterface, DecompileOptions
from ghidra.program.model.address import AddressSet

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
OUT_PATH = "/home/lesley/.claude/worktrees/ai-m12-ghidra-magicmouse-extended/docs/M12-GHIDRA-FINDINGS-EXTENDED.md"
DECOMPILE_TIMEOUT = 180          # seconds per function (first-pass = 60)
DECOMPILE_TOP_N   = 10           # number of largest functions to decompile
BCRYPT_FUNCS = [
    "BCryptOpenAlgorithmProvider",
    "BCryptCloseAlgorithmProvider",
    "BCryptCreateHash",
    "BCryptDestroyHash",
    "BCryptFinishHash",
    "BCryptHashData",
    "BCryptGenerateSymmetricKey",
    "BCryptDestroyKey",
    "BCryptEncrypt",
    "BCryptDecrypt",
    "BCryptGetProperty",
    "BCryptSetProperty",
]

# Known addresses from first-pass findings
REGISTRY_STRING_ADDR = "1405acb30"   # \Registry\Machine\Software\MagicUtilities\Driver
RAWPDO_STRING_ADDR   = "1405ad4a0"   # {7D55502A...}\MagicMouseRawPdo

# IOCTL_HID_GET_REPORT_DESCRIPTOR = CTL_CODE(0xb, 0x800, 2, 0) = 0x000B0000 | ...
# More precisely: FILE_DEVICE_KEYBOARD=0x0b, function=0x100, METHOD_NEITHER=3, FILE_ANY_ACCESS=0
# IOCTL_HID_GET_REPORT_DESCRIPTOR = 0x000B0193  (METHOD_NEITHER variant commonly cited)
IOCTL_HID_REPORT_DESC = 0x000B0193
# Also search nearby variants
IOCTL_HID_CANDIDATES = [
    0x000B0193,   # IOCTL_HID_GET_REPORT_DESCRIPTOR (METHOD_NEITHER)
    0x000B0003,   # METHOD_BUFFERED variant
    0x000B0100,   # internal variant sometimes used
    0x000B0007,   # IOCTL_HID_GET_DEVICE_DESCRIPTOR
    0x000B0113,   # IOCTL_HID_READ_REPORT
    0xB0003,
    0xB0007,
    0xB0013,
    0xB0017,
]

# HID Mode A descriptor signature bytes
# Usage Page Generic Desktop (0x05 0x01), Usage Mouse (0x09 0x02)
HID_MOEA_HEADER = jarray.array([0x05, 0x01, 0x09, 0x02], "b")
# Wheel usage (0x09 0x38)
HID_WHEEL_USAGE = jarray.array([0x09, 0x38], "b")
# AC Pan (0x0A 0x38 0x02)
HID_ACPAN_USAGE = jarray.array([0x0A, 0x38, 0x02], "b")
# Resolution Multiplier (0x09 0x48)
HID_RESMULT_USAGE = jarray.array([0x09, 0x48], "b")

# WDF function names to search for call sites
WDF_QUEUE_FUNCS = [
    "WdfIoQueueCreate",
    "WdfRequestComplete",
    "WdfRequestCompleteWithInformation",
    "WdfDeviceCreateDeviceInterface",
    "WdfDeviceCreate",
    "WdfDriverCreate",
    "WdfFdoInitSetFilter",
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

prog      = currentProgram
listing   = prog.getListing()
mem       = prog.getMemory()
fm        = prog.getFunctionManager()
sym_table = prog.getSymbolTable()
ref_mgr   = prog.getReferenceManager()

lines = []
def out(s=""):
    lines.append(s)

def addr_from_str(s):
    """Convert hex string (no 0x) to Ghidra Address."""
    return prog.getAddressFactory().getAddress(s)

def get_func_at_or_containing(addr):
    f = fm.getFunctionAt(addr)
    if f is None:
        f = fm.getFunctionContaining(addr)
    return f

def refs_to_addr(addr_obj):
    """Return list of (from_addr, containing_func_name) for xrefs TO addr_obj."""
    result = []
    for ref in ref_mgr.getReferencesTo(addr_obj):
        from_addr = ref.getFromAddress()
        func = get_func_at_or_containing(from_addr)
        func_name = func.getName() if func else "?"
        func_ep   = str(func.getEntryPoint()) if func else "?"
        result.append((from_addr, func_name, func_ep))
    return result

def refs_to_sym_name(sym_name):
    """
    Find all thunk symbols for sym_name (import wrappers),
    then return all call-sites into those thunks.
    Returns list of (from_addr, containing_func, func_ep).
    """
    results = []
    for sym in sym_table.getGlobalSymbols(sym_name):
        for ref in ref_mgr.getReferencesTo(sym.getAddress()):
            from_addr = ref.getFromAddress()
            func = get_func_at_or_containing(from_addr)
            func_name = func.getName() if func else "?"
            func_ep   = str(func.getEntryPoint()) if func else "?"
            results.append((from_addr, func_name, func_ep))
    # Also check external symbols (sometimes in EXTERNAL namespace)
    for sym in sym_table.getSymbols(sym_name):
        addr = sym.getAddress()
        for ref in ref_mgr.getReferencesTo(addr):
            from_addr = ref.getFromAddress()
            func = get_func_at_or_containing(from_addr)
            func_name = func.getName() if func else "?"
            func_ep   = str(func.getEntryPoint()) if func else "?"
            entry = (from_addr, func_name, func_ep)
            if entry not in results:
                results.append(entry)
    return results

def find_bytes_all(pattern_bytes, desc):
    """Search all initialized memory for pattern. Returns list of Address."""
    hits = []
    addr_set = mem.getAllInitializedAddressSet()
    try:
        addr = mem.findBytes(addr_set.getMinAddress(), pattern_bytes, None, True, monitor)
        while addr is not None:
            hits.append(addr)
            next_start = addr.add(1)
            if next_start.compareTo(addr_set.getMaxAddress()) > 0:
                break
            addr = mem.findBytes(next_start, pattern_bytes, None, True, monitor)
    except Exception as e:
        out("  [WARN] findBytes(%s): %s" % (desc, str(e)))
    return hits

def decompile_function(dec, f, timeout=DECOMPILE_TIMEOUT):
    """Decompile function, return C string or error string."""
    try:
        res = dec.decompileFunction(f, timeout, monitor)
        if res and res.decompileCompleted():
            return res.getDecompiledFunction().getC()
        elif res:
            err = res.getErrorMessage()
            return "// decompile failed: %s" % (err if err else "unknown")
        else:
            return "// decompile failed: null result"
    except Exception as e:
        return "// decompile exception: %s" % str(e)

def scan_for_ioctl_constants():
    """
    Scan .text/.rdata for 32-bit values matching known IOCTL patterns.
    CTL_CODE shape: bits[31:16]=0, bits[15:14]=access(0-3),
    bits[13:2]=function, bits[1:0]=method.
    HID device type = 0x000B, so upper word of IOCTL = 0x000B.
    Returns list of (addr, value).
    """
    results = []
    target_prefix = 0x000B0000
    target_mask   = 0xFFFF0000
    blocks = []
    for block in mem.getBlocks():
        name = block.getName().lower()
        if block.isInitialized() and (".text" in name or ".rdata" in name or name == ".text"):
            blocks.append(block)
    if not blocks:
        # Fallback: scan all initialized
        for block in mem.getBlocks():
            if block.isInitialized():
                blocks.append(block)
    checked = 0
    for block in blocks:
        start = block.getStart()
        end   = block.getEnd()
        size  = block.getSize()
        buf   = jarray.zeros(min(int(size), 0x100000), "b")
        try:
            n_read = block.getBytes(start, buf, 0, len(buf))
        except Exception:
            continue
        for i in range(n_read - 4):
            b0 = buf[i]   & 0xFF
            b1 = buf[i+1] & 0xFF
            b2 = buf[i+2] & 0xFF
            b3 = buf[i+3] & 0xFF
            val = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
            if (val & target_mask) == target_prefix and val != target_prefix:
                addr = start.add(i)
                # Check it's a DWORD-aligned reference (heuristic)
                if i % 2 == 0:
                    results.append((addr, val))
        checked += 1
    return results

# ---------------------------------------------------------------------------
# Begin output
# ---------------------------------------------------------------------------

out("# M12 Ghidra Findings Extended -- MagicMouse.sys (Magic Utilities v3.1.5.3)")
out("")
out("Extended analysis pass. Timeout: %ds per function. Top %d functions decompiled." % (
    DECOMPILE_TIMEOUT, DECOMPILE_TOP_N))
out("")
out("Binary: %s" % prog.getExecutablePath())
out("MD5: %s" % prog.getExecutableMD5())
out("Architecture: %s" % prog.getLanguage().getProcessor())
out("Image base: %s" % prog.getImageBase())
out("Created: %s" % prog.getCreationDate())
out("")

# ---------------------------------------------------------------------------
# SECTION 1: BCrypt xrefs -- license check call sites
# ---------------------------------------------------------------------------
out("## Section 1: BCrypt Import Xrefs (License Gate Call Sites)")
out("")
out("Each BCrypt API is traced to its call sites. These are WHERE the license check")
out("logic runs in the driver.")
out("")

bcrypt_callsite_funcs = {}   # func_ep -> set of (api_name)
for api in BCRYPT_FUNCS:
    sites = refs_to_sym_name(api)
    out("### %s" % api)
    out("```")
    if sites:
        for from_addr, func_name, func_ep in sites:
            out("  called from 0x%s  in %s @ %s" % (from_addr, func_name, func_ep))
            if func_ep not in bcrypt_callsite_funcs:
                bcrypt_callsite_funcs[func_ep] = set()
            bcrypt_callsite_funcs[func_ep].add(api)
    else:
        out("  (no call sites found via symbol table -- may be resolved dynamically)")
    out("```")
    out("")

out("### BCrypt Call Site Summary")
out("")
out("Functions that call ANY BCrypt API (candidate license-gate functions):")
out("")
out("```")
out("func_ep          apis_called")
for ep, apis in sorted(bcrypt_callsite_funcs.items()):
    out("%-20s %s" % (ep, ", ".join(sorted(apis))))
out("```")
out("")

# ---------------------------------------------------------------------------
# SECTION 2: Registry string xrefs
# ---------------------------------------------------------------------------
out("## Section 2: Registry String Xrefs")
out("")
out("String: `\\Registry\\Machine\\Software\\MagicUtilities\\Driver`")
out("Expected address from first pass: 0x%s" % REGISTRY_STRING_ADDR)
out("")

registry_callers = []
try:
    reg_addr = addr_from_str(REGISTRY_STRING_ADDR)
    sites = refs_to_addr(reg_addr)
    out("```")
    if sites:
        for from_addr, func_name, func_ep in sites:
            out("  ref from 0x%s  in %s @ %s" % (from_addr, func_name, func_ep))
            registry_callers.append((from_addr, func_name, func_ep))
    else:
        out("  (no references found at expected address)")
    out("```")
    out("")
except Exception as e:
    out("  [ERROR] resolving registry address: %s" % str(e))
    out("")

# Also scan all strings for \Registry\ or MagicUtilities patterns
out("### All strings referencing MagicUtilities or Registry paths")
out("")
out("```")
out("addr           refs  value")
strs_iter = listing.getDefinedData(True)
reg_strs_found = 0
for d in strs_iter:
    if d is None:
        continue
    val = d.getDefaultValueRepresentation()
    if not val:
        continue
    s = str(val).lower()
    if "magicutilities" in s or "magicmouse" in s or "registry" in s:
        refs = list(ref_mgr.getReferencesTo(d.getAddress()))
        out("  %s  %3d  %s" % (d.getAddress(), len(refs), str(d.getDefaultValueRepresentation())[:100]))
        reg_strs_found += 1
    if reg_strs_found > 200:
        break
out("```")
out("")

# ---------------------------------------------------------------------------
# SECTION 3: RawPdo string xrefs
# ---------------------------------------------------------------------------
out("## Section 3: RawPdo Device Interface String Xrefs")
out("")
out("String: `{7D55502A-2C87-441F-9993-0761990E0C7A}\\MagicMouseRawPdo`")
out("Expected address from first pass: 0x%s" % RAWPDO_STRING_ADDR)
out("")

rawpdo_callers = []
try:
    rawpdo_addr = addr_from_str(RAWPDO_STRING_ADDR)
    sites = refs_to_addr(rawpdo_addr)
    out("```")
    if sites:
        for from_addr, func_name, func_ep in sites:
            out("  ref from 0x%s  in %s @ %s" % (from_addr, func_name, func_ep))
            rawpdo_callers.append((from_addr, func_name, func_ep))
    else:
        out("  (no references found at expected address)")
        # Scan for the string by content
        out("  Scanning for {7D55502A string bytes ...")
    out("```")
    out("")
except Exception as e:
    out("  [ERROR] resolving rawpdo address: %s" % str(e))
    out("")

# Scan for GUID bytes in memory
out("### GUID byte scan: {7D55502A-2C87-441F-9993-0761990E0C7A}")
out("")
_guid_ints = [0x2A, 0x50, 0x55, 0x7D, 0x87, 0x2C, 0x1F, 0x44,
              0x99, 0x93, 0x07, 0x61, 0x99, 0x0E, 0x0C, 0x7A]
guid_bytes = jarray.array([(b - 256) if b >= 128 else b for b in _guid_ints], "b")
guid_hits = find_bytes_all(guid_bytes, "GUID {7D55502A...}")
out("```")
if guid_hits:
    for gh in guid_hits:
        refs = refs_to_addr(gh)
        out("  GUID at %s" % gh)
        for from_addr, fn, ep in refs:
            out("    ref from %s in %s @ %s" % (from_addr, fn, ep))
else:
    out("  GUID bytes not found in memory (may be built from fields at runtime)")
out("```")
out("")

# ---------------------------------------------------------------------------
# SECTION 4: HID descriptor byte pattern search
# ---------------------------------------------------------------------------
out("## Section 4: HID Descriptor Byte Pattern Search")
out("")
out("Searching for Mode A descriptor signature bytes.")
out("Expected: HID report descriptor embedded as literal byte array.")
out("")

desc_patterns = [
    (HID_MOEA_HEADER,  "Mode A header: UsagePage=GenericDesktop + Usage=Mouse (05 01 09 02)"),
    (HID_WHEEL_USAGE,  "Wheel usage (09 38)"),
    (HID_ACPAN_USAGE,  "AC Pan usage (0A 38 02)"),
    (HID_RESMULT_USAGE,"Resolution Multiplier usage (09 48)"),
]
for pattern, desc in desc_patterns:
    hits = find_bytes_all(pattern, desc)
    out("### %s" % desc)
    out("```")
    if hits:
        for h in hits[:10]:
            # Get surrounding context to help identify the descriptor array
            func = get_func_at_or_containing(h)
            fn_info = "in %s @ %s" % (func.getName(), func.getEntryPoint()) if func else "not in function"
            # Try to read a few surrounding bytes for context
            try:
                ctx = jarray.zeros(16, "b")
                mem.getBytes(h, ctx)
                ctx_hex = " ".join("%02X" % (b & 0xFF) for b in ctx)
                out("  at %s  [%s]  %s" % (h, ctx_hex, fn_info))
            except Exception:
                out("  at %s  %s" % (h, fn_info))
    else:
        out("  (not found -- descriptor may be built at runtime, not stored as literal bytes)")
    out("```")
    out("")

# ---------------------------------------------------------------------------
# SECTION 5: IOCTL code search
# ---------------------------------------------------------------------------
out("## Section 5: IOCTL Code Search")
out("")
out("Scanning for IOCTL_HID_GET_REPORT_DESCRIPTOR (0xB0193) and related HID IOCTL codes.")
out("")

# Search for known IOCTL values as 4-byte LE constants
for ioctl_val in IOCTL_HID_CANDIDATES:
    b0 = (ioctl_val >>  0) & 0xFF
    b1 = (ioctl_val >>  8) & 0xFF
    b2 = (ioctl_val >> 16) & 0xFF
    b3 = (ioctl_val >> 24) & 0xFF
    pattern = jarray.array([
        (b0 - 256) if b0 >= 128 else b0,
        (b1 - 256) if b1 >= 128 else b1,
        (b2 - 256) if b2 >= 128 else b2,
        (b3 - 256) if b3 >= 128 else b3,
    ], "b")
    hits = find_bytes_all(pattern, "IOCTL 0x%08X" % ioctl_val)
    if hits:
        out("### IOCTL 0x%08X -- FOUND at %d location(s)" % (ioctl_val, len(hits)))
        out("```")
        for h in hits[:5]:
            func = get_func_at_or_containing(h)
            fn_info = "in %s @ %s" % (func.getName(), str(func.getEntryPoint())) if func else "not in function"
            out("  at %s  %s" % (h, fn_info))
        out("```")
        out("")

# Full CTL_CODE scan for device type 0x000B
out("### Full CTL_CODE scan (device type 0x000B = HID/keyboard)")
out("")
ioctl_hits = scan_for_ioctl_constants()
out("```")
out("address         ioctl_value  device  access  function  method  containing_func")
for addr, val in sorted(ioctl_hits, key=lambda x: x[1])[:50]:
    device   = (val >> 16) & 0xFFFF
    access   = (val >> 14) & 0x3
    function = (val >>  2) & 0xFFF
    method   = (val >>  0) & 0x3
    func = get_func_at_or_containing(addr)
    fn_info = func.getName() if func else "?"
    out("  %s  0x%08X  0x%04X  %d  0x%03X  %d  %s" % (
        addr, val, device, access, function, method, fn_info))
if not ioctl_hits:
    out("  (no IOCTL codes matching device type 0x000B found in accessible blocks)")
out("```")
out("")

# ---------------------------------------------------------------------------
# SECTION 6: WDF queue / callback identification
# ---------------------------------------------------------------------------
out("## Section 6: WDF Queue Setup and EvtIoDeviceControl Callback")
out("")
out("Tracing WDF API call sites to identify queue setup and I/O callback registration.")
out("")

wdf_callsites = {}
for wdf_func in WDF_QUEUE_FUNCS:
    sites = refs_to_sym_name(wdf_func)
    if sites:
        out("### %s" % wdf_func)
        out("```")
        for from_addr, func_name, func_ep in sites:
            out("  called from %s  in %s @ %s" % (from_addr, func_name, func_ep))
            if func_ep not in wdf_callsites:
                wdf_callsites[func_ep] = []
            wdf_callsites[func_ep].append(wdf_func)
        out("```")
        out("")

if not wdf_callsites:
    out("No WDF API call sites found via symbol table.")
    out("Note: WDF functions may be resolved via WdfVersionBind table (indirect dispatch).")
    out("See Section 8 for WdfVersionBind xrefs.")
    out("")

# ---------------------------------------------------------------------------
# SECTION 7: All imports with xrefs
# ---------------------------------------------------------------------------
out("## Section 7: All Imports with Call Sites")
out("")
out("Full import cross-reference for all kernel APIs. Organizes driver behavior map.")
out("")
out("```")
out("import_name                              call_count  calling_functions")
all_imports = []
for sym in sym_table.getExternalSymbols():
    name = sym.getName()
    if not name or name.startswith("_"):
        continue
    sites = []
    for ref in ref_mgr.getReferencesTo(sym.getAddress()):
        from_addr = ref.getFromAddress()
        func = get_func_at_or_containing(from_addr)
        fn_ep = str(func.getEntryPoint()) if func else "?"
        sites.append(fn_ep)
    unique_callers = sorted(set(sites))
    all_imports.append((name, len(sites), unique_callers))

for name, cnt, callers in sorted(all_imports, key=lambda x: -x[1]):
    caller_str = ", ".join(callers[:5])
    if len(callers) > 5:
        caller_str += " ...+%d" % (len(callers) - 5)
    out("  %-40s %3d  %s" % (name, cnt, caller_str))
out("```")
out("")

# ---------------------------------------------------------------------------
# SECTION 8: WdfVersionBind / WdfLdrQueryInterface xrefs
# ---------------------------------------------------------------------------
out("## Section 8: WdfVersionBind / WdfLdrQueryInterface Xrefs")
out("")
out("WDF indirect dispatch: driver registers callbacks via WdfVersionBind.")
out("Finding the call site tells us which function initializes the WDF table.")
out("")
for wdf_init in ["WdfVersionBind", "WdfVersionBindClass", "WdfLdrQueryInterface",
                 "WdfVersionUnbind", "WdfVersionUnbindClass"]:
    sites = refs_to_sym_name(wdf_init)
    if sites:
        out("### %s" % wdf_init)
        out("```")
        for from_addr, fn, ep in sites:
            out("  from %s  in %s @ %s" % (from_addr, fn, ep))
        out("```")
        out("")

# ---------------------------------------------------------------------------
# SECTION 9: Initialize decompiler
# ---------------------------------------------------------------------------
dec = DecompInterface()
opts = DecompileOptions()
opts.grabFromProgram(prog)
dec.setOptions(opts)
dec.openProgram(prog)

# ---------------------------------------------------------------------------
# SECTION 10: DriverEntry decompilation
# ---------------------------------------------------------------------------
out("## Section 9: DriverEntry Decompilation (timeout=%ds)" % DECOMPILE_TIMEOUT)
out("")
out("```c")
de_func = None
for f in fm.getFunctions(True):
    if f.getName() in ("DriverEntry", "GsDriverEntry", "_DriverEntry", "entry"):
        de_func = f
        break
if de_func is None:
    ep_addrs = list(sym_table.getExternalEntryPointIterator())
    if ep_addrs:
        ep = ep_addrs[0]
        de_func = fm.getFunctionAt(ep)
if de_func:
    out("// Function: %s @ %s" % (de_func.getName(), de_func.getEntryPoint()))
    out(decompile_function(dec, de_func))
else:
    out("// DriverEntry not found")
out("```")
out("")

# ---------------------------------------------------------------------------
# SECTION 11: Top N functions decompiled
# ---------------------------------------------------------------------------
out("## Section 10: Top %d Functions Decompiled (timeout=%ds each)" % (
    DECOMPILE_TOP_N, DECOMPILE_TIMEOUT))
out("")
out("These are the largest functions by byte count -- most likely dispatchers,")
out("descriptor-mutation logic, and translation routines.")
out("")

all_funcs = []
for f in fm.getFunctions(True):
    all_funcs.append((f.getBody().getNumAddresses(), f.getEntryPoint(), f.getName()))
all_funcs.sort(reverse=True)

decompile_success = 0
decompile_total   = 0
for sz, ad, nm in all_funcs[:DECOMPILE_TOP_N]:
    decompile_total += 1
    f = fm.getFunctionAt(ad)
    out("### %s @ %s (%d bytes)" % (nm, ad, sz))
    if f:
        c_code = decompile_function(dec, f)
        if "decompile failed" not in c_code and "decompile exception" not in c_code:
            decompile_success += 1
        out("```c")
        out(c_code)
        out("```")
    else:
        out("```c")
        out("// function object not found at address")
        out("```")
    out("")

# ---------------------------------------------------------------------------
# SECTION 12: BCrypt-calling functions decompiled
# ---------------------------------------------------------------------------
out("## Section 11: BCrypt-Calling Functions Decompiled")
out("")
out("These functions call BCrypt APIs -- the license gate implementation.")
out("")
for ep, apis in sorted(bcrypt_callsite_funcs.items()):
    f = fm.getFunctionAt(addr_from_str(ep)) if ep != "?" else None
    out("### %s (BCrypt APIs: %s)" % (ep, ", ".join(sorted(apis))))
    if f and not any(ep == str(a) for a, _, _ in all_funcs[:DECOMPILE_TOP_N]):
        # Not already decompiled in top N -- decompile now
        c_code = decompile_function(dec, f)
        if "decompile failed" not in c_code and "decompile exception" not in c_code:
            decompile_success += 1
        decompile_total += 1
        out("```c")
        out(c_code)
        out("```")
    elif f:
        out("(already decompiled in Section 10 above)")
    else:
        out("(function not found at %s)" % ep)
    out("")

# ---------------------------------------------------------------------------
# SECTION 13: Registry-referencing functions decompiled
# ---------------------------------------------------------------------------
out("## Section 12: Registry-Referencing Functions Decompiled")
out("")
out("Functions that reference the MagicUtilities registry path -- config read logic.")
out("")
already_decompiled = set(str(a) for _, a, _ in all_funcs[:DECOMPILE_TOP_N])
for from_addr, fn, ep in registry_callers:
    if ep in already_decompiled or ep in bcrypt_callsite_funcs:
        out("### %s @ %s -- already decompiled above" % (fn, ep))
        out("")
        continue
    f = fm.getFunctionAt(addr_from_str(ep)) if ep != "?" else None
    out("### %s @ %s" % (fn, ep))
    if f:
        c_code = decompile_function(dec, f)
        if "decompile failed" not in c_code and "decompile exception" not in c_code:
            decompile_success += 1
        decompile_total += 1
        out("```c")
        out(c_code)
        out("```")
    else:
        out("(function not found at %s)" % ep)
    out("")

# ---------------------------------------------------------------------------
# SECTION 14: RawPdo-referencing functions decompiled
# ---------------------------------------------------------------------------
out("## Section 13: RawPdo Device Interface Functions Decompiled")
out("")
out("Functions that reference {7D55502A...}\\MagicMouseRawPdo -- PDO registration logic.")
out("")
for from_addr, fn, ep in rawpdo_callers:
    if ep in already_decompiled or ep in bcrypt_callsite_funcs:
        out("### %s @ %s -- already decompiled above" % (fn, ep))
        out("")
        continue
    f = fm.getFunctionAt(addr_from_str(ep)) if ep != "?" else None
    out("### %s @ %s" % (fn, ep))
    if f:
        c_code = decompile_function(dec, f)
        if "decompile failed" not in c_code and "decompile exception" not in c_code:
            decompile_success += 1
        decompile_total += 1
        out("```c")
        out(c_code)
        out("```")
    else:
        out("(function not found at %s)" % ep)
    out("")

# ---------------------------------------------------------------------------
# SECTION 15: Confirmed Architecture Summary
# ---------------------------------------------------------------------------
out("## Confirmed Architecture Summary")
out("")
out("*Synthesized from xref tracing + decompilation above.*")
out("")
out("### Q1: WHERE is the BCrypt-based license check called?")
out("")
if bcrypt_callsite_funcs:
    out("BCrypt APIs called from these functions:")
    for ep, apis in sorted(bcrypt_callsite_funcs.items()):
        f = fm.getFunctionAt(addr_from_str(ep)) if ep != "?" else None
        sz = f.getBody().getNumAddresses() if f else 0
        out("  - %s @ %s (%d bytes) -- calls: %s" % (
            (f.getName() if f else "?"), ep, sz, ", ".join(sorted(apis))))
else:
    out("  BCrypt call sites not resolved via symbol table.")
    out("  Possible causes: (a) driver uses MmGetSystemRoutineAddress to resolve BCrypt at runtime,")
    out("  (b) BCrypt linked as inline, (c) Ghidra analysis incomplete.")
    out("  See import list: BCryptOpenAlgorithmProvider IS in the import table (confirmed first pass).")
out("")

out("### Q2: WHERE is descriptor mutation done?")
out("")
if any(h for pattern, _ in desc_patterns for h in find_bytes_all(pattern, "")):
    out("  HID descriptor bytes found in binary -- see Section 4 for addresses.")
    out("  The function containing those bytes performs the descriptor substitution.")
else:
    out("  HID descriptor literal bytes NOT found in binary.")
    out("  Architecture implication: descriptor is built from individual HID item byte sequences")
    out("  scattered in code, or assembled at runtime from field values.")
    out("  Recommended: decompile functions near IoOpenDeviceRegistryKey call sites and")
    out("  look for IRP completion with STATUS_SUCCESS where the InformationBuffer is")
    out("  filled with descriptor-shaped data.")
out("")

out("### Q3: WHERE is the IPC IOCTL handler?")
out("")
if ioctl_hits:
    out("  IOCTL codes found -- see Section 5 for containing functions.")
    out("  The function containing the largest cluster of IOCTL codes is the DeviceControl handler.")
else:
    out("  No IOCTL codes matching device type 0x000B found by constant scan.")
    out("  WDF drivers often use WdfIoQueueCreate with an EvtIoDeviceControl callback pointer.")
    out("  The callback address can be read from the WDF_IO_QUEUE_CONFIG structure passed")
    out("  to WdfIoQueueCreate. The WdfIoQueueCreate call site (Section 6) is the entry point.")
out("")

out("### Q4: WHAT triggers translation vs passthrough?")
out("")
out("  From empirical findings (SESSION-12):")
out("  - Mode A descriptor is set unconditionally (kernel loads, descriptor changes immediately)")
out("  - Scroll and battery are BROKEN under trial-expired state")
out("  - MagicMouseUtilities.exe silent-exits (license check in userland)")
out("  Hypothesis: kernel filter has a 'enabled' flag set via IOCTL from userland service.")
out("  BCrypt in kernel = validates a license token passed via IOCTL from userland.")
out("  Without the IOCTL enable sequence: descriptor correct, translation zero-fills.")
out("  This hypothesis is supported if BCrypt-calling function is NOT in DriverEntry call chain")
out("  and IS reachable from an IOCTL dispatch path.")
out("")

# ---------------------------------------------------------------------------
# Decompile stats
# ---------------------------------------------------------------------------
out("## Decompilation Statistics")
out("")
out("```")
out("total_attempts : %d" % decompile_total)
out("succeeded      : %d" % decompile_success)
out("failed         : %d" % (decompile_total - decompile_success))
out("success_rate   : %.0f%%" % (100.0 * decompile_success / decompile_total if decompile_total else 0))
out("timeout_used   : %ds" % DECOMPILE_TIMEOUT)
out("```")
out("")

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------
with open(OUT_PATH, "w") as fh:
    fh.write("\n".join(lines))

print("M12 Extended Ghidra findings written to: %s" % OUT_PATH)
print("Total lines: %d" % len(lines))
print("Decompile success: %d/%d" % (decompile_success, decompile_total))
