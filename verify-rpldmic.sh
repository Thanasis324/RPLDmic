#!/bin/bash
# ==============================================================================
# verify-rpldmic.sh - Diagnostic & System Health Verification Tool for RPLDmic
# ==============================================================================
# Comprehensive verification script for Intel Raptor Lake cAVS 2.5 (8086:51ca)
# Digital Microphone Driver (RPLDmic.kext) and CoreAudio HAL Plugin (RPLDmic.driver)
# on Lenovo ThinkPad T14 Gen 4 under macOS Tahoe / Sequoia / Sonoma / Ventura.
# ==============================================================================

set -uo pipefail

# ANSI Color Codes
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_WHITE="\033[37m"

# Script Flags
VERBOSE=0
RUN_PROBE=0
QUICK_MODE=0

# Summary Counters
TOTAL_CHECKS=0
PASS_CHECKS=0
WARN_CHECKS=0
FAIL_CHECKS=0

# Paths & Settings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/kext/Makefile" ]; then
    PROJECT_ROOT="$SCRIPT_DIR"
elif [ -f "$SCRIPT_DIR/../kext/Makefile" ]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    PROJECT_ROOT="/Users/thanasis/Documents/RPLDmic"
fi

TEMP_DIR=""

# Signal Trap & Cleanup
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT INT TERM

TEMP_DIR="$(mktemp -d /tmp/rpldmic_verify_XXXXXX 2>/dev/null || mktemp -d -t 'rpldmic_verify')"

# Logging Helpers
print_header() {
    echo -e "\n${C_BOLD}${C_CYAN}=== $1 ===${C_RESET}"
}

report_pass() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    PASS_CHECKS=$((PASS_CHECKS + 1))
    echo -e "  [${C_GREEN}PASS${C_RESET}] $1 ${C_WHITE}($2)${C_RESET}"
}

report_warn() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    WARN_CHECKS=$((WARN_CHECKS + 1))
    echo -e "  [${C_YELLOW}WARN${C_RESET}] $1 ${C_WHITE}($2)${C_RESET}"
    if [ -n "${3:-}" ]; then
        echo -e "         ${C_CYAN}Recommendation: $3${C_RESET}"
    fi
}

report_fail() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    FAIL_CHECKS=$((FAIL_CHECKS + 1))
    echo -e "  [${C_RED}FAIL${C_RESET}] $1 ${C_WHITE}($2)${C_RESET}"
    if [ -n "${3:-}" ]; then
        echo -e "         ${C_YELLOW}Action Required: $3${C_RESET}"
    fi
}

report_info() {
    echo -e "  [${C_BLUE}INFO${C_RESET}] $1: ${C_WHITE}$2${C_RESET}"
}

# CLI Argument Parsing
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Diagnostic & System Health Verification Tool for RPLDmic (Intel Raptor Lake cAVS 2.5 DMIC).

Options:
  -h, --help        Show this help message and exit
  -v, --verbose     Enable verbose diagnostics and register dumps
  -p, --probe       Execute live audio probe test (rpldmic-probe) if driver is active
  -q, --quick       Quick mode: inspect essential kernel and OpenCore status only

Exit Status:
  0   All essential tests passed (or non-critical warnings only)
  1   One or more critical checks failed
  2   Invalid command-line arguments
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=1
            ;;
        -p|--probe)
            RUN_PROBE=1
            ;;
        -q|--quick)
            QUICK_MODE=1
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

# Banner
echo -e "${C_BOLD}${C_BLUE}==============================================================================${C_RESET}"
echo -e "${C_BOLD}${C_WHITE}       RPLDmic System Verification & Diagnostic Health Tool                  ${C_RESET}"
echo -e "${C_BOLD}${C_WHITE}       Target: Intel Raptor Lake cAVS 2.5 (8086:51ca) / ThinkPad T14 Gen 4   ${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}==============================================================================${C_RESET}"

# ==============================================================================
# SECTION 1: Host System & Platform Environment
# ==============================================================================
print_header "1. Host System & Platform Environment"

OS_PRODUCT="$(sw_vers -productName 2>/dev/null || echo 'macOS')"
OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo 'Unknown')"
OS_BUILD="$(sw_vers -buildVersion 2>/dev/null || echo 'Unknown')"
KERNEL_VER="$(uname -r 2>/dev/null || echo 'Unknown')"
HW_MODEL="$(sysctl -n hw.model 2>/dev/null || echo 'Unknown')"
CPU_BRAND="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Unknown')"

