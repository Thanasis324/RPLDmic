#!/bin/bash
# ==============================================================================
# Tier 1 - Feature 2: OpenCore Plist Syntax & Parity Verification
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 1: Feature 2 - OpenCore Plist Syntax & Parity Verification"

# T1.2.1: plutil -lint config.plist
if [ -f "$CONFIG_PLIST" ]; then
    out=$(plutil -lint "$CONFIG_PLIST" 2>&1 || true)
    if echo "$out" | grep -q "OK"; then
        record_pass "T1.2.1" "config.plist passes plutil -lint validation" "valid XML/plist"
    else
        record_fail "T1.2.1" "config.plist plutil -lint failed" "$out"
    fi
else
    record_fail "T1.2.1" "config.plist missing" "$CONFIG_PLIST not found"
fi

# T1.2.2: plutil -lint config-post.plist
if [ -f "$CONFIG_POST_PLIST" ]; then
    out=$(plutil -lint "$CONFIG_POST_PLIST" 2>&1 || true)
    if echo "$out" | grep -q "OK"; then
        record_pass "T1.2.2" "config-post.plist passes plutil -lint validation" "valid XML/plist"
    else
        record_fail "T1.2.2" "config-post.plist plutil -lint failed" "$out"
    fi
else
    record_fail "T1.2.2" "config-post.plist missing" "$CONFIG_POST_PLIST not found"
fi

# T1.2.3: Structural schema parity (Top-level sections)
if [ -f "$CONFIG_PLIST" ] && [ -f "$CONFIG_POST_PLIST" ]; then
    parity_check=$(python3 -c "
import plistlib, sys
try:
    with open('$CONFIG_PLIST', 'rb') as f1, open('$CONFIG_POST_PLIST', 'rb') as f2:
        p1 = plistlib.load(f1)
        p2 = plistlib.load(f2)
    required = {'ACPI', 'Booter', 'DeviceProperties', 'Kernel', 'Misc', 'NVRAM', 'PlatformInfo', 'UEFI'}
    k1, k2 = set(p1.keys()), set(p2.keys())
    if not required.issubset(k1) or not required.issubset(k2):
        print(f'Missing required top-level keys: p1 missing {required - k1}, p2 missing {required - k2}')
        sys.exit(1)
    if k1 != k2:
        print(f'Key mismatch: {k1.symmetric_difference(k2)}')
        sys.exit(1)
    print('MATCH')
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
" 2>&1 || true)
    if [ "$parity_check" = "MATCH" ]; then
        record_pass "T1.2.3" "Top-level OpenCore sections match between config and config-post" "all 8 root schema keys match"
    else
        record_fail "T1.2.3" "Top-level OpenCore sections mismatch" "$parity_check"
    fi
else
    record_fail "T1.2.3" "One or both plists missing" "cannot evaluate parity"
fi

# T1.2.4: Kernel -> Add list parity
if [ -f "$CONFIG_PLIST" ] && [ -f "$CONFIG_POST_PLIST" ]; then
    kext_parity=$(python3 -c "
import plistlib, sys
try:
    with open('$CONFIG_PLIST', 'rb') as f1, open('$CONFIG_POST_PLIST', 'rb') as f2:
        p1 = plistlib.load(f1)
        p2 = plistlib.load(f2)
    k1 = [(k.get('BundlePath'), k.get('Enabled')) for k in p1.get('Kernel', {}).get('Add', [])]
    k2 = [(k.get('BundlePath'), k.get('Enabled')) for k in p2.get('Kernel', {}).get('Add', [])]
    if k1 == k2:
        print(f'MATCH:{len(k1)}')
    else:
        print(f'MISMATCH: len(k1)={len(k1)}, len(k2)={len(k2)}')
        sys.exit(1)
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
" 2>&1 || true)
    if echo "$kext_parity" | grep -q "^MATCH:"; then
        record_pass "T1.2.4" "Kernel -> Add kext list and enabled states match identically" "$kext_parity"
    else
        record_fail "T1.2.4" "Kernel -> Add kext mismatch between plists" "$kext_parity"
    fi
else
    record_fail "T1.2.4" "One or both plists missing" "cannot evaluate kext parity"
fi

# T1.2.5: NVRAM boot-args parity
if [ -f "$CONFIG_PLIST" ] && [ -f "$CONFIG_POST_PLIST" ]; then
    bootargs_parity=$(python3 -c "
import plistlib, sys
try:
    with open('$CONFIG_PLIST', 'rb') as f1, open('$CONFIG_POST_PLIST', 'rb') as f2:
        p1 = plistlib.load(f1)
        p2 = plistlib.load(f2)
    uuid = '7C436110-AB2A-4BBB-A880-FE41995C9F82'
    ba1 = p1.get('NVRAM', {}).get('Add', {}).get(uuid, {}).get('boot-args', '')
    ba2 = p2.get('NVRAM', {}).get('Add', {}).get(uuid, {}).get('boot-args', '')
    if ba1 == ba2 and len(ba1) > 0:
        print('MATCH')
    else:
        print(f'MISMATCH: ba1={ba1} != ba2={ba2}')
        sys.exit(1)
except Exception as e:
    print(f'Error: {e}')
    sys.exit(1)
" 2>&1 || true)
    if [ "$bootargs_parity" = "MATCH" ]; then
        record_pass "T1.2.5" "NVRAM 7C436110 boot-args are identical between config and config-post" "exact match"
    else
        record_fail "T1.2.5" "NVRAM boot-args mismatch between plists" "$bootargs_parity"
    fi
else
    record_fail "T1.2.5" "One or both plists missing" "cannot evaluate boot-args parity"
fi

print_summary "Tier 1 Feature 2 (Plist Parity & Syntax)"
exit $?
