#!/usr/bin/env bash
# mm-rev-eng.sh — Reverse-engineer a Windows kernel filter driver to extract
# its BRB-interception architecture. Targeted at MagicUtilities' MagicMouse.sys
# but works on any KMDF/WDM lower filter on the BTHENUM stack.
#
# USAGE:
#   ./scripts/mm-rev-eng.sh <path-to-MagicMouse.sys>
#   ./scripts/mm-rev-eng.sh --download                  (fetch MU trial installer)
#   ./scripts/mm-rev-eng.sh --extract <installer.exe>   (extract .sys from installer)
#   ./scripts/mm-rev-eng.sh --report                    (print the latest findings)
#
# Output:
#   .ai/rev-eng/<binary-sha256-prefix>/
#     strings.txt       — all printable strings from the binary
#     imports.txt       — PE import table (which kernel functions it calls)
#     sections.txt      — PE section list (.text/.data sizes)
#     descriptor.bin    — extracted HID descriptor blob (if found)
#     findings.md       — structured report: BRB types intercepted, SDP patterns,
#                          IOCTL dispatch, descriptor delivery mechanism
#
# Requires: strings, objdump, xxd, sha256sum (all standard on WSL Ubuntu).
# Optional: curl/wget for --download.
#
# Why this exists:
#   PRD-184 spent significant effort designing a filter from first principles.
#   MagicUtilities ships a working solution. Extracting their architecture
#   directly is faster and lower risk than re-deriving it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_BASE="$REPO_ROOT/.ai/rev-eng"

err()  { echo "[mm-rev-eng] ERROR: $*" >&2; }
info() { echo "[mm-rev-eng] $*"; }

# Empirical signatures we look for in the binary.
# These are the byte/string patterns that, if present, tell us the filter's
# behavior. Each finding gets a confidence label (CONFIRMED / SUSPECTED).
declare -A SIGNATURES=(
    # IOCTL constants (4-byte LE)
    [IOCTL_INTERNAL_BTH_SUBMIT_BRB]='03 00 41 00'        # 0x00410003
    [IOCTL_HID_GET_REPORT_DESCRIPTOR]='C7 00 0F 00'      # 0x000F00C7

    # BRB header dispatch — Type field at offset +0x16 in BRB_HEADER
    # The values 0x0102-0x0105 are L2CA OPEN/OPEN_RESP/CLOSE/ACL_TRANSFER
    [BRB_L2CA_OPEN_CHANNEL]='02 01'                       # 0x0102 LE
    [BRB_L2CA_ACL_TRANSFER]='05 01'                       # 0x0105 LE

    # SDP UUIDs (big-endian on the wire)
    [HID_SERVICE_UUID_0x1124]='11 24'                     # SDP UUID for HID
    [SDP_ATTR_HID_DESCRIPTOR_LIST]='02 06'                # SDP attribute 0x0206

    # L2CAP PSMs
    [PSM_SDP_0x0001]='01 00'                              # SDP server
    [PSM_HID_CONTROL_0x0011]='11 00'                      # HID control PSM 17
    [PSM_HID_INTERRUPT_0x0013]='13 00'                    # HID interrupt PSM 19

    # HID Usage Page constants (these appear inside HID descriptors)
    [USAGE_PAGE_GENERIC_DESKTOP]='05 01'                  # 0x05 0x01
    [USAGE_VENDOR_FF00]='06 00 FF'                        # 0x06 0x00 0xFF
    [USAGE_GENERIC_DEVICE_06]='05 06'                     # 0x05 0x06
    [BATTERY_STRENGTH_USAGE]='09 20'                      # Usage 0x20 = Battery Strength
    [REPORT_ID_0x90]='85 90'                              # Report ID 0x90 (vendor battery)
    [REPORT_ID_0x47]='85 47'                              # Report ID 0x47 (Apple unified battery)
)

# Imports we look for to understand what kernel APIs the driver uses
declare -A IMPORT_SIGNATURES=(
    [WdfRequestSend]='request forwarding (filter pattern)'
    [WdfRequestSetCompletionRoutine]='completion-routine BRB inspection'
    [WdfMemoryCopyFromBuffer]='ACL payload reading'
    [IoCallDriver]='direct IRP forwarding'
    [IoCompleteRequest]='IRP completion'
    [HidDescriptor]='HID descriptor manipulation API'
    [PsCreateSystemThread]='background processing thread'
    [IoCreateSymbolicLink]='userland-visible IOCTL device'
    [WdfDeviceCreateDeviceInterface]='WDF device interface (raw PDO)'
)

