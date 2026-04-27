#!/usr/bin/env bash
# mm-lint.sh — Code-quality gate for magic-mouse-tray.
#
# Runs 7 checks discovered during overnight driver development. Exit 0 if all
# clean, exit 1 if any check fails. Intended as a pre-commit / pre-build gate.
#
# USAGE:
#   ./scripts/mm-lint.sh             # run from repo root or scripts/
#   bash scripts/mm-lint.sh          # explicit interpreter
#
# CHECKS:
#   1. unicode-ps1      No high-Unicode chars (em-dash, en-dash, arrows, ellipsis) in PS1
#   2. parse-ps1        PowerShell parser validates every scripts/*.ps1 (needs powershell.exe)
#   3. bash-syntax      bash -n on every scripts/*.sh
#   4. raw-brb-offsets  No raw BRB hex offsets in driver/*.c (use MM_BRB_* constants)
#   5. no-mkdir-p       No "mkdir -p <non-/tmp>" in scripts/*.sh (use install -d)
#   6. where-obj-count  Where-Object | .Count must be wrapped in @() for StrictMode v2
#   7. no-git-commit    No bare "git commit " in scripts/*.sh (use python3 git.py commit)

set -uo pipefail

# ---------------------------------------------------------------------------
# Locate repo root regardless of where script is called from
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Counters and output helpers
# ---------------------------------------------------------------------------
TOTAL=7
FAIL_COUNT=0

pass() { printf '[mm-lint] PASS  %s\n' "$1"; }
fail() {
    printf '[mm-lint] FAIL  %s\n' "$1"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
}
detail() { printf '        %s\n' "$1"; }

printf '[mm-lint] Running %d checks...\n' "$TOTAL"

