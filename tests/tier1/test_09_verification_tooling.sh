#!/bin/bash
# ==============================================================================
# Tier 1 - Feature 9: Verification Tooling Verification (verify-rpldmic.sh)
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 1: Feature 9 - Verification Tooling Verification"

VERIFY_SCRIPT=""
for candidate in \
    "$TOOLS_DIR/verify-rpldmic.sh" \
    "$PROJECT_ROOT/verify-rpldmic.sh"; do
    if [ -f "$candidate" ]; then
        VERIFY_SCRIPT="$candidate"
        break
    fi
done

# T1.9.1: Verification script existence
if [ -n "$VERIFY_SCRIPT" ] && [ -f "$VERIFY_SCRIPT" ]; then
    record_pass "T1.9.1" "Verification script verify-rpldmic.sh exists" "$VERIFY_SCRIPT"
else
    record_fail "T1.9.1" "verify-rpldmic.sh script not found" "expected in tools/ or project root (worker_m5 pending)"
fi

# T1.9.2: Execution permissions
if [ -n "$VERIFY_SCRIPT" ] && [ -x "$VERIFY_SCRIPT" ]; then
    record_pass "T1.9.2" "verify-rpldmic.sh has executable permissions" "chmod +x verified"
else
    record_fail "T1.9.2" "verify-rpldmic.sh is not executable" "missing +x permission or file missing"
fi

# T1.9.3: Syntax validation (bash -n)
if [ -n "$VERIFY_SCRIPT" ] && [ -f "$VERIFY_SCRIPT" ]; then
    if bash -n "$VERIFY_SCRIPT" 2>&1; then
        record_pass "T1.9.3" "verify-rpldmic.sh passes bash syntax validation (bash -n)" "clean syntax"
    else
        record_fail "T1.9.3" "verify-rpldmic.sh syntax error" "failed bash -n"
    fi
else
    record_fail "T1.9.3" "Syntax check skipped" "file missing"
fi

# T1.9.4: IORegistry query capability
if [ -n "$VERIFY_SCRIPT" ] && [ -f "$VERIFY_SCRIPT" ]; then
    if grep -q "ioreg" "$VERIFY_SCRIPT" && (grep -q "RPLDmic" "$VERIFY_SCRIPT" || grep -q "TGLDmic" "$VERIFY_SCRIPT"); then
        record_pass "T1.9.4" "verify-rpldmic.sh queries IORegistry for driver IOService node" "ioreg query present"
    else
        record_fail "T1.9.4" "verify-rpldmic.sh missing IORegistry driver query" "ioreg/RPLDmic not found"
    fi
else
    record_fail "T1.9.4" "IORegistry query check skipped" "file missing"
fi

# T1.9.5: CoreAudio inspection capability
if [ -n "$VERIFY_SCRIPT" ] && [ -f "$VERIFY_SCRIPT" ]; then
    if grep -q "system_profiler" "$VERIFY_SCRIPT" || grep -q "coreaudiod" "$VERIFY_SCRIPT" || grep -q "Audio" "$VERIFY_SCRIPT"; then
        record_pass "T1.9.5" "verify-rpldmic.sh inspects CoreAudio input device stream state" "audio inspection logic present"
    else
        record_fail "T1.9.5" "verify-rpldmic.sh missing CoreAudio inspection logic" "audio checks absent"
    fi
else
    record_fail "T1.9.5" "CoreAudio check skipped" "file missing"
fi

print_summary "Tier 1 Feature 9 (Verification Tooling)"
exit $?