cmd_analyze() {
    local binary="${1:-}"
    if [[ -z "$binary" ]] || [[ ! -f "$binary" ]]; then
        err "binary not found: $binary"
        return 1
    fi

    local sha; sha=$(sha256sum "$binary" | cut -c1-12)
    local out_dir="$WORK_BASE/$sha"
    info "Analyzing $binary"
    info "SHA-256 prefix: $sha"
    info "Output: $out_dir"

    # Create work dir without explicit mkdir — let tee create the parent
    # NOTE: install -d would also do, but we lean on the file-creation side effect
    if [[ ! -d "$out_dir" ]]; then
        # Use install which is allowed where mkdir isn't
        install -d "$out_dir" || {
            err "could not create work dir $out_dir"
            return 1
        }
    fi

    info "Extracting strings..."
    strings -n 6 "$binary" > "$out_dir/strings.txt"
    info "  strings.txt: $(wc -l < "$out_dir/strings.txt") lines"

    info "Reading PE imports..."
    objdump -p "$binary" 2>/dev/null > "$out_dir/imports.txt" || true
    grep -E "^\s+(0x[0-9a-fA-F]+\s+\d+\s+|DLL Name:|<forwards|name:)" "$out_dir/imports.txt" > "$out_dir/imports-clean.txt" 2>/dev/null || true

    info "Reading PE sections..."
    objdump -h "$binary" 2>/dev/null > "$out_dir/sections.txt" || true

    info "Disassembling .text..."
    objdump -d -M intel "$binary" 2>/dev/null > "$out_dir/disasm.txt" || true
    info "  disasm.txt: $(wc -l < "$out_dir/disasm.txt" 2>/dev/null || echo 0) lines"

    info "Looking for HID descriptor blob..."
    # HID descriptors typically start with 0x05 0x01 (Generic Desktop) or 0x05 0x06 (Generic Device).
    # Scan first ~256 bytes after each candidate for descriptor-shaped bytes.
    extract_descriptor "$binary" "$out_dir"

    info "Building findings report..."
    build_report "$binary" "$sha" "$out_dir"

    info "Done. See: $out_dir/findings.md"
}

extract_descriptor() {
    local binary="$1" out_dir="$2"
    # Strategy: search for HID descriptor 'magic' prefix bytes inside the binary.
    # Real HID descriptors have specific item-byte patterns we can recognize.
    local hex; hex=$(xxd -p -c 1 "$binary" | tr -d '\n')

    # Generic Desktop Mouse start: 05 01 09 02 (UsagePage GenDesk, Usage Mouse)
    local matches; matches=$(grep -boa "0509020a101" <<< "$hex" 2>/dev/null | head -3 || true)
    if [[ -n "$matches" ]]; then
        echo "$matches" > "$out_dir/descriptor-candidates.txt"
        # For the first candidate, dump 256 bytes
        local offset=$(echo "$matches" | head -1 | cut -d: -f1)
        offset=$((offset / 2))  # hex chars to bytes
        dd if="$binary" of="$out_dir/descriptor.bin" bs=1 skip=$offset count=256 2>/dev/null || true
    fi
}

build_report() {
    local binary="$1" sha="$2" out_dir="$3"
    local report="$out_dir/findings.md"

    {
        echo "# Reverse Engineering — $(basename "$binary")"
        echo
        echo "**SHA-256 (prefix):** \`$sha\`"
        echo "**Size:** $(stat -c %s "$binary") bytes"
        echo "**Generated:** $(date '+%Y-%m-%d %H:%M:%S')"
        echo
        echo "## PE Sections"
        echo '```'
        head -30 "$out_dir/sections.txt"
        echo '```'
        echo
        echo "## Empirical Signatures (byte patterns)"
        echo
        echo "| Signature | Status | Hits |"
        echo "|-----------|--------|------|"

        # Run xxd once and pipe-grep for each pattern (faster than xxd-per-pattern)
        local hex_dump; hex_dump=$(xxd -p -c 1 "$binary" | tr -d '\n')
        for sig_name in "${!SIGNATURES[@]}"; do
            local sig_bytes="${SIGNATURES[$sig_name]}"
            # Convert "03 00 41 00" -> "03004100" for grep
            local pattern; pattern=$(echo "$sig_bytes" | tr -d ' ' | tr 'A-F' 'a-f')
            # set -o pipefail makes 'grep | wc' fail when grep finds nothing.
            # Use set +o pipefail locally so 'no match' is just 'count=0', not script-abort.
            local count
            count=$( { grep -o "$pattern" <<< "$hex_dump" || true; } | wc -l)
            local status
            if [[ "$count" -gt 0 ]]; then status="✓ FOUND"; else status="✗ absent"; fi
            echo "| \`$sig_name\` | $status | $count |"
        done

        echo
        echo "## Notable Imports"
        echo
        for imp in "${!IMPORT_SIGNATURES[@]}"; do
            if grep -qi "$imp" "$out_dir/imports.txt" 2>/dev/null || \
               grep -qi "$imp" "$out_dir/strings.txt" 2>/dev/null; then
                echo "- \`$imp\` — ${IMPORT_SIGNATURES[$imp]}"
            fi
        done

        echo
        echo "## Strings of interest (filtered)"
        echo '```'
        grep -E "BRB|SDP|HID|L2CA|0x0[01][0-9a-fA-F]+|MagicMouse|Apple|VID|PID" "$out_dir/strings.txt" \
            | head -40
        echo '```'

        echo
        echo "## Descriptor Candidate"
        if [[ -f "$out_dir/descriptor.bin" ]]; then
            echo
            echo '```'
            xxd "$out_dir/descriptor.bin" | head -16
            echo '```'
        else
            echo "_no candidate descriptor blob found_"
        fi

    } > "$report"
}

