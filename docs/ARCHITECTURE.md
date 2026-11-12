# RPLDmic Technical Architecture: Intel Raptor Lake cAVS 2.5 Audio DSP

This document provides an exhaustive, register-level technical breakdown of the `RPLDmic` driver architecture for Intel Raptor Lake-P/U/H cAVS 2.5 audio DSPs (PCI device `8086:51ca` / `8086:51c8`, subsystem `17aa:230e`, Lenovo ThinkPad T14 Gen 4) under macOS Tahoe (26.x).

---

## 1. Architectural Motivation & Coexistence Model

On modern Intel mobile architectures (Raptor Lake, Alder Lake, Tiger Lake, Comet Lake), the internal digital microphones (DMIC) are not connected to the High Definition Audio (HDA) codec (e.g. Realtek ALC257). Instead, they are routed directly to the integrated cAVS (converged Audio Voice Speech) Smart Sound Technology audio DSP via Pulse-Density Modulation (PDM) lines.

```
       ┌───────────────────────────── SoC Audio Controller ────────────────────────────┐
       │                                                                                │
       │   ┌────────────────────┐                 ┌──────────────────────────────────┐  │
       │   │  HDA Controller    │                 │         cAVS 2.5 Audio DSP       │  │
       │   │  (BAR0, 16 KB)     │                 │         (BAR4, 1 MB SRAM)        │  │
       │   └─────────┬──────────┘                 └─────────────────┬────────────────┘  │
       └─────────────┼──────────────────────────────────────────────┼───────────────────┘
                     │ HDA Link (Azalia)                            │ PDM Lines (DMIC0/1)
       ┌─────────────▼──────────┐                 ┌─────────────────▼───────────────────┐
       │   Realtek ALC257 Codec │                 │  Dual/Quad Digital Microphone Array │
       │  Speakers & 3.5mm Jack │                 │     (Webcam Bezel Integrated)       │
       └────────────────────────┘                 └─────────────────────────────────────┘
```

Because macOS's `AppleHDA.kext` and open-source injector `AppleALC.kext` only program codec verbs over the external HDA link, they have no visibility or control over the cAVS DSP. Without dedicated DSP firmware loading and pipeline management, the digital microphones remain unpowered and silent.

### The Coexistence Challenge
Attempting to drive the entire audio controller with a monolithic custom driver would displace `AppleHDAController` and `AppleHDADriver`, breaking analog speakers, headphones, and the 3.5mm combo jack. RPLDmic solves this with a **hybrid non-interfering architecture**:

1. **Non-Exclusive IOKit Matching**:
   In `kext/RPLDmic/Info.plist`, `RPLDmic` declares:
   ```xml
   <key>IOClass</key>
   <string>RPLDmic</string>
   <key>IOMatchCategory</key>
   <string>RPLDmic</string>
   <key>IOProviderClass</key>
   <string>IOPCIDevice</string>
   <key>IONameMatch</key>
   <array>
       <string>pci8086,51ca</string>
       <string>pci8086,51c8</string>
       <string>pci17aa,230e</string>
   </array>
   ```
   Standard macOS drivers match under `IODefaultMatchCategory`. By defining `IOMatchCategory = RPLDmic`, IOKit allows `RPLDmic` to attach as a peer client to the same `IOPCIDevice` (`_SB.PC00.HDAS@1f0003`) concurrently with `AppleHDAController`.
2. **Never Opening the Provider**:
   `RPLDmic` **never** calls `provider->open(this)`. It maps BAR0 and BAR4 MMIO spaces directly, reads capabilities, and manages its own decoupled streams without interfering with AppleHDA's exclusive controller open.
3. **Interrupt Independence (100% Polled Operation)**:
   The single Message Signaled Interrupt (MSI) vector allocated to the PCI function is owned by `AppleHDAController`. `RPLDmic` never touches `INTCTL` or enables stream interrupts. All firmware DMA loading, IPC handshake protocols, and buffer position monitoring operate in bounded polling mode on dedicated IOWorkLoop timers.

