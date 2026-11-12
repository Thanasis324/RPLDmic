# RPLDmic Troubleshooting & Diagnostic Runbook

This guide covers failure modes, error codes, and step-by-step diagnostic procedures for `RPLDmic` on Intel Raptor Lake cAVS 2.5 (`8086:51ca` / `8086:51c8`) and related hardware.

---

## 1. Quick Diagnostic Checklist

When encountering issues with microphone capture:

```bash
# 1. Run the comprehensive verification tool
./verify-rpldmic.sh

# 2. Check if the kext service is recognized by IOKit
ioreg -l -w0 -c RPLDmic

# 3. Check CoreAudio daemon state and loaded plug-ins
pgrep -fl coreaudiod
ls -la /Library/Audio/Plug-Ins/HAL/RPLDmic.driver

# 4. Inspect kernel log messages from RPLDmic
log show --last 5m --predicate 'sender CONTAINS "RPLDmic"' --info
```

---

## 2. DSP Boot & Firmware Loading Failures

During initial boot or when an application opens the audio stream, `RPLDmic` powers up the DSP, configures the loader stream, and initiates firmware DMA transfer.

### 2.1 Timeout Waiting for `ADSPCS.CPA` (Core Power Up)
- **Symptom**: `FAIL core0 power up (CPA) (0x00000000)` in `BootResult` or `ioreg`.
- **Root Cause**:
  - Setting an unsupported core mask on Raptor Lake cAVS 2.5. Raptor Lake only allows host management of Core 0 (`targetCoreMask = 0x01`). If `0x0F` (Comet Lake mask) is set, hardware never asserts `CPA` for cores 1–3.
  - Controller stuck in low-power state `D0i3`.
- **Solution**:
  - Add boot-arg `rpldmiccoremask=1`.
  - Verify that `VS_D0I3C` (BAR0 offset `0x104A`) has bit 2 (`D0I3`) cleared.

---

### 2.2 ROM Code Loader Halts at FSR `0x80000003` (macOS Tahoe Stalls)
- **Symptom**: `FAIL FW_ENTERED (0x80000003)` with `HALTED` flag asserted in `ROM_STATUS`.
- **Root Cause 1: PCI No-Snoop Gating Disabled (macOS Tahoe)**:
  - Under macOS Tahoe, AppleHDA replacement drivers (like `HDAUniversal`) often clear bit 11 (`PCI_DEVC_NSNPEN`) in PCI configuration register `0x78` (`PCI_DEVC`), leaving the value as `0x2000`.
  - When `NSNPEN` is cleared, the cAVS DSP ROM can fetch initial manifest headers from Host memory, but hardware DMA snooping fails during bulk firmware payload transfer. The ROM halts immediately with FSR `0x80000003`.
  - **Fix**: RPLDmic automatically asserts bit 11 during DSP boot (`0x2800`). Ensure boot-arg `rpldmicsnoop=1` or `rpldmicsnoop=2` is active. Never set `rpldmicsnoop=0`.
- **Root Cause 2: Extended Manifest Not Stripped**:
  - Passing raw firmware files beginning with `XMan` (`0x6e614d58`) or `$AE1` (`0x31454124`) directly to the code loader DMA engine causes the ROM manifest parser to fail.
  - **Fix**: Verify firmware parser skips `skip = w[1]` bytes so DMA buffer starts directly at the `$CPD` signature.

---

### 2.3 Intel ROM Error Codes (`HDA_DSP_SRAM_REG_ROM_ERROR` at `BAR4 + 0x80004`)

When the DSP halts, `DspBoot.cpp` logs the 32-bit value at `BAR4 + 0x80004`:

| Error Code | Intel Identifier | Meaning & Resolution |
|------------|------------------|----------------------|
| **40** | `CSE_ERROR` | Communication error with Intel CSME/CSE security engine. Verify CSME is enabled in BIOS. |
| **41** | `CSE_WRONG_RESPONSE` | CSME returned an invalid response. Usually caused by a corrupted Common Package Directory (`$CPD`) header. Re-generate firmware using `tools/gen-fw.py`. |
| **42** | `IMR_TOO_SMALL` | Isolated Memory Region allocated by BIOS/CSE is smaller than firmware payload. Update ThinkPad BIOS to latest version. |
| **43** | `BASE_FW_NOT_FOUND` | ROM loader could not locate the `BASEFW` module entry point (`$AME`). Caused by bad manifest offset or un-stripped extended manifest. |
| **44** | `CSE_VALIDATION_FAILED` | **Cryptographic Signature Rejection**. Retail Intel Raptor Lake silicon enforces strict RSA-3072 signature validation against Intel's production root key. Community-built or un-signed SOF binaries are rejected. **You must use official Intel production-signed `sof-rpl.ri`** from `thesofproject/sof-bin/v2.2.x/sof-v2.2/intel-signed/sof-adl.ri`. |
| **45** | `IPC_FATAL_ERROR` | Fatal internal DSP firmware panic during initialization. |

