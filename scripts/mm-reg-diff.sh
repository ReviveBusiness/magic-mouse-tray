#!/usr/bin/env bash
# mm-reg-diff.sh - diff two HKLM\SYSTEM .reg exports and verify expected mutations.
#
# Used as the post-cleanup audit gate at every M13 phase boundary that includes
# registry mutations (Phase 1 cleanup, Phase 4 cache patch, etc.). Confirms that
# what was supposed to change actually changed AND nothing unexpected drifted.
#
# Usage:
#   ./scripts/mm-reg-diff.sh <pre.reg> <post.reg> [out.md]
#   ./scripts/mm-reg-diff.sh --auto [tag-prefix-pre] [tag-prefix-post] [out.md]
#
#   --auto         pick the latest matching .reg from $MM_BACKUP_DIR.
#                  defaults: pre = "pre-cleanup", post = "post-cleanup".
#
# Env:
#   MM_BACKUP_DIR        default /mnt/d/Users/Lesley/Documents/Backups
#   MM_REG_DIFF_FILTER   ERE filter (default 'MagicMouse|RAWPDO|0323|applewirelessmouse')
#
# Output: markdown summary of (a) added/removed registry sections matching the
# filter, (b) value-level changes matching the filter, (c) decoded UTF-16 LE
# REG_MULTI_SZ values inline so the diff is human-readable. To stdout if no
# out.md, otherwise written to the file.
#
# Exit 0: diff produced. Exit 1: file missing or iconv fail. Exit 2: usage.

set -euo pipefail

BACKUP_BASE="${MM_BACKUP_DIR:-/mnt/d/Users/Lesley/Documents/Backups}"
FILTER_PATTERN="${MM_REG_DIFF_FILTER:-MagicMouse|RAWPDO|0323|applewirelessmouse|LowerFilters|UpperFilters|BTHPORT|HidBth}"

usage() {
    sed -n '4,20p' "$0" >&2
    exit 2
}

pre=""
post=""
out_file=""

if [[ "${1:-}" == "--auto" ]]; then
    pre_tag="${2:-pre-cleanup}"
    post_tag="${3:-post-cleanup}"
    out_file="${4:-}"
    pre=$(ls -t "$BACKUP_BASE"/*"$pre_tag"*.reg 2>/dev/null | head -1 || true)
    post=$(ls -t "$BACKUP_BASE"/*"$post_tag"*.reg 2>/dev/null | head -1 || true)
    if [[ -z "$pre" || -z "$post" ]]; then
        echo "[mm-reg-diff] --auto could not find both pre ($pre_tag) and post ($post_tag) in $BACKUP_BASE" >&2
        exit 1
    fi
elif [[ $# -ge 2 ]]; then
    pre="$1"
    post="$2"
    out_file="${3:-}"
else
    usage
fi

[[ -f "$pre"  ]] || { echo "[mm-reg-diff] pre file not found: $pre"  >&2; exit 1; }
[[ -f "$post" ]] || { echo "[mm-reg-diff] post file not found: $post" >&2; exit 1; }

pre_u8=$(mktemp)
post_u8=$(mktemp)
decoder_py=$(mktemp --suffix=.py)
trap 'rm -f "$pre_u8" "$post_u8" "$decoder_py"' EXIT

# Emit decoder to a temp file so its stdin is the pipe (not the heredoc).
cat > "$decoder_py" <<'PY'
import sys, re
filt = sys.argv[1]
data = sys.stdin.read()
# Collapse hex line continuations within a unified diff:
#   ",\<nl>[+\- ] +<rest>"  ->  ",<rest>"
data = re.sub(r',\\\n[+\- ]\s*', ',', data)
def decode(match):
    prefix = match.group(1)
    raw = match.group(2).replace(',', '').replace(' ', '').replace('\n', '')
    try:
        b = bytes.fromhex(raw)
        text = b.decode('utf-16-le', errors='replace').rstrip('\x00').replace('\x00', ' | ')
        return f"{prefix}  # decoded utf-16-le: {text!r}"
    except Exception:
        return match.group(0)
data = re.sub(r'^([+\-] ?"[^"]+"=hex\((?:1|7)\)):([0-9a-fA-F, ]+)$', decode, data, flags=re.MULTILINE)
out = []
section = None
for line in data.splitlines():
    if line.startswith('[') and line.endswith(']'):
        section = line
        continue
    if line.startswith('@@'):
        out.append(line)
        continue
    if re.search(filt, line, re.IGNORECASE):
        if section:
            out.append(f"  in: {section}")
            section = None
        out.append(line)
print('\n'.join(out))
PY

iconv -f UTF-16LE -t UTF-8 < "$pre"  | tr -d '\r' > "$pre_u8"
iconv -f UTF-16LE -t UTF-8 < "$post" | tr -d '\r' > "$post_u8"

# --- section-level diff (lines starting with '[') ---
sec_removed=$(diff <(grep '^\[' "$pre_u8") <(grep '^\[' "$post_u8") | grep '^<' | sed 's/^< //' || true)
sec_added=$(diff   <(grep '^\[' "$pre_u8") <(grep '^\[' "$post_u8") | grep '^>' | sed 's/^> //' || true)

filtered_removed=$(printf '%s\n' "$sec_removed" | grep -iE "$FILTER_PATTERN" || true)
filtered_added=$(printf   '%s\n' "$sec_added"   | grep -iE "$FILTER_PATTERN" || true)

# --- value-level diff with hex decoded inline (calls temp-file decoder) ---
val_diff=$( { diff -U 0 "$pre_u8" "$post_u8" 2>/dev/null || true; } | python3 "$decoder_py" "$FILTER_PATTERN" || true)

# --- render markdown ---
emit() {
    local ts
    ts=$(TZ='America/Edmonton' date '+%Y-%m-%dT%H:%M:%S%z')
    echo "# Reg-export diff verification"
    echo ""
    echo "- pre:  \`$pre\`"
    echo "- post: \`$post\`"
    echo "- captured: $ts"
    echo "- filter: \`$FILTER_PATTERN\`"
    echo ""
    echo "## Sections removed (filtered)"
    echo ""
    if [[ -n "$filtered_removed" ]]; then
        printf '%s\n' "$filtered_removed" | sed 's/^/- /'
    else
        echo "_(none)_"
    fi
    echo ""
    echo "## Sections added (filtered)"
    echo ""
    if [[ -n "$filtered_added" ]]; then
        printf '%s\n' "$filtered_added" | sed 's/^/- /'
    else
        echo "_(none)_"
    fi
    echo ""
    echo "## Value-level changes (filtered, hex decoded inline)"
    echo ""
    if [[ -n "$val_diff" ]]; then
        echo '```'
        printf '%s\n' "$val_diff"
        echo '```'
    else
        echo "_(none)_"
    fi
    echo ""
    local sec_rm_total sec_ad_total val_total
    sec_rm_total=$(printf '%s\n' "$sec_removed" | grep -c '.' || true)
    sec_ad_total=$(printf '%s\n' "$sec_added"   | grep -c '.' || true)
    val_total=$( { diff "$pre_u8" "$post_u8" || true; } | wc -l | tr -d ' ')
    echo "## Diff totals (full, unfiltered — kernel/timestamp noise included)"
    echo ""
    echo "- sections removed: $sec_rm_total"
    echo "- sections added: $sec_ad_total"
    echo "- value-level diff lines: $val_total"
}

if [[ -n "$out_file" ]]; then
    emit > "$out_file"
    echo "[mm-reg-diff] OK -> $out_file"
else
    emit
fi