---

## 2. Hardware Memory Maps & Register Architecture

The Intel Raptor Lake-P cAVS 2.5 controller exposes two primary Base Address Registers (BARs):

| Register Base | Size | Memory Space | Description |
|---------------|------|--------------|-------------|
| **BAR0** | 16 KB (`0x4000`) | MMIO | High Definition Audio (HDA) Controller & Extended Capabilities |
| **BAR4** | 1 MB (`0x100000`) | MMIO / SRAM | Audio DSP Shim, IPC Mailboxes, and SRAM Memory Windows |

### 2.1 BAR0 Register Layout (HDA Controller & Capabilities)

```text
BAR0 + 0x0000  ┌────────────────────────────────────────────────────────┐
               │ Standard HDA Controller Registers (GCAP, GCTL, etc.)   │
BAR0 + 0x0080  ├────────────────────────────────────────────────────────┤
               │ Stream Descriptors (Base 0x80, Stride 0x20 per stream) │
               │   Input Streams  0..8 (Descriptor 0x80 .. 0x180)       │
               │   Output Streams 0..7 (Descriptor 0x1A0 .. 0x280)      │
BAR0 + 0x0700  ├────────────────────────────────────────────────────────┤
               │ Processing Pipe Capability (Capability ID 0x03)        │
BAR0 + 0x0800  ├────────────────────────────────────────────────────────┤
               │ Software Position-In-Buffer (SPB) Capability (ID 0x04) │
BAR0 + 0x1000  ├────────────────────────────────────────────────────────┤
               │ Intel Vendor-Specific Space (EM2, D0i3C, DPIB)         │
BAR0 + 0x4000  └────────────────────────────────────────────────────────┘
```

#### Standard HDA Registers
- `0x00` `GCAP` (Global Capabilities):
  - Bits [15:12]: Number of Output Streams (`numOut`, typically 8 on cAVS 2.5).
  - Bits [11:8]: Number of Input Streams (`numIn`, typically 9 on cAVS 2.5).
  - Bits [7:3]: Number of Bidirectional Streams (`numBidi`, 0).
  - Bit 0: 64-bit Address Support (always 1 on Raptor Lake).
- `0x08` `GCTL` (Global Control):
  - Bit 0: `CRST` (Controller Reset). 1 = operational; 0 = in reset.
- `0x20` `INTCTL` (Interrupt Control): Unmodified by RPLDmic to prevent MSI disruption.

#### Stream Descriptor Registers (`SD_BASE = 0x80 + 0x20 * n`)
For any global stream index $n$:
- `+0x00` `SD_CTL` (Control, 24-bit):
  - Bit 1: `RUN` (DMA Run Control).
  - Bit 0: `SRST` (Stream Reset). Must be asserted, polled, then de-asserted to flush FIFO.
  - Bits [23:20]: `STREAM_TAG` (Active stream identifier on HDA bus).
- `+0x04` `SD_LPIB` (Link Position in Buffer, 32-bit): DMA position relative to physical HDA pins.
- `+0x08` `SD_CBL` (Cyclic Buffer Length, 32-bit): Total ring buffer size in bytes (e.g., 65,536).
- `+0x0C` `SD_LVI` (Last Valid Index, 16-bit): $M - 1$ where $M$ is the number of BDL entries.
- `+0x12` `SD_FMT` (Stream Format, 16-bit):
  - Value `0x0043`: Base rate 48 kHz (0), 32-bit container (100b), 4 audio channels (0011b).
  - Value `0x0040`: 1 channel 32-bit (used for firmware code loader).
- `+0x18` `SD_BDPL` / `+0x1C` `SD_BDPU`: Low and High 32 bits of physical 64-bit IOVA pointing to Buffer Descriptor List (BDL).

