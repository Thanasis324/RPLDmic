#!/bin/bash
# ==============================================================================
# Tier 2 - Feature 8 Boundary: Repository Documentation Corner Cases
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "Tier 2: Feature 8 - Repository Documentation Boundary Cases"
TEMP_DIR=$(make_temp_dir "rpldmic_bva_docs")
trap 'rm -rf "$TEMP_DIR"' EXIT

validate_doc_file() {
    local doc_path="$1"
    if [ ! -f "$doc_path" ]; then
        echo "FAIL: file missing"
        return 1
    fi
    local size
    size=$(stat -f%z "$doc_path" 2>/dev/null || echo 0)
    if [ "$size" -eq 0 ]; then
        echo "FAIL: zero-byte file"
        return 1
    fi
    # Check for binary non-printable control characters
    if ! python3 -c "
with open('$doc_path', 'rb') as f: data = f.read()
bad = any(b < 9 or (b > 13 and b < 32) for b in data)
exit(1 if bad else 0)
"; then
        echo "FAIL: corrupted binary control codes detected"
        return 1
    fi
    echo "OK"
    return 0
}

# T2.8.1: Zero-length markdown file rejection
EMPTY_MD="$TEMP_DIR/empty.md"
touch "$EMPTY_MD"
if validate_doc_file "$EMPTY_MD" > /dev/null 2>&1; then
    record_fail "T2.8.1" "Zero-length documentation file unexpectedly accepted" "must fail"
else
    record_pass "T2.8.1" "Zero-length documentation file is cleanly rejected" "size check verified"
fi

# T2.8.2: Broken internal relative markdown links detection
BROKEN_LINK_MD="$TEMP_DIR/broken_link.md"
cat << 'EOF' > "$BROKEN_LINK_MD"
# Test Document
Please see [Non Existent](docs/DOES_NOT_EXIST.md) for details.
EOF
broken_links=$(python3 -c "
import re, os
with open('$BROKEN_LINK_MD') as f: content = f.read()
links = re.findall(r'\[.*?\]\((?!http)(.*?)\)', content)
broken = [l for l in links if not os.path.exists(os.path.join('$TEMP_DIR', l))]
print('BROKEN' if broken else 'OK')
")
if [ "$broken_links" = "BROKEN" ]; then
    record_pass "T2.8.2" "Broken internal relative documentation links are accurately detected" "link audit verified"
else
    record_fail "T2.8.2" "Broken link was not detected" "$broken_links"
fi

# T2.8.3: Missing required section headers in README
MOCK_README="$TEMP_DIR/bad_readme.md"
cat << 'EOF' > "$MOCK_README"
# Minimal Readme
Just a short note without hardware or install details.
EOF
missing_sections=$(python3 -c "
with open('$MOCK_README') as f: text = f.read().lower()
required = ['hardware', 'install', 'architecture']
missing = [r for r in required if r not in text]
print('MISSING' if missing else 'COMPLETE')
")
if [ "$missing_sections" = "MISSING" ]; then
    record_pass "T2.8.3" "Missing required documentation sections are accurately flagged" "header audit verified"
else
    record_fail "T2.8.3" "Missing section was not detected" "$missing_sections"
fi

# T2.8.4: Hexadecimal PCI ID format validator
validate_pci_id_syntax() {
    local val="$1"
    if echo "$val" | grep -Eq "^(0x[0-9a-fA-F]{4}|[0-9a-fA-F]{4}:[0-9a-fA-F]{4})$"; then
        return 0
    else
        return 1
    fi
}
if validate_pci_id_syntax "INVALID_PCI_ID"; then
    record_fail "T2.8.4" "Invalid PCI ID format unexpectedly accepted" "must fail syntax check"
else
    record_pass "T2.8.4" "Invalid PCI ID format is cleanly rejected" "syntax validation verified"
fi

# T2.8.5: Binary corruption / null byte detection
CORRUPT_MD="$TEMP_DIR/corrupt.md"
printf "# Title\x00\x01\x02\x03\x04\nCorrupt text" > "$CORRUPT_MD"
if validate_doc_file "$CORRUPT_MD" > /dev/null 2>&1; then
    record_fail "T2.8.5" "Binary corrupted markdown unexpectedly accepted" "must reject control codes"
else
    record_pass "T2.8.5" "Corrupted markdown with binary control characters is cleanly rejected" "integrity verified"
fi

print_summary "Tier 2 Feature 8 (Documentation Boundary)"
exit $?