---

## 3. CoreAudio HAL Plug-In Issues

### 3.1 Microphone Device Not Visible in System Settings
If "Intel Raptor Lake Digital Microphone" does not appear under **System Settings → Sound → Input**:

1. **Check if `coreaudiod` Loaded the Driver**:
   ```bash
   log show --last 5m --predicate 'process == "coreaudiod"' --info | grep -i rpldmic
   ```
2. **Verify Sandbox Entitlements**:
   macOS Tahoe runs `coreaudiod` in a strict sandbox. If `coreaudiod` attempts to open an IOKit user client that is not explicitly whitelisted, macOS blocks the connection:
   ```text
   Sandbox: coreaudiod(xxx) deny(1) iokit-open-user-client RPLDmicUserClient
   ```
   **Solution**: Ensure `/Library/Audio/Plug-Ins/HAL/RPLDmic.driver/Contents/Info.plist` includes:
   ```xml
   <key>AudioServerPlugIn_IOKitUserClients</key>
   <array>
       <string>RPLDmicUserClient</string>
       <string>TGLDmicUserClient</string>
   </array>
   ```
3. **Verify File Ownership & Permissions**:
   ```bash
   sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/RPLDmic.driver
   sudo chmod -R 755 /Library/Audio/Plug-Ins/HAL/RPLDmic.driver
   sudo xattr -dr com.apple.quarantine /Library/Audio/Plug-Ins/HAL/RPLDmic.driver 2>/dev/null || true
   ```
4. **Restart CoreAudio**:
   ```bash
   sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
   ```

---

### 3.2 Interface Version Mismatch
- **Symptom**: `RPLDmic: interface mismatch kr=0x0 ver=0 ring=0`.
- **Root Cause**: The running `RPLDmic.kext` in memory was compiled with an older or newer interface version than `RPLDmic.driver`.
- **Solution**: Recompile both kext and HAL plugin together and redeploy:
  ```bash
  make -C kext && make -C hal
  sudo bash hal/install-hal.sh
  ```

---

## 4. Audio Quality, Levels & Channel Mapping

### 4.1 Microphone Captures Digital Silence (-inf dBFS)
1. **Check Software Gain Slider**:
   The input gain slider in System Settings maps from 0.0 dB to +36.0 dB. If set to minimum, audio level may be extremely quiet. Set to 70% (+24 dB default).
2. **Check Channel Routing Mode**:
   Lenovo ThinkPads may route the dual physical mics to channels 0/1 or channels 2/3.
   Try switching between channel modes:
   ```bash
   # Try mode 0 (front array)
   defaults write org.thesofproject.driver.RPLDmic ChannelMode -int 0
   sudo launchctl kickstart -k system/com.apple.audio.coreaudiod

   # If silent, try mode 1 (rear array)
   defaults write org.thesofproject.driver.RPLDmic ChannelMode -int 1
   sudo launchctl kickstart -k system/com.apple.audio.coreaudiod

   # Try mode 2 (4-channel blend mix)
   defaults write org.thesofproject.driver.RPLDmic ChannelMode -int 2
   sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
   ```
3. **Check Privacy Permissions**:
   macOS requires microphone permission for individual applications. Navigate to:
   **System Settings → Privacy & Security → Microphone**
   Ensure your recording application (Voice Memos, QuickTime, Zoom) is enabled.

---

### 4.2 Audio Stuttering or Buffer Glitches
- **Root Cause**: Audio buffer size mismatch or PLL clock drift.
- **Diagnostics**:
  - The driver uses 128-point sliding-window least-squares linear regression to filter DMA step quantization.
  - If third-party virtual audio devices (Soundflower, BlackHole, Loopback) alter the CoreAudio host clock, clock tracking may destabilize.
  - Test recording using standard QuickTime Player or `./hal/build/rpldmic-probe 5 test.wav` to isolate CoreAudio pipeline issues.

---

## 5. Emergency EFI Fallback Recovery

If configuration changes prevent macOS from booting:

1. **Boot into an Alternate Environment**:
   - Use an OpenCore USB installer or alternate boot drive.
2. **Mount the Target EFI Partition**:
   ```bash
   diskutil mount /dev/disk0s1
   ```
3. **Restore the Safety Archive**:
   A verified backup was created at `~/Desktop/EFI_Backup.zip` prior to any modifications:
   ```bash
   cd /Volumes/EFI
   unzip -o /Users/thanasis/Desktop/EFI_Backup.zip
   ```
4. **Reboot**: The original, pristine EFI configuration is restored.
