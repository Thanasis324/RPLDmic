#!/bin/bash
# ==============================================================================
# Tier 4 - Scenario 1: End-to-End Driver Build & Release Packaging Simulation
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 4: Scenario 1 - End-to-End Build & Release Packaging Simulation"
TEMP_DIR=$(make_temp_dir "rpldmic_sim_build")
trap 'rm -rf "$TEMP_DIR"' EXIT

# T4.1: Test full build workflow and packaging
# Verify both kext and hal build targets can produce valid release zip packages
kext_built=false
hal_built=false

# Check kext build artifact
if [ -f "$KEXT_DIR/build/RPLDmic.kext/Contents/MacOS/RPLDmic" ] || [ -f "$KEXT_DIR/RPLDmic.kext/Contents/MacOS/RPLDmic" ]; then
    kext_built=true
fi

# Check HAL build artifact
if [ -f "$HAL_DIR/build/RPLDmic.driver/Contents/MacOS/RPLDmic" ] || [ -f "$HAL_DIR/RPLDmic.driver/Contents/MacOS/RPLDmic" ]; then
    hal_built=true
fi

if [ "$kext_built" = true ] && [ "$hal_built" = true ]; then
    # Test creating release package in temp dir
    PKG_DIR="$TEMP_DIR/RPLDmic-Release"
    mkdir -p "$PKG_DIR"
    cp -R "$KEXT_DIR/build/RPLDmic.kext" "$PKG_DIR/" 2>/dev/null || cp -R "$KEXT_DIR/RPLDmic.kext" "$PKG_DIR/"
    cp -R "$HAL_DIR/build/RPLDmic.driver" "$PKG_DIR/" 2>/dev/null || cp -R "$HAL_DIR/RPLDmic.driver" "$PKG_DIR/"
    cp "$PROJECT_ROOT/README.md" "$PKG_DIR/"
    cp "$PROJECT_ROOT/LICENSE" "$PKG_DIR/"

    ZIP_OUT="$TEMP_DIR/RPLDmic-Release.zip"
    (cd "$TEMP_DIR" && zip -q -r "$ZIP_OUT" "RPLDmic-Release")

    if [ -f "$ZIP_OUT" ] && unzip -t "$ZIP_OUT" > /dev/null 2>&1; then
        pkg_size=$(stat -f%z "$ZIP_OUT")
        record_pass "T4.1" "End-to-end driver build and release packaging simulation succeeds" "release zip size=${pkg_size} bytes"
    else
        record_fail "T4.1" "Release package creation failed" "archive invalid"
    fi
else
    record_fail "T4.1" "End-to-end build artifacts missing" "kext_built=$kext_built, hal_built=$hal_built"
fi

print_summary "Tier 4 Scenario 1 (Build & Packaging)"
exit $?