#### Extended Capability 3: Processing Pipe (`CAP_PP`, Offset 0x700 or discovered via `LLCH`)
- `+0x04` `PP_PPCTL` (Processing Pipe Control, 32-bit):
  - Bit 30: `GPROCEN` (Global Processing Enable). Must be 1 to enable DSP routing.
  - Bit $n$: `PROCEN[n]` (Stream Decoupling Bit). When bit $n$ is set to 1, stream descriptor $n$ is **decoupled** from the external physical HDA link and routed directly into DSP internal memory.

#### Extended Capability 4: Software Position-In-Buffer (`CAP_SPB`, Offset 0x800)
- `+0x04` `SPB_SPBFCCTL` (Position Buffer Control, 32-bit): Bitmask of streams utilizing software fetch windows.
- `+0x08 + 0x08 * n` `SPIB[n]` (Software Position-In-Buffer, 32-bit):
  - Controls the maximum byte window the DMA engine is allowed to fetch.
  - **CRITICAL**: If `SPBFCCTL` bit $n$ is enabled while `SPIB[n]` is zero, the DMA engine halts and issues zero bus transactions. During firmware loading, `SPIB[n]` must be programmed with the exact firmware byte size.

#### Intel Vendor-Specific MMIO (`0x1000 - 0x10FF`)
- `0x1030` `HDA_EM2` (Extended Mode 2):
  - Bit 13 `L1SEN` (L1 Sub-states Enable). Must be cleared during firmware load to prevent clock gating latency stalls.
- `0x104A` `VS_D0I3C` (Device Low Power State Control):
  - Bit 2 `D0I3`: When set, DSP block is in D0i3 low-power state. Must be cleared prior to DSP boot.
- `0x1084 + 0x20 * n` `VS_DPIB[n]` (Decoupled DMA Position in Buffer, 32-bit):
  - Reports the linear byte write position of decoupled capture stream $n$ directly from DSP SRAM.

---

### 2.2 BAR4 Register Layout (DSP Shim, IPC & SRAM Windows)

```text
BAR4 + 0x00000  ┌────────────────────────────────────────────────────────┐
                │ DSP Shim Control & Status (ADSPCS, ADSPIC, ADSPIS)     │
BAR4 + 0x000C0  ├────────────────────────────────────────────────────────┤
                │ DSP-to-Host IPC Registers (HIPCTDR, HIPCTDA, HIPCTDD)  │
BAR4 + 0x000D0  ├────────────────────────────────────────────────────────┤
                │ Host-to-DSP IPC Registers (HIPCIDR, HIPCIDA, HIPCIDD)  │
BAR4 + 0x000E8  ├────────────────────────────────────────────────────────┤
                │ IPC Control (HIPCCTL)                                  │
BAR4 + 0x80000  ├────────────────────────────────────────────────────────┤
                │ SRAM Window 0: ROM Status (FSR 0x80000), Error 0x80004 │
BAR4 + 0x81000  ├────────────────────────────────────────────────────────┤
                │ SRAM Window 0: Uplink Mailbox (DSP -> Host, 4 KB)      │
BAR4 + 0xA0000  ├────────────────────────────────────────────────────────┤
                │ SRAM Window 1: Downlink Mailbox (Host -> DSP, 8 KB)    │
BAR4 + 0xC1000  ├────────────────────────────────────────────────────────┤
                │ SRAM Window 2: Stream Position Box (DPIB Mailbox)      │
BAR4 + 0x100000 └────────────────────────────────────────────────────────┘
```

#### DSP Shim Control Register (`ADSPCS`, BAR4 Offset `0x04`)
The primary hardware power and execution sequencer for the Tensilica Xtensa HiFi3 DSP cores:

| Bits | Name | Description |
|------|------|-------------|
| [31:24] | `CPA` | **Core Power Active**. Read-only bitmask. Bit $k$ is 1 when Core $k$ is powered. |
| [23:16] | `SPA` | **Set Power Active**. Host-writable bitmask. Host sets bit $k$ to request power on Core $k$. |
| [15:8]  | `CSTALL` | **Core Stall**. Bit $k$ holds Core $k$ in execution stall. 1 = stalled, 0 = executing. |
| [7:0]   | `CRST` | **Core Reset**. Bit $k$ holds Core $k$ in reset. 1 = reset asserted, 0 = running. |

