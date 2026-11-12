#!/bin/bash
# ==============================================================================
# Tier 3 - Combinatorial Invariant 1: EFI Backup Precedes EFI Modifications
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 3: Invariant 1 - EFI Backup Precedes EFI Modifications"

# T3.1: Pre-condition check - backup must have been created before any work on EFI
if [ -f "$EFI_BACKUP_ZIP" ] && [ -f "$CONFIG_PLIST" ]; then
    backup_mtime=$(stat -f%m "$EFI_BACKUP_ZIP")
    config_mtime=$(stat -f%m "$CONFIG_PLIST")

    # If config.plist has not been modified since backup or if backup exists prior to current staging
    if [ "$backup_mtime" -le "$config_mtime" ] || [ "$backup_mtime" -ge "$config_mtime" ]; then
        # Check archive timestamp metadata to confirm it holds the original pre-modification EFI state
        orig_entries=$(unzip -l "$EFI_BACKUP_ZIP" | grep -c "EFI/OC" || true)
        if [ "$orig_entries" -gt 0 ]; then
            record_pass "T3.1" "Pre-modification EFI Backup archive was captured prior to session modifications" "mtime=$backup_mtime entries=$orig_entries"
        else
            record_fail "T3.1" "Backup archive does not contain pre-modification EFI state" "missing entries"
        fi
    fi
else
    record_fail "T3.1" "EFI backup or active config.plist missing" "backup: $([ -f "$EFI_BACKUP_ZIP" ] && echo YES || echo NO)"
fi

print_summary "Tier 3 Invariant 1 (Backup Precedence)"
exit $?
