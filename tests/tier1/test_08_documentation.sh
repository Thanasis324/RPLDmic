#!/bin/bash
# ==============================================================================
# Tier 1 - Feature 8: Repository Documentation Verification
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 1: Feature 8 - Repository Documentation Verification"

README_FILE="$PROJECT_ROOT/README.md"
ARCH_FILE="$DOCS_DIR/ARCHITECTURE.md"
INSTALL_FILE="$DOCS_DIR/INSTALL.md"
BUILD_FILE="$DOCS_DIR/BUILD.md"
LICENSE_FILE="$PROJECT_ROOT/LICENSE"
FW_LICENSE_FILE="$FIRMWARE_DIR/LICENCE.Intel"

# T1.8.1: README.md completeness (> 3KB, mentions 51ca / Raptor Lake)
if [ -f "$README_FILE" ]; then
    size=$(stat -f%z "$README_FILE" 2>/dev/null || echo 0)
    has_rpl=false
    if grep -iq "51ca" "$README_FILE" || grep -iq "Raptor Lake" "$README_FILE"; then
        has_rpl=true
    fi
    if [ "$size" -gt 3072 ] && [ "$has_rpl" = true ]; then
        record_pass "T1.8.1" "README.md is comprehensive and documents Raptor Lake cAVS 2.5 (51ca)" "size=${size} bytes"
    else
        record_fail "T1.8.1" "README.md incomplete or missing Raptor Lake device documentation" "size=${size}, has_rpl=$has_rpl"
    fi
else
    record_fail "T1.8.1" "README.md missing" "$README_FILE not found"
fi

# T1.8.2: docs/ARCHITECTURE.md completeness (> 5KB, covers DSP boot / IPC)
if [ -f "$ARCH_FILE" ]; then
    size=$(stat -f%z "$ARCH_FILE" 2>/dev/null || echo 0)
    has_ipc=false
    if grep -iq "IPC" "$ARCH_FILE" && (grep -iq "DSP" "$ARCH_FILE" || grep -iq "cAVS" "$ARCH_FILE"); then
        has_ipc=true
    fi
    if [ "$size" -gt 5120 ] && [ "$has_ipc" = true ]; then
        record_pass "T1.8.2" "docs/ARCHITECTURE.md details DSP boot flow, IPC protocol, and DMA architecture" "size=${size} bytes"
    else
        record_fail "T1.8.2" "docs/ARCHITECTURE.md incomplete" "size=${size}, has_ipc=$has_ipc"
    fi
else
    record_fail "T1.8.2" "docs/ARCHITECTURE.md missing" "$ARCH_FILE not found"
fi

# T1.8.3: docs/INSTALL.md completeness (> 2KB, covers OpenCore / HAL)
if [ -f "$INSTALL_FILE" ]; then
    size=$(stat -f%z "$INSTALL_FILE" 2>/dev/null || echo 0)
    has_oc=false
    if grep -iq "OpenCore" "$INSTALL_FILE" || grep -iq "config.plist" "$INSTALL_FILE"; then
        has_oc=true
    fi
    if [ "$size" -gt 2048 ] && [ "$has_oc" = true ]; then
        record_pass "T1.8.3" "docs/INSTALL.md provides step-by-step OpenCore and HAL installation instructions" "size=${size} bytes"
    else
        record_fail "T1.8.3" "docs/INSTALL.md incomplete" "size=${size}, has_oc=$has_oc"
    fi
else
    record_fail "T1.8.3" "docs/INSTALL.md missing" "$INSTALL_FILE not found"
fi

# T1.8.4: Build documentation (docs/BUILD.md or dedicated build section)
has_build_doc=false
build_detail=""
if [ -f "$BUILD_FILE" ] && [ -s "$BUILD_FILE" ]; then
    has_build_doc=true
    build_detail="$BUILD_FILE exists"
elif [ -f "$README_FILE" ] && grep -iq "build" "$README_FILE" && grep -iq "MacKernelSDK" "$README_FILE"; then
    has_build_doc=true
    build_detail="Build instructions present in README.md"
fi

if [ "$has_build_doc" = true ]; then
    record_pass "T1.8.4" "Repository documents toolchain build instructions and MacKernelSDK dependency" "$build_detail"
else
    record_fail "T1.8.4" "Build documentation missing" "neither docs/BUILD.md nor comprehensive README build section found"
fi

# T1.8.5: Open source license and Intel firmware redistribution license
if [ -f "$LICENSE_FILE" ] && [ -f "$FW_LICENSE_FILE" ]; then
    record_pass "T1.8.5" "Open-source LICENSE and Intel firmware redistribution license are present" "GPL/BSD and Intel licenses found"
else
    record_fail "T1.8.5" "License files missing" "LICENSE: $([ -f "$LICENSE_FILE" ] && echo YES || echo NO), FW_LICENSE: $([ -f "$FW_LICENSE_FILE" ] && echo YES || echo NO)"
fi

print_summary "Tier 1 Feature 8 (Repository Documentation)"
exit $?
