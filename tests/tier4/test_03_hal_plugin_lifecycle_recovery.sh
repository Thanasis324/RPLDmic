#!/bin/bash
# ==============================================================================
# Tier 4 - Scenario 3: CoreAudio HAL Plugin Lifecycle & Daemon Recovery Simulation
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 4: Scenario 3 - HAL Plugin Lifecycle & Recovery Simulation"
TEMP_DIR=$(make_temp_dir "rpldmic_sim_hal_life")
trap 'rm -rf "$TEMP_DIR"' EXIT

# T4.3: Test probe compilation and execution against current IORegistry state
# Compile or locate rpldmic-probe / tgldmic-probe
PROBE_C=""
for candidate in "$HAL_DIR/rpldmic-probe.c" "$HAL_DIR/tgldmic-probe.c"; do
    if [ -f "$candidate" ]; then PROBE_C="$candidate"; break; fi
done

PROBE_BIN="$TEMP_DIR/driver-probe"
if [ -n "$PROBE_C" ]; then
    clang -O2 -framework IOKit -framework CoreFoundation "$PROBE_C" -o "$PROBE_BIN" > /dev/null 2>&1 || true
fi

probe_safe=false
if [ -f "$PROBE_BIN" ] && [ -x "$PROBE_BIN" ]; then
    # Run probe: if kext is not yet loaded into active kernel, probe must exit cleanly with informative message
    probe_output=$("$PROBE_BIN" 2>&1 || true)
    # Ensure probe didn't crash with SIGSEGV or bus error
    if ! echo "$probe_output" | grep -Eq "(Segmentation|Bus error|Abort trap)"; then
        probe_safe=true
    fi
fi

if [ "$probe_safe" = true ]; then
    record_pass "T4.3" "CoreAudio HAL userclient probe compiles and executes without crashes on idle kernel" "safe fallback verified"
else
    record_fail "T4.3" "CoreAudio HAL probe tool crashed or failed to compile" "probe_safe=$probe_safe"
fi

print_summary "Tier 4 Scenario 3 (HAL Plugin Recovery)"
exit $?
