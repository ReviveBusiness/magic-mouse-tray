#!/usr/bin/env python3
"""
mm-rid27-etl-parser.py - Parse RID=0x27 input report frames and identify battery byte offset.

Sources accepted:
  1. JSON output from mm-test-A4-hidpayload-capture.ps1 (preferred)
  2. Raw hex dump file (one 94-char line per frame, no spaces)
  3. CSV from tracerpt (legacy A2 format -- limited to metadata only)

Usage:
  python3 mm-rid27-etl-parser.py --json <frames.json>
  python3 mm-rid27-etl-parser.py --hex <frames.hex>
  python3 mm-rid27-etl-parser.py --csv <capture.csv>   # legacy, low-yield

Output:
  Variance table for all 46 byte positions.
  Battery byte offset candidates with confidence ratings.
  Recommended BATTERY_OFFSET value.
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path


PAYLOAD_LEN = 46          # RID=0x27 payload size (after stripping the 0x27 RID byte)
BATTERY_MIN = 1           # Per HID descriptor Logical Min
BATTERY_MAX = 65          # Per HID descriptor Logical Max


def load_frames_from_json(path: str) -> list[bytes]:
    """Load frames from A4 JSON output. Each frame has a PayloadHex field."""
    frames = []
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    if not isinstance(data, list):
        data = [data]

    for item in data:
        hex_str = item.get('PayloadHex', '')
        payload_len = item.get('PayloadLength', 0)

        if not hex_str:
            continue

        raw = bytes.fromhex(hex_str)

        # Strip leading RID byte if present (byte[0] == 0x27)
        if len(raw) > 0 and raw[0] == 0x27:
            raw = raw[1:]
        # Strip leading RID at position 1 if flagged
        elif item.get('Note') == 'RID at offset 1' and len(raw) > 1 and raw[1] == 0x27:
            raw = raw[2:]

        if len(raw) == PAYLOAD_LEN:
            frames.append(raw)
        elif len(raw) > PAYLOAD_LEN:
            # Truncate to expected length
            frames.append(raw[:PAYLOAD_LEN])
        # Skip short frames

    return frames


def load_frames_from_hex(path: str) -> list[bytes]:
    """Load frames from a plain hex file (one 92-char line per frame)."""
    frames = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            # Accept lines with or without spaces/colons
            clean = re.sub(r'[^0-9A-Fa-f]', '', line)
            if len(clean) == PAYLOAD_LEN * 2:
                frames.append(bytes.fromhex(clean))
            elif len(clean) == (PAYLOAD_LEN + 1) * 2:
                # 47 bytes including RID -- strip first byte if it is 0x27
                raw = bytes.fromhex(clean)
                if raw[0] == 0x27:
                    frames.append(raw[1:])
    return frames


def load_frames_from_csv(path: str) -> list[bytes]:
    """
    Attempt to extract RID=0x27 payloads from tracerpt CSV.
    Legacy path -- A2 CSV does not contain payloads; returns empty.
    Retained so callers get an explicit "no payloads" message rather than a crash.
    """
    frames = []
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    # Search for 47-byte hex sequences adjacent to "27" or "0x27"
    # Pattern: 0x27 followed by 92 hex chars (46 bytes)
    pattern = re.compile(r'(?:0x27|27)\s*[,\s]+([0-9A-Fa-f]{92})')
    for m in pattern.finditer(content):
        try:
            frames.append(bytes.fromhex(m.group(1)))
        except ValueError:
            pass

    return frames


def analyze_variance(frames: list[bytes]) -> dict:
    """
    For each of 46 byte positions, compute:
      - unique value count
      - value set
      - min, max
      - whether all values fall in [BATTERY_MIN..BATTERY_MAX]
    Returns dict keyed by offset.
    """
    stats = {}
    for offset in range(PAYLOAD_LEN):
        values = set()
        for frame in frames:
            if offset < len(frame):
                values.add(frame[offset])
        sorted_vals = sorted(values)
        in_range = bool(values) and all(BATTERY_MIN <= v <= BATTERY_MAX for v in values)
        stats[offset] = {
            'unique_count': len(values),
            'values': sorted_vals,
            'min': min(values) if values else None,
            'max': max(values) if values else None,
            'in_range_1_65': in_range,
        }
    return stats


def score_candidates(stats: dict, frame_count: int) -> list[tuple]:
    """
    Score each byte offset as a battery candidate.

    Scoring rules (per M12-HID-PROTOCOL-VALIDATION-2026-04-28.md guidance):
      - Must be in range [1..65] (BATTERY_MIN..BATTERY_MAX)
      - VERY_HIGH: unique_count == 1 and in_range (battery didn't change during capture)
      - VERY_HIGH: unique_count in [2..4] and in_range (small variation = battery stable)
      - HIGH:      unique_count in [5..10] and in_range
      - MEDIUM:    unique_count in [11..20] and in_range (possibly touched high-variance)
      - LOW:       any other case (out of range or very high variance)

    Touch/scroll bytes will have unique_count > 20 or values outside [1..65].
    Timestamp bytes will have monotonically increasing, very high unique count.
    Padding bytes will have unique_count == 1 with a constant outside [1..65].

    Returns list of (offset, confidence, unique_count, values) sorted best-first.
    """
    candidates = []
    for offset, s in stats.items():
        uc = s['unique_count']
        in_r = s['in_range_1_65']
        vals = s['values']

        if not in_r:
            confidence = 'LOW'
        elif uc == 0:
            confidence = 'LOW'
        elif uc == 1:
            # Single value -- could be battery at fixed level, or static field
            # If the single value is in [1..65], it could be either.
            # Prefer calling it VERY_HIGH since battery often stays stable during short capture.
            confidence = 'VERY_HIGH'
        elif 2 <= uc <= 4:
            confidence = 'VERY_HIGH'
        elif 5 <= uc <= 10:
            confidence = 'HIGH'
        elif 11 <= uc <= 20:
            confidence = 'MEDIUM'
        else:
            confidence = 'LOW'

        order = {'VERY_HIGH': 0, 'HIGH': 1, 'MEDIUM': 2, 'LOW': 3}
        candidates.append((offset, confidence, uc, vals, order[confidence]))

    # Sort: best confidence first, then lowest variance (most stable = most likely battery)
    candidates.sort(key=lambda x: (x[4], x[2]))
    return candidates


def translate_battery(raw: int) -> int:
    """Apply M12 translation formula: (raw - 1) * 100 / 64 clamped [0..100]."""
    if raw < 1:
        return 0
    if raw > 65:
        return 100
    return int((raw - 1) * 100 / 64)


def print_variance_table(stats: dict):
    """Print per-byte variance table."""
    print(f"\n{'Offset':>6}  {'Unique':>6}  {'Min':>4}  {'Max':>4}  {'In[1..65]':>9}  {'Values (first 10)'}")
    print('-' * 80)
    for offset in range(PAYLOAD_LEN):
        s = stats[offset]
        vals_preview = str(s['values'][:10])[1:-1] if s['values'] else ''
        print(f"{offset:>6}  {s['unique_count']:>6}  {str(s['min']):>4}  {str(s['max']):>4}  "
              f"{'YES' if s['in_range_1_65'] else 'no':>9}  {vals_preview}")


def main():
    ap = argparse.ArgumentParser(description='RID=0x27 battery byte offset analyzer')
    src = ap.add_mutually_exclusive_group()
    src.add_argument('--json', metavar='FILE', help='A4 JSON frames file')
    src.add_argument('--hex', metavar='FILE', help='Plain hex frames file')
    src.add_argument('--csv', metavar='FILE', help='tracerpt CSV (legacy, low-yield)')
    ap.add_argument('--out', metavar='FILE', default='', help='Write summary to file')
    args = ap.parse_args()

    # Default to searching well-known paths if no source given
    if not args.json and not args.hex and not args.csv:
        search_dirs = [
            Path('/home/lesley/projects/Personal/magic-mouse-tray/.ai/test-runs'),
            Path('/home/lesley/.claude/worktrees/ai-m12-empirical-and-crd/.ai'),
        ]
        found_json = None
        for d in search_dirs:
            if d.exists():
                matches = sorted(d.rglob('rid27-frames.json'), reverse=True)
                if matches:
                    found_json = str(matches[0])
                    break
        if found_json:
            print(f"[auto] Using most recent frames file: {found_json}")
            args.json = found_json
        else:
            # Fall back to legacy CSV
            legacy_csv = '/home/lesley/projects/Personal/magic-mouse-tray/.ai/test-runs/2026-04-27-154930-T-V3-AF/test-A2-etw-bth-hid-20260428-181312.csv'
            if Path(legacy_csv).exists():
                print(f"[auto] Falling back to legacy CSV: {legacy_csv}")
                args.csv = legacy_csv
            else:
                print("ERROR: no frame source found. Provide --json, --hex, or --csv.")
                return 1

    # Load frames
    if args.json:
        frames = load_frames_from_json(args.json)
        source = args.json
    elif args.hex:
        frames = load_frames_from_hex(args.hex)
        source = args.hex
    else:
        frames = load_frames_from_csv(args.csv)
        source = args.csv

    print(f"\nRID=0x27 Battery Offset Analyzer")
    print(f"=================================")
    print(f"Source: {source}")
    print(f"Frames loaded: {len(frames)}")

    if not frames:
        print("\nRESULT: BLOCKED -- No RID=0x27 frames found in source.")
        print()
        print("The ETW capture (even at Verbose level) does not preserve")
        print("HID input report payloads in a form accessible via Get-WinEvent.")
        print()
        print("REQUIRED FALLBACK OPTIONS (in priority order):")
        print()
        print("1. M12 driver LogShadowBuffer() [RECOMMENDED for Phase 3]")
        print("   - Install M12 with DbgPrint enabled (debug build)")
        print("   - Run WinDbg or DebugView II")
        print("   - Query tray battery display at 100% charge -> capture shadow hex")
        print("   - Charge to 20%, repeat -> identify changing byte position")
        print("   - Update BATTERY_OFFSET registry value")
        print()
        print("2. Bluetooth HCI sniff")
        print("   - Install npcap with BT capture support, or use Ubertooth")
        print("   - Wireshark filter: btl2cap.cid == 0x13 && btl2cap.length == 47")
        print("   - Byte 0 of L2CAP payload = 0x27 (RID); bytes 1..46 = vendor blob")
        print("   - Diff byte positions across captures at different battery levels")
        print()
        print("3. Registry-based empirical probe (no kernel debug)")
        print("   - Set BATTERY_OFFSET=0 through BATTERY_OFFSET=45 in sequence")
        print("   - At each value, check tray battery display against device actual")
        print("   - Stop when display matches actual battery level")
        print("   - Requires 46 test cycles but needs no special tools")
        print()
        print("DESIGN IMPLICATION:")
        print("  BATTERY_OFFSET is already registry-tunable in M12 v1.2 design.")
        print("  Default value of 1 (first payload byte) is a reasonable starting point.")
        print("  The Phase 3 acceptance gate requires empirical confirmation.")
        return 1

    # Analyze
    stats = analyze_variance(frames)
    candidates = score_candidates(stats, len(frames))

    # Print table
    print_variance_table(stats)

    # Top candidates
    print(f"\nTop Battery Offset Candidates:")
    print('=' * 70)
    very_high = [(o, c, uc, v) for o, c, uc, v, _ in candidates if c == 'VERY_HIGH']
    high      = [(o, c, uc, v) for o, c, uc, v, _ in candidates if c == 'HIGH']
    medium    = [(o, c, uc, v) for o, c, uc, v, _ in candidates if c == 'MEDIUM']

    shown = 0
    for offset, conf, uc, vals in (very_high + high + medium)[:10]:
        raw_example = vals[0] if vals else None
        pct_example = translate_battery(raw_example) if raw_example is not None else 'N/A'
        print(f"\n  Offset {offset:2d}: confidence={conf}, unique_values={uc}")
        print(f"           values={vals}")
        if raw_example is not None:
            print(f"           if battery: raw={raw_example} -> {pct_example}% (formula: (raw-1)*100/64)")
        shown += 1
        if shown >= 10:
            break

    # Final verdict
    print(f"\n{'='*70}")
    print(f"\nFINAL VERDICT:")

    if len(very_high) == 1:
        best = very_high[0]
        print(f"\n  BATTERY_OFFSET = {best[0]}")
        print(f"  Confidence: VERY_HIGH")
        print(f"  Values seen: {best[3]}")
        if best[3]:
            sample_raw = best[3][0]
            sample_pct = translate_battery(sample_raw)
            print(f"  Sample translation: raw={sample_raw} -> {sample_pct}%")
        print(f"\n  Action: Set BATTERY_OFFSET={best[0]} in registry.")
        print(f"  Verify: At known battery %, check tray display matches.")
    elif len(very_high) > 1:
        print(f"\n  MULTIPLE VERY_HIGH candidates found: offsets {[x[0] for x in very_high]}")
        print(f"  Confidence: MEDIUM")
        print(f"\n  Disambiguation required:")
        print(f"  Capture at TWO significantly different battery levels (e.g., 90% and 20%).")
        print(f"  Only one offset will change between captures. That is BATTERY_OFFSET.")
    elif len(high) >= 1:
        best = high[0]
        print(f"\n  BATTERY_OFFSET = {best[0]} (provisional, HIGH confidence)")
        print(f"  Values: {best[3]}")
        print(f"\n  Recommend second capture at different battery level to confirm.")
    else:
        print(f"\n  NO confident battery offset identified.")
        print(f"  All bytes either out of range [1..65] or too variable.")
        print(f"  The ETW capture may not contain valid RID=0x27 payload data.")
        print(f"  Recommend: use M12 LogShadowBuffer() or BT HCI sniff.")

    return 0


if __name__ == '__main__':
    sys.exit(main())
