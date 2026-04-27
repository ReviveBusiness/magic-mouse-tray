#!/usr/bin/env python3
"""
mm-extract-pe.py — Find and extract embedded PE binaries from a larger file.

Useful when standard installer-extraction tools (innoextract, 7z) don't
recognize the installer format. We scan for `MZ` headers, validate each
candidate has a real PE signature, and extract the PE up to its declared
size.

Usage:
  python3 mm-extract-pe.py <input-file> [--filter NAME] [--out DIR]

Options:
  --filter NAME   Only extract PE files whose embedded resource string contains NAME
                  (e.g., 'MagicMouse'). Default: extract all.
  --out DIR       Output directory (default: ./extracted/).
  --list          Just list what's there, don't extract.
"""
import argparse
import os
import struct
import sys

DOS_SIG = b'MZ'
PE_SIG  = b'PE\0\0'

def find_pe_at(buf, offset):
    """If buf[offset:] looks like a real PE/PE32+ binary, return its declared size, else None."""
    # DOS header: 64 bytes, 'MZ' + e_lfanew at offset 0x3C
    if buf[offset:offset+2] != DOS_SIG:
        return None
    if offset + 0x40 > len(buf):
        return None
    e_lfanew = struct.unpack_from('<I', buf, offset + 0x3C)[0]
    pe_off = offset + e_lfanew
    if pe_off + 4 > len(buf) or buf[pe_off:pe_off+4] != PE_SIG:
        return None
    # COFF header at pe_off+4: MachineType(2) NumberOfSections(2) ...
    # Optional header at pe_off+24: starts with magic 0x10b (PE32) or 0x20b (PE32+)
    if pe_off + 24 + 2 > len(buf):
        return None
    opt_magic = struct.unpack_from('<H', buf, pe_off + 24)[0]
    if opt_magic not in (0x10b, 0x20b):
        return None
    # Calculate size: walk section headers and find the max PointerToRawData + SizeOfRawData
    coff_size = 24
    n_sections = struct.unpack_from('<H', buf, pe_off + 6)[0]
    size_of_opt = struct.unpack_from('<H', buf, pe_off + 20)[0]
    section_table = pe_off + 4 + 20 + size_of_opt
    max_end = 0
    for i in range(n_sections):
        sh = section_table + i * 40
        if sh + 40 > len(buf):
            return None
        size_raw = struct.unpack_from('<I', buf, sh + 16)[0]
        ptr_raw  = struct.unpack_from('<I', buf, sh + 20)[0]
        end = ptr_raw + size_raw
        if end > max_end:
            max_end = end
    return max_end if max_end > 0 else None

def get_resource_strings(pe_buf):
    """Best-effort extraction of printable strings inside a PE's .rsrc and overlay.
    Used to identify which extracted PE is which (look for 'MagicMouse' etc)."""
    strings = []
    cur = bytearray()
    for b in pe_buf:
        if 32 <= b < 127:
            cur.append(b)
        else:
            if len(cur) >= 6:
                strings.append(bytes(cur).decode('latin-1'))
            cur.clear()
    if len(cur) >= 6:
        strings.append(bytes(cur).decode('latin-1'))
    return strings

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('input')
    ap.add_argument('--filter', default=None)
    ap.add_argument('--out', default='./extracted')
    ap.add_argument('--list', action='store_true')
    args = ap.parse_args()

    with open(args.input, 'rb') as f:
        buf = f.read()
    print(f'[mm-extract-pe] input: {args.input} ({len(buf):,} bytes)', file=sys.stderr)

    found = []
    pos = 0
    while True:
        idx = buf.find(DOS_SIG, pos)
        if idx < 0:
            break
        size = find_pe_at(buf, idx)
        if size and size >= 4096:    # skip tiny stubs
            found.append((idx, size))
            pos = idx + size
        else:
            pos = idx + 2

    print(f'[mm-extract-pe] found {len(found)} PE candidates', file=sys.stderr)

    if not args.list:
        os.makedirs(args.out, exist_ok=True)

    for i, (off, sz) in enumerate(found):
        pe_data = buf[off:off+sz]
        # Identify by looking at strings
        strs = get_resource_strings(pe_data[-40000:])
        descriptor = next((s for s in strs if 'MagicMouse' in s or 'magicmouse' in s
                          or '.sys' in s or 'AppleWireless' in s), '<unknown>')
        # Only short identifying excerpt
        descriptor = descriptor[:80]

        # Apply filter
        if args.filter and args.filter.lower() not in descriptor.lower() \
            and not any(args.filter.lower() in s.lower() for s in strs[-30:]):
            continue

        # Look for filename hint
        name_hint = next((s for s in strs if s.endswith('.sys') or s.endswith('.exe')
                         or s.endswith('.dll')), None)
        machine = struct.unpack_from('<H', pe_data, struct.unpack_from('<I', pe_data, 0x3C)[0] + 4)[0]
        machine_name = {0x8664:'x64', 0x14c:'x86', 0xaa64:'arm64'}.get(machine, f'0x{machine:04x}')

        print(f'[{i:02d}] offset=0x{off:08x} size={sz:,} arch={machine_name}  '
              f'hint={name_hint!r}  desc={descriptor!r}')

        if not args.list:
            out_name = name_hint if name_hint else f'pe_{i:02d}_{off:08x}.bin'
            # Sanitize
            out_name = os.path.basename(out_name)
            out_path = os.path.join(args.out, out_name)
            # If exists, append index
            if os.path.exists(out_path):
                root, ext = os.path.splitext(out_name)
                out_path = os.path.join(args.out, f'{root}_{i:02d}{ext}')
            with open(out_path, 'wb') as fo:
                fo.write(pe_data)
            print(f'     -> {out_path}', file=sys.stderr)

if __name__ == '__main__':
    main()
