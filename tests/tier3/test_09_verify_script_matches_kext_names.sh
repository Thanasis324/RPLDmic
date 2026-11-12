#!/bin/bash
# ==============================================================================
# Tier 3 - Combinatorial Invariant 9: Diagnostic Tool & IOService Name Alignment
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 3: Invariant 9 - Diagnostic Tool & IOService Name Alignment"

VERIFY_SCRIPT=""
for candidate in \
    "$TOOLS_DIR/verify-rpldmic.sh" \
    "$PROJECT_ROOT/verify-rpldmic.sh"; do
    if [ -f "$candidate" ]; then
        VERIFY_SCRIPT="$candidate"
        break
    fi
done

KEXT_PLIST=""
for candidate in \
    "$KEXT_DIR/build/RPLDmic.kext/Contents/Info.plist" \
    "$KEXT_DIR/RPLDmic/Info.plist"; do
    if [ -f "$candidate" ]; then
        KEXT_PLIST="$candidate"
        break
    fi
done

if [ -n "$VERIFY_SCRIPT" ] && [ -n "$KEXT_PLIST" ]; then
    kext_service=$(python3 -c "
import plistlib
with open('$KEXT_PLIST', 'rb') as f:
    pl = plistlib.load(f)
personalities = pl.get('IOKitPersonalities', {})
pers = list(personalities.values())[0] if personalities else {}
print(pers.get('IOClass', ''))
")

    if [ -n "$kext_service" ] && grep -q "$kext_service" "$VERIFY_SCRIPT"; then
        record_pass "T3.9" "verify-rpldmic.sh inspects the exact IOClass ($kext_service) registered by the driver" "service name aligned"
    else
        record_fail "T3.9" "verify-rpldmic.sh does not query kext IOClass $kext_service" "name mismatch"
    fi
else
    record_fail "T3.9" "verify-rpldmic.sh or kext Info.plist missing" "tool: $([ -n "$VERIFY_SCRIPT" ] && echo YES || echo NO), kext: $([ -n "$KEXT_PLIST" ] && echo YES || echo NO) (worker_m5 pending)"
fi

print_summary "Tier 3 Invariant 9 (Tool-Service Alignment)"
exit $?
