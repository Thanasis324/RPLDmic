# RPLDmic Installation & Deployment Guide

This guide provides end-to-end instructions for deploying `RPLDmic.kext` to OpenCore EFI and staging `RPLDmic.driver` to macOS CoreAudio on the **Lenovo ThinkPad T14 Gen 4** (`21HDS37000`, Raptor Lake cAVS 2.5, `8086:51ca` / `8086:51c8`).

---

## 1. Safety Guardrails & Pre-Installation Backup

Modifying OpenCore EFI configurations carries inherent system stability risks. Before applying any changes:

1. **Verify Existing Safety Backup**:
   Confirm that a full zip backup archive of your working EFI exists at `~/Desktop/EFI_Backup.zip`:
   ```bash
   ls -lh ~/Desktop/EFI_Backup.zip
   # Must be >= 50 MB
   ```
   If absent, create it immediately before proceeding:
   ```bash
   cd /Volumes/EFI && zip -r ~/Desktop/EFI_Backup.zip EFI/
   ```
2. **Preserve OpenCore Graphics & Backlight Settings**:
   - Strictly preserve `ngreenSched=5` in `boot-args`. **Never** force `ngreenSched=4`, as doing so disables NootedGreen multi-engine sibling reset recovery and causes permanent WindowServer watchdog kernel panics.
   - Retain backlight calibrations (`ngreenblmax=19393`, `ngreenblmin=200`, `SSDT-PNLF.aml`).
   - Retain `UpdateSMBIOSMode = Create` and `CustomSMBIOSGuid = false`.

---

## 2. Staging the Kernel Extension (`RPLDmic.kext`)

### Step 2.1: Mount EFI Partition
```bash
diskutil mount /dev/disk0s1   # Or use OpenCore Auxiliary Tools / MountEFI
```

### Step 2.2: Copy Kext to EFI Volume
```bash
cp -R kext/RPLDmic.kext /Volumes/EFI/EFI/OC/Kexts/
# (or cp -R kext/build/RPLDmic.kext if built from source)
```
Verify that the staged kext contains the compiled binary:
```bash
file /Volumes/EFI/EFI/OC/Kexts/RPLDmic.kext/Contents/MacOS/RPLDmic
# Expected output: Mach-O 64-bit kext bundle x86_64
```

### Step 2.3: Inject into OpenCore `config.plist` and `config-post.plist`
Open both `/Volumes/EFI/EFI/OC/config.plist` and `/Volumes/EFI/EFI/OC/config-post.plist` in your plist editor (or ProperTree).

Insert `RPLDmic.kext` into `Kernel -> Add` at **index `[06]`**, immediately following `SimpleHDA.kext` (`[05]`) and `AppleALC.kext` (`[04]`):

```xml
<dict>
    <key>Arch</key>
    <string>x86_64</string>
    <key>BundlePath</key>
    <string>RPLDmic.kext</string>
    <key>Comment</key>
    <string>Intel Raptor Lake cAVS 2.5 Digital Microphone Driver</string>
    <key>Enabled</key>
    <true/>
    <key>ExecutablePath</key>
    <string>Contents/MacOS/RPLDmic</string>
    <key>MaxKernel</key>
    <string></string>
    <key>MinKernel</key>
    <string>19.0.0</string>
    <key>PlistPath</key>
    <string>Contents/Info.plist</string>
</dict>
```

### Step 2.4: Update `boot-args`
In `NVRAM -> Add -> 7C436110-AB2A-4BBB-A880-FE41995C9F82 -> boot-args`:
Append `-rpldmic` (or `-rpldmicrpl`) while retaining existing audio and graphics arguments:
```text
alcid=86 ngreenSched=5 -rpldmic
```

### Step 2.5: Synchronize & Lint Configurations
Ensure that `config.plist` and `config-post.plist` remain **100% identical**:
```bash
# Verify XML syntax
plutil -lint /Volumes/EFI/EFI/OC/config.plist
plutil -lint /Volumes/EFI/EFI/OC/config-post.plist

# Verify configuration parity
diff /Volumes/EFI/EFI/OC/config.plist /Volumes/EFI/EFI/OC/config-post.plist
# Must return empty diff
```