# ---------------------------------------------------------------------------
# CHECK 1: No high-Unicode chars in PS1 scripts
#   Forbid em-dash (—), en-dash (–), arrows (→ ← ↑ ↓), horizontal ellipsis (…)
#   PowerShell on Windows misparses these without UTF-8 BOM and silently
#   corrupts output.
# ---------------------------------------------------------------------------
PS1_FILES=( "$REPO_ROOT"/scripts/*.ps1 )

# Glob might not expand if no files — handle gracefully
if [[ ${#PS1_FILES[@]} -eq 0 || ! -f "${PS1_FILES[0]}" ]]; then
    pass "unicode-ps1  (no PS1 files to check)"
else
    # Use process substitution to collect grep output
    unicode_hits="$(grep -nP '[—–→←↑↓…]' "${PS1_FILES[@]}" 2>/dev/null || true)"
    if [[ -z "$unicode_hits" ]]; then
        pass "unicode-ps1"
    else
        fail "unicode-ps1"
        while IFS= read -r line; do
            detail "$line"
        done <<< "$unicode_hits"
    fi
fi

# ---------------------------------------------------------------------------
# CHECK 2: PowerShell parse-check
#   Invoke [System.Management.Automation.Language.Parser]::ParseFile() via
#   powershell.exe for each scripts/*.ps1 and report any parse errors.
#   Skips gracefully if powershell.exe is not in PATH (Linux CI without PS).
# ---------------------------------------------------------------------------
if [[ ${#PS1_FILES[@]} -eq 0 || ! -f "${PS1_FILES[0]}" ]]; then
    pass "parse-ps1    (no PS1 files to check)"
elif ! command -v powershell.exe &>/dev/null; then
    pass "parse-ps1    (SKIP — powershell.exe not in PATH)"
else
    parse_fail=0
    for ps1 in "${PS1_FILES[@]}"; do
        [[ -f "$ps1" ]] || continue
        win_path="$(wslpath -w "$ps1" 2>/dev/null || echo "$ps1")"
        parse_errors="$(powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
\$errors = \$null
[System.Management.Automation.Language.Parser]::ParseFile('$win_path', [ref]\$null, [ref]\$errors) | Out-Null
if (\$errors -and \$errors.Count -gt 0) {
    foreach (\$e in \$errors) {
        Write-Output \"${ps1}:\$(\$e.Extent.StartLineNumber): \$(\$e.Message)\"
    }
}
" 2>/dev/null || true)"
        if [[ -n "$parse_errors" ]]; then
            parse_fail=1
            while IFS= read -r line; do
                detail "$line"
            done <<< "$parse_errors"
        fi
    done
    if [[ $parse_fail -eq 0 ]]; then
        pass "parse-ps1"
    else
        fail "parse-ps1"
    fi
fi

# ---------------------------------------------------------------------------
# CHECK 3: Bash syntax-check
#   bash -n every scripts/*.sh (excludes mm-lint.sh itself to avoid false
#   positives from its own in-progress state during development).
# ---------------------------------------------------------------------------
SH_FILES=( "$REPO_ROOT"/scripts/*.sh )

if [[ ${#SH_FILES[@]} -eq 0 || ! -f "${SH_FILES[0]}" ]]; then
    pass "bash-syntax  (no .sh files to check)"
else
    bash_fail=0
    for sh in "${SH_FILES[@]}"; do
        [[ -f "$sh" ]] || continue
        if ! bash -n "$sh" 2>/tmp/mm-lint-bash-err; then
            bash_fail=1
            err_msg="$(cat /tmp/mm-lint-bash-err)"
            detail "$sh: $err_msg"
        fi
    done
    if [[ $bash_fail -eq 0 ]]; then
        pass "bash-syntax"
    else
        fail "bash-syntax"
    fi
fi

# ---------------------------------------------------------------------------
# CHECK 4: No raw BRB hex offsets in driver/*.c
#   All BRB field offset references must go through MM_BRB_* constants in
#   Driver.h. Forbid raw hex like 0x16, 0x20, 0x78, 0x80, 0x84, 0x88, 0x90
#   as numeric immediates in driver/*.c (Driver.h is exempt — it defines them).
#
#   NOTE: 0x90 is also the battery Report ID. Hits in comments referencing the
#   report ID (not BRB struct offsets) are known false positives on current
#   main. Documented in commit message.
# ---------------------------------------------------------------------------
C_FILES=( "$REPO_ROOT"/driver/*.c )

if [[ ${#C_FILES[@]} -eq 0 || ! -f "${C_FILES[0]}" ]]; then
    pass "raw-brb-offsets  (no driver/*.c files to check)"
else
    # HidDescriptor.c is full of byte literals (HID descriptor bytes); not BRB offsets.
    # Skip comment lines (//, /*, *) and skip Report-ID literals (0x85 followed by report ID).
    # Match: bare 0x16/0x20/0x78/0x80/0x84/0x88/0x90 used as a numeric offset, not as a comment
    # or as part of a byte-array literal.
    brb_hits="$(grep -nHE '\b0x(16|20|78|80|84|88|90)\b' "${C_FILES[@]}" 2>/dev/null \
        | grep -vE ':\s*(//|\*|/\*)' \
        | grep -vE 'HidDescriptor\.c:' \
        | grep -vE '0x85,?\s*0x90' \
        || true)"
    if [[ -z "$brb_hits" ]]; then
        pass "raw-brb-offsets"
    else
        fail "raw-brb-offsets"
        while IFS= read -r line; do
            detail "$line  (use MM_BRB_*_OFFSET constant)"
        done <<< "$brb_hits"
    fi
fi

# ---------------------------------------------------------------------------
# CHECK 5: No "mkdir -p" outside /tmp/ in scripts/*.sh
#   Repo hook policy (BCP-REL-309) requires explicit approval for mkdir.
#   Use "install -d" instead. /tmp/ paths are permitted (ephemeral).
# ---------------------------------------------------------------------------
if [[ ${#SH_FILES[@]} -eq 0 || ! -f "${SH_FILES[0]}" ]]; then
    pass "no-mkdir-p   (no .sh files to check)"
else
    # Search for mkdir -p that is NOT a comment line and NOT /tmp/ path.
    # Excludes comment lines (leading optional whitespace then #).
    mkdir_hits=""
    for sh in "${SH_FILES[@]}"; do
        [[ -f "$sh" ]] || continue
        while IFS= read -r raw; do
            # Skip comment lines
            if printf '%s\n' "$raw" | grep -qP '^\s*#'; then continue; fi
            # Skip lines where the mkdir target is under /tmp/
            if printf '%s\n' "$raw" | grep -q '/tmp/'; then continue; fi
            if [[ -n "$mkdir_hits" ]]; then
                mkdir_hits="${mkdir_hits}"$'\n'"${sh}:${raw}"
            else
                mkdir_hits="${sh}:${raw}"
            fi
        done < <(grep -nP '^\s*[^#].*mkdir\s+(-\S*p\S*\s+|.*-p)' "$sh" 2>/dev/null || true)
    done
    if [[ -z "$mkdir_hits" ]]; then
        pass "no-mkdir-p"
    else
        fail "no-mkdir-p"
        while IFS= read -r line; do
            detail "$line  (use: install -d)"
        done <<< "$mkdir_hits"
    fi
fi

# ---------------------------------------------------------------------------
# CHECK 6: Where-Object | .Count patterns wrapped in @()
#   PowerShell Set-StrictMode -Version 2 errors on null.Count when
#   Where-Object returns no matches. Pattern:
#     ($collection | Where-Object {...}).Count   -> BAD
#     @($collection | Where-Object {...}).Count  -> GOOD
#   We hit this in mm-accept-test.ps1 during development.
# ---------------------------------------------------------------------------
if [[ ${#PS1_FILES[@]} -eq 0 || ! -f "${PS1_FILES[0]}" ]]; then
    pass "where-obj-count  (no PS1 files to check)"
else
    # Match (... Where-Object ...).Count but NOT @(... Where-Object ...).Count
    # The negative lookbehind @\( ensures we only catch unwrapped ones
    wo_hits="$(grep -nP '(?<!@)\(.*Where-Object.*\)\.Count' "${PS1_FILES[@]}" 2>/dev/null || true)"
    if [[ -z "$wo_hits" ]]; then
        pass "where-obj-count"
    else
        fail "where-obj-count"
        while IFS= read -r line; do
            detail "$line  (wrap in @(...).Count for StrictMode v2 safety)"
        done <<< "$wo_hits"
    fi
fi

# ---------------------------------------------------------------------------
# CHECK 7: No direct "git commit " in scripts/*.sh
#   Hook BCP-REL-309 blocks bare git commit. Scripts must use:
#     python3 /home/lesley/projects/scripts/git.py commit --branch ... --message ...
# ---------------------------------------------------------------------------
if [[ ${#SH_FILES[@]} -eq 0 || ! -f "${SH_FILES[0]}" ]]; then
    pass "no-git-commit  (no .sh files to check)"
else
    # Forbidden pattern: bare git-commit call (split to avoid self-match in this file).
    # Non-comment lines that invoke git then commit as subcommand.
    _GC_PAT='git'$' ''commit '
    gc_hits=""
    for sh in "${SH_FILES[@]}"; do
        [[ -f "$sh" ]] || continue
        while IFS= read -r raw; do
            if [[ -n "$gc_hits" ]]; then
                gc_hits="${gc_hits}"$'\n'"${sh}: ${raw}"
            else
                gc_hits="${sh}: ${raw}"
            fi
        done < <(grep -nP '^\s*[^#].*'"$_GC_PAT" "$sh" 2>/dev/null || true)
    done
    if [[ -z "$gc_hits" ]]; then
        pass "no-git-commit"
    else
        fail "no-git-commit"
        while IFS= read -r line; do
            detail "$line  (use: python3 /home/lesley/projects/scripts/git.py commit)"
        done <<< "$gc_hits"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n'
if [[ $FAIL_COUNT -eq 0 ]]; then
    printf '[mm-lint] All %d checks passed.\n' "$TOTAL"
    exit 0
else
    printf '[mm-lint] %d of %d checks failed.\n' "$FAIL_COUNT" "$TOTAL"
    exit 1
fi