**Raptor Lake cAVS 2.5 Rule**:
Unlike Comet Lake (cAVS 1.8) where the host driver must power all 4 cores (`SPA = 0x0F`), Raptor Lake enforces that the host manages **only Core 0** (`targetCoreMask() = 0x01`). Attempting to set `SPA = 0x0F` causes `CPA` polling to time out. Secondary cores are dynamically powered by firmware.

#### IPC Mailbox Protocol
Host-to-DSP communication uses a hardware mailbox protocol with mutual busy/done handshakes:

1. **Host-to-DSP Request (`HIPCIDR` at `0xD0`, `HIPCIDA` at `0xD4`)**:
   - Host copies payload into Downlink Mailbox (`BAR4 + 0xA0000`).
   - Host writes `HIPCIDR = IPC_BUSY (bit 31) | Command`.
   - DSP hardware detects BUSY, processes message, writes reply into Downlink Mailbox, and asserts `DONE` (bit 31) in `HIPCIDA`.
   - Host polls `HIPCIDA` for `IPC_DONE`, reads response, and writes 1 to clear `HIPCIDA.DONE` (Write-1-to-Clear).
2. **DSP-to-Host Notification (`HIPCTDR` at `0xC0`, `HIPCTDA` at `0xC4`)**:
   - DSP writes notification (e.g. `FW_READY` = `0x70000000`) into Uplink Mailbox (`BAR4 + 0x81000`).
   - DSP asserts `HIPCTDR.BUSY` (bit 31).
   - Host detects `BUSY`, reads payload, and clears `HIPCTDR.BUSY` (W1C) and writes `HIPCTDA.DONE` (bit 31).

---

## 3. DSP Boot Sequence & macOS Tahoe Specifics

The complete DSP initialization follows a deterministic 11-step state machine implemented in `DspBoot.cpp`:

```
 [1. Power Un-Gating] ──▶ [2. Bus Master & D0i3] ──▶ [3. PCI No-Snoop Bit 0x78]
                                                              │
 ┌────────────────────────────────────────────────────────────┘
 ▼
 [4. Decoupled Loader Stream] ──▶ [5. Core 0 Power Up (SPA=1)] ──▶ [6. ROM Purge IPC]
                                                                            │
 ┌──────────────────────────────────────────────────────────────────────────┘
 ▼
 [7. Core 0 Un-Stall] ──▶ [8. Code Loader DMA Start] ──▶ [9. Poll FSR: FW_ENTERED (0x5)]
                                                                    │
 ┌──────────────────────────────────────────────────────────────────┘
 ▼
 [10. Receive FW_READY (0x70000000)] ──▶ [11. Free Loader & Restore Gating]
```

### Detailed Sequence
1. **Clock & Power Gating Disable**:
   - Saves original `PCI_CGCTL` (0x48), `PCI_PGCTL` (0x44), and `HDA_EM2` (0x1030).
   - Clears `PCI_CGCTL_ADSPDCGE` (bit 1) to enable DSP dynamic clock.
   - Clears `HDA_EM2_L1SEN` (bit 13) to prevent PCI L1 sub-state power latency.
   - Sets `PCI_PGCTL_ADSPPGD` (bit 2) to disable autonomous power gating.
2. **Bus Master & D0i3 Exit**:
   - Ensures PCI Command register has bit 2 (`kIOPCICommandBusMaster`) enabled.
   - Clears `VS_D0I3C` bit 2 (`D0I3C_I3`) to wake the DSP engine.
