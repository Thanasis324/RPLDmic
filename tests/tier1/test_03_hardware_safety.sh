#!/bin/bash
# ==============================================================================
# Tier 1 - Feature 3: Hardware Safety Guardrails Verification
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 1: Feature 3 - Hardware Safety Guardrails Verification"

# Read boot-args from config.plist
BOOT_ARGS=""
if [ -f "$CONFIG_PLIST" ]; then
    BOOT_ARGS=$(python3 -c "
import plistlib
try:
    with open('$CONFIG_PLIST', 'rb') as f:
        pl = plistlib.load(f)
    print(pl.get('NVRAM', {}).get('Add', {}).get('7C436110-AB2A-4BBB-A880-FE41995C9F82', {}).get('boot-args', ''))
except Exception:
    pass
")
fi

# T1.3.1: Host Preemptive Scheduler (ngreenSched=5)
assert_contains "T1.3.1" "boot-args specifies ngreenSched=5 (Host Preemptive Scheduler)" "$BOOT_ARGS" "ngreenSched=5"

# T1.3.2: Forbidden scheduler ngreenSched=4 is absent
assert_not_contains "T1.3.2" "boot-args does NOT contain forbidden ngreenSched=4" "$BOOT_ARGS" "ngreenSched=4"

# T1.3.3: Backlight PWM calibrations (ngreenblmax=19393 and ngreenblmin=200)
if echo "$BOOT_ARGS" | grep -q "ngreenblmax=19393" && echo "$BOOT_ARGS" | grep -q "ngreenblmin=200"; then
    record_pass "T1.3.3" "boot-args preserves Innolux panel backlight calibrations" "ngreenblmax=19393, ngreenblmin=200"
else
    record_fail "T1.3.3" "boot-args missing required backlight parameters" "ngreenblmax=19393 or ngreenblmin=200 missing"
fi

# T1.3.4: ACPI SSDT-PNLF.aml is present and enabled
if [ -f "$CONFIG_PLIST" ]; then
    pnlf_status=$(python3 -c "
import plistlib, sys
try:
    with open('$CONFIG_PLIST', 'rb') as f:
        pl = plistlib.load(f)
    acpi_add = pl.get('ACPI', {}).get('Add', [])
    for entry in acpi_add:
        if 'SSDT-PNLF.aml' in entry.get('Path', ''):
            if entry.get('Enabled', False):
                print('ENABLED')
                sys.exit(0)
            else:
                print('DISABLED')
                sys.exit(1)
    print('NOT_FOUND')
    sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1 || true)
    if [ "$pnlf_status" = "ENABLED" ]; then
        record_pass "T1.3.4" "ACPI -> Add contains enabled SSDT-PNLF.aml" "backlight ACPI patch active"
    else
        record_fail "T1.3.4" "SSDT-PNLF.aml not active in ACPI -> Add" "$pnlf_status"
    fi
else
    record_fail "T1.3.4" "config.plist missing" "cannot inspect ACPI section"
fi

# T1.3.5: PlatformInfo SMBIOS Mode stability
if [ -f "$CONFIG_PLIST" ]; then
    smbios_status=$(python3 -c "
import plistlib, sys
try:
    with open('$CONFIG_PLIST', 'rb') as f:
        pl = plistlib.load(f)
    mode = pl.get('PlatformInfo', {}).get('UpdateSMBIOSMode', '')
    custom_guid = pl.get('Kernel', {}).get('Quirks', {}).get('CustomSMBIOSGuid', None)
    if mode == 'Create' and custom_guid is False:
        print('PASS')
    else:
        print(f'MISMATCH: UpdateSMBIOSMode={mode}, Kernel->Quirks->CustomSMBIOSGuid={custom_guid}')
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1 || true)
    if [ "$smbios_status" = "PASS" ]; then
        record_pass "T1.3.5" "SMBIOS specifies UpdateSMBIOSMode=Create and CustomSMBIOSGuid=false" "avoids platform hang"
    else
        record_fail "T1.3.5" "SMBIOS configuration violates ThinkPad safety rules" "$smbios_status"
    fi
else
    record_fail "T1.3.5" "config.plist missing" "cannot inspect PlatformInfo"
fi

print_summary "Tier 1 Feature 3 (Hardware Safety Guardrails)"
exit $?
