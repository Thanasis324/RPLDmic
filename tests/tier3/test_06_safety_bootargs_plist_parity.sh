#!/bin/bash
# ==============================================================================
# Tier 3 - Combinatorial Invariant 6: Safety Boot-Args Parity Between Plists
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 3: Invariant 6 - Safety Boot-Args Parity Between Plists"

if [ -f "$CONFIG_PLIST" ] && [ -f "$CONFIG_POST_PLIST" ]; then
    parity_result=$(python3 -c "
import plistlib, sys
try:
    with open('$CONFIG_PLIST', 'rb') as f1, open('$CONFIG_POST_PLIST', 'rb') as f2:
        p1 = plistlib.load(f1)
        p2 = plistlib.load(f2)
    uuid = '7C436110-AB2A-4BBB-A880-FE41995C9F82'
    ba1 = p1.get('NVRAM', {}).get('Add', {}).get(uuid, {}).get('boot-args', '')
    ba2 = p2.get('NVRAM', {}).get('Add', {}).get(uuid, {}).get('boot-args', '')

    # Check required safety tokens in both
    tokens = ['ngreenSched=5', 'ngreenblmax=19393', 'ngreenblmin=200']
    for t in tokens:
        if t not in ba1 or t not in ba2:
            print(f'FAIL: token {t} missing in one or both plists')
            sys.exit(1)

    if ba1 != ba2:
        print('FAIL: boot-args string differs between config and config-post')
        sys.exit(1)

    print('MATCH: All safety tokens present and boot-args identical')
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1 || true)

    if echo "$parity_result" | grep -q "MATCH"; then
        record_pass "T3.6" "Safety boot-args are identical and fully preserved across config and config-post" "$parity_result"
    else
        record_fail "T3.6" "Safety boot-args parity mismatch" "$parity_result"
    fi
else
    record_fail "T3.6" "config.plist or config-post.plist missing" "plists missing"
fi

print_summary "Tier 3 Invariant 6 (Boot-Args Parity)"
exit $?
