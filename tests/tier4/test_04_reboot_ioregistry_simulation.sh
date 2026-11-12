#!/bin/bash
# ==============================================================================
# Tier 4 - Scenario 4: Hardware PCI Matching & IORegistry Inspection Simulation
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 4: Scenario 4 - Hardware PCI Matching & IORegistry Simulation"

# T4.4: Test PCI matching personality rules against Raptor Lake cAVS specifications
KEXT_PLIST=""
for candidate in \
    "$KEXT_DIR/build/RPLDmic.kext/Contents/Info.plist" \
    "$KEXT_DIR/RPLDmic/Info.plist"; do
    if [ -f "$candidate" ]; then
        KEXT_PLIST="$candidate"
        break
    fi
done

if [ -n "$KEXT_PLIST" ]; then
    matching_result=$(python3 -c "
import plistlib, sys
try:
    with open('$KEXT_PLIST', 'rb') as f:
        pl = plistlib.load(f)
    personalities = pl.get('IOKitPersonalities', {})
    pers = list(personalities.values())[0] if personalities else {}

    pci_class = pers.get('IOPCIClassMatch', '')
    pci_primary = pers.get('IOPCIPrimaryMatch', '')
    match_cat = pers.get('IOMatchCategory', '')
    ioname = pers.get('IONameMatch', [])
    if isinstance(ioname, str):
        ioname = [ioname]

    # Check 1: Audio PCI matching (either Class 0403 or PrimaryMatch with 51ca8086)
    has_pci_match = ('0403' in pci_class) or ('51ca8086' in pci_primary.lower()) or ('51c88086' in pci_primary.lower())
    if not has_pci_match:
        print(f'FAIL: Neither IOPCIClassMatch nor IOPCIPrimaryMatch matches Raptor Lake cAVS (primary={pci_primary}, class={pci_class})')
        sys.exit(1)

    # Check 2: IOMatchCategory avoids blocking AppleHDA
    if match_cat != 'RPLDmic':
        print(f'FAIL: IOMatchCategory ({match_cat}) must be RPLDmic to avoid exclusive access conflict')
        sys.exit(1)

    # Check 3: Raptor Lake PCI IDs
    has_rpl = any('51ca' in n.lower() or '51c8' in n.lower() for n in ioname) or ('51ca8086' in pci_primary.lower())
    if not has_rpl:
        print(f'FAIL: Neither IONameMatch ({ioname}) nor IOPCIPrimaryMatch contains 51ca or 51c8')
        sys.exit(1)

    print('MATCH: PCI Matching, IOMatchCategory RPLDmic, and 51ca/51c8 IDs verified')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1 || true)

    if echo "$matching_result" | grep -q "MATCH:"; then
        record_pass "T4.4" "IORegistry driver personality criteria accurately match Raptor Lake cAVS hardware" "$matching_result"
    else
        record_fail "T4.4" "Driver personality matching failed" "$matching_result"
    fi
else
    record_fail "T4.4" "Kext Info.plist missing" "cannot inspect IOKitPersonalities"
fi

print_summary "Tier 4 Scenario 4 (Hardware & IORegistry Matching)"
exit $?