### Step 2.6: Disable Realtek ALC257 Dummy Node (Recommended)
On modern laptops (such as Lenovo ThinkPad T14 Gen 4), the physical microphone array connects directly to Intel cAVS via PDM, not to the Realtek ALC257 codec. AppleALC Layout 86 defines pin 0x12 as an internal mic, creating a dead, silent input engine that macOS often prefers over external/secondary inputs.

Run the automated patching tool to disable pin 0x12 (`0x400000f0`) on your mounted EFI:
```bash
python3 tools/patch-applealc.py /Volumes/EFI/EFI/OC/Kexts/AppleALC.kext
```
*(The script creates a `.bak` backup and verifies syntax with `plutil`).*

---

## 3. Supported Boot-Arg Flags & Parameters

RPLDmic provides rich configuration options via kernel boot arguments:

| Boot Argument | Default | Description |
|---------------|---------|-------------|
| `-rpldmic` / `-tgldmic` | Enabled | Enables the driver service. |
| `-rpldmicoff` / `-tgldmicoff` | Disabled | Disables the driver completely without removing from EFI. |
| `-rpldmicrpl` | Auto | Forces platform family to **Raptor Lake cAVS 2.5** (`kPlatformRaptorLake = 3`). |
| `-rpldmictgl` | Auto | Forces platform family to **Tiger Lake cAVS 2.5** (`kPlatformTigerLake = 1`). |
| `-rpldmiccml` | Auto | Forces platform family to **Comet Lake cAVS 1.8** (`kPlatformCometLake = 2`). |
| `-rpldmicforce` | Disabled | Forces driver attachment even if subsystem vendor/device does not match. |
| `-rpldmicboot` | Disabled | Executes a one-time DSP firmware boot test upon startup, then idles Core 0. |
| `-rpldmiccap` | Disabled | Executes a boot-time capture test and stores a 1-second audio snapshot in IORegistry (`CaptureSnapshot`). |
| `rpldmicdelay=<s>` | `20` | Boot test execution delay in seconds (10 to 170). Allows AppleHDA to settle. |
| `rpldmicsnoop=<0\|1\|2>` | `1` | **PCI No-Snoop control (PCI 0x78 bit 11)**:<br>`0`: Never touch `PCI_DEVC`<br>`1`: Set `NSNPEN` for boot, restore original value when Core 0 idles (default)<br>`2`: Keep `NSNPEN` permanently set |
| `rpldmiccoremask=<mask\>` | `1` (RPL) | DSP core power mask override (`ADSPCS.SPA`). Default `0x01` (Core 0) on Raptor Lake; `0x0F` on Comet Lake. |
| `rpldmicin=<idx>` | `6` | Overrides dynamic capture input stream descriptor index. |

---

## 4. Staging the CoreAudio HAL Plug-in (`RPLDmic.driver`)

CoreAudio requires the user-space companion plug-in `RPLDmic.driver` to be installed in `/Library/Audio/Plug-Ins/HAL/`.

### Automated Installation
Execute the provided staging script with administrative privileges:
```bash
sudo bash hal/install-hal.sh
```

### Manual Installation Steps
If performing manual deployment:
```bash
# 1. Remove any stale driver
sudo rm -rf /Library/Audio/Plug-Ins/HAL/RPLDmic.driver

# 2. Copy driver bundle
sudo cp -R hal/RPLDmic.driver /Library/Audio/Plug-Ins/HAL/
# (or sudo cp -R hal/build/RPLDmic.driver /Library/Audio/Plug-Ins/HAL/ if built from source)

# 3. Apply root:wheel ownership and 755 permissions
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/RPLDmic.driver
sudo chmod -R 755 /Library/Audio/Plug-Ins/HAL/RPLDmic.driver

# 4. Strip macOS quarantine attributes
sudo xattr -dr com.apple.quarantine /Library/Audio/Plug-Ins/HAL/RPLDmic.driver 2>/dev/null || true

# 5. Restart coreaudiod
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
```

