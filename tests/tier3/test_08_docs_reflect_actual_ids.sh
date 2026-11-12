#!/bin/bash
# ==============================================================================
# Tier 3 - Combinatorial Invariant 8: Documentation & Kext PCI ID Alignment
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 3: Invariant 8 - Documentation & Kext PCI ID Alignment"

KEXT_PLIST=""
for candidate in \
    "$KEXT_DIR/build/RPLDmic.kext/Contents/Info.plist" \
    "$KEXT_DIR/RPLDmic/Info.plist"; do
    if [ -f "$candidate" ]; then
        KEXT_PLIST="$candidate"
        break
    fi
done

DOC_ARCH="$DOCS_DIR/ARCHITECTURE.md"

if [ -n "$KEXT_PLIST" ] && [ -f "$DOC_ARCH" ]; then
    id_alignment=$(python3 -c "
import plistlib, sys
try:
    with open('$KEXT_PLIST', 'rb') as f:
        pl = plistlib.load(f)
    personalities = pl.get('IOKitPersonalities', {})
    driver_pers = list(personalities.values())[0] if personalities else {}
    ioname = driver_pers.get('IONameMatch', [])
    if isinstance(ioname, str):
        ioname = [ioname]

    has_51ca = any('51ca' in n.lower() for n in ioname)
    has_51c8 = any('51c8' in n.lower() for n in ioname)

    with open('$DOC_ARCH') as f:
        doc_text = f.read().lower()

    doc_has_51ca = '51ca' in doc_text
    doc_has_subsys = '230e' in doc_text

    if (has_51ca or has_51c8) and doc_has_51ca:
        print(f'MATCH: PCI 51ca documented and present in IONameMatch {ioname}')
    else:
        print(f'MISMATCH: kext_51ca={has_51ca}, doc_51ca={doc_has_51ca}, doc_subsys={doc_has_subsys}')
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1 || true)

    if echo "$id_alignment" | grep -q "^MATCH:"; then
        record_pass "T3.8" "PCI Device ID 51ca is documented and matched in kext Info.plist" "$id_alignment"
    else
        record_fail "T3.8" "Documentation and kext PCI ID discrepancy" "$id_alignment"
    fi
else
    record_fail "T3.8" "Kext Info.plist or ARCHITECTURE.md missing" "kext: $KEXT_PLIST, doc: $([ -f "$DOC_ARCH" ] && echo YES || echo NO)"
fi

print_summary "Tier 3 Invariant 8 (PCI ID Alignment)"
exit $?
