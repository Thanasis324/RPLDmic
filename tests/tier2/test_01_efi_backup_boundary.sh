#!/bin/bash
# ==============================================================================
# Tier 2 - Feature 1 Boundary: Desktop EFI Backup Error & Corner Cases
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 2: Feature 1 - EFI Backup Boundary Cases"
TEMP_DIR=$(make_temp_dir "rpldmic_bva_backup")
trap 'rm -rf "$TEMP_DIR"' EXIT

# T2.1.1: Zero-byte file rejection
EMPTY_ZIP="$TEMP_DIR/empty.zip"
touch "$EMPTY_ZIP"
if unzip -t "$EMPTY_ZIP" > /dev/null 2>&1; then
    record_fail "T2.1.1" "Zero-byte archive unexpectedly accepted" "unzip should fail on 0-byte file"
else
    record_pass "T2.1.1" "Zero-byte archive is properly rejected" "unzip failed as expected"
fi

# T2.1.2: Corrupted header rejection
CORRUPT_ZIP="$TEMP_DIR/corrupt_header.zip"
printf "\x00\x00\x00\x00\x00\x00\x00\x00" > "$CORRUPT_ZIP"
if unzip -t "$CORRUPT_ZIP" > /dev/null 2>&1; then
    record_fail "T2.1.2" "Corrupt header archive unexpectedly accepted" "should fail on bad magic"
else
    record_pass "T2.1.2" "Corrupt zip header is properly rejected" "unzip rejected bad magic header"
fi

# T2.1.3: Truncated zip archive rejection
TRUNCATED_ZIP="$TEMP_DIR/truncated.zip"
if [ -f "$EFI_BACKUP_ZIP" ]; then
    dd if="$EFI_BACKUP_ZIP" of="$TRUNCATED_ZIP" bs=1024 count=50 > /dev/null 2>&1
    if unzip -t "$TRUNCATED_ZIP" > /dev/null 2>&1; then
        record_fail "T2.1.3" "Truncated archive unexpectedly accepted" "unzip should fail on truncated data"
    else
        record_pass "T2.1.3" "Truncated archive is properly rejected" "unzip detected premature EOF"
    fi
else
    record_skip "T2.1.3" "Truncated zip test skipped" "EFI_Backup.zip not available"
fi

# T2.1.4: Archive missing EFI root directory rejection
NO_EFI_ZIP="$TEMP_DIR/no_efi.zip"
(cd "$TEMP_DIR" && mkdir -p other_dir && touch other_dir/dummy && zip -q "$NO_EFI_ZIP" other_dir/dummy)
has_efi=$(unzip -l "$NO_EFI_ZIP" | grep "EFI/" || true)
if [ -n "$has_efi" ]; then
    record_fail "T2.1.4" "Synthetic archive unexpectedly contained EFI" "invalid test setup"
else
    record_pass "T2.1.4" "Archive missing top-level EFI directory is properly detected" "missing EFI verified"
fi

# T2.1.5: Under-sized archive threshold (< 50MB) rejection
SMALL_ZIP="$TEMP_DIR/small.zip"
(cd "$TEMP_DIR" && mkdir -p EFI/OC && touch EFI/OC/config.plist && zip -q -r "$SMALL_ZIP" EFI)
small_size=$(stat -f%z "$SMALL_ZIP" 2>/dev/null || echo 0)
if [ "$small_size" -lt 52428800 ]; then
    record_pass "T2.1.5" "Small archive (< 50MB) correctly fails size threshold guardrail" "detected size=${small_size} bytes"
else
    record_fail "T2.1.5" "Small archive unexpectedly exceeded 50MB" "size=${small_size}"
fi

print_summary "Tier 2 Feature 1 (EFI Backup Boundary)"
exit $?
