# RPLDmic: Intel Raptor Lake cAVS 2.5 Digital Microphone Driver for macOS

[![macOS](https://img.shields.io/badge/macOS-Ventura%20|%20Sonoma%20|%20Sequoia%20|%20Tahoe-blue.svg)](https://apple.com)
[![Platform](https://img.shields.io/badge/Intel-Raptor%20Lake%20cAVS%202.5-orange.svg)](https://www.intel.com)
[![Hardware](https://img.shields.io/badge/Target-ThinkPad%20T14%20Gen%204%20(8086%3A51ca)-green.svg)](https://www.lenovo.com)
[![Firmware](https://img.shields.io/badge/SOF-v2.2%20IPC3%20(Intel%20Signed)-purple.svg)](https://github.com/thesofproject/sof)
[![License](https://img.shields.io/badge/License-BSD--3--Clause%20/%20GPL--2.0-blue.svg)](LICENSE)

An open-source macOS kernel extension (`RPLDmic.kext`) and companion CoreAudio HAL plugin (`RPLDmic.driver`) that enable the built-in digital microphones (DMIC / PDM array) on **Intel Raptor Lake-P/U/H cAVS 2.5** platforms, tailored specifically for the **Lenovo ThinkPad T14 Gen 4** (`21HDS37000`, PCI `8086:51ca`, subsystem `17aa:230e`) running **macOS Tahoe** (26.x), Sequoia (15.x), Sonoma (14.x), and Ventura (13.x).

> [!NOTE]
> On modern Intel platforms (Raptor Lake, Alder Lake, Tiger Lake, Comet Lake), the internal digital microphones are physically connected to the Intel Smart Sound Technology (cAVS) audio DSP via PDM lines, rather than being wired as analog inputs to the High Definition Audio (HDA) codec. Because AppleALC and AppleHDA only interface with codec nodes over the HDA link, internal digital microphones remain completely non-functional out of the box on Hackintosh systems.
>
> **RPLDmic** solves this by booting Intel's production-signed Sound Open Firmware (`sof-rpl.ri`) directly on the cAVS 2.5 audio DSP, setting up decoupled DMA streams alongside AppleHDA, replaying the SOF IPC3 pipeline, and presenting a native CoreAudio input device—**Intel Raptor Lake Digital Microphone**—to macOS.

---

## Architecture Overview

RPLDmic operates on a hybrid coexistence model. It does not replace `AppleHDAController`, `AppleHDADriver`, or `AppleALC`; instead, it runs concurrently on the same PCI controller without claiming exclusive access:

```
  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │                            macOS CoreAudio Subsystem                            │
  │     (System Settings, QuickTime, Voice Memos, FaceTime, Zoom, Teams, WebRTC)    │
  └───────────────────────────────▲─────────────────────────────────────────────────┘
                                  │ Float32 Stereo (48 kHz)
  ┌───────────────────────────────┴─────────────────────────────────────────────────┐
  │         RPLDmic.driver (AudioServerPlugIn HAL Plug-In in /Library)              │
  │  - Zero-copy shared memory mapping via IOConnectMapMemory64                     │
  │  - 128-point sliding-window least-squares linear regression (jitter-free clock) │
  │  - Master software gain control (0.0 dB to +36.0 dB, default +24.0 dB)          │
  │  - Multi-mic channel routing (Front Array, Ambient Array, 4-Channel Blend)      │
  └───────────────────────────────▲─────────────────────────────────────────────────┘
                                  │ mach_task shared ring + scalar IPC (selectors 0..3)
  ┌───────────────────────────────┴─────────────────────────────────────────────────┐
  │                     RPLDmic.kext (Kernel Extension / IOKit)                     │
  │  - Custom IOMatchCategory: RPLDmic (never calls provider->open(this))           │
  │  - Decoupled DMA stream allocation via BAR0 Processing Pipe (PPCTL.PROCEN)      │
  │  - Single-core Core 0 power gating via ADSPCS (SPA = 0x01, CPA = 0x01)          │
  │  - PCI No-Snoop Bit (DEVC 0x78 bit 11 NSNPEN) management for macOS Tahoe        │
  │  - Embedded Intel production-signed SOF v2.2 firmware (sof-rpl.ri)              │
  │  - SOF IPC3 DMIC Pipeline 10 configuration replay & 48 kHz S32_LE DMA capture   │
  └───────────────────────▲─────────────────────────────────▲───────────────────────┘
                          │                                 │
              BAR0 (16 KB MMIO)                 BAR4 (1 MB DSP SRAM)
    HDA Processing Pipe & DMA Streams      DSP Shim, Mailboxes & PDM DAI
                          │                                 │
  ┌───────────────────────▼─────────────────────────────────▼───────────────────────┐
  │         Intel Raptor Lake-P/U/H cAVS 2.5 Audio Controller (8086:51ca)           │
  │                     Lenovo ThinkPad T14 Gen 4 (Subsystem 17aa:230e)             │
  │           ALC257 HDA Codec (Speakers & Jack) + Dual PDM Microphone Array        │
  └─────────────────────────────────────────────────────────────────────────────────┘
```

For complete register-level specifications, timing diagrams, and DMA buffer geometry, refer to the [Architecture Documentation](docs/ARCHITECTURE.md).

---

## Key Features

- **Native CoreAudio Integration**: Exposes a standard audio input device recognized throughout macOS (System Settings, Logic Pro, FaceTime, QuickTime, WebRTC).
- **Zero-Copy Memory Path**: Maps a 64 KB kernel DMA ring buffer directly into `coreaudiod` memory via `IOConnectMapMemory64`, eliminating kernel-to-user copy overhead during real-time capture.
- **Jitter-Free Clock Synchronization**: Uses a 128-point sliding-window least-squares linear regression algorithm (`fitHostForSample`) to map discrete ~1 ms DSP DMA steps to `mach_absolute_time`, satisfying CoreAudio's PLL requirements without timestamp jitter or buffer drift.
- **Dynamic Stream Decoupling**: Dynamically discovers active AppleHDA playback/capture streams and allocates the highest unallocated input and output stream descriptors, decoupling them via `PPCTL.PROCEN` to isolate DSP traffic from codec traffic.
- **Power Gating & Energy Efficiency**: Enforces single-core host power gating on Core 0 (`ADSPCS.SPA = 0x01`). The DSP is kept in a low-power gated state until an application requests recording, powering up within ~120 ms and returning to idle when capture halts.
- **macOS Tahoe Compatibility**: Automatically ensures the PCI No-Snoop enable bit (`PCI_DEVC` 0x78 bit 11 `NSNPEN`) is asserted during firmware DMA transfers, overcoming the Tahoe ROM load halt issue (`0x80000003`).
- **Flexible Channel Routing**: Supports front-facing dual arrays, rear/ambient arrays, and 4-channel omnidirectional blend modes via user defaults.
- **Universal Manifest Parser**: Supports both legacy SOF `XMan` (Extended Manifest v1, magic `0x6e614d58`) and modern `$AE1` (Extended Manifest v4, magic `0x31454124`) metadata headers.

---

## Hardware Compatibility Matrix

| Platform Generation | cAVS IP Version | PCI Device ID | Subsystem ID | Reference Hardware | Status |
|---------------------|-----------------|---------------|--------------|--------------------|--------|
| **Intel Raptor Lake-P/U/H** | **cAVS 2.5** | **`8086:51ca`** | **`17aa:230e`** | **Lenovo ThinkPad T14 Gen 4 (`21HDS37000`)** | **Supported / Target** |
| Intel Raptor Lake (Spoofed) | cAVS 2.5 | `8086:51c8` | `17aa:230e` | Lenovo ThinkPad T14 Gen 4 | Supported |
| Intel Tiger Lake-LP | cAVS 2.5 | `8086:a0c8` | `103c:8ab9` | HP EliteBook 840 G8 / Dell XPS 13 9310 | Supported |
| Intel Tiger Lake-H | cAVS 2.5 | `8086:43c8` | various | ThinkPad P15 Gen 2 / Dell XPS 15 | Supported |
| Intel Comet Lake-LP | cAVS 1.8 | `8086:02c8` | `17aa:2292` | Lenovo ThinkPad X1 Carbon Gen 7 | Supported |
| Intel Cannon Lake-LP | cAVS 1.8 | `8086:9dc8` | `17aa:2292` | ThinkPad X1 Carbon Gen 7 (i7-8565U) | Supported |
| Intel Comet Lake-H | cAVS 1.8 | `8086:06c8` | various | Dell Latitude 5410 / ThinkPad T14 Gen 1 | Supported |
| Intel Coffee Lake-H | cAVS 1.8 | `8086:a348` | various | ThinkPad X1 Extreme Gen 2 | Supported |

### Operating System Compatibility
- **macOS Tahoe (26.x)**: Darwin 25.x (Full support with PCI No-Snoop fix).
- **macOS Sequoia (15.x)**: Darwin 24.x (Full support).
- **macOS Sonoma (14.x)**: Darwin 23.x (Full support).
- **macOS Ventura (13.x)**: Darwin 22.x (Full support).

---

## Quick Start Installation

### Step 1: Stage Kext into OpenCore
1. Mount your EFI partition:
   ```bash
   diskutil mount /dev/disk0s1   # adjust disk identifier as needed
   ```
2. Copy `RPLDmic.kext` into `/Volumes/EFI/EFI/OC/Kexts/`:
   ```bash
   cp -R kext/build/RPLDmic.kext /Volumes/EFI/EFI/OC/Kexts/
   ```
3. Add `RPLDmic.kext` to `Kernel -> Add` in both `/Volumes/EFI/EFI/OC/config.plist` and `config-post.plist` immediately following `SimpleHDA.kext` at index `[06]`.
4. Ensure `boot-args` contains `-rpldmic` while strictly preserving `ngreenSched=5`:
   ```xml
   <string>-v keepsyms=1 alcid=86 ngreenSched=5 -rpldmic</string>
   ```
5. Validate configuration syntax:
   ```bash
   plutil -lint /Volumes/EFI/EFI/OC/config.plist
   plutil -lint /Volumes/EFI/EFI/OC/config-post.plist
   ```

### Step 2: Reboot & Verify Kernel Service
Reboot the machine. Once booted, confirm the kext is active in the IORegistry:
```bash
ioreg -l -w0 -c RPLDmic | grep -E '"PlatformFamily"|"RPLDmicVersion"|"BootResult"'
```
Expected output:
```text
"PlatformFamily" = 3
"RPLDmicVersion" = "1.0.0"
"BootResult" = "OK FW_READY"
```

### Step 3: Install CoreAudio HAL Plug-in
Run the automated HAL staging script:
```bash
sudo bash hal/install-hal.sh
```
This installs `RPLDmic.driver` to `/Library/Audio/Plug-Ins/HAL/`, sets permissions to `root:wheel` (`755`), strips quarantine flags, and restarts `coreaudiod`.

### Step 4: Run Diagnostic Verification
Execute the verification tool to confirm end-to-end functionality:
```bash
./verify-rpldmic.sh
```

For complete step-by-step instructions, rollback procedures, and fallback recovery using `EFI_Backup.zip`, see the [Installation Guide](docs/INSTALL.md).

---

## Microphone Routing Modes

Lenovo ThinkPads feature far-field digital microphone arrays. You can configure channel mapping via macOS user defaults:

```bash
# Mode 0 (Default): Front-facing microphone array (Left = mic 0, Right = mic 1)
defaults write org.thesofproject.driver.RPLDmic ChannelMode -int 0

# Mode 1: Ambient / room microphone array (Left = mic 2, Right = mic 3)
defaults write org.thesofproject.driver.RPLDmic ChannelMode -int 1

# Mode 2: 4-Channel Blend (omnidirectional stereo sum across all four microphones)
defaults write org.thesofproject.driver.RPLDmic ChannelMode -int 2
```
Restart `coreaudiod` after modifying the channel mode:
```bash
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
```

---

## Building from Source

### Prerequisites
- macOS machine running Xcode Command Line Tools (`clang` / `clang++`).
- Python 3.
- [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK) staged at `../MacKernelSDK` or symlinked in project root.

### Build Commands
```bash
# 1. Generate firmware byte arrays from signed binaries
python3 tools/gen-fw.py --rpl firmware/intel/sof-rpl.ri \
                       --tgl firmware/intel/sof-tgl.ri \
                       --cml firmware/intel/sof-cml.ri \
                       -o kext/build/Firmware.c

# 2. Build kernel extension (RPLDmic.kext)
make -C kext SDK=/path/to/MacKernelSDK

# 3. Build CoreAudio HAL plug-in (RPLDmic.driver) & probe utility
make -C hal
```

Detailed build options, debug symbols, and release packaging are documented in the [Build Guide](docs/BUILD.md).

---

## Repository Structure

```text
/Users/thanasis/Documents/RPLDmic/
├── README.md                      # Publication overview, architecture diagram, and quick start
├── LICENSE                        # Open-source BSD-3-Clause / GPL-2.0 license
├── verify-rpldmic.sh              # Production-grade diagnostic verification script
├── docs/                          # In-depth technical documentation
│   ├── ARCHITECTURE.md            # Hardware register maps, cAVS boot flow, IPC, regression timestamps
│   ├── BUILD.md                   # Toolchain requirements, clang flags, debug/release builds
│   ├── INSTALL.md                 # OpenCore deployment, config.plist synchronization, boot-args
│   └── TROUBLESHOOTING.md         # Diagnostic runbook: timeouts, ROM errors 41/44, Tahoe snoop fix
├── firmware/                      # Sound Open Firmware binaries
│   ├── LICENCE.Intel              # Intel firmware redistribution license
│   └── intel/
│       ├── sof-rpl.ri             # Production-signed SOF v2.2 binary for Raptor Lake (8086:51ca)
│       ├── sof-tgl.ri             # Production-signed SOF v2.2 binary for Tiger Lake (8086:a0c8)
│       └── sof-cml.ri             # Production-signed SOF v2.2 binary for Comet Lake (8086:02c8)
├── kext/                          # RPLDmic.kext kernel driver
│   ├── Makefile                   # Clang kernel module build recipe
│   └── RPLDmic/
│       ├── RPLDmic.hpp / .cpp     # Main IOService lifecycle, matching, and stream management
│       ├── DspBoot.cpp            # cAVS DSP power gating, no-snoop, and code loader DMA boot
│       ├── Capture.cpp            # Decoupled DMA capture ring buffer and IPC3 pipeline replay
│       ├── RPLDmicUserClient.cpp  # User-space Mach scalar dispatch and memory mapping
│       ├── RPLDmicShared.h        # Shared structures, ring sizes, and method selectors
│       ├── Regs.hpp               # Intel cAVS 2.5 BAR0 / BAR4 register definitions
│       ├── DmaBuffer.hpp          # Physical contiguous memory allocator (<4 GB IOVA)
│       ├── IpcReplay.hpp          # SOF IPC3 pipeline setup message payloads
│       └── Info.plist             # IOKit matching dictionary (8086:51ca, 8086:51c8)
├── hal/                           # RPLDmic.driver CoreAudio HAL companion plug-in
│   ├── Makefile                   # Bundle compiler recipe
│   ├── RPLDmicDriver.cpp          # AudioServerPlugIn implementation with least-squares fit
│   ├── Info.plist                 # PlugIn factory UUID and sandbox entitlement definition
│   ├── install-hal.sh             # Automated staging script for /Library/Audio/Plug-Ins/HAL/
│   ├── uninstall-hal.sh           # Safe uninstaller and cleanup tool
│   └── rpldmic-probe.c            # Standalone CLI probe reading shared ring memory directly
├── tools/                         # Maintenance and diagnostic utilities
│   ├── gen-fw.py                  # Firmware binary to C array converter
│   ├── diff-regs.py               # Pre-boot vs post-boot hardware register diff inspector
│   └── verify-rpldmic.sh          # Mirrored copy of diagnostic verification tool
└── tests/                         # Comprehensive automated test suite
    ├── common.sh                  # Shared logging, assertion framework, and color formatters
    ├── tier1/                     # Baseline functional unit tests (Features 1-9)
    ├── tier2/                     # Boundary value and corner-case test suite
    └── tier3/                     # System integration and OpenCore ordering verification
```

---

## Troubleshooting & Diagnostics

If audio capture does not start or the microphone is silent, consult the detailed [Troubleshooting Guide](docs/TROUBLESHOOTING.md).

Quick diagnostic commands:
```bash
# 1. Run automated diagnostic tool
./verify-rpldmic.sh

# 2. Inspect kernel driver ring log (last 128 events)
ioreg -l -w0 -c RPLDmic | grep -A 30 '"Log" ='

# 3. Test raw audio capture directly from kernel without CoreAudio
./hal/build/rpldmic-probe 3 probe.wav

# 4. View CoreAudio log events
log show --last 5m --predicate 'eventMessage CONTAINS "RPLDmic"' --info
```

---

## Credits & Acknowledgments

- **[Sound Open Firmware (thesofproject)](https://github.com/thesofproject)**: For the open-source audio DSP firmware architecture, IPC definitions, and Linux drivers upon which this work is based.
- **[labrouss](https://github.com/labrouss)**: Author of the original [TGLDmic](https://github.com/labrouss/TGLDmic) driver baseline.
- **[Acidanthera](https://github.com/acidanthera)**: For `MacKernelSDK`, `OpenCorePkg`, `AppleALC`, and `Lilu`, which made modern macOS kernel development and audio integration possible.
- **Intel Corporation**: For production-signed SOF binaries enabling secure execution on retail cAVS hardware.

---

## Licensing

- **RPLDmic Code**: Licensed under the **BSD-3-Clause** / **GPL-2.0** dual license. See [LICENSE](LICENSE) for terms.
- **Sound Open Firmware**: Distributed unmodified under Intel's binary license. See [firmware/LICENCE.Intel](firmware/LICENCE.Intel) for terms.
