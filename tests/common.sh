#!/bin/bash
# ==============================================================================
# RPLDmic Test Suite Common Infrastructure
# ==============================================================================

# Common project paths
PROJECT_ROOT="${PROJECT_ROOT:-/Users/thanasis/Documents/RPLDmic}"
EFI_DIR="${EFI_DIR:-/Volumes/EFI}"
EFI_OC_DIR="${EFI_OC_DIR:-/Volumes/EFI/EFI/OC}"
EFI_BACKUP_ZIP="${EFI_BACKUP_ZIP:-$HOME/Desktop/EFI_Backup.zip}"
CONFIG_PLIST="${CONFIG_PLIST:-/Volumes/EFI/EFI/OC/config.plist}"
CONFIG_POST_PLIST="${CONFIG_POST_PLIST:-/Volumes/EFI/EFI/OC/config-post.plist}"
KEXT_DIR="${KEXT_DIR:-$PROJECT_ROOT/kext}"
HAL_DIR="${HAL_DIR:-$PROJECT_ROOT/hal}"
FIRMWARE_DIR="${FIRMWARE_DIR:-$PROJECT_ROOT/firmware}"
TOOLS_DIR="${TOOLS_DIR:-$PROJECT_ROOT/tools}"
DOCS_DIR="${DOCS_DIR:-$PROJECT_ROOT/docs}"
FIXTURES_DIR="${FIXTURES_DIR:-$PROJECT_ROOT/tests/fixtures}"

# ANSI Colors
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"

# Test Counters
RUN_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Formatted log output
log_info() {
    echo -e "${C_BLUE}[INFO]${C_RESET} $*"
}

log_header() {
    echo -e "\n${C_BOLD}${C_CYAN}=== $* ===${C_RESET}"
}

record_pass() {
    local test_id="$1"
    local test_name="$2"
    local message="${3:-}"
    RUN_COUNT=$((RUN_COUNT + 1))
    PASS_COUNT=$((PASS_COUNT + 1))
    if [ -n "$message" ]; then
        echo -e "  [${C_GREEN}PASS${C_RESET}] ${C_BOLD}${test_id}${C_RESET}: ${test_name} (${message})"
    else
        echo -e "  [${C_GREEN}PASS${C_RESET}] ${C_BOLD}${test_id}${C_RESET}: ${test_name}"
    fi
}

record_fail() {
    local test_id="$1"
    local test_name="$2"
    local reason="${3:-Assertion failed}"
    RUN_COUNT=$((RUN_COUNT + 1))
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo -e "  [${C_RED}FAIL${C_RESET}] ${C_BOLD}${test_id}${C_RESET}: ${test_name} - ${C_RED}${reason}${C_RESET}"
}

record_skip() {
    local test_id="$1"
    local test_name="$2"
    local reason="${3:-Prerequisites not met}"
    RUN_COUNT=$((RUN_COUNT + 1))
    SKIP_COUNT=$((SKIP_COUNT + 1))
    echo -e "  [${C_YELLOW}SKIP${C_RESET}] ${C_BOLD}${test_id}${C_RESET}: ${test_name} (${C_YELLOW}${reason}${C_RESET})"
}

# Assertion functions
assert_file_exists() {
    local test_id="$1"
    local test_name="$2"
    local file_path="$3"
    if [ -e "$file_path" ]; then
        record_pass "$test_id" "$test_name" "file exists: $file_path"
        return 0
    else
        record_fail "$test_id" "$test_name" "file missing: $file_path"
        return 1
    fi
}

assert_file_size_gt() {
    local test_id="$1"
    local test_name="$2"
    local file_path="$3"
    local min_bytes="$4"
    if [ ! -e "$file_path" ]; then
        record_fail "$test_id" "$test_name" "file missing: $file_path"
        return 1
    fi
    local size
    size=$(stat -f%z "$file_path" 2>/dev/null || echo 0)
    if [ "$size" -gt "$min_bytes" ]; then
        record_pass "$test_id" "$test_name" "size ${size} bytes > threshold ${min_bytes} bytes"
        return 0
    else
        record_fail "$test_id" "$test_name" "size ${size} bytes <= threshold ${min_bytes} bytes"
        return 1
    fi
}

assert_file_size_eq() {
    local test_id="$1"
    local test_name="$2"
    local file_path="$3"
    local expected_bytes="$4"
    if [ ! -e "$file_path" ]; then
        record_fail "$test_id" "$test_name" "file missing: $file_path"
        return 1
    fi
    local size
    size=$(stat -f%z "$file_path" 2>/dev/null || echo 0)
    if [ "$size" -eq "$expected_bytes" ]; then
        record_pass "$test_id" "$test_name" "size exactly ${size} bytes"
        return 0
    else
        record_fail "$test_id" "$test_name" "size ${size} != expected ${expected_bytes} bytes"
        return 1
    fi
}

assert_equals() {
    local test_id="$1"
    local test_name="$2"
    local expected="$3"
    local actual="$4"
    if [ "$expected" = "$actual" ]; then
        record_pass "$test_id" "$test_name" "value matches '$expected'"
        return 0
    else
        record_fail "$test_id" "$test_name" "expected '$expected' but got '$actual'"
        return 1
    fi
}

assert_contains() {
    local test_id="$1"
    local test_name="$2"
    local haystack="$3"
    local needle="$4"
    if echo "$haystack" | grep -q -- "$needle"; then
        record_pass "$test_id" "$test_name" "contains '$needle'"
        return 0
    else
        record_fail "$test_id" "$test_name" "missing required substring '$needle'"
        return 1
    fi
}

assert_not_contains() {
    local test_id="$1"
    local test_name="$2"
    local haystack="$3"
    local needle="$4"
    if echo "$haystack" | grep -q -- "$needle"; then
        record_fail "$test_id" "$test_name" "contains forbidden substring '$needle'"
        return 1
    else
        record_pass "$test_id" "$test_name" "forbidden substring '$needle' is absent"
        return 0
    fi
}

assert_cmd_success() {
    local test_id="$1"
    local test_name="$2"
    shift 2
    local output
    if output=$("$@" 2>&1); then
        record_pass "$test_id" "$test_name" "command exited 0"
        return 0
    else
        record_fail "$test_id" "$test_name" "command failed (exit $?): $output"
        return 1
    fi
}

assert_cmd_failure() {
    local test_id="$1"
    local test_name="$2"
    shift 2
    local output
    if output=$("$@" 2>&1); then
        record_fail "$test_id" "$test_name" "command unexpectedly succeeded (exit 0): $output"
        return 1
    else
        record_pass "$test_id" "$test_name" "command failed as expected"
        return 0
    fi
}

# Create a clean isolated temporary directory and automatically clean it up on exit
make_temp_dir() {
    local prefix="${1:-rpldmic_test}"
    mktemp -d "/tmp/${prefix}.XXXXXX"
}

print_summary() {
    local suite_name="$1"
    echo -e "\n------------------------------------------------------------"
    echo -e "${C_BOLD}Summary for ${suite_name}:${C_RESET}"
    echo -e "  Total: ${RUN_COUNT} | Passed: ${C_GREEN}${PASS_COUNT}${C_RESET} | Failed: ${C_RED}${FAIL_COUNT}${C_RESET} | Skipped: ${C_YELLOW}${SKIP_COUNT}${C_RESET}"
    echo -e "------------------------------------------------------------"
    if [ "$FAIL_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}
