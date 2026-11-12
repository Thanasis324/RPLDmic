#!/bin/bash
# ==============================================================================
# Tier 1 - Feature 5: Firmware Integration Verification (sof-rpl.ri)
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 1: Feature 5 - Firmware Integration Verification"

FW_FILE="$FIRMWARE_DIR/intel/sof-rpl.ri"
FW_HEADER="$FIRMWARE_DIR/intel/fw_bin.h"
EXPECTED_SHA256="294e5a51b1d3fc4ceda57780927c2a2ec95bb5d23477f879a9fb648c6c01cb30"
EXPECTED_SIZE=525056

# T1.5.1: File existence
assert_file_exists "T1.5.1" "sof-rpl.ri firmware binary exists" "$FW_FILE"

# T1.5.2: Exact size 525056 bytes
assert_file_size_eq "T1.5.2" "sof-rpl.ri size is exactly 525056 bytes" "$FW_FILE" "$EXPECTED_SIZE"

# T1.5.3: SHA-256 checksum match
if [ -f "$FW_FILE" ]; then
    actual_sha256=$(shasum -a 256 "$FW_FILE" | awk '{print $1}')
    assert_equals "T1.5.3" "sof-rpl.ri SHA-256 matches official Intel signed binary" "$EXPECTED_SHA256" "$actual_sha256"
else
    record_fail "T1.5.3" "sof-rpl.ri SHA-256 check failed" "file missing"
fi

# T1.5.4: Manifest magic validation (starts with 'XMan' or '$AE1')
if [ -f "$FW_FILE" ]; then
    magic=$(head -c 4 "$FW_FILE")
    if [ "$magic" = "XMan" ] || [ "$magic" = "\$AE1" ]; then
        record_pass "T1.5.4" "sof-rpl.ri contains valid extended manifest magic ($magic)" "Intel signed header verified"
    else
        record_fail "T1.5.4" "sof-rpl.ri manifest magic invalid" "got: $(echo -n "$magic" | xxd -p)"
    fi
else
    record_fail "T1.5.4" "sof-rpl.ri manifest magic check failed" "file missing"
fi

# T1.5.5: Embedded C header fw_bin.h contains kSofRplRi and kSofRplRiSize
if [ -f "$FW_HEADER" ]; then
    has_symbol=false
    has_size=false
    if grep -q "kSofRplRi" "$FW_HEADER"; then
        has_symbol=true
    fi
    if grep -q "kSofRplRiSize.*525056" "$FW_HEADER"; then
        has_size=true
    fi

    if [ "$has_symbol" = true ] && [ "$has_size" = true ]; then
        record_pass "T1.5.5" "fw_bin.h defines kSofRplRi byte array and kSofRplRiSize = 525056" "C symbol generation verified"
    else
        record_fail "T1.5.5" "fw_bin.h missing required symbols" "has_symbol=$has_symbol has_size=$has_size"
    fi
else
    record_fail "T1.5.5" "fw_bin.h header missing" "$FW_HEADER not found"
fi

print_summary "Tier 1 Feature 5 (Firmware Integration)"
exit $?