---

## 5. Verification & Audio Testing

### Step 5.1: Run Verification Script
Execute the diagnostic script to check kernel, CoreAudio, and OpenCore state:
```bash
./verify-rpldmic.sh
```

### Step 5.2: Verify Kernel Extension in IORegistry
```bash
ioreg -l -w0 -c RPLDmic | grep -E '"BootResult"|"PlatformFamily"|"Streaming"'
```
Expected output:
```text
"BootResult" = "OK FW_READY"
"PlatformFamily" = 3
"Streaming" = No
```

### Step 5.3: Test Kernel Audio Pipeline with CLI Probe
Capture a 3-second raw WAV file directly from the kernel DMA ring buffer without involving CoreAudio:
```bash
./hal/build/rpldmic-probe 3 probe.wav
```
Expected output:
```text
Connected to RPLDmic kernel service (ver 1, state 0x1)
Sampling rate: 48000 Hz, channels: 4, ring: 65536 bytes
Recording 3 seconds into probe.wav...
[sec 1] 48000 frames/s, Ch0: -52.1 dBFS, Ch1: -52.4 dBFS, Ch2: -58.0 dBFS, Ch3: -58.1 dBFS
[sec 2] 48000 frames/s, Ch0: -48.2 dBFS, Ch1: -48.6 dBFS, Ch2: -57.4 dBFS, Ch3: -57.5 dBFS
Recording completed: 144000 frames captured.
```

### Step 5.4: Test Native CoreAudio Input & Siri
1. Open **System Settings → Sound → Input**.
2. Verify **Built-in Microphone** is selected with **Input source: Internal Microphone** (48,000 Hz, Apple Inc.).
3. Speak into the ThinkPad microphone: observe the input level meter moving responsively.
4. Test Siri ("Hey Siri" or click Siri icon): verify Siri receives and executes your spoken commands accurately.
5. Open **Voice Memos** or **QuickTime Player** (File → New Audio Recording) to make a test recording.

---

## 6. Channel Routing Modes

Configure microphone channel routing using macOS `defaults`:

```bash
# Mode 0 (Default): Front-facing microphone array (Left = mic 0, Right = mic 1)
# Recommended for standard conferencing, Zoom, FaceTime, and voice calls.
defaults write org.thesofproject.driver.RPLDmic ChannelMode -int 0

# Mode 1: Ambient / room microphone array (Left = mic 2, Right = mic 3)
defaults write org.thesofproject.driver.RPLDmic ChannelMode -int 1

# Mode 2: 4-Channel Blend (omnidirectional stereo sum across all four microphones)
# Mixes (Ch0 + Ch2) / 2 into Left and (Ch1 + Ch3) / 2 into Right for 360-degree capture.
defaults write org.thesofproject.driver.RPLDmic ChannelMode -int 2
```

Apply changes by restarting `coreaudiod`:
```bash
sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
```

---

## 7. Rollback & Uninstallation

To remove RPLDmic and restore previous audio configuration:

1. **Remove CoreAudio Plug-in**:
   ```bash
   sudo bash hal/uninstall-hal.sh
   ```
2. **Disable / Remove Kext from OpenCore**:
   - In both `/Volumes/EFI/EFI/OC/config.plist` and `config-post.plist`, set `Kernel -> Add -> [RPLDmic.kext] -> Enabled = false` (or remove the dict entry).
   - Remove `-rpldmic` from `boot-args`.
   - Remove `/Volumes/EFI/EFI/OC/Kexts/RPLDmic.kext`.
   - Run `plutil -lint` on both config files.
3. **Emergency Fallback Recovery**:
   If system fails to boot after an edit, boot into recovery or another OS and restore the EFI archive:
   ```bash
   cd /Volumes/EFI && unzip -o ~/Desktop/EFI_Backup.zip
   ```