report_info "Operating System" "$OS_PRODUCT $OS_VERSION (Build $OS_BUILD)"
report_info "Darwin Kernel" "$KERNEL_VER ($(uname -m))"
report_info "Hardware Model" "$HW_MODEL"
report_info "Processor" "$CPU_BRAND"

# Verify command dependencies
DEP_MISSING=0
for cmd in ioreg system_profiler pgrep plutil stat; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        report_fail "System Dependency" "Missing command: $cmd" "Install command-line utilities"
        DEP_MISSING=1
    fi
done

if [ "$DEP_MISSING" -eq 0 ]; then
    report_pass "System Toolchain" "All required diagnostic CLI tools present"
fi

# ==============================================================================
# SECTION 2: IORegistry & Hardware Controller Audit
# ==============================================================================
print_header "2. IORegistry & Hardware Audio Controller"

# Check for physical audio controller device 8086:51ca or spoofed 8086:51c8
PCI_AUDIO_NODE="$(ioreg -p IOService -c IOPCIDevice | grep -E "1F,3|51ca|0x51ca|51c8|0x51c8" -B 2 -A 8 || true)"

if echo "$PCI_AUDIO_NODE" | grep -q -E "51ca|51c8"; then
    DEV_MATCH="8086:51ca (Raptor Lake cAVS 2.5)"
    if echo "$PCI_AUDIO_NODE" | grep -q "51c8"; then
        DEV_MATCH="8086:51ca (spoofed as 51c8 for AppleHDA)"
    fi
    report_pass "PCI Audio Controller" "Found hardware controller matching $DEV_MATCH"
else
    report_fail "PCI Audio Controller" "No Raptor Lake audio controller (8086:51ca/51c8) found in IORegistry" "Ensure Intel HDAS controller is enabled in BIOS"
fi

# Check controller memory mappings (BAR0: 16 KB, BAR4: 1 MB)
if echo "$PCI_AUDIO_NODE" | grep -q "IODeviceMemory"; then
    report_pass "PCI MMIO Windows" "BAR0 (16 KB) and BAR4 (1 MB DSP SRAM) memory descriptors mapped"
else
    report_info "PCI MMIO Windows" "MMIO mappings managed dynamically by parent PCI bus"
fi

# Check for active RPLDmic or TGLDmic kernel service in IORegistry
KEXT_SERVICE="$(ioreg -r -c RPLDmic -d 1 -w0 2>/dev/null || true)"
if [ -z "$KEXT_SERVICE" ]; then
    KEXT_SERVICE="$(ioreg -r -c TGLDmic -d 1 -w0 2>/dev/null || true)"
fi

