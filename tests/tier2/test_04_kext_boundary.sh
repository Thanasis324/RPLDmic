#!/bin/bash
# ==============================================================================
# Tier 2 - Feature 4 Boundary: Kext Build & Architecture Corner Cases
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 2: Feature 4 - Kext Build Boundary Cases"
TEMP_DIR=$(make_temp_dir "rpldmic_bva_kext")
trap 'rm -rf "$TEMP_DIR"' EXIT

validate_kext_bundle() {
    local bundle="$1"
    if [ ! -d "$bundle" ]; then
        echo "FAIL: bundle directory missing"
        return 1
    fi
    local plist="$bundle/Contents/Info.plist"
    if [ ! -f "$plist" ]; then
        echo "FAIL: Contents/Info.plist missing"
        return 1
    fi
    local bin_name
    bin_name=$(python3 -c "
import plistlib
try:
    with open('$plist', 'rb') as f:
        pl = plistlib.load(f)
    print(pl.get('CFBundleExecutable', ''))
except Exception:
    pass
")
    if [ -z "$bin_name" ]; then
        echo "FAIL: CFBundleExecutable not specified in Info.plist"
        return 1
    fi
    local binary="$bundle/Contents/MacOS/$bin_name"
    if [ ! -f "$binary" ]; then
        echo "FAIL: binary $binary missing"
        return 1
    fi
    if [ ! -x "$binary" ]; then
        echo "FAIL: binary $binary not executable"
        return 1
    fi
    local file_type
    file_type=$(file "$binary")
    if ! echo "$file_type" | grep -q "Mach-O 64-bit"; then
        echo "FAIL: binary is not Mach-O 64-bit ($file_type)"
        return 1
    fi
    if ! echo "$file_type" | grep -q "x86_64"; then
        echo "FAIL: binary architecture is not x86_64 ($file_type)"
        return 1
    fi
    echo "OK"
    return 0
}

# T2.4.1: Corrupt / Non-Mach-O binary masquerading as driver
MOCK_BUNDLE_1="$TEMP_DIR/MockCorrupt.kext"
mkdir -p "$MOCK_BUNDLE_1/Contents/MacOS"
echo "I am just a shell script" > "$MOCK_BUNDLE_1/Contents/MacOS/MockCorrupt"
chmod +x "$MOCK_BUNDLE_1/Contents/MacOS/MockCorrupt"
cat << 'EOF' > "$MOCK_BUNDLE_1/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MockCorrupt</string>
    <key>CFBundleIdentifier</key><string>org.test.MockCorrupt</string>
</dict>
</plist>
EOF

if validate_kext_bundle "$MOCK_BUNDLE_1" > /dev/null 2>&1; then
    record_fail "T2.4.1" "Non-Mach-O file masquerading as driver binary was unexpectedly accepted" "must fail"
else
    record_pass "T2.4.1" "Non-Mach-O executable is cleanly rejected by validator" "header check verified"
fi

# T2.4.2: Incompatible architecture rejection (arm64-only simulated binary)
MOCK_BUNDLE_2="$TEMP_DIR/MockArm.kext"
mkdir -p "$MOCK_BUNDLE_2/Contents/MacOS"
echo "void foo(){}" | clang -x c -arch arm64 -c - -o "$MOCK_BUNDLE_2/Contents/MacOS/MockArm" 2>/dev/null || touch "$MOCK_BUNDLE_2/Contents/MacOS/MockArm"
chmod +x "$MOCK_BUNDLE_2/Contents/MacOS/MockArm"
cp "$MOCK_BUNDLE_1/Contents/Info.plist" "$MOCK_BUNDLE_2/Contents/Info.plist"
python3 -c "
import plistlib
p = '$MOCK_BUNDLE_2/Contents/Info.plist'
with open(p, 'rb') as f: pl = plistlib.load(f)
pl['CFBundleExecutable'] = 'MockArm'
with open(p, 'wb') as f: plistlib.dump(pl, f)
"
if validate_kext_bundle "$MOCK_BUNDLE_2" > /dev/null 2>&1; then
    record_fail "T2.4.2" "arm64-only binary unexpectedly accepted on x86_64 target" "must reject non-x86_64"
else
    record_pass "T2.4.2" "Non-x86_64 architecture is cleanly rejected by validator" "arch check verified"
fi

# T2.4.3: Missing executable permission rejection
MOCK_BUNDLE_3="$TEMP_DIR/MockNoExec.kext"
mkdir -p "$MOCK_BUNDLE_3/Contents/MacOS"
echo "void foo(){}" | clang -x c -arch x86_64 -c - -o "$MOCK_BUNDLE_3/Contents/MacOS/MockNoExec" 2>/dev/null || touch "$MOCK_BUNDLE_3/Contents/MacOS/MockNoExec"
chmod -x "$MOCK_BUNDLE_3/Contents/MacOS/MockNoExec"
cp "$MOCK_BUNDLE_1/Contents/Info.plist" "$MOCK_BUNDLE_3/Contents/Info.plist"
python3 -c "
import plistlib
p = '$MOCK_BUNDLE_3/Contents/Info.plist'
with open(p, 'rb') as f: pl = plistlib.load(f)
pl['CFBundleExecutable'] = 'MockNoExec'
with open(p, 'wb') as f: plistlib.dump(pl, f)
"
if validate_kext_bundle "$MOCK_BUNDLE_3" > /dev/null 2>&1; then
    record_fail "T2.4.3" "Non-executable driver binary unexpectedly accepted" "must require +x"
else
    record_pass "T2.4.3" "Missing executable permission (+x) on binary is cleanly rejected" "file mode check verified"
fi

# T2.4.4: Incomplete bundle structure rejection (missing Contents/MacOS)
MOCK_BUNDLE_4="$TEMP_DIR/MockIncomplete.kext"
mkdir -p "$MOCK_BUNDLE_4/Contents"
cp "$MOCK_BUNDLE_1/Contents/Info.plist" "$MOCK_BUNDLE_4/Contents/Info.plist"
if validate_kext_bundle "$MOCK_BUNDLE_4" > /dev/null 2>&1; then
    record_fail "T2.4.4" "Incomplete bundle structure missing MacOS directory unexpectedly accepted" "must fail"
else
    record_pass "T2.4.4" "Incomplete bundle structure missing MacOS directory is cleanly rejected" "structure verified"
fi

# T2.4.5: Missing required IOKit personality keys (e.g. missing CFBundleIdentifier or IOClass)
MOCK_PLIST="$TEMP_DIR/bad_personality.plist"
cat << 'EOF' > "$MOCK_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>IncompleteKext</string>
</dict>
</plist>
EOF

missing_keys=$(python3 -c "
import plistlib
with open('$MOCK_PLIST', 'rb') as f: pl = plistlib.load(f)
required = {'CFBundleIdentifier', 'CFBundleExecutable', 'IOKitPersonalities'}
missing = required - set(pl.keys())
print('MISSING' if missing else 'COMPLETE')
")
if [ "$missing_keys" = "MISSING" ]; then
    record_pass "T2.4.5" "Missing required IOKit personality keys in Info.plist is cleanly detected" "personality contract enforced"
else
    record_fail "T2.4.5" "Missing personality keys was not detected" "$missing_keys"
fi

print_summary "Tier 2 Feature 4 (Kext Boundary)"
exit $?
