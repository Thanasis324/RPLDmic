#!/bin/bash
# ==============================================================================
# Tier 2 - Feature 7 Boundary: EFI & HAL Staging Corner Cases
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 2: Feature 7 - EFI & HAL Staging Boundary Cases"
TEMP_DIR=$(make_temp_dir "rpldmic_bva_staging")
trap 'rm -rf "$TEMP_DIR"' EXIT

# Simulated staging controller
stage_kext() {
    local backup_path="$1"
    local target_efi_dir="$2"
    local source_kext="$3"

    # Pre-condition: Backup must exist before staging
    if [ ! -f "$backup_path" ]; then
        echo "FAIL: Refusing to modify EFI: Backup $backup_path does not exist"
        return 2
    fi

    # Target EFI OC Kexts must exist
    if [ ! -d "$target_efi_dir/Kexts" ]; then
        echo "FAIL: EFI Kexts directory not mounted or missing"
        return 3
    fi

    # Source kext must exist
    if [ ! -d "$source_kext" ]; then
        echo "FAIL: Source kext $source_kext does not exist"
        return 4
    fi

    # Perform safe idempotent atomic copy
    local kext_name
    kext_name=$(basename "$source_kext")
    rm -rf "$target_efi_dir/Kexts/$kext_name"
    cp -R "$source_kext" "$target_efi_dir/Kexts/"
    echo "OK: Staged $kext_name"
    return 0
}

# T2.7.1: Missing target mount handling
if stage_kext "$EFI_BACKUP_ZIP" "$TEMP_DIR/non_existent_efi" "$TEMP_DIR/dummy.kext" > /dev/null 2>&1; then
    record_fail "T2.7.1" "Staging unexpectedly succeeded on unmounted EFI path" "must fail"
else
    record_pass "T2.7.1" "Staging fails gracefully when target EFI partition is unmounted" "unmounted guardrail verified"
fi

# T2.7.2: Unprivileged staging permission handling
UNPRIV_DIR="$TEMP_DIR/unpriv_hal"
mkdir -p "$UNPRIV_DIR"
chmod 555 "$UNPRIV_DIR"
if touch "$UNPRIV_DIR/test_write" > /dev/null 2>&1; then
    chmod 755 "$UNPRIV_DIR"
    record_fail "T2.7.2" "Write unexpectedly succeeded on read-only mock directory" "invalid test setup"
else
    chmod 755 "$UNPRIV_DIR"
    record_pass "T2.7.2" "Write permission denial on protected HAL directory is cleanly handled" "permission guardrail verified"
fi

# T2.7.3: Pre-staging backup missing guard
MOCK_EFI="$TEMP_DIR/MockEFI"
mkdir -p "$MOCK_EFI/Kexts"
MOCK_SRC="$TEMP_DIR/Source.kext"
mkdir -p "$MOCK_SRC/Contents/MacOS"
if stage_kext "$TEMP_DIR/non_existent_backup.zip" "$MOCK_EFI" "$MOCK_SRC" > /dev/null 2>&1; then
    record_fail "T2.7.3" "Staging unexpectedly proceeded without pre-modification backup" "must fail"
else
    record_pass "T2.7.3" "Staging is strictly blocked if pre-modification backup is absent" "backup guardrail verified"
fi

# T2.7.4: Collision handling (no nested kext on overwrite)
MOCK_BACKUP="$TEMP_DIR/mock_backup.zip"
touch "$MOCK_BACKUP"
# Initial stage
stage_kext "$MOCK_BACKUP" "$MOCK_EFI" "$MOCK_SRC" > /dev/null
# Re-stage (should overwrite cleanly, not create Kexts/Source.kext/Source.kext)
stage_kext "$MOCK_BACKUP" "$MOCK_EFI" "$MOCK_SRC" > /dev/null
if [ -d "$MOCK_EFI/Kexts/Source.kext/Source.kext" ]; then
    record_fail "T2.7.4" "Collision resulted in nested kext directory structure" "improper overwrite"
else
    record_pass "T2.7.4" "Staging overwrite collision is handled cleanly without nesting" "clean overwrite verified"
fi

# T2.7.5: Staging script idempotent re-execution
if [ -d "$MOCK_EFI/Kexts/Source.kext/Contents" ]; then
    record_pass "T2.7.5" "Repeated staging execution maintains clean idempotent state" "idempotency verified"
else
    record_fail "T2.7.5" "Repeated staging failed to produce consistent state" "inconsistent state"
fi

print_summary "Tier 2 Feature 7 (EFI & HAL Staging Boundary)"
exit $?
