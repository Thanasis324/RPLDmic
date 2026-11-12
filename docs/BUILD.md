# RPLDmic Build & Compilation Guide

This guide details the prerequisites, toolchain environment, and build commands required to compile `RPLDmic.kext` (macOS kernel extension) and `RPLDmic.driver` (CoreAudio HAL plug-in) from source.

---

## 1. Toolchain Prerequisites

Compilation requires standard Apple Command Line Tools and MacKernelSDK. No full Xcode GUI installation is required.

### Required Software
- **Operating System**: macOS Ventura (13.x), Sonoma (14.x), Sequoia (15.x), or Tahoe (26.x).
- **Compiler**: Apple `clang` / `clang++` (version 12.0 or higher; Apple clang 21.x verified on macOS Tahoe).
- **SDK**: `MacOSX.sdk` (provided by Xcode CLT under `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` or Xcode platform directories).
- **Kernel Headers**: [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) maintained by Acidanthera.
- **Python**: Python 3.8+ (for firmware array generation via `tools/gen-fw.py`).

### Setting Up MacKernelSDK
Ensure `MacKernelSDK` is cloned or symlinked to the project root or passed via the `SDK` variable:
```bash
# Option A: Symlink existing local copy
ln -s /Users/thanasis/Documents/NootedGreen/MacKernelSDK /Users/thanasis/Documents/RPLDmic/MacKernelSDK

# Option B: Clone from official Acidanthera repository
git clone https://github.com/acidanthera/MacKernelSDK.git /Users/thanasis/Documents/RPLDmic/MacKernelSDK
```

Verify that the SDK contains the required IOKit kernel headers and static helper library:
```bash
ls -la MacKernelSDK/Headers/IOKit
ls -la MacKernelSDK/Library/x86_64/libkmod.a
```

---

## 2. Generating Firmware Headers (`tools/gen-fw.py`)

RPLDmic embeds Intel production-signed Sound Open Firmware binaries directly into the compiled kext image so that retail Intel cAVS audio DSPs can authenticate and execute them without external file dependencies.

Before compiling the kext, `tools/gen-fw.py` parses the signed `.ri` files in `firmware/intel/` and generates `kext/build/Firmware.c`:

```bash
python3 tools/gen-fw.py \
    --rpl firmware/intel/sof-rpl.ri \
    --tgl firmware/intel/sof-tgl.ri \
    --cml firmware/intel/sof-cml.ri \
    -o kext/build/Firmware.c
```

### Generated Symbols:
- `kSofRplRi` & `kSofRplRiSize`: Raptor Lake-P/U/H cAVS 2.5 firmware (`8086:51ca` / `8086:51c8`).
- `kSofTglRi` & `kSofTglRiSize`: Tiger Lake-LP/H cAVS 2.5 firmware (`8086:a0c8` / `8086:43c8`).
- `kSofCmlRi` & `kSofCmlRiSize`: Comet Lake / Cannon Lake cAVS 1.8 firmware (`8086:02c8` / `8086:9dc8`).

---

## 3. Compiling the Kernel Extension (`RPLDmic.kext`)

The kernel driver is compiled using Apple clang with specific kernel module flags (`-mkernel`, `-fapple-kext`, `-nostdinc`).

### Command
```bash
make -C kext SDK=/Users/thanasis/Documents/RPLDmic/MacKernelSDK
```

### Compiler & Linker Flags Explained
- **Compilation Flags (`clang++`)**:
  ```text
  -arch x86_64
  -mmacosx-version-min=10.15
  -std=gnu++17
  -O2
  -nostdinc
  -isystem $(SDK)/Headers
  -mkernel
  -fapple-kext
  -fno-rtti
  -fno-exceptions
  -fno-builtin
  -fno-common
  -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT
  ```
  These flags instruct clang to generate compliant Mach-O 64-bit kernel object code without C++ runtime exceptions, RTTI, or userspace C runtime headers.
- **Linker Flags (`clang++`)**:
  ```text
  -arch x86_64
  -nostdlib
  -Xlinker -kext
  -Xlinker -export_dynamic
  -L$(SDK)/Library/x86_64 -lkmod
  $(CLANG_RESOURCE_DIR)/lib/darwin/libclang_rt.cc_kext.a
  ```
  Resolves kernel runtime symbols (`_kmod_info`, module constructors) against Acidanthera's `libkmod.a` and clang's `libclang_rt.cc_kext.a`.

### Output Artifacts
- Binary bundle: `kext/build/RPLDmic.kext`
- Distributable zip archive: `kext/build/RPLDmic.kext.zip`

---

## 4. Compiling the CoreAudio HAL Plug-in (`RPLDmic.driver`)

The user-space companion driver is an `AudioServerPlugIn` CFPlugIn bundle that `coreaudiod` loads dynamically.

### Command
```bash
make -C hal
```

### Compiler & Linker Flags Explained
```text
clang++ -arch x86_64 -mmacosx-version-min=10.15 -std=c++17 -O2 \
    -Wall -Wextra -Wno-unused-parameter -bundle \
    -o build/RPLDmic.driver/Contents/MacOS/RPLDmic RPLDmicDriver.cpp \
    -framework CoreAudio -framework CoreFoundation -framework IOKit
```
- `-bundle`: Produces a standard macOS loadable bundle.
- `-framework CoreAudio`: Imports `AudioServerPlugIn.h` interfaces.
- `-framework IOKit`: Enables user-client connection (`IOServiceOpen`, `IOConnectMapMemory64`).

### CLI Probe Utility
The HAL Makefile also automatically builds `hal/build/rpldmic-probe`, a standalone C11 utility that verifies kernel communication and captures audio directly from the mapped ring buffer without involving CoreAudio.

---

## 5. Debug vs. Release Builds

By default, builds are compiled in **Release** mode (`-O2`, minimal log verbosity).

### Building with Debug Symbols & Trace Logging
To enable verbose hardware register logging, FSR trace prints, and debug symbols:
```bash
# Build debug kext
make -C kext DEBUG=1

# Build debug HAL plug-in
make -C hal DEBUG=1
```

Debug flags enabled with `DEBUG=1`:
- `-g`: Generates full DWARF debugging symbols.
- `-O0`: Disables compiler optimization for exact stack inspection.
- `-DDEBUG=1`: Enables detailed IPC packet dumping and register transition logs in `ioreg` property `"Log"`.

---

## 6. Verifying Built Binaries

After building, verify binary architectures, exported symbols, and plist validity:

### 1. Verify Architecture & Bundles
```bash
file kext/build/RPLDmic.kext/Contents/MacOS/RPLDmic
# Expected: Mach-O 64-bit kext bundle x86_64

file hal/build/RPLDmic.driver/Contents/MacOS/RPLDmic
# Expected: Mach-O 64-bit bundle x86_64
```

### 2. Verify Exported Symbols
```bash
# Verify kernel module declaration
nm -gU kext/build/RPLDmic.kext/Contents/MacOS/RPLDmic | grep _kmod_info
# Expected: 0000000000194880 D _kmod_info

# Verify HAL factory export
nm -gU hal/build/RPLDmic.driver/Contents/MacOS/RPLDmic | grep _RPLDmic_Create
# Expected: 00000000000007d0 T _RPLDmic_Create
```

### 3. Verify Plist Syntax
```bash
plutil -lint kext/RPLDmic/Info.plist
plutil -lint hal/Info.plist
# Expected: Both output "OK"
```

### 4. Clean Build Directories
```bash
make -C kext clean
make -C hal clean
```
