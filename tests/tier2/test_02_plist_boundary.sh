#!/bin/bash
# ==============================================================================
# Tier 2 - Feature 2 Boundary: Plist Syntax & Parity Corner Cases
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 2: Feature 2 - Plist Syntax & Parity Boundary Cases"
TEMP_DIR=$(make_temp_dir "rpldmic_bva_plist")
trap 'rm -rf "$TEMP_DIR"' EXIT

# T2.2.1: Unclosed XML tag rejected by plutil -lint
BAD_XML_TAG="$TEMP_DIR/bad_tag.plist"
cat << 'EOF' > "$BAD_XML_TAG"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Kernel</key>
    <dict>
        <key>Add</key>
        <array>
    </dict>
</plist>
EOF
if plutil -lint "$BAD_XML_TAG" > /dev/null 2>&1; then
    record_fail "T2.2.1" "Malformed XML with unclosed array tag was unexpectedly accepted" "plutil should fail"
else
    record_pass "T2.2.1" "Malformed XML with unclosed tag is cleanly rejected by plutil" "syntax error detected"
fi

# T2.2.2: Unescaped entity rejection
BAD_XML_ENTITY="$TEMP_DIR/bad_entity.plist"
cat << 'EOF' > "$BAD_XML_ENTITY"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>boot-args</key>
    <string>foo & bar</string>
</dict>
</plist>
EOF
if plutil -lint "$BAD_XML_ENTITY" > /dev/null 2>&1; then
    record_fail "T2.2.2" "Unescaped ampersand entity unexpectedly accepted" "plutil should fail on raw &"
else
    record_pass "T2.2.2" "Unescaped XML entity is cleanly rejected by plutil" "entity error detected"
fi

# T2.2.3: Non-key element directly inside dictionary rejected
BAD_XML_STRUCT="$TEMP_DIR/bad_struct.plist"
cat << 'EOF' > "$BAD_XML_STRUCT"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <string>value_without_preceding_key</string>
</dict>
</plist>
EOF
if plutil -lint "$BAD_XML_STRUCT" > /dev/null 2>&1; then
    record_fail "T2.2.3" "Non-key element inside dictionary unexpectedly accepted" "plutil should fail"
else
    record_pass "T2.2.3" "Non-key element inside dictionary is cleanly rejected" "schema violation detected"
fi

# T2.2.4: Mismatched kext count detection between config plists
P1="$TEMP_DIR/p1.plist"
P2="$TEMP_DIR/p2.plist"
cat << 'EOF' > "$P1"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Kernel</key>
    <dict>
        <key>Add</key>
        <array>
            <dict><key>BundlePath</key><string>Lilu.kext</string></dict>
            <dict><key>BundlePath</key><string>RPLDmic.kext</string></dict>
        </array>
    </dict>
</dict>
</plist>
EOF

cat << 'EOF' > "$P2"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Kernel</key>
    <dict>
        <key>Add</key>
        <array>
            <dict><key>BundlePath</key><string>Lilu.kext</string></dict>
        </array>
    </dict>
</dict>
</plist>
EOF

mismatch_detected=$(python3 -c "
import plistlib
with open('$P1', 'rb') as f1, open('$P2', 'rb') as f2:
    k1 = plistlib.load(f1).get('Kernel', {}).get('Add', [])
    k2 = plistlib.load(f2).get('Kernel', {}).get('Add', [])
print('MISMATCH' if len(k1) != len(k2) else 'MATCH')
")
if [ "$mismatch_detected" = "MISMATCH" ]; then
    record_pass "T2.2.4" "Kext entry count discrepancy between plists is accurately detected" "diff caught (2 vs 1)"
else
    record_fail "T2.2.4" "Kext entry count discrepancy was not detected" "$mismatch_detected"
fi

# T2.2.5: Mismatched boot-args detection between mock plists
cat << 'EOF' > "$P1"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NVRAM</key>
    <dict>
        <key>Add</key>
        <dict>
            <key>7C436110-AB2A-4BBB-A880-FE41995C9F82</key>
            <dict><key>boot-args</key><string>ngreenSched=5 ngreenblmax=19393</string></dict>
        </dict>
    </dict>
</dict>
</plist>
EOF

cat << 'EOF' > "$P2"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NVRAM</key>
    <dict>
        <key>Add</key>
        <dict>
            <key>7C436110-AB2A-4BBB-A880-FE41995C9F82</key>
            <dict><key>boot-args</key><string>ngreenSched=5</string></dict>
        </dict>
    </dict>
</dict>
</plist>
EOF

ba_mismatch=$(python3 -c "
import plistlib
with open('$P1', 'rb') as f1, open('$P2', 'rb') as f2:
    uuid = '7C436110-AB2A-4BBB-A880-FE41995C9F82'
    ba1 = plistlib.load(f1).get('NVRAM', {}).get('Add', {}).get(uuid, {}).get('boot-args', '')
    ba2 = plistlib.load(f2).get('NVRAM', {}).get('Add', {}).get(uuid, {}).get('boot-args', '')
print('MISMATCH' if ba1 != ba2 else 'MATCH')
")
if [ "$ba_mismatch" = "MISMATCH" ]; then
    record_pass "T2.2.5" "boot-args discrepancy between config and config-post is accurately detected" "diff caught"
else
    record_fail "T2.2.5" "boot-args discrepancy was not detected" "$ba_mismatch"
fi

print_summary "Tier 2 Feature 2 (Plist Boundary)"
exit $?
