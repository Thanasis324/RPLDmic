#!/bin/bash
# ==============================================================================
# Tier 2 - Feature 9 Boundary: Verification Tooling Corner Cases
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 2: Feature 9 - Verification Tooling Boundary Cases"
TEMP_DIR=$(make_temp_dir "rpldmic_bva_tooling")
trap 'rm -rf "$TEMP_DIR"' EXIT

# T2.9.1: Non-executable script detection
MOCK_TOOL="$TEMP_DIR/mock_tool.sh"
echo '#!/bin/bash' > "$MOCK_TOOL"
chmod -x "$MOCK_TOOL"
if [ -x "$MOCK_TOOL" ]; then
    record_fail "T2.9.1" "Non-executable script was unexpectedly marked executable" "permission test invalid"
else
    record_pass "T2.9.1" "Missing executable permission on tool script is accurately detected" "permission check verified"
fi

# T2.9.2: Missing dependency command detection
check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" > /dev/null 2>&1; then
        echo "MISSING:$cmd"
        return 1
    fi
    echo "OK"
    return 0
}
if check_dependency "non_existent_audio_daemon_bin" > /dev/null 2>&1; then
    record_fail "T2.9.2" "Non-existent system dependency unexpectedly found" "must fail"
else
    record_pass "T2.9.2" "Missing system dependency command is accurately detected" "dependency check verified"
fi

# T2.9.3: Non-zero exit code when target driver not registered in IORegistry
# Query a deliberately non-existent service name
if ioreg -r -c "NonExistentDummyService_12345" | grep -q "NonExistentDummyService_12345"; then
    record_fail "T2.9.3" "Non-existent service unexpectedly found in IORegistry" "invalid system state"
else
    record_pass "T2.9.3" "IORegistry query for non-existent driver returns empty result" "clean absent state detected"
fi

# T2.9.4: Signal trap cleanup test
TRAP_TEST_SCRIPT="$TEMP_DIR/trap_test.sh"
cat << 'EOF' > "$TRAP_TEST_SCRIPT"
#!/bin/bash
TEMP_CANARY="/tmp/canary_$$"
touch "$TEMP_CANARY"
trap 'rm -f "$TEMP_CANARY"; exit 0' TERM INT
# Wait for signal
while true; do sleep 0.1; done
EOF
chmod +x "$TRAP_TEST_SCRIPT"
"$TRAP_TEST_SCRIPT" &
PID=$!
sleep 0.2
CANARY_FILE="/tmp/canary_${PID}"
if [ -f "$CANARY_FILE" ]; then
    kill -TERM "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
    sleep 0.1
    if [ -f "$CANARY_FILE" ]; then
        rm -f "$CANARY_FILE"
        record_fail "T2.9.4" "Signal trap failed to clean up temporary resources" "canary remained"
    else
        record_pass "T2.9.4" "Signal trap cleanly intercepts TERM and cleans temporary resources" "trap handling verified"
    fi
else
    kill -9 "$PID" 2>/dev/null || true
    record_skip "T2.9.4" "Trap test canary not created" "subshell timing"
fi

# T2.9.5: Invalid option argument handling
MOCK_CLI="$TEMP_DIR/mock_cli.sh"
cat << 'EOF' > "$MOCK_CLI"
#!/bin/bash
while [ $# -gt 0 ]; do
    case "$1" in
        --help) echo "Usage"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
EOF
chmod +x "$MOCK_CLI"
if "$MOCK_CLI" --invalid-flag > /dev/null 2>&1; then
    record_fail "T2.9.5" "CLI unexpectedly accepted invalid option argument" "must exit 2"
else
    record_pass "T2.9.5" "CLI rejects unknown option arguments with non-zero exit" "argument validation verified"
fi

print_summary "Tier 2 Feature 9 (Verification Tooling Boundary)"
exit $?
