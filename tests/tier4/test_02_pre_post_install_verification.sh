#!/bin/bash
# ==============================================================================
# Tier 4 - Scenario 2: Pre-Install / Post-Install Lifecycle Verification
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 4: Scenario 2 - Pre-Install / Post-Install Lifecycle Simulation"
TEMP_DIR=$(make_temp_dir "rpldmic_sim_lifecycle")
trap 'rm -rf "$TEMP_DIR"' EXIT

# T4.2: Simulate entire staging lifecycle in isolated mock EFI environment
MOCK_EFI="$TEMP_DIR/EFI/OC"
mkdir -p "$MOCK_EFI/Kexts"
cp "$CONFIG_PLIST" "$MOCK_EFI/config.plist"
cp "$CONFIG_POST_PLIST" "$MOCK_EFI/config-post.plist"

# 1. Pre-flight check
pre_flight_ok=false
if [ -f "$EFI_BACKUP_ZIP" ] && plutil -lint "$MOCK_EFI/config.plist" > /dev/null 2>&1; then
    pre_flight_ok=true
fi

# 2. Simulated Kext staging
staged_ok=false
KEXT_SRC=""
for cand in "$KEXT_DIR/build/RPLDmic.kext" "$KEXT_DIR/RPLDmic.kext"; do
    if [ -d "$cand" ]; then KEXT_SRC="$cand"; break; fi
done

if [ "$pre_flight_ok" = true ] && [ -n "$KEXT_SRC" ]; then
    cp -R "$KEXT_SRC" "$MOCK_EFI/Kexts/RPLDmic.kext"
    # Inject kext into mock config plists at index [06]
    python3 -c "
import plistlib
for p in ['$MOCK_EFI/config.plist', '$MOCK_EFI/config-post.plist']:
    with open(p, 'rb') as f: pl = plistlib.load(f)
    kext_list = pl.get('Kernel', {}).get('Add', [])
    entry = {
        'Arch': 'x86_64',
        'BundlePath': 'RPLDmic.kext',
        'Comment': 'Intel Raptor Lake cAVS 2.5 DMIC Driver',
        'Enabled': True,
        'ExecutablePath': 'Contents/MacOS/RPLDmic',
        'MaxKernel': '',
        'MinKernel': '19.0.0',
        'PlistPath': 'Contents/Info.plist'
    }
    # Insert at index 6 (after SimpleHDA [5])
    kext_list.insert(6, entry)
    with open(p, 'wb') as f: plistlib.dump(pl, f)
"
    # 3. Post-flight validation
    lint1=$(plutil -lint "$MOCK_EFI/config.plist" 2>&1 || true)
    lint2=$(plutil -lint "$MOCK_EFI/config-post.plist" 2>&1 || true)

    if echo "$lint1" | grep -q "OK" && echo "$lint2" | grep -q "OK"; then
        staged_ok=true
    fi
fi

if [ "$staged_ok" = true ]; then
    record_pass "T4.2" "Pre-install to post-install staging lifecycle simulation completes cleanly" "mock EFI staging & plist lint verified"
else
    record_fail "T4.2" "Staging lifecycle simulation failed" "pre_flight=$pre_flight_ok, staged=$staged_ok"
fi

print_summary "Tier 4 Scenario 2 (Lifecycle Simulation)"
exit $?
