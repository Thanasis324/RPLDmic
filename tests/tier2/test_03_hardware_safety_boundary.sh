#!/bin/bash
# ==============================================================================
# Tier 2 - Feature 3 Boundary: Hardware Safety Guardrail Violations
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 2: Feature 3 - Hardware Safety Guardrail Boundary Cases"

# Validation function simulating guardrail checker
validate_hardware_guardrails() {
    local boot_args="$1"
    local smbios_mode="${2:-Create}"
    local custom_guid="${3:-false}"

    # Check 1: ngreenSched must not be 4
    if echo "$boot_args" | grep -q "ngreenSched=4"; then
        echo "FAIL: forbidden ngreenSched=4 disables xeRecProc / xeRecList recovery"
        return 1
    fi

    # Check 2: ngreenSched must be 5
    if ! echo "$boot_args" | grep -q "ngreenSched=5"; then
        echo "FAIL: ngreenSched=5 is required for Host Preemptive Scheduler"
        return 1
    fi

    # Check 3 & 4: Backlight parameters
    local blmax blmin
    blmax=$(echo "$boot_args" | tr ' ' '\n' | grep '^ngreenblmax=' | cut -d= -f2 || true)
    blmin=$(echo "$boot_args" | tr ' ' '\n' | grep '^ngreenblmin=' | cut -d= -f2 || true)

    if [ -z "$blmax" ] || [ -z "$blmin" ]; then
        echo "FAIL: missing backlight parameters"
        return 1
    fi

    if [ "$blmin" -le 0 ]; then
        echo "FAIL: ngreenblmin ($blmin) must be positive (> 0) to avoid screen blackouts"
        return 1
    fi

    if [ "$blmax" -le "$blmin" ]; then
        echo "FAIL: ngreenblmax ($blmax) must be greater than ngreenblmin ($blmin)"
        return 1
    fi

    # Check 5: SMBIOS settings
    if [ "$smbios_mode" != "Create" ] || [ "$custom_guid" != "false" ]; then
        echo "FAIL: Lenovo ThinkPad requires UpdateSMBIOSMode=Create and CustomSMBIOSGuid=false"
        return 1
    fi

    echo "OK"
    return 0
}

# T2.3.1: Strict rejection of forbidden ngreenSched=4
if validate_hardware_guardrails "-v keepsyms=1 ngreenSched=4 ngreenblmax=19393 ngreenblmin=200" > /dev/null 2>&1; then
    record_fail "T2.3.1" "Forbidden ngreenSched=4 unexpectedly allowed" "must trigger guardrail failure"
else
    record_pass "T2.3.1" "Forbidden ngreenSched=4 is strictly rejected" "prevents watchdog reset hangs"
fi

# T2.3.2: Rejection of missing ngreenSched parameter
if validate_hardware_guardrails "-v keepsyms=1 ngreenblmax=19393 ngreenblmin=200" > /dev/null 2>&1; then
    record_fail "T2.3.2" "Missing ngreenSched unexpectedly allowed" "must require ngreenSched=5"
else
    record_pass "T2.3.2" "Missing ngreenSched is strictly rejected" "requires explicit scheduler policy"
fi

# T2.3.3: Backlight boundary inversion rejection (max < min)
if validate_hardware_guardrails "ngreenSched=5 ngreenblmax=100 ngreenblmin=200" > /dev/null 2>&1; then
    record_fail "T2.3.3" "Inverted backlight range (max < min) unexpectedly allowed" "must fail"
else
    record_pass "T2.3.3" "Inverted backlight range (max < min) is strictly rejected" "prevents PWM inversion"
fi

# T2.3.4: Backlight minimum floor zero / negative rejection (min <= 0)
if validate_hardware_guardrails "ngreenSched=5 ngreenblmax=19393 ngreenblmin=0" > /dev/null 2>&1; then
    record_fail "T2.3.4" "Zero backlight floor unexpectedly allowed" "must fail"
else
    record_pass "T2.3.4" "Zero or negative backlight minimum floor is strictly rejected" "prevents panel blackout"
fi

# T2.3.5: Invalid SMBIOS mode rejection
if validate_hardware_guardrails "ngreenSched=5 ngreenblmax=19393 ngreenblmin=200" "Custom" "true" > /dev/null 2>&1; then
    record_fail "T2.3.5" "Custom SMBIOS mode on ThinkPad unexpectedly allowed" "must require Create/false"
else
    record_pass "T2.3.5" "Non-Create SMBIOS mode on Lenovo ThinkPad is strictly rejected" "avoids ACPI stalls"
fi

print_summary "Tier 2 Feature 3 (Hardware Safety Boundary)"
exit $?