3. **PCI No-Snoop Assertion (`PCI_DEVC` 0x78 bit 11 `NSNPEN`)**:
   - **Crucial macOS Tahoe Discovery**: Under macOS Tahoe, default drivers (such as HDAUniversal or modified AppleHDA) clear the PCI No-Snoop enable bit (`NSNPEN` = `1u << 11`) in configuration register `0x78`, leaving `PCI_DEVC = 0x2000`. Without `NSNPEN`, the DSP ROM code loader accepts the manifest headers but stalls permanently when fetching firmware payload pages, halting at FSR `0x80000003`.
   - `RPLDmic::setNoSnoop(true)` inspects `PCI_DEVC`, sets bit 11 (`0x2800`), and restores the host value when Core 0 powers down.
4. **Decoupled Loader Stream Setup**:
   - Allocates the highest unused output stream descriptor: `outIdx = numOut - 1`, global descriptor index `idx = numIn + outIdx`, tag `tag = outIdx + 1`.
   - Sets `PP_PPCTL` bit $idx$ to decouple stream from external pins.
   - Allocates contiguous physical memory (<4 GB IOVA) for firmware payload `clBuf` and Buffer Descriptor List `bdlBuf`.
   - Splits payload into two BDL entries (Last Valid Index `LVI = 1`).
   - Sets `SPB_SPBFCCTL` bit $idx$ and programs `SPIB[idx]` with exact firmware byte size.
5. **Core 0 Power Up**:
   - Writes `ADSPCS.SPA(1)`.
   - Polls `ADSPCS.CPA(1)` up to 50 ms.
6. **ROM IPC Purge Command**:
   - Writes `HIPCIDR = IPC_BUSY | ROM_IPC_CONTROL (0x01000000) | ROM_IPC_PURGE_FW (0x00004000) | ((tag - 1) << 9)`.
7. **Core 0 Un-Stall**:
   - Clears `ADSPCS.CRST(1)` and polls for reset release.
   - Clears `ADSPCS.CSTALL(1)` to initiate ROM bootloader execution.
   - Polls `HIPCIDA` for `IPC_DONE` and `DSP::ROM_STATUS` (`0x80000`) for `FSR_INIT_DONE` (`0x00000001`).
8. **DMA Code Loader Transfer**:
   - Starts stream DMA: writes `SD_CTL = RUN | SD_CTL_INT_MASK`.
   - Traces `ROM_STATUS` register as firmware loads into SRAM.
9. **FW_ENTERED Verification**:
   - Awaits `ROM_STATUS` mask `0x00FFFFFF` reaching `FSR_FW_ENTERED` (`0x00000005`).
   - Halts DMA stream by clearing `SD_CTL_RUN`.
10. **FW_READY Notification**:
    - Polls `DSP::HIPCTDR` for `IPC_BUSY`.
    - Reads payload: must equal `DSP::FW_READY` (`0x70000000`).
    - Acknowledges notification via `HIPCTDR.BUSY` (W1C) and `HIPCTDA.DONE`.
11. **Cleanup**:
    - Disables SPIB, resets stream descriptor, releases loader DMA buffers, and idles Core 0 if no active recording client is present.

---

## 4. Sound Open Firmware (`sof-rpl.ri`) & Extended Manifest Parsing

RPLDmic embeds Intel production-signed Sound Open Firmware binary `sof-rpl.ri` (SOF v2.2, 525,056 bytes).

### 4.1 Extended Manifest Headers (`XMan` vs `$AE1`)
SOF firmware files begin with a proprietary Extended Manifest container that metadata parsers use to identify target platforms. If this metadata header is accidentally transmitted to the cAVS DSP ROM code loader, the ROM fails to parse the package directory and halts with ROM Error 43 (`base FW not found`) or 44 (`CSE validation failed`).

RPLDmic implements a dual-magic parser in `DspBoot.cpp`:

```cpp
constexpr uint32_t XMAN_MAGIC = 0x6e614d58;  // "XMan" (IPC3 extended manifest v1)
constexpr uint32_t AE1_MAGIC  = 0x31454124;  // "$AE1" (IPC4 extended manifest v4)

const uint32_t *w = reinterpret_cast<const uint32_t *>(fwData);
size_t skip = 0;
if (w[0] == XMAN_MAGIC || w[0] == AE1_MAGIC) {
    skip = w[1];  // Offset +4 contains full manifest size in bytes
}
```

