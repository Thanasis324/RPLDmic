#!/bin/bash
# ==============================================================================
# Tier 1 - Feature 4: Kext Build & Architecture Verification
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 1: Feature 4 - Kext Build & Architecture Verification"

# Locate RPLDmic.kext
KEXT_BUNDLE=""
for candidate in \
    "$KEXT_DIR/build/RPLDmic.kext" \
    "$KEXT_DIR/RPLDmic.kext" \
    "$EFI_OC_DIR/Kexts/RPLDmic.kext"; do
    if [ -d "$candidate" ]; then
        KEXT_BUNDLE="$candidate"
        break
    fi
done

# If not found yet, check if make can build it
if [ -z "$KEXT_BUNDLE" ] && [ -f "$KEXT_DIR/Makefile" ]; then
    log_info "RPLDmic.kext not pre-built; attempting build via make -C $KEXT_DIR..."
    make -C "$KEXT_DIR" > /dev/null 2>&1 || true
    for candidate in "$KEXT_DIR/build/RPLDmic.kext" "$KEXT_DIR/RPLDmic.kext"; do
        if [ -d "$candidate" ]; then
            KEXT_BUNDLE="$candidate"
            break
        fi
    done
fi

# T1.4.1: Kext bundle existence
if [ -n "$KEXT_BUNDLE" ] && [ -d "$KEXT_BUNDLE" ]; then
    record_pass "T1.4.1" "RPLDmic.kext bundle exists" "found at $KEXT_BUNDLE"
else
    record_fail "T1.4.1" "RPLDmic.kext bundle not found" "neither pre-built nor staged"
fi

# T1.4.2: Mach-O binary existence
MACHO_BIN=""
if [ -n "$KEXT_BUNDLE" ] && [ -f "$KEXT_BUNDLE/Contents/MacOS/RPLDmic" ]; then
    MACHO_BIN="$KEXT_BUNDLE/Contents/MacOS/RPLDmic"
    record_pass "T1.4.2" "RPLDmic Mach-O binary exists inside bundle" "$MACHO_BIN"
else
    record_fail "T1.4.2" "RPLDmic Mach-O binary missing inside bundle" "Contents/MacOS/RPLDmic not found"
fi

# T1.4.3: Architecture validation (strictly x86_64)
if [ -n "$MACHO_BIN" ] && [ -f "$MACHO_BIN" ]; then
    file_info=$(file "$MACHO_BIN")
    if echo "$file_info" | grep -q "Mach-O 64-bit" && echo "$file_info" | grep -q "x86_64"; then
        record_pass "T1.4.3" "Mach-O binary targets x86_64 architecture" "Mach-O 64-bit kext x86_64"
    else
        record_fail "T1.4.3" "Mach-O binary is not x86_64" "$file_info"
    fi
else
    record_fail "T1.4.3" "Architecture check failed" "binary missing"
fi

# T1.4.4: Binary size > 50KB and non-empty
if [ -n "$MACHO_BIN" ] && [ -f "$MACHO_BIN" ]; then
    assert_file_size_gt "T1.4.4" "RPLDmic binary size exceeds 50KB" "$MACHO_BIN" 51200
else
    record_fail "T1.4.4" "Binary size check failed" "binary missing"
fi

# T1.4.5: Valid Info.plist with bundle identifier
if [ -n "$KEXT_BUNDLE" ] && [ -f "$KEXT_BUNDLE/Contents/Info.plist" ]; then
    plist_path="$KEXT_BUNDLE/Contents/Info.plist"
    lint_out=$(plutil -lint "$plist_path" 2>&1 || true)
    bundle_id=$(python3 -c "
import plistlib
try:
    with open('$plist_path', 'rb') as f:
        pl = plistlib.load(f)
    print(pl.get('CFBundleIdentifier', ''))
except Exception:
    pass
")
    if echo "$lint_out" | grep -q "OK" && [ "$bundle_id" = "org.thesofproject.RPLDmic" ]; then
        record_pass "T1.4.5" "kext Info.plist is valid XML with CFBundleIdentifier org.thesofproject.RPLDmic" "id=$bundle_id"
    else
        record_fail "T1.4.5" "kext Info.plist validation failed" "lint: $lint_out, bundle_id: $bundle_id"
    fi
else
    record_fail "T1.4.5" "kext Info.plist check failed" "bundle or plist missing"
fi

print_summary "Tier 1 Feature 4 (Kext Build & Architecture)"
exit $?
