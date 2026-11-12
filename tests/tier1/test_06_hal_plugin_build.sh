#!/bin/bash
# ==============================================================================
# Tier 1 - Feature 6: CoreAudio HAL Plugin Build Verification
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 1: Feature 6 - CoreAudio HAL Plugin Build Verification"

HAL_BUNDLE=""
for candidate in \
    "$HAL_DIR/build/RPLDmic.driver" \
    "$HAL_DIR/RPLDmic.driver" \
    "/Library/Audio/Plug-Ins/HAL/RPLDmic.driver"; do
    if [ -d "$candidate" ]; then
        HAL_BUNDLE="$candidate"
        break
    fi
done

# If not pre-built, check if make can build it
if [ -z "$HAL_BUNDLE" ] && [ -f "$HAL_DIR/Makefile" ]; then
    log_info "RPLDmic.driver not pre-built; attempting build via make -C $HAL_DIR..."
    make -C "$HAL_DIR" > /dev/null 2>&1 || true
    for candidate in "$HAL_DIR/build/RPLDmic.driver" "$HAL_DIR/RPLDmic.driver"; do
        if [ -d "$candidate" ]; then
            HAL_BUNDLE="$candidate"
            break
        fi
    done
fi

# T1.6.1: HAL bundle existence
if [ -n "$HAL_BUNDLE" ] && [ -d "$HAL_BUNDLE" ]; then
    record_pass "T1.6.1" "RPLDmic.driver HAL plug-in bundle exists" "found at $HAL_BUNDLE"
else
    record_fail "T1.6.1" "RPLDmic.driver HAL plug-in bundle not found" "neither pre-built nor staged"
fi

# T1.6.2: Mach-O binary existence
HAL_MACHO=""
if [ -n "$HAL_BUNDLE" ] && [ -f "$HAL_BUNDLE/Contents/MacOS/RPLDmic" ]; then
    HAL_MACHO="$HAL_BUNDLE/Contents/MacOS/RPLDmic"
    record_pass "T1.6.2" "RPLDmic Mach-O binary exists inside driver bundle" "$HAL_MACHO"
else
    record_fail "T1.6.2" "RPLDmic Mach-O binary missing inside driver bundle" "Contents/MacOS/RPLDmic not found"
fi

# T1.6.3: Architecture validation (strictly x86_64)
if [ -n "$HAL_MACHO" ] && [ -f "$HAL_MACHO" ]; then
    file_info=$(file "$HAL_MACHO")
    if echo "$file_info" | grep -q "Mach-O 64-bit" && echo "$file_info" | grep -q "x86_64"; then
        record_pass "T1.6.3" "HAL plug-in Mach-O targets x86_64 architecture" "Mach-O 64-bit bundle x86_64"
    else
        record_fail "T1.6.3" "HAL plug-in Mach-O is not x86_64" "$file_info"
    fi
else
    record_fail "T1.6.3" "HAL architecture check failed" "binary missing"
fi

# T1.6.4: Info.plist declares AudioServerPlugIn_IOKitUserClients with RPLDmicUserClient
if [ -n "$HAL_BUNDLE" ] && [ -f "$HAL_BUNDLE/Contents/Info.plist" ]; then
    user_clients=$(python3 -c "
import plistlib
try:
    with open('$HAL_BUNDLE/Contents/Info.plist', 'rb') as f:
        pl = plistlib.load(f)
    clients = pl.get('AudioServerPlugIn_IOKitUserClients', [])
    print(','.join(clients))
except Exception:
    pass
")
    if echo "$user_clients" | grep -q "RPLDmicUserClient"; then
        record_pass "T1.6.4" "HAL Info.plist declares AudioServerPlugIn_IOKitUserClients with RPLDmicUserClient" "clients=$user_clients"
    else
        record_fail "T1.6.4" "AudioServerPlugIn_IOKitUserClients does not declare RPLDmicUserClient" "got: $user_clients"
    fi
else
    record_fail "T1.6.4" "HAL Info.plist check failed" "plist missing"
fi

# T1.6.5: HAL Factory UUID & Bundle ID
if [ -n "$HAL_BUNDLE" ] && [ -f "$HAL_BUNDLE/Contents/Info.plist" ]; then
    hal_meta=$(python3 -c "
import plistlib, sys
try:
    with open('$HAL_BUNDLE/Contents/Info.plist', 'rb') as f:
        pl = plistlib.load(f)
    factories = pl.get('CFPlugInFactories', {})
    uuid = pl.get('AudioServerPlugIn_FactoryUUID') or (list(factories.keys())[0] if factories else '')
    bid = pl.get('CFBundleIdentifier', '')
    if uuid and bid == 'org.thesofproject.driver.RPLDmic':
        print(f'PASS:{uuid}')
    else:
        print(f'FAIL: uuid={uuid}, bid={bid}')
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1 || true)
    if echo "$hal_meta" | grep -q "PASS"; then
        record_pass "T1.6.5" "HAL plug-in declares CFPlugInFactories UUID and bundle ID org.thesofproject.driver.RPLDmic" "$hal_meta"
    else
        record_fail "T1.6.5" "HAL plug-in missing FactoryUUID or valid CFBundleIdentifier" "$hal_meta"
    fi
else
    record_fail "T1.6.5" "HAL metadata check failed" "bundle or plist missing"
fi

print_summary "Tier 1 Feature 6 (CoreAudio HAL Plugin Build)"
exit $?