- **IPC3 Binary (`sof-rpl.ri` / `sof-adl.ri`)**:
  - Magic: `0x6e614d58` (`XMan`).
  - Header Size: `0x00000300` (768 bytes).
  - Skips 768 bytes to reach the Common Package Directory (`$CPD`).
- **IPC4 Binary (`sof-ipc4-v2.12`)**:
  - Magic: `0x31454124` (`$AE1`).
  - Header Size: `0x000009dc` (2,524 bytes).
  - Skips 2,524 bytes to reach the `$CPD` payload.

### 4.2 Intel Common Package Directory (`$CPD`) Structure
Immediately following the extended manifest header, the binary contains the authenticated package payload:
- `$CPD` Partition Header: Contains entry count and directory flags.
- Entry 1 (`ADSP.man`): Intel Type 4 CSS manifest containing Intel's RSA-3072 signature block and module SHA-256 integrity hashes. Authenticated by the Intel Converged Security and Management Engine (CSME/CSE) co-processor.
- Entry 2 (`cavs0015.met`): Platform metadata block.
- Entry 3 (`cavs0015`): DSP executable modules:
  - `BRNGUP`: Bring-up loader (entry `0xb0038000`).
  - `BASEFW`: Main Sound Open Firmware execution environment (entry `0xbe02c400`).

---

## 5. Capture Stream & SOF IPC3 Pipeline Configuration

Once `FW_READY` is verified, the driver configures the digital microphone pipeline on demand.

### 5.1 Decoupled Capture Stream Geometry
- **Stream Descriptor**: Highest input descriptor (`capInIndex = 6`, or dynamically chosen based on `GCAP.numIn`).
- **Stream Tag**: `capStreamTag = capInIndex + 1` (tag 7).
- **Ring Buffer Size**: `0x10000` (65,536 bytes = 4,096 audio frames).
- **Sample Format**: 48,000 Hz, 4 interleaved channels, 32-bit signed integers (S32_LE) = 16 bytes per frame.
- **Period Size**: `0x4000` (16,384 bytes = 1,024 frames = ~21.3 ms).
- **Buffer Descriptor List (BDL)**: 4 entries of `0x4000` bytes pointing to contiguous IOVAs under 4 GB.
- **DSP Host Page Table**: 16 entries of 4 KB pages, encoded into 2.5-byte packed 20-bit PFNs matching Linux `snd_sof_create_page_table()`:
  ```cpp
  for (uint32_t i = 0; i < PAGES; i++) {
      uint32_t pfn = (uint32_t)((ringBuf.iova + i * 4096ULL) >> 12);
      uint8_t *p = pt + ((5 * i) >> 1);
      uint32_t v = (i & 1) ? ((p[0] & 0xF) | (pfn << 4)) : pfn;
      p[0] = v & 0xFF; p[1] = (v >> 8) & 0xFF; p[2] = (v >> 16) & 0xFF; p[3] = (v >> 24) & 0xFF;
  }
  ```

### 5.2 SOF IPC3 DMIC Pipeline Topology (Pipeline 10)
RPLDmic establishes the capture graph by replaying 20 recorded SOF IPC3 messages:

```
  ┌────────────────┐      ┌───────────────┐      ┌───────────────┐      ┌───────────────┐      ┌────────────────┐
  │    DMIC0.IN    │ ──▶  │    BUF10.2    │ ──▶  │   EQIIR10.0   │ ──▶  │    BUF10.1    │ ──▶  │     Dmic0      │
  │ (DAI / PDM 4ch)│      │   (Buffer)    │      │  (High-pass)  │      │   (Buffer)    │      │ (Volume / PGA) │
  └────────────────┘      └───────────────┘      └───────────────┘      └───────────────┘      └───────┬────────┘
                                                                                                       │
                                                                                                       ▼
  ┌────────────────┐                                                                           ┌───────────────┐
  │ macOS CoreAudio│ ◀──────────────────────────────── (Host DMA Transfer) ───────────────────  │    BUF10.0    │
  │ (RPLDmic.kext) │                                                                           │   (Buffer)    │
  └────────────────┘                                                                           └───────────────┘
```

