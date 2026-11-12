#!/bin/bash
# ==============================================================================
# RPLDmic End-to-End Test Runner
# Supported flags:
#   --all      Run all 4 tiers (Tier 1..4)
#   --tier1    Run Tier 1 (Feature Coverage: 9 features, 45 tests)
#   --tier2    Run Tier 2 (Boundary & Corner Cases: 9 features, 45 tests)
#   --tier3    Run Tier 3 (Cross-Feature Combinations: 9 pairwise/invariants)
#   --tier4    Run Tier 4 (Real-World Scenarios: 5 scenarios)
#   --help     Show usage
# ==============================================================================
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

RUN_T1=false
RUN_T2=false
RUN_T3=false
RUN_T4=false

if [ $# -eq 0 ]; then
    RUN_T1=true
    RUN_T2=true
    RUN_T3=true
    RUN_T4=true
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --all|-a)
            RUN_T1=true
            RUN_T2=true
            RUN_T3=true
            RUN_T4=true
            ;;
        --tier1|-1)
            RUN_T1=true
            ;;
        --tier2|-2)
            RUN_T2=true
            ;;
        --tier3|-3)
            RUN_T3=true
            ;;
        --tier4|-4)
            RUN_T4=true
            ;;
        --help|-h)
            echo "Usage: $0 [--all] [--tier1] [--tier2] [--tier3] [--tier4]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--all] [--tier1] [--tier2] [--tier3] [--tier4]" >&2
            exit 2
            ;;
    esac
    shift
done

TOTAL_RUN=0
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0

# Track failing test names
declare -a FAILED_TESTS=()

run_suite() {
    local script_path="$1"
    local suite_name
    suite_name=$(basename "$script_path")

    if [ ! -f "$script_path" ]; then
        echo "Error: test script $script_path not found" >&2
        return 1
    fi

    # Run script and capture stdout/stderr
    local output
    output=$("$script_path" 2>&1)
    local exit_code=$?
    echo "$output"

    # Parse output summary line: Total: X | Passed: Y | Failed: Z | Skipped: W
    local sum_line
    sum_line=$(echo "$output" | grep "Summary for " -A 1 | grep "Total:" || true)
    if [ -n "$sum_line" ]; then
        local clean_sum t p f s
        clean_sum=$(printf '%s\n' "$sum_line" | sed -E $'s/\x1b\\[[0-9;]*[a-zA-Z]//g')
        t=$(echo "$clean_sum" | awk -F'|' '{print $1}' | tr -dc '0-9')
        p=$(echo "$clean_sum" | awk -F'|' '{print $2}' | tr -dc '0-9')
        f=$(echo "$clean_sum" | awk -F'|' '{print $3}' | tr -dc '0-9')
        s=$(echo "$clean_sum" | awk -F'|' '{print $4}' | tr -dc '0-9')

        t=${t:-0}
        p=${p:-0}
        f=${f:-0}
        s=${s:-0}

        TOTAL_RUN=$((TOTAL_RUN + t))
        TOTAL_PASS=$((TOTAL_PASS + p))
        TOTAL_FAIL=$((TOTAL_FAIL + f))
        TOTAL_SKIP=$((TOTAL_SKIP + s))

        if [ "$f" -gt 0 ]; then
            FAILED_TESTS+=("$suite_name ($f failures)")
        fi
    else
        if [ "$exit_code" -ne 0 ]; then
            TOTAL_RUN=$((TOTAL_RUN + 1))
            TOTAL_FAIL=$((TOTAL_FAIL + 1))
            FAILED_TESTS+=("$suite_name (exit $exit_code)")
        else
            TOTAL_RUN=$((TOTAL_RUN + 1))
            TOTAL_PASS=$((TOTAL_PASS + 1))
        fi
    fi
}

echo "============================================================"
echo "          RPLDmic Comprehensive E2E Test Suite              "
echo "============================================================"
echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "Host: $(uname -smpr)"
echo "Project Root: $PROJECT_ROOT"
echo "Active EFI: /Volumes/EFI"
echo "============================================================"

START_TIME=$(date +%s)

# Tier 1
if [ "$RUN_T1" = true ]; then
    echo -e "\n==================== STARTING TIER 1 ===================="
    for t in "$TESTS_DIR"/tier1/test_*.sh; do
        if [ -f "$t" ]; then
            run_suite "$t"
        fi
    done
fi

# Tier 2
if [ "$RUN_T2" = true ]; then
    echo -e "\n==================== STARTING TIER 2 ===================="
    for t in "$TESTS_DIR"/tier2/test_*.sh; do
        if [ -f "$t" ]; then
            run_suite "$t"
        fi
    done
fi

# Tier 3
if [ "$RUN_T3" = true ]; then
    echo -e "\n==================== STARTING TIER 3 ===================="
    for t in "$TESTS_DIR"/tier3/test_*.sh; do
        if [ -f "$t" ]; then
            run_suite "$t"
        fi
    done
fi

# Tier 4
if [ "$RUN_T4" = true ]; then
    echo -e "\n==================== STARTING TIER 4 ===================="
    for t in "$TESTS_DIR"/tier4/test_*.sh; do
        if [ -f "$t" ]; then
            run_suite "$t"
        fi
    done
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo -e "\n============================================================"
echo "                   FINAL TEST RUN SUMMARY                   "
echo "============================================================"
echo "Total Test Assertions: $TOTAL_RUN"
echo "Passed:                $TOTAL_PASS"
echo "Failed:                $TOTAL_FAIL"
echo "Skipped:               $TOTAL_SKIP"
echo "Elapsed Time:          ${DURATION}s"
echo "============================================================"

if [ "$TOTAL_FAIL" -gt 0 ]; then
    echo -e "\nFailed Test Suites (${#FAILED_TESTS[@]}):"
    for ft in "${FAILED_TESTS[@]}"; do
        echo "  - $ft"
    done
    echo -e "\nOVERALL STATUS: FAILED ($TOTAL_FAIL failures)"
    exit 1
else
    echo -e "\nOVERALL STATUS: ALL TESTS PASSED (100% Pass Rate)"
    exit 0
fi