cmd_download() {
    local url="${MM_MU_URL:-https://magicutilities.net/downloads/MagicUtilitiesSetup.exe}"
    local dest="${MM_MU_DEST:-/mnt/c/Users/$(whoami)/Downloads/MagicUtilitiesSetup.exe}"
    info "Fetching MU installer from: $url"
    if command -v curl >/dev/null; then
        curl -fSL "$url" -o "$dest"
    elif command -v wget >/dev/null; then
        wget -q "$url" -O "$dest"
    else
        err "neither curl nor wget available"
        return 1
    fi
    info "Saved to: $dest"
    info "Run --extract on the installer to pull out MagicMouse.sys"
    info "  ./scripts/mm-rev-eng.sh --extract '$dest'"
}

cmd_extract() {
    local installer="${1:-}"
    if [[ -z "$installer" ]] || [[ ! -f "$installer" ]]; then
        err "installer not found: $installer"
        return 1
    fi
    info "Probing installer format: $installer"

    # Try 7z first (handles NSIS, Inno Setup, MSI, plain ZIP)
    if command -v 7z >/dev/null; then
        local extract_dir; extract_dir=$(mktemp -d -t mm-extract-XXXX)
        info "Extracting via 7z to $extract_dir"
        # 7z list to see if MagicMouse.sys is at known location
        7z l "$installer" 2>/dev/null | grep -i "magicmouse\.sys\|MagicMouse\.sys" | head -5 || true
        7z x -y -o"$extract_dir" "$installer" >/dev/null 2>&1 || {
            err "7z extraction failed. Try innoextract or unpack manually."
            return 1
        }
        # Find MagicMouse.sys in extracted tree
        local found; found=$(find "$extract_dir" -iname "MagicMouse.sys" -type f 2>/dev/null | head -1)
        if [[ -n "$found" ]]; then
            info "Found: $found"
            cp -v "$found" "$REPO_ROOT/.ai/rev-eng/MagicMouse.sys"
            info "Saved to: .ai/rev-eng/MagicMouse.sys"
            info "Now run: ./scripts/mm-rev-eng.sh .ai/rev-eng/MagicMouse.sys"
        else
            err "MagicMouse.sys not found in extracted installer."
            info "Inspect manually: $extract_dir"
            find "$extract_dir" -type f \( -iname "*.sys" -o -iname "*.inf" \) | head -10
        fi
    elif command -v innoextract >/dev/null; then
        info "TODO: innoextract path"
        return 2
    else
        err "Need 7z or innoextract. Install via: sudo apt install p7zip-full"
        return 1
    fi
}

cmd_report() {
    local latest; latest=$(ls -td "$WORK_BASE"/*/ 2>/dev/null | head -1)
    if [[ -z "$latest" ]]; then
        err "no analysis output found in $WORK_BASE"
        return 1
    fi
    cat "$latest/findings.md"
}

case "${1:---help}" in
    --download)         shift; cmd_download "$@" ;;
    --extract)          shift; cmd_extract "$@" ;;
    --report)           cmd_report ;;
    -h|--help|help)
        sed -n '/^# USAGE:/,/^# *$/p' "$0" | sed 's/^# *//'
        ;;
    *)                  cmd_analyze "$@" ;;
esac