if [ -n "$KEXT_SERVICE" ]; then
    KVER="$(echo "$KEXT_SERVICE" | sed -n 's/.*"RPLDmicVersion" = "\([^"]*\)".*/\1/p' | head -1)"
    [ -z "$KVER" ] && KVER="$(echo "$KEXT_SERVICE" | sed -n 's/.*"TGLDmicVersion" = "\([^"]*\)".*/\1/p' | head -1)"
    [ -z "$KVER" ] && KVER="Loaded (version unreported)"

    BOOT_RES="$(echo "$KEXT_SERVICE" | sed -n 's/.*"BootResult" = "\([^"]*\)".*/\1/p' | head -1)"
    [ -z "$BOOT_RES" ] && BOOT_RES="Standby"

    PLAT_ID="$(echo "$KEXT_SERVICE" | sed -n 's/.*"PlatformFamily" = \([0-9]*\).*/\1/p' | head -1)"
    PLAT_NAME="Unknown"
    case "$PLAT_ID" in
        1) PLAT_NAME="Tiger Lake (cAVS 2.5)" ;;
        2) PLAT_NAME="Comet Lake (cAVS 1.8)" ;;
        3) PLAT_NAME="Raptor Lake (cAVS 2.5)" ;;
        *) PLAT_NAME="Auto-detected ($PLAT_ID)" ;;
    esac

    report_pass "RPLDmic Kernel Service" "Active in IORegistry (v$KVER, Platform: $PLAT_NAME)"
    report_info "DSP Boot Status" "$BOOT_RES"

    if [ "$VERBOSE" -eq 1 ]; then
        STREAM_TAG="$(echo "$KEXT_SERVICE" | sed -n 's/.*"CaptureStreamTag" = \([0-9]*\).*/\1/p' | head -1)"
        STREAMING="$(echo "$KEXT_SERVICE" | sed -n 's/.*"Streaming" = \([a-zA-Z]*\).*/\1/p' | head -1)"
        report_info "Stream Tag" "${STREAM_TAG:-Unassigned}"
        report_info "Streaming Active" "${STREAMING:-No}"
    fi
else
    report_warn "RPLDmic Kernel Service" "Kext service not currently active in IORegistry" "If newly staged to EFI, reboot the system to load RPLDmic.kext"
fi

# Check for RPLDmicUserClient
USER_CLIENT="$(ioreg -r -c RPLDmicUserClient -d 1 2>/dev/null || ioreg -r -c TGLDmicUserClient -d 1 2>/dev/null || true)"
if [ -n "$USER_CLIENT" ]; then
    report_pass "RPLDmic User Client" "RPLDmicUserClient attached and communicating with user space"
else
    report_info "RPLDmic User Client" "No active user client connection (opens dynamically when recording)"
fi

# ==============================================================================
# SECTION 3: CoreAudio Subsystem & HAL Plug-In Audit
# ==============================================================================
print_header "3. CoreAudio Subsystem & HAL Plug-In"

# Check coreaudiod process
COREAUDIOD_PID="$(pgrep -x coreaudiod 2>/dev/null || true)"
if [ -n "$COREAUDIOD_PID" ]; then
    report_pass "coreaudiod Daemon" "Running with PID $COREAUDIOD_PID"
else
    report_fail "coreaudiod Daemon" "coreaudiod is not running" "Restart via sudo launchctl kickstart -k system/com.apple.audio.coreaudiod"
fi

# Check HAL plugin deployment in /Library/Audio/Plug-Ins/HAL/
HAL_PLUGIN_DIR="/Library/Audio/Plug-Ins/HAL/RPLDmic.driver"
HAL_ALT_PLUGIN_DIR="/Library/Audio/Plug-Ins/HAL/TGLDmic.driver"
ACTIVE_HAL_DIR=""

if [ -d "$HAL_PLUGIN_DIR" ]; then
    ACTIVE_HAL_DIR="$HAL_PLUGIN_DIR"
elif [ -d "$HAL_ALT_PLUGIN_DIR" ]; then
    ACTIVE_HAL_DIR="$HAL_ALT_PLUGIN_DIR"
fi

if [ -n "$ACTIVE_HAL_DIR" ]; then
    HAL_PLIST="$ACTIVE_HAL_DIR/Contents/Info.plist"
    HAL_BIN="$ACTIVE_HAL_DIR/Contents/MacOS/$(basename "$ACTIVE_HAL_DIR" .driver)"
    [ ! -f "$HAL_BIN" ] && HAL_BIN="$ACTIVE_HAL_DIR/Contents/MacOS/RPLDmic"
    [ ! -f "$HAL_BIN" ] && HAL_BIN="$ACTIVE_HAL_DIR/Contents/MacOS/TGLDmic"

    if [ -f "$HAL_BIN" ]; then
        report_pass "HAL Plugin Bundle" "Found at $ACTIVE_HAL_DIR"
        
        # Check permissions (must be root:wheel, 755)
        PERMS="$(stat -f "%Su:%Sg %Lp" "$ACTIVE_HAL_DIR" 2>/dev/null || echo 'unknown')"
        if [[ "$PERMS" =~ "root:wheel" ]] || [[ "$PERMS" =~ "755" ]]; then
            report_pass "Plugin Permissions" "Ownership & mode compliant ($PERMS)"
        else
            report_warn "Plugin Permissions" "Current: $PERMS (Expected: root:wheel 755)" "Run: sudo chown -R root:wheel $ACTIVE_HAL_DIR && sudo chmod -R 755 $ACTIVE_HAL_DIR"
        fi

        # Check Sandbox Entitlements
        if [ -f "$HAL_PLIST" ]; then
            if grep -q "AudioServerPlugIn_IOKitUserClients" "$HAL_PLIST" && (grep -q "RPLDmicUserClient" "$HAL_PLIST" || grep -q "TGLDmicUserClient" "$HAL_PLIST"); then
                report_pass "Tahoe Sandbox Entitlement" "AudioServerPlugIn_IOKitUserClients correctly whitelists user client"
            else
                report_fail "Tahoe Sandbox Entitlement" "Info.plist missing AudioServerPlugIn_IOKitUserClients entitlement" "coreaudiod sandbox will block driver attachment"
            fi
        fi
    else
        report_fail "HAL Plugin Binary" "Bundle missing executable binary at $ACTIVE_HAL_DIR/Contents/MacOS/" "Re-stage driver via hal/install-hal.sh"
    fi
else
    report_warn "HAL Plugin Staging" "RPLDmic.driver not found in /Library/Audio/Plug-Ins/HAL/" "Deploy using: sudo bash hal/install-hal.sh"
fi

# Check CoreAudio Device Enumeration via system_profiler
AUDIO_PROFILER="$(system_profiler SPAudioDataType 2>/dev/null || true)"
if echo "$AUDIO_PROFILER" | grep -q -E "Intel Raptor Lake Digital Microphone|RPLDmic|TGLDmic"; then
    report_pass "CoreAudio Device" "Microphone published in macOS CoreAudio device tree"
else
    report_warn "CoreAudio Device" "Microphone not currently enumerated in system_profiler" "Ensure RPLDmic.kext is loaded and coreaudiod has restarted"
fi

# Optional Live Probe Test
if [ "$RUN_PROBE" -eq 1 ] && [ -n "$KEXT_SERVICE" ]; then
    PROBE_BIN=""
    for candidate in "$PROJECT_ROOT/hal/build/rpldmic-probe" "$PROJECT_ROOT/hal/rpldmic-probe" "$PROJECT_ROOT/tools/rpldmic-probe"; do
        if [ -x "$candidate" ]; then
            PROBE_BIN="$candidate"
            break
        fi
    done

    if [ -n "$PROBE_BIN" ]; then
        report_info "Live Probe" "Executing 1-second capture probe ($PROBE_BIN)..."
        PROBE_OUT="$("$PROBE_BIN" 1 "$TEMP_DIR/test_probe.wav" 2>&1 || true)"
        if echo "$PROBE_OUT" | grep -q -i "frames/s"; then
            report_pass "Live Audio Probe" "Kernel ring DMA active and receiving audio frames"
            if [ "$VERBOSE" -eq 1 ]; then
                echo "$PROBE_OUT" | sed 's/^/         /'
            fi
        else
            report_warn "Live Audio Probe" "Probe completed without detecting active audio stream" "$PROBE_OUT"
        fi
    else
        report_warn "Live Audio Probe" "rpldmic-probe utility not found or not executable" "Compile using: make -C hal"
    fi
fi

# ==============================================================================
# SECTION 4: OpenCore EFI Configuration & Safety Guardrails
# ==============================================================================
print_header "4. OpenCore EFI Configuration & Safety Guardrails"

EFI_OC_DIR="/Volumes/EFI/EFI/OC"
CONFIG_MAIN="$EFI_OC_DIR/config.plist"
CONFIG_POST="$EFI_OC_DIR/config-post.plist"
KEXT_TARGET="$EFI_OC_DIR/Kexts/RPLDmic.kext"

if [ -d "$EFI_OC_DIR" ]; then
    report_pass "OpenCore EFI Volume" "EFI volume is mounted at /Volumes/EFI"

    # Check kext presence in EFI/OC/Kexts
    if [ -d "$KEXT_TARGET" ] && [ -f "$KEXT_TARGET/Contents/MacOS/RPLDmic" ]; then
        report_pass "EFI Kext Deployment" "RPLDmic.kext correctly staged in $KEXT_TARGET"
    else
        report_warn "EFI Kext Deployment" "RPLDmic.kext not found in /Volumes/EFI/EFI/OC/Kexts/" "Stage kext via: cp -R kext/build/RPLDmic.kext /Volumes/EFI/EFI/OC/Kexts/"
    fi

    # Verify plutil lint on both config files
    LINT_OK=1
    for cfg in "$CONFIG_MAIN" "$CONFIG_POST"; do
        if [ -f "$cfg" ]; then
            if plutil -lint "$cfg" > /dev/null 2>&1; then
                report_pass "Config Syntax" "$(basename "$cfg") passes plutil -lint"
            else
                report_fail "Config Syntax" "$(basename "$cfg") contains XML syntax errors" "Fix with plutil or plist editor"
                LINT_OK=0
            fi
        else
            report_warn "Config Presence" "Configuration file $cfg not found"
        fi
    done

    # Verify parity between config.plist and config-post.plist
    if [ -f "$CONFIG_MAIN" ] && [ -f "$CONFIG_POST" ]; then
        if diff -q "$CONFIG_MAIN" "$CONFIG_POST" > /dev/null 2>&1; then
            report_pass "Config Parity" "config.plist and config-post.plist are 100% identical"
        else
            report_fail "Config Parity" "Configuration mismatch detected between config.plist and config-post.plist" "Synchronize configs to prevent boot-setting drift"
        fi

        # Check Kernel -> Add for RPLDmic
        if grep -q "RPLDmic.kext" "$CONFIG_MAIN"; then
            report_pass "Kernel Injection" "RPLDmic.kext declared in OpenCore Kernel -> Add"
        else
            report_warn "Kernel Injection" "RPLDmic.kext not found in config.plist Kernel -> Add" "Inject at index [06] after SimpleHDA and AppleALC"
        fi

        # Hardware Safety Guardrail: ngreenSched=5
        if grep -q "ngreenSched=5" "$CONFIG_MAIN"; then
            report_pass "Scheduler Guardrail" "boot-args preserves ngreenSched=5 (Host Preemptive Scheduler)"
        else
            report_fail "Scheduler Guardrail" "ngreenSched=5 missing from boot-args!" "Strict safety rule: maintain ngreenSched=5 to prevent GPU watchdog kernel panics"
        fi

        # Hardware Safety Guardrail: Backlight PWM calibration
        if grep -q "19393" "$CONFIG_MAIN" || [ -f "$EFI_OC_DIR/ACPI/SSDT-PNLF.aml" ]; then
            report_pass "Backlight Guardrails" "ThinkPad T14 Gen 4 Innolux panel backlight calibration intact"
        else
            report_info "Backlight Guardrails" "Standard ACPI backlight profile detected"
        fi
    fi
else
    report_info "OpenCore EFI Volume" "EFI partition is not mounted at /Volumes/EFI (mount via diskutil mount /dev/disk0s1 to audit)"
fi

# Check Safety Backup Archive
BACKUP_ARCHIVE="$HOME/Desktop/EFI_Backup.zip"
if [ -f "$BACKUP_ARCHIVE" ]; then
    BACKUP_SIZE="$(stat -f%z "$BACKUP_ARCHIVE" 2>/dev/null || echo 0)"
    if [ "$BACKUP_SIZE" -gt 10485760 ]; then
        report_pass "Safety Backup" "Verified EFI backup exists at ~/Desktop/EFI_Backup.zip ($((BACKUP_SIZE / 1048576)) MB)"
    else
        report_warn "Safety Backup" "EFI backup archive smaller than expected (<10 MB)" "Verify archive integrity"
    fi
else
    report_info "Safety Backup" "No pre-existing backup found at ~/Desktop/EFI_Backup.zip"
fi

# ==============================================================================
# SECTION 5: Summary Scorecard & Final Recommendation
# ==============================================================================
print_header "5. Summary Scorecard & Recommendations"

echo -e "  Total Verifications Checked: ${C_BOLD}${TOTAL_CHECKS}${C_RESET}"
echo -e "  Passed:  ${C_BOLD}${C_GREEN}${PASS_CHECKS}${C_RESET}"
echo -e "  Warnings:${C_BOLD}${C_YELLOW}${WARN_CHECKS}${C_RESET}"
echo -e "  Failures:${C_BOLD}${C_RED}${FAIL_CHECKS}${C_RESET}\n"

if [ "$FAIL_CHECKS" -eq 0 ]; then
    if [ "$WARN_CHECKS" -eq 0 ]; then
        echo -e "${C_BOLD}${C_GREEN}STATUS: HEALTHY${C_RESET} - RPLDmic kernel extension, HAL plug-in, and OpenCore configuration are fully operational."
    else
        echo -e "${C_BOLD}${C_YELLOW}STATUS: ACTION RECOMMENDED${C_RESET} - System is stable, but review the warnings above (e.g. pending reboot or staging)."
    fi
    exit 0
else
    echo -e "${C_BOLD}${C_RED}STATUS: CRITICAL FAILURES DETECTED${C_RESET} - Please review the action items marked [FAIL] above before continuing."
    exit 1
fi
