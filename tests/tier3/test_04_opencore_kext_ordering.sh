#!/bin/bash
# ==============================================================================
# Tier 3 - Combinatorial Invariant 4: OpenCore Kext Load Ordering
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 3: Invariant 4 - OpenCore Kext Load Ordering"

# Verify active config.plist kext ordering
if [ -f "$CONFIG_PLIST" ]; then
    order_result=$(python3 -c "
import plistlib, sys
try:
    with open('$CONFIG_PLIST', 'rb') as f:
        pl = plistlib.load(f)
    kexts = [k.get('BundlePath', '') for k in pl.get('Kernel', {}).get('Add', [])]

    lilu_idx = next((i for i, k in enumerate(kexts) if 'Lilu.kext' in k), -1)
    alc_idx = next((i for i, k in enumerate(kexts) if 'AppleALC.kext' in k), -1)
    shda_idx = next((i for i, k in enumerate(kexts) if 'SimpleHDA.kext' in k), -1)
    rpldmic_idx = next((i for i, k in enumerate(kexts) if 'RPLDmic.kext' in k), -1)

    if rpldmic_idx == -1:
        print('NOT_YET_INJECTED: RPLDmic.kext not found in Kernel -> Add (worker_m4 pending)')
        sys.exit(2)

    if lilu_idx == -1:
        print('FAIL: Lilu.kext missing')
        sys.exit(1)

    if rpldmic_idx < lilu_idx:
        print(f'FAIL: RPLDmic.kext index {rpldmic_idx} precedes Lilu index {lilu_idx}')
        sys.exit(1)

    audio_dep = max(alc_idx, shda_idx)
    if audio_dep != -1 and rpldmic_idx < audio_dep:
        print(f'FAIL: RPLDmic.kext index {rpldmic_idx} precedes audio dependency index {audio_dep}')
        sys.exit(1)

    print(f'MATCH: RPLDmic [{rpldmic_idx}] loads after Lilu [{lilu_idx}] and Audio [{audio_dep}]')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1 || true)

    if echo "$order_result" | grep -q "MATCH:"; then
        record_pass "T3.4" "RPLDmic.kext is ordered strictly after Lilu and AppleALC/SimpleHDA" "$order_result"
    elif echo "$order_result" | grep -q "NOT_YET_INJECTED"; then
        record_fail "T3.4" "OpenCore kext ordering cannot be verified yet" "$order_result"
    else
        record_fail "T3.4" "OpenCore kext ordering violation" "$order_result"
    fi
else
    record_fail "T3.4" "config.plist missing" "cannot inspect kext ordering"
fi

print_summary "Tier 3 Invariant 4 (OpenCore Kext Ordering)"
exit $?
