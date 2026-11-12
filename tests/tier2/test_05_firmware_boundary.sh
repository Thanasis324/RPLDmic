#!/bin/bash
# ==============================================================================
# Tier 2 - Feature 5 Boundary: Firmware Integration Corner Cases
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 2: Feature 5 - Firmware Integration Boundary Cases"
TEMP_DIR=$(make_temp_dir "rpldmic_bva_fw")
trap 'rm -rf "$TEMP_DIR"' EXIT

validate_firmware_binary() {
    local fw_path="$1"
    local expected_size=525056
    local expected_sha="294e5a51b1d3fc4ceda57780927c2a2ec95bb5d23477f879a9fb648c6c01cb30"

    if [ ! -f "$fw_path" ]; then
        echo "FAIL: file missing"
        return 1
    fi

    local size
    size=$(stat -f%z "$fw_path" 2>/dev/null || echo 0)
    if [ "$size" -ne "$expected_size" ]; then
        echo "FAIL: size mismatch (got $size, expected $expected_size)"
        return 1
    fi

    local magic
    magic=$(head -c 4 "$fw_path")
    if [ "$magic" != "XMan" ] && [ "$magic" != "\$AE1" ]; then
        echo "FAIL: invalid manifest magic ($magic)"
        return 1
    fi

    local sha
    sha=$(shasum -a 256 "$fw_path" | awk '{print $1}')
    if [ "$sha" != "$expected_sha" ]; then
        echo "FAIL: sha256 mismatch ($sha)"
        return 1
    fi

    echo "OK"
    return 0
}

# T2.5.1: Truncated firmware file rejection
TRUNC_FW="$TEMP_DIR/truncated.ri"
head -c 1000 "$FIRMWARE_DIR/intel/sof-rpl.ri" > "$TRUNC_FW"
if validate_firmware_binary "$TRUNC_FW" > /dev/null 2>&1; then
    record_fail "T2.5.1" "Truncated firmware unexpectedly accepted" "must fail size check"
else
    record_pass "T2.5.1" "Truncated firmware is cleanly rejected" "size check verified"
fi

# T2.5.2: Corrupted extended manifest magic rejection
BAD_MAGIC_FW="$TEMP_DIR/bad_magic.ri"
cp "$FIRMWARE_DIR/intel/sof-rpl.ri" "$BAD_MAGIC_FW"
printf "BADM" | dd of="$BAD_MAGIC_FW" bs=1 count=4 conv=notrunc > /dev/null 2>&1
if validate_firmware_binary "$BAD_MAGIC_FW" > /dev/null 2>&1; then
    record_fail "T2.5.2" "Firmware with corrupt magic header unexpectedly accepted" "must fail magic check"
else
    record_pass "T2.5.2" "Corrupt firmware magic header is cleanly rejected" "magic check verified"
fi

# T2.5.3: Checksum mismatch detection on single-byte modification
TAMPERED_FW="$TEMP_DIR/tampered.ri"
cp "$FIRMWARE_DIR/intel/sof-rpl.ri" "$TAMPERED_FW"
printf "\xFF" | dd of="$TAMPERED_FW" bs=1 seek=100 count=1 conv=notrunc > /dev/null 2>&1
if validate_firmware_binary "$TAMPERED_FW" > /dev/null 2>&1; then
    record_fail "T2.5.3" "Tampered firmware unexpectedly passed integrity validation" "sha256 should fail"
else
    record_pass "T2.5.3" "Single-byte tampered firmware fails SHA-256 integrity validation" "tamper detection verified"
fi

# T2.5.4: Oversized firmware binary rejection (> 1MB)
BIG_FW="$TEMP_DIR/oversized.ri"
cat "$FIRMWARE_DIR/intel/sof-rpl.ri" "$FIRMWARE_DIR/intel/sof-rpl.ri" > "$BIG_FW"
if validate_firmware_binary "$BIG_FW" > /dev/null 2>&1; then
    record_fail "T2.5.4" "Oversized firmware binary unexpectedly accepted" "size check should fail"
else
    record_pass "T2.5.4" "Oversized firmware binary is cleanly rejected" "boundary check verified"
fi

# T2.5.5: Corrupt C-header array syntax detection in fw_bin.h
BAD_HEADER="$TEMP_DIR/bad_fw_bin.h"
cat << 'EOF' > "$BAD_HEADER"
const unsigned char kSofRplRi[] = { 0x58, 0x4d, ; // syntax error
const unsigned int kSofRplRiSize = 525056;
EOF
if clang -x c -fsyntax-only -c "$BAD_HEADER" -o /dev/null > /dev/null 2>&1; then
    record_fail "T2.5.5" "Corrupt C header syntax unexpectedly passed clang syntax check" "must fail syntax"
else
    record_pass "T2.5.5" "Corrupt C header array syntax is cleanly detected by compiler" "syntax validation verified"
fi

print_summary "Tier 2 Feature 5 (Firmware Integration Boundary)"
exit $?
