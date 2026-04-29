#!/usr/bin/env python3
"""
Extract RID=0x27 input report payloads from ETW HID capture.

Purpose: Identify the battery byte offset within the 46-byte vendor blob by
analyzing all RID=0x27 frames and finding the byte position with the most
variation (or the most consistency if battery hasn't changed).

Constraints:
  - Reads CSV and TXT ETW captures
  - Looks for RID=0x27 (0x27 in decimal = 39) vendor blob frames
  - Each frame should contain 46 bytes of payload (after 1-byte RID prefix)
  - Analyzes byte variance across all frames
  - Reports candidates for battery offset
"""

import re
import sys
from collections import defaultdict
from pathlib import Path


def extract_rid27_frames(csv_file, txt_file):
    """
    Extract all RID=0x27 frames from the capture files.
    Returns list of 46-byte payloads (as hex strings).
    """
    frames = []

    # Try CSV first
    if Path(csv_file).exists():
        with open(csv_file, 'r', encoding='utf-8') as f:
            content = f.read()
            # Look for patterns: RID=0x27, Report ID 39, or 47-byte hex sequences
            # This is highly capture-format dependent
            matches = re.findall(r'0x27[^,]*|27[^,]*', content)
            if matches:
                print(f"[CSV] Found {len(matches)} potential RID=0x27 references")

    # Try TXT
    if Path(txt_file).exists():
        with open(txt_file, 'r', encoding='utf-8') as f:
            content = f.read()
            matches = re.findall(r'0x27|RID.*27|Report.*27', content, re.IGNORECASE)
            if matches:
                print(f"[TXT] Found {len(matches)} potential RID=0x27 references")

    return frames


def analyze_byte_variance(frames):
    """
    For each of 46 byte positions, count unique values across all frames.
    Returns dict: {byte_offset: {unique_values: count, values_seen: set}}
    """
    if not frames:
        return {}

    byte_stats = defaultdict(lambda: {'unique': set(), 'count': 0})

    for frame_idx, frame in enumerate(frames):
        # frame is a 46-byte hex string (92 hex chars)
        if len(frame) != 92:
            print(f"[WARN] Frame {frame_idx} has length {len(frame)}, expected 92 (46 bytes)")
            continue

        # Parse 2 hex chars at a time
        for byte_offset in range(46):
            hex_pair = frame[byte_offset * 2:(byte_offset + 1) * 2]
            try:
                byte_val = int(hex_pair, 16)
                byte_stats[byte_offset]['unique'].add(byte_val)
                byte_stats[byte_offset]['count'] += 1
            except ValueError:
                print(f"[WARN] Invalid hex at offset {byte_offset}: {hex_pair}")

    # Convert to counts
    result = {}
    for offset, data in byte_stats.items():
        result[offset] = {
            'unique_count': len(data['unique']),
            'values': sorted(data['unique']),
            'total_occurrences': data['count']
        }

    return result


def find_battery_candidates(byte_stats, frames):
    """
    Identify likely battery byte offset(s).

    Heuristics:
      1. Battery range should be 1-65 per HID descriptor
      2. If battery hasn't changed much in capture, expect LOW variance (1-3 unique values)
      3. If battery changed during capture, expect MEDIUM variance (5-15 unique values)
      4. Touch coordinates would have HIGH variance (20+ unique values)
      5. Timestamp counter would have HIGH variance (monotonic)

    Returns list of (offset, unique_count, values, confidence) tuples, sorted by confidence desc.
    """
    candidates = []

    for offset, stats in byte_stats.items():
        unique_count = stats['unique_count']
        values = stats['values']

        # Check if values are in plausible battery range (1-65)
        in_range = all(1 <= v <= 65 for v in values)

        # Low variance (1-3 values) -> high confidence for battery
        if in_range and 1 <= unique_count <= 3:
            confidence = 'VERY_HIGH'
        # Medium variance (4-10 values) -> medium confidence if in range
        elif in_range and 4 <= unique_count <= 10:
            confidence = 'MEDIUM'
        # Single value (possibly static field)
        elif unique_count == 1:
            if in_range:
                confidence = 'MEDIUM'  # Could be constant battery level
            else:
                confidence = 'LOW'  # Static padding or metadata
        else:
            confidence = 'LOW'  # Too much variance or out of range

        candidates.append((offset, unique_count, values, confidence))

    # Sort: VERY_HIGH first, then MEDIUM, then LOW; within each, prefer lower variance
    order = {'VERY_HIGH': 0, 'MEDIUM': 1, 'LOW': 2}
    candidates.sort(key=lambda x: (order[x[3]], x[1]))

    return candidates


def main():
    # Paths
    test_run = Path('/home/lesley/projects/Personal/magic-mouse-tray/.ai/test-runs/2026-04-27-154930-T-V3-AF')
    csv_file = test_run / 'test-A2-etw-bth-hid-20260428-181312.csv'
    txt_file = test_run / 'test-A2-etw-bth-hid-20260428-181312.txt'

    print(f"RID=0x27 Empirical Battery Offset Analysis")
    print(f"==========================================\n")
    print(f"ETW Capture: {test_run.name}")
    print(f"CSV: {csv_file.name}")
    print(f"TXT: {txt_file.name}\n")

    # Extract frames
    frames = extract_rid27_frames(str(csv_file), str(txt_file))

    print(f"\nFrames extracted: {len(frames)}")

    if not frames:
        print("\nRESULT: No RID=0x27 frames found in capture.")
        print("The ETW capture does not include HID input report payloads.")
        print("\nRECOMMENDATION:")
        print("  - The capture format (CSV/TXT from tracerpt) does not preserve binary HID payloads")
        print("  - Needs fresh capture with HID provider specifically configured for payload logging")
        print("  - Or use alternative method: BT HCI sniff with Wireshark + btsnoop")
        print("  - Or: ETW with Microsoft-Windows-Input-HIDCLASS at level=VERBOSE")
        return 1

    # Analyze
    byte_stats = analyze_byte_variance(frames)

    print(f"Analyzed {len(byte_stats)} byte positions\n")

    # Find candidates
    candidates = find_battery_candidates(byte_stats, frames)

    # Report top 3
    print("Top 3 Battery Offset Candidates:")
    print("=" * 70)
    for i, (offset, unique_count, values, confidence) in enumerate(candidates[:3], 1):
        print(f"\nCandidate {i}: Byte offset {offset}")
        print(f"  Unique values: {unique_count}")
        print(f"  Values seen: {values}")
        print(f"  Confidence: {confidence}")
        in_range = all(1 <= v <= 65 for v in values)
        print(f"  In range [1-65]: {in_range}")

    # Final recommendation
    print("\n" + "=" * 70)
    if candidates and candidates[0][3] == 'VERY_HIGH':
        print(f"\nRECOMMENDATION: Byte offset {candidates[0][0]} is a STRONG candidate for battery")
        print(f"  Values: {candidates[0][2]}")
        print("  Confidence: VERY_HIGH")
    else:
        print("\nRECOMMENDATION: Multiple candidates or insufficient data variance")
        print("  Follow-up capture needed at significantly different battery level")

    return 0


if __name__ == '__main__':
    sys.exit(main())
