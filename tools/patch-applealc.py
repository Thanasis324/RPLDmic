#!/usr/bin/env python3
"""
patch-applealc.py: Disables Realtek ALC257 dummy internal microphone pin 0x12 in AppleALC.kext.

On modern Intel laptops (such as Lenovo ThinkPad T14 Gen 4), the physical digital microphone
array is wired directly to Intel cAVS 2.5 via PDM, not to the Realtek ALC257 codec.
AppleALC's Layout 86 defines pin 0x12 as an internal mic, creating a dead, silent input engine
that conflicts with macOS Siri and Dictation.

This script patches pin 0x12 default configuration to 0x400000f0 (disabled/no physical connection),
allowing RPLDmic to seamlessly serve as the sole Built-in Microphone.
"""

import sys
import os
import shutil
import plistlib

def patch_applealc(kext_path):
    plist_path = os.path.join(kext_path, "Contents", "Info.plist")
    if not os.path.isfile(plist_path):
        print(f"Error: {plist_path} not found.")
        sys.exit(1)

    bak_path = plist_path + ".bak"
    if not os.path.isfile(bak_path):
        shutil.copyfile(plist_path, bak_path)
        print(f"Created safety backup at: {bak_path}")
    else:
        print(f"Safety backup already exists at: {bak_path}")

    with open(plist_path, "rb") as f:
        pl = plistlib.load(f)

    hda_configs = pl.get("IOKitPersonalities", {}).get("as.vit9696.AppleALC", {}).get("HDAConfigDefault", [])
    alc257_id = 0x10ec0257
    patched = False

    for i, cfg in enumerate(hda_configs):
        if cfg.get("CodecID") == alc257_id and cfg.get("LayoutID") == 86:
            raw_data = cfg.get("ConfigData", b"").hex()
            # Pin 0x12 disabled verb: 01271cf0 01271d00 01271e00 01271f40
            if raw_data.startswith("01271cf001271d0001271e0001271f40"):
                print("Pin 0x12 is already disabled in Layout 86.")
                return
            elif raw_data.startswith("01271c"):
                new_data_hex = "01271cf001271d0001271e0001271f40" + raw_data[32:]
                cfg["ConfigData"] = bytes.fromhex(new_data_hex)
                print(f"Successfully patched ALC257 Layout 86 ConfigData (entry {i}).")
                patched = True

    if patched:
        with open(plist_path, "wb") as f:
            plistlib.dump(pl, f)
        print(f"Updated {plist_path} successfully!")
    else:
        print("Warning: No matching ALC257 Layout 86 entry found to patch.")

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "/Volumes/EFI/EFI/OC/Kexts/AppleALC.kext"
    patch_applealc(target)