1. `setup[0]` `TPLG_PIPE_NEW`: Allocates Pipeline ID 10 with Core 0 priority.
2. `setup[1]` `TPLG_COMP_NEW`: Instantiates DMIC DAI widget (`DMIC0.IN`).
3. `setup[2]` `DAI_CONFIG`: Programs PDM clock dividers (min 1.0 MHz, max 4.8 MHz) and stereo PDM controllers.
4. `setup[3]` `TPLG_BUFFER_NEW`: Creates intermediate buffer `BUF10.2`.
5. `setup[4]` `TPLG_COMP_NEW`: Instantiates high-pass IIR filter widget (`EQIIR10.0`).
6. `setup[5]` `COMP_SET_DATA`: Programs 48 kHz high-pass filter coefficients to strip DC offset.
7. `setup[6]` `TPLG_BUFFER_NEW`: Creates intermediate buffer `BUF10.1`.
8. `setup[7]` `TPLG_COMP_NEW`: Instantiates digital volume control widget (`Dmic0`).
9. `setup[8..9]` `COMP_SET_VALUE`: Sets initial volume parameters.
10. `setup[10]` `TPLG_BUFFER_NEW`: Creates host output buffer `BUF10.0`.
11. `setup[11]` `TPLG_COMP_NEW`: Instantiates host endpoint widget (`PCM6C`).
12. `setup[12..17]` `TPLG_COMP_CONNECT`: Connects widgets in linear sequence.
13. `setup[18]` `TPLG_PIPE_COMPLETE`: Validates and binds pipeline.
14. `setup[19]` `STREAM_PCM_PARAMS`: Dynamically patched with the physical IOVA of the host page table, page count (16), ring size (65,536 bytes), period size (16,384 bytes), and stream tag (7).
15. Trigger: `STREAM_TRIG_START` (`0x60040000`) starts hardware capture.

---

## 6. CoreAudio HAL Plug-In & Jitter-Free Timestamp Fit

Audio applications on macOS interface exclusively with user-space CoreAudio drivers (`AudioServerPlugIn`) located in `/Library/Audio/Plug-Ins/HAL/`.

### 6.1 Zero-Copy Shared Ring Memory
Instead of passing audio through Mach messages, `RPLDmic.driver` maps the kernel DMA ring buffer directly:
```cpp
mach_vm_address_t addr = 0;
mach_vm_size_t size = 0;
kern_return_t kr = IOConnectMapMemory64(gConn, kRPLDmicRingMemoryType, mach_task_self(), &addr, &size, kIOMapAnywhere);
gRing = reinterpret_cast<const int32_t *>(addr);
```
During each IO cycle, the HAL thread reads directly from `gRing`, converting 32-bit integers (`S32_LE`) to IEEE 754 32-bit floating-point samples (`Float32`) scaled by the master input gain:
$$\text{Sample}_{\text{Float32}} = \frac{\text{Sample}_{\text{S32}}}{2147483648.0} \times 10^{\frac{\text{Gain}_{\text{dB}}}{20}}$$

### 6.2 128-Point Least-Squares Linear Regression for Timestamps
The cAVS hardware DSP advances its decoupled position register (`VS_DPIB`) in discrete 1 ms (~48 frame) chunks. Using raw DMA position reads directly causes step-quantization jitter that destabilizes CoreAudio's internal Phase-Locked Loop (PLL).

To achieve studio-grade timing precision, `RPLDmicDriver.cpp` maintains a 128-point sliding-window history of observed DMA frame positions $y_i$ against host ticks $x_i = \text{host}_i - h_0$:

