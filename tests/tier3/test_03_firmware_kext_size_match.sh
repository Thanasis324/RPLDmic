#!/bin/bash
# ==============================================================================
# Tier 3 - Combinatorial Invariant 3: Firmware Binary & Kext Symbol Match
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 3: Invariant 3 - Firmware Binary & Kext Symbol Match"

FW_BIN="$FIRMWARE_DIR/intel/sof-rpl.ri"
FW_HEADER="$FIRMWARE_DIR/intel/fw_bin.h"

if [ -f "$FW_BIN" ] && [ -f "$FW_HEADER" ]; then
    fw_size=$(stat -f%z "$FW_BIN")
    header_size=$(grep "kSofRplRiSize" "$FW_HEADER" | head -n 1 | grep -o "[0-9]\+" || echo 0)

    if [ "$fw_size" -eq "$header_size" ] && [ "$fw_size" -eq 525056 ]; then
        record_pass "T3.3" "Firmware disk size strictly matches embedded kSofRplRiSize header constant" "size=$fw_size bytes"
    else
        record_fail "T3.3" "Firmware disk size does not match kSofRplRiSize" "disk=$fw_size vs header=$header_size"
    fi
else
    record_fail "T3.3" "Firmware binary or fw_bin.h missing" "fw: $([ -f "$FW_BIN" ] && echo YES || echo NO), header: $([ -f "$FW_HEADER" ] && echo YES || echo NO)"
fi

print_summary "Tier 3 Invariant 3 (Firmware-Kext Size Match)"
exit $?
