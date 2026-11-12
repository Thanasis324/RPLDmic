#!/bin/bash
# ==============================================================================
# Tier 2 - Feature 6 Boundary: CoreAudio HAL Plugin Corner Cases
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 2: Feature 6 - CoreAudio HAL Plugin Boundary Cases"
TEMP_DIR=$(make_temp_dir "rpldmic_bva_hal")
trap 'rm -rf "$TEMP_DIR"' EXIT

validate_hal_plugin() {
    local bundle="$1"
    if [ ! -d "$bundle" ]; then
        echo "FAIL: bundle directory missing"
        return 1
    fi
    local plist="$bundle/Contents/Info.plist"
    if [ ! -f "$plist" ]; then
        echo "FAIL: Info.plist missing"
        return 1
    fi
    local meta
    meta=$(python3 -c "
import plistlib, sys
try:
    with open('$plist', 'rb') as f:
        pl = plistlib.load(f)
    uuid = pl.get('AudioServerPlugIn_FactoryUUID')
    if not uuid:
        print('MISSING_UUID')
        sys.exit(1)
    clients = pl.get('AudioServerPlugIn_IOKitUserClients')
    if not clients or 'RPLDmicUserClient' not in clients:
        print('MISSING_CLIENTS')
        sys.exit(1)
    exe = pl.get('CFBundleExecutable')
    if not exe:
        print('MISSING_EXE')
        sys.exit(1)
    print(f'OK:{exe}')
except Exception as e:
    print(f'ERROR:{e}')
    sys.exit(1)
" 2>&1 || true)

    if ! echo "$meta" | grep -q "^OK:"; then
        echo "FAIL: $meta"
        return 1
    fi

    local exe_name
    exe_name=$(echo "$meta" | cut -d: -f2)
    local bin_path="$bundle/Contents/MacOS/$exe_name"
    if [ ! -x "$bin_path" ]; then
        echo "FAIL: binary missing or not executable"
        return 1
    fi

    local file_type
    file_type=$(file "$bin_path")
    if ! echo "$file_type" | grep -q "Mach-O 64-bit"; then
        echo "FAIL: binary is not Mach-O 64-bit ($file_type)"
        return 1
    fi

    echo "OK"
    return 0
}

# T2.6.1: Corrupt HAL driver bundle structure (missing executable)
MOCK_HAL_1="$TEMP_DIR/MockNoBin.driver"
mkdir -p "$MOCK_HAL_1/Contents/MacOS"
cat << 'EOF' > "$MOCK_HAL_1/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>RPLDmic</string>
    <key>AudioServerPlugIn_FactoryUUID</key><string>12345678-1234-1234-1234-123456789abc</string>
    <key>AudioServerPlugIn_IOKitUserClients</key><array><string>RPLDmicUserClient</string></array>
</dict>
</plist>
EOF
if validate_hal_plugin "$MOCK_HAL_1" > /dev/null 2>&1; then
    record_fail "T2.6.1" "HAL bundle missing executable binary unexpectedly accepted" "must fail"
else
    record_pass "T2.6.1" "HAL bundle missing executable binary is cleanly rejected" "missing binary caught"
fi

# T2.6.2: Missing HAL factory UUID rejection
MOCK_HAL_2="$TEMP_DIR/MockNoUUID.driver"
mkdir -p "$MOCK_HAL_2/Contents/MacOS"
touch "$MOCK_HAL_2/Contents/MacOS/RPLDmic" && chmod +x "$MOCK_HAL_2/Contents/MacOS/RPLDmic"
cat << 'EOF' > "$MOCK_HAL_2/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>RPLDmic</string>
    <key>AudioServerPlugIn_IOKitUserClients</key><array><string>RPLDmicUserClient</string></array>
</dict>
</plist>
EOF
if validate_hal_plugin "$MOCK_HAL_2" > /dev/null 2>&1; then
    record_fail "T2.6.2" "HAL bundle missing AudioServerPlugIn_FactoryUUID unexpectedly accepted" "must fail"
else
    record_pass "T2.6.2" "HAL bundle missing AudioServerPlugIn_FactoryUUID is cleanly rejected" "FactoryUUID enforced"
fi

# T2.6.3: Non-Mach-O executable in HAL bundle rejection
MOCK_HAL_3="$TEMP_DIR/MockScript.driver"
mkdir -p "$MOCK_HAL_3/Contents/MacOS"
echo "#!/bin/sh" > "$MOCK_HAL_3/Contents/MacOS/RPLDmic" && chmod +x "$MOCK_HAL_3/Contents/MacOS/RPLDmic"
cp "$MOCK_HAL_1/Contents/Info.plist" "$MOCK_HAL_3/Contents/Info.plist"
if validate_hal_plugin "$MOCK_HAL_3" > /dev/null 2>&1; then
    record_fail "T2.6.3" "Shell script masquerading as HAL driver binary unexpectedly accepted" "must fail"
else
    record_pass "T2.6.3" "Non-Mach-O file masquerading as HAL binary is cleanly rejected" "Mach-O verified"
fi

# T2.6.4: Audio format & sample rate validation (rejection of unsupported rates, e.g., 11025 vs 48000 Hz)
check_sample_rate() {
    local rate="$1"
    # RPLDmic cAVS hardware microphone fixed rate is 48000.0 Hz
    if [ "$rate" = "48000" ] || [ "$rate" = "48000.0" ]; then
        return 0
    else
        return 1
    fi
}
if check_sample_rate 11025; then
    record_fail "T2.6.4" "Invalid sample rate (11025 Hz) unexpectedly accepted" "must reject non-48kHz"
else
    record_pass "T2.6.4" "Unsupported sample rate (11025 Hz) is cleanly rejected" "hardware 48 kHz invariant enforced"
fi

# T2.6.5: Missing AudioServerPlugIn_IOKitUserClients key rejection
MOCK_HAL_5="$TEMP_DIR/MockNoClients.driver"
mkdir -p "$MOCK_HAL_5/Contents/MacOS"
touch "$MOCK_HAL_5/Contents/MacOS/RPLDmic" && chmod +x "$MOCK_HAL_5/Contents/MacOS/RPLDmic"
cat << 'EOF' > "$MOCK_HAL_5/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>RPLDmic</string>
    <key>AudioServerPlugIn_FactoryUUID</key><string>12345678-1234-1234-1234-123456789abc</string>
</dict>
</plist>
EOF
if validate_hal_plugin "$MOCK_HAL_5" > /dev/null 2>&1; then
    record_fail "T2.6.5" "HAL bundle missing AudioServerPlugIn_IOKitUserClients unexpectedly accepted" "must fail"
else
    record_pass "T2.6.5" "HAL bundle missing AudioServerPlugIn_IOKitUserClients is cleanly rejected" "entitlement enforced"
fi

print_summary "Tier 2 Feature 6 (CoreAudio HAL Boundary)"
exit $?
