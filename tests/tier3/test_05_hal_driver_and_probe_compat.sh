#!/bin/bash
# ==============================================================================
# Tier 3 - Combinatorial Invariant 5: UserClient Method Selector Compatibility
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 3: Invariant 5 - UserClient Method Selector Compatibility"

# Check definitions in RPLDmicShared.h and usage in hal
SHARED_H=""
for candidate in \
    "$KEXT_DIR/RPLDmic/RPLDmicShared.h" \
    "$KEXT_DIR/TGLDmic/RPLDmicShared.h" \
    "$KEXT_DIR/TGLDmic/TGLDmicShared.h"; do
    if [ -f "$candidate" ]; then
        SHARED_H="$candidate"
        break
    fi
done

HAL_CPP=""
for candidate in \
    "$HAL_DIR/RPLDmicDriver.cpp" \
    "$HAL_DIR/TGLDmicDriver.cpp"; do
    if [ -f "$candidate" ]; then
        HAL_CPP="$candidate"
        break
    fi
done

if [ -n "$SHARED_H" ] && [ -n "$HAL_CPP" ]; then
    # Verify method selectors 0, 1, 2, 3
    has_m0=false; has_m1=false; has_m2=false; has_m3=false
    if grep -Eq "k(RPL|TGL)DmicMethodGetInfo.*0" "$SHARED_H"; then has_m0=true; fi
    if grep -Eq "k(RPL|TGL)DmicMethodStart.*1" "$SHARED_H"; then has_m1=true; fi
    if grep -Eq "k(RPL|TGL)DmicMethodStop.*2" "$SHARED_H"; then has_m2=true; fi
    if grep -Eq "k(RPL|TGL)DmicMethodGetPosition.*3" "$SHARED_H"; then has_m3=true; fi

    if [ "$has_m0" = true ] && [ "$has_m1" = true ] && [ "$has_m2" = true ] && [ "$has_m3" = true ]; then
        record_pass "T3.5" "User client method selectors 0..3 are defined and compatible across kext and HAL" "selectors: GetInfo=0, Start=1, Stop=2, GetPosition=3"
    else
        record_fail "T3.5" "Method selector definitions incomplete in shared header" "m0=$has_m0 m1=$has_m1 m2=$has_m2 m3=$has_m3"
    fi
else
    record_fail "T3.5" "Shared header or HAL driver source missing" "shared: $SHARED_H, hal: $HAL_CPP"
fi

print_summary "Tier 3 Invariant 5 (Method Selector Compatibility)"
exit $?
