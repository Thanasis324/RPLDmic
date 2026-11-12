#!/bin/bash
# ==============================================================================
# Tier 3 - Combinatorial Invariant 7: Driver Binary Integrity & Symbol Exports
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 3: Invariant 7 - Driver Binary Integrity & Symbol Exports"

BUILT_MACHO=""
for candidate in \
    "$KEXT_DIR/build/RPLDmic.kext/Contents/MacOS/RPLDmic" \
    "$KEXT_DIR/RPLDmic.kext/Contents/MacOS/RPLDmic"; do
    if [ -f "$candidate" ]; then
        BUILT_MACHO="$candidate"
        break
    fi
done

if [ -n "$BUILT_MACHO" ] && [ -f "$BUILT_MACHO" ]; then
    # Inspect symbol exports via nm
    has_kmod=false
    has_start=false
    symbols=$(nm -gU "$BUILT_MACHO" 2>/dev/null || true)
    if echo "$symbols" | grep -q "kmod_info"; then
        has_kmod=true
    fi
    if echo "$symbols" | grep -Eq "(_start|__start)"; then
        has_start=true
    fi

    if [ "$has_kmod" = true ]; then
        record_pass "T3.7" "RPLDmic Mach-O binary exports required kmod_info kernel symbols" "kmod_info verified"
    else
        record_fail "T3.7" "RPLDmic Mach-O missing required kmod_info export" "has_kmod=$has_kmod"
    fi
else
    record_fail "T3.7" "Built RPLDmic Mach-O binary missing" "cannot inspect symbols"
fi

print_summary "Tier 3 Invariant 7 (Symbol Exports)"
exit $?
