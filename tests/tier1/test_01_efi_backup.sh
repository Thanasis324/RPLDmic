#!/bin/bash
# ==============================================================================
# Tier 1 - Feature 1: Desktop EFI Backup Verification
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 1: Feature 1 - Desktop EFI Backup Verification"

# T1.1.1: Backup archive existence
assert_file_exists "T1.1.1" "Desktop EFI Backup archive exists" "$EFI_BACKUP_ZIP"

# T1.1.2: Backup size > 50MB (52428800 bytes)
assert_file_size_gt "T1.1.2" "Desktop EFI Backup archive size exceeds 50MB threshold" "$EFI_BACKUP_ZIP" 52428800

# T1.1.3: Archive integrity via unzip -t
if [ -f "$EFI_BACKUP_ZIP" ]; then
    if unzip -t "$EFI_BACKUP_ZIP" > /dev/null 2>&1; then
        record_pass "T1.1.3" "Zip archive integrity test passes (unzip -t)" "zero decompression errors"
    else
        record_fail "T1.1.3" "Zip archive integrity test failed" "corrupt or truncated zip"
    fi
else
    record_fail "T1.1.3" "Zip archive integrity test failed" "file missing"
fi

# T1.1.4: Archive contains EFI/ directory hierarchy
if [ -f "$EFI_BACKUP_ZIP" ]; then
    if unzip -l "$EFI_BACKUP_ZIP" | grep "EFI/" > /dev/null; then
        record_pass "T1.1.4" "Archive contains top-level EFI directory hierarchy" "EFI/ found in zip index"
    else
        record_fail "T1.1.4" "Archive missing EFI directory hierarchy" "EFI/ not found in zip"
    fi
else
    record_fail "T1.1.4" "Archive directory check failed" "file missing"
fi

# T1.1.5: Archive contains critical OpenCore boot files
if [ -f "$EFI_BACKUP_ZIP" ]; then
    if unzip -l "$EFI_BACKUP_ZIP" | grep "EFI/OC/OpenCore.efi" > /dev/null && unzip -l "$EFI_BACKUP_ZIP" | grep "EFI/OC/config.plist" > /dev/null; then
        record_pass "T1.1.5" "Archive contains critical OpenCore boot components" "OpenCore.efi and config.plist verified"
    else
        record_fail "T1.1.5" "Archive missing OpenCore.efi or config.plist" "incomplete EFI backup"
    fi
else
    record_fail "T1.1.5" "Archive component check failed" "file missing"
fi

print_summary "Tier 1 Feature 1 (EFI Backup)"
exit $?
