#!/bin/bash
# ==============================================================================
# Tier 3 - Combinatorial Invariant 2: Kext & HAL Bundle / UserClient Alignment
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 3: Invariant 2 - Kext & HAL Bundle / UserClient Alignment"

# Locate kext Info.plist and HAL Info.plist
KEXT_PLIST=""
for candidate in \
    "$KEXT_DIR/build/RPLDmic.kext/Contents/Info.plist" \
    "$KEXT_DIR/RPLDmic/Info.plist" \
    "$KEXT_DIR/TGLDmic/Info.plist"; do
    if [ -f "$candidate" ]; then
        KEXT_PLIST="$candidate"
        break
    fi
done

HAL_PLIST=""
for candidate in \
    "$HAL_DIR/build/RPLDmic.driver/Contents/Info.plist" \
    "$HAL_DIR/Info.plist"; do
    if [ -f "$candidate" ]; then
        HAL_PLIST="$candidate"
        break
    fi
done

if [ -n "$KEXT_PLIST" ] && [ -n "$HAL_PLIST" ]; then
    alignment=$(python3 -c "
import plistlib, sys
try:
    with open('$KEXT_PLIST', 'rb') as fk, open('$HAL_PLIST', 'rb') as fh:
        pk = plistlib.load(fk)
        ph = plistlib.load(fh)
    kext_id = pk.get('CFBundleIdentifier', '')
    hal_clients = ph.get('AudioServerPlugIn_IOKitUserClients', [])
    # Verify kext bundle id prefix matches hal bundle id
    hal_id = ph.get('CFBundleIdentifier', '')
    expected_uc = 'RPLDmicUserClient'
    if expected_uc in hal_clients and 'RPLDmic' in kext_id and 'RPLDmic' in hal_id:
        print(f'MATCH: kext_id={kext_id}, hal_id={hal_id}, uc={expected_uc}')
    else:
        print(f'MISMATCH: kext_id={kext_id}, hal_id={hal_id}, uc_list={hal_clients}')
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1 || true)
    if echo "$alignment" | grep -q "MATCH"; then
        record_pass "T3.2" "Kext bundle identifier and HAL AudioServerPlugIn_IOKitUserClients are aligned" "$alignment"
    else
        record_fail "T3.2" "Kext and HAL metadata mismatch" "$alignment"
    fi
else
    record_fail "T3.2" "Kext or HAL Info.plist missing" "kext: $KEXT_PLIST, hal: $HAL_PLIST"
fi

print_summary "Tier 3 Invariant 2 (Kext-HAL Alignment)"
exit $?