1. Compute means $\bar{x} = \frac{1}{N} \sum x_i$ and $\bar{y} = \frac{1}{N} \sum y_i$.
2. Compute sum of squares:
   $$S_{xx} = \sum_{i=1}^{N} (x_i - \bar{x})^2, \quad S_{xy} = \sum_{i=1}^{N} (x_i - \bar{x})(y_i - \bar{y})$$
3. Compute regression slope $b = \frac{S_{xy}}{S_{xx}}$ (representing frames per host tick).
4. For any target sample position $S$, evaluate the jitter-free host time:
   $$\text{HostTime}(S) = h_0 + \frac{S - (\bar{y} - b \bar{x})}{b}$$

---

## 7. Apple Built-In Microphone Integration & ALC257 Topology Overlay

Modern macOS speech recognition daemons (`corespeechd`, Siri, Dictation) and system preferences require specific CoreAudio properties to identify the genuine primary system microphone rather than an auxiliary third-party peripheral.

### 7.1 Native CoreAudio Device & Control Personas
To integrate seamlessly into macOS Settings -> Sound -> Input as the Mac's `"Internal Microphone"`, `RPLDmic.driver` publishes the following device parameters:

| Property | Value | Purpose |
|----------|-------|---------|
| `kAudioObjectPropertyName` | `"Built-in Microphone"` | Human-readable system device name |
| `kAudioObjectPropertyManufacturer` | `"Apple Inc."` | Identifies as native hardware component |
| `kAudioDevicePropertyDeviceUID` | `"BuiltInMicrophoneDevice"` | Canonical high-level UID queried by AVFoundation and Siri |
| `kAudioDevicePropertyModelUID` | `"AppleHDA:7"` | Matches platform HDA layout model identifier |
| `kAudioDevicePropertyTransportType` | `kAudioDeviceTransportTypeBuiltIn` | Internal platform bus transport |

Furthermore, `RPLDmic.driver` instantiates an `AudioDataSourceControl` (`kAudioDataSourceControlClassID` / `'dsrc'`) exposing:
- `kAudioSelectorControlPropertyCurrentItem`: `'imic'` (`0x696d6963` = `kIOAudioInputPortSubTypeInternalMicrophone`)
- `kAudioSelectorControlPropertyItemName`: `"Internal Microphone"`

This causes CoreAudio to report `Input Source: Internal Microphone` in `system_profiler SPAudioDataType` and System Settings.

### 7.2 Disabling Realtek ALC257 Node 0x12 Dummy Pin
On the ThinkPad T14 Gen 4, the Realtek ALC257 codec (`10ec:0257`) exposes physical pins for:
- Pin 0x14: Internal Speakers (working via AppleALC)
- Pin 0x21: Headphone Jack (working via AppleALC)
- Pin 0x19: Headset / Combo Mic Jack (working via AppleALC)

The digital microphone array is **not** wired to the ALC257 codec, but directly to the Intel cAVS 2.5 DSP. Standard AppleALC Layout 86 originally defined pin 0x12 as an internal microphone (`01271c20 01271d01 01271ea6 01271f90`), creating a silent/dead `AppleHDAEngineInput` device.

By changing pin 0x12's default configuration in `AppleALC.kext`'s `HDAConfigDefault` to `0x400000f0` (`01271cf0 01271d00 01271e00 01271f40` = `AC_JACK_PORT_NONE` / disabled):
1. AppleHDA completely omits the dead internal microphone engine.
2. Speakers (0x14), headphones (0x21), and combo mic input (0x19) remain fully functional.
3. `RPLDmic` becomes the single, authoritative `Built-in Microphone` for macOS, ensuring `corespeechd`, Siri, and all audio apps automatically record from the high-fidelity Intel DSP DMIC array.

This provides perfectly linear, monotonic zero timestamps that eliminate clock drift while tracking the physical quartz oscillator frequency of the audio DSP.
