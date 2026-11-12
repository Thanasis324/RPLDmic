#!/bin/bash
# ==============================================================================
# Tier 1 - Feature 7: EFI & HAL Staging Verification
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 1: Feature 7 - EFI & HAL Staging Verification"

# T1.7.1: RPLDmic.kext staging check in /Volumes/EFI/EFI/OC/Kexts/
STAGED_KEXT="$EFI_OC_DIR/Kexts/RPLDmic.kext"
if [ -d "$STAGED_KEXT" ]; then
    record_pass "T1.7.1" "RPLDmic.kext is staged in OpenCore Kexts directory" "$STAGED_KEXT"
else
    record_fail "T1.7.1" "RPLDmic.kext not found in OpenCore Kexts directory" "$STAGED_KEXT missing (worker_m4 staging pending)"
fi

# T1.7.2: HAL installation script exists and is executable
INSTALL_HAL="$HAL_DIR/install-hal.sh"
if [ -f "$INSTALL_HAL" ] && [ -x "$INSTALL_HAL" ] && [ -s "$INSTALL_HAL" ]; then
    record_pass "T1.7.2" "hal/install-hal.sh exists, is non-empty, and executable" "permissions verified"
else
    record_fail "T1.7.2" "hal/install-hal.sh missing or not executable" "$INSTALL_HAL"
fi

# T1.7.3: HAL uninstallation script exists and is executable
UNINSTALL_HAL="$HAL_DIR/uninstall-hal.sh"
if [ -f "$UNINSTALL_HAL" ] && [ -x "$UNINSTALL_HAL" ] && [ -s "$UNINSTALL_HAL" ]; then
    record_pass "T1.7.3" "hal/uninstall-hal.sh exists, is non-empty, and executable" "permissions verified"
else
    record_fail "T1.7.3" "hal/uninstall-hal.sh missing or not executable" "$UNINSTALL_HAL"
fi

# T1.7.4: install-hal.sh targets /Library/Audio/Plug-Ins/HAL and triggers coreaudiod reload
if [ -f "$INSTALL_HAL" ]; then
    targets_hal=false
    reloads_daemon=false
    if grep -q "/Library/Audio/Plug-Ins/HAL" "$INSTALL_HAL"; then
        targets_hal=true
    fi
    if grep -q "coreaudiod" "$INSTALL_HAL"; then
        reloads_daemon=true
    fi

    if [ "$targets_hal" = true ] && [ "$reloads_daemon" = true ]; then
        record_pass "T1.7.4" "install-hal.sh targets /Library/Audio/Plug-Ins/HAL and reloads coreaudiod" "staging flow verified"
    else
        record_fail "T1.7.4" "install-hal.sh missing required staging actions" "targets_hal=$targets_hal reloads_daemon=$reloads_daemon"
    fi
else
    record_fail "T1.7.4" "install-hal.sh script missing" "$INSTALL_HAL not found"
fi

# T1.7.5: EFI volume accessibility and OC hierarchy
if [ -d "$EFI_OC_DIR" ] && [ -f "$EFI_OC_DIR/OpenCore.efi" ]; then
    record_pass "T1.7.5" "EFI volume is mounted and OpenCore structure is accessible" "$EFI_OC_DIR verified"
else
    record_fail "T1.7.5" "EFI volume or OpenCore hierarchy missing" "$EFI_OC_DIR unmounted or invalid"
fi

print_summary "Tier 1 Feature 7 (EFI & HAL Staging)"
exit $?
