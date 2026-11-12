#include "RPLDmic.hpp"
#include "Regs.hpp"
#include "RPLDmicShared.h"
#include <IOKit/IOLib.h>
#include <libkern/version.h>

#define super IOService
OSDefineMetaClassAndStructors(RPLDmic, IOService)

#include <stdarg.h>
#define LOG(fmt, ...) logLine(fmt, ##__VA_ARGS__)
static constexpr unsigned kLogLines = 128;

static constexpr uint32_t kPollMs = 2000;      // stream observation interval
static constexpr uint32_t kPollCount = 90;     // 3 minutes, then stop polling

static bool bootArg(const char *name) {
    char buf[16];
    return PE_parse_boot_argn(name, buf, sizeof(buf));
}

static IOPMPowerState gPowerStates[2] = {
    { kIOPMPowerStateVersion1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    { kIOPMPowerStateVersion1, kIOPMPowerOn | kIOPMDeviceUsable, kIOPMPowerOn, kIOPMPowerOn, 0, 0, 0, 0, 0, 0, 0, 0 },
};

// Become a power child of the HDA driver once it has attached. While we hold
// state 1 the HDA driver cannot enter its idle state (in which it holds the controller
// in reset CRST=0, wiping DSP state). Never joins the PCI device directly.
void RPLDmic::joinPowerParent() {
    if (pmJoined || !serviceMode) return;
    IOService *parent = nullptr;
    if (OSIterator *it = pci->getChildIterator(gIOServicePlane)) {
        while (OSObject *o = it->getNextObject()) {
            IOService *s = OSDynamicCast(IOService, o);
            if (!s || s == this || s->isInactive()) continue;
            const char *cn = s->getMetaClass()->getClassName();
            if (cn && (strnstr(const_cast<char *>(cn), "HDA", 64) || strnstr(const_cast<char *>(cn), "Audio", 64))) {
                parent = s;
                break;
            }
        }
        it->release();
    }
    if (!parent) {
        if (++pmSearchTicks == 30) {
            LOG("PM: no HDA driver on this controller - operating without power child tree");
            pmSearchTicks = 1000;
        }
        return;
    }
    const char *pcn = parent->getMetaClass()->getClassName();
    int pmArg = -1;
    if (!PE_parse_boot_argn("rpldmicpm", &pmArg, sizeof(pmArg))) {
        PE_parse_boot_argn("tgldmicpm", &pmArg, sizeof(pmArg));
    }
    bool join = pmArg == 1 || (pmArg != 0 && (strnstr(const_cast<char *>(pcn), "AppleHDA", 64) || strnstr(const_cast<char *>(pcn), "SimpleHDA", 64)));
    if (!join) {
        LOG("PM: HDA driver is %s - not joining its power tree (controller managed independently)%s",
            pcn, pmArg == 0 ? " [pm=0]" : "");
        pmSearchTicks = 1000;
        return;
    }
    PMinit();
    parent->joinPMtree(this);
    if (registerPowerDriver(this, gPowerStates, 2) != kIOReturnSuccess) {
        PMstop();
        LOG("PM: registerPowerDriver failed - running without power holds");
        pmSearchTicks = 1000;
        return;
    }
    pmParent = parent;
    pmParent->retain();
    pmJoined = true;
    changePowerStateTo(0);                             // idle until a client records
    LOG("PM: power child of %s (power state %u)", parent->getMetaClass()->getClassName(), (unsigned)parent->getPowerState());
}

IOReturn RPLDmic::setPowerState(unsigned long state, IOService *) {
    unsigned long old = pmState;
    pmState = state;
    if (state == 0 && old == 1 && gate && (streaming || setupDone)) gate->runAction(gatedPowerLost);
    return kIOPMAckImplied;
}

const char *RPLDmic::platformName() const {
    switch (platformFamily) {
        case kPlatformRaptorLake: return "Raptor Lake (cAVS 2.5)";
        case kPlatformTigerLake:  return "Tiger Lake (cAVS 2.5)";
        case kPlatformCometLake:  return "Comet Lake / Cannon Lake (cAVS 1.8)";
        default: return "Unknown";
    }
}

IOService *RPLDmic::probe(IOService *provider, SInt32 *score) {
    if (bootArg("-rpldmicoff") || bootArg("-tgldmicoff")) return nullptr;
    auto dev = OSDynamicCast(IOPCIDevice, provider);
    if (!dev) return nullptr;

    pciId = dev->configRead32(kIOPCIConfigVendorID);
    uint16_t vendor = pciId & 0xFFFF;
    uint16_t device = (pciId >> 16) & 0xFFFF;

    if (vendor != 0x8086) {
        IOLog("RPLDmic: probe: unexpected PCI vendor %04x (id %08x), not attaching\n", vendor, pciId);
        return nullptr;
    }

    subId = dev->configRead32(kIOPCIConfigSubSystemVendorID);
    uint16_t subVendor = subId & 0xFFFF;
    uint16_t subDevice = (subId >> 16) & 0xFFFF;

    platformFamily = kPlatformUnknown;
    switch (device) {
        // Raptor Lake-P/U/H family (cAVS 2.5)
        case 0x51CA: // Raptor Lake-P/U/H native cAVS 2.5 (e.g. ThinkPad T14 Gen 4)
        case 0x51C8: // Raptor Lake spoofed ID (e.g. for AppleHDA/SimpleHDA matching)
            platformFamily = kPlatformRaptorLake;
            break;

        // Tiger Lake family (cAVS 2.5)
        case 0xA0C8: // Tiger Lake-LP (11th-gen Core, UP3/UP4)
        case 0x43C8: // Tiger Lake-H
            platformFamily = kPlatformTigerLake;
            break;

        // Comet Lake / Cannon Lake / Coffee Lake family (cAVS 1.8)
        case 0x02C8: // Comet Lake PCH-LP (Lenovo ThinkPad X1 Carbon Gen 7 i7-10710U / i5-10210U)
        case 0x9DC8: // Cannon Lake / Whiskey Lake PCH-LP (Lenovo ThinkPad X1 Carbon Gen 7 i7-8565U)
        case 0x06C8: // Comet Lake PCH-H
        case 0xA348: // Cannon Point / Coffee Lake PCH-H
        case 0x34C8: // Ice Lake-LP spoof
            platformFamily = kPlatformCometLake;
            break;

        default:
            break;
    }

    // Explicit boot-arg overrides:
    // -rpldmicrpl / -tgldmicrpl: force Raptor Lake cAVS 2.5 mode
    // -rpldmictgl / -tgldmictgl: force Tiger Lake cAVS 2.5 mode
    // -rpldmiccml / -tgldmiccml: force Comet Lake cAVS 1.8 mode
    // -rpldmicforce / -tgldmicforce: attach regardless of PCI ID
    if (bootArg("-rpldmicrpl") || bootArg("-tgldmicrpl")) {
        platformFamily = kPlatformRaptorLake;
    } else if (bootArg("-rpldmictgl") || bootArg("-tgldmictgl")) {
        platformFamily = kPlatformTigerLake;
    } else if (bootArg("-rpldmiccml") || bootArg("-tgldmiccml")) {
        platformFamily = kPlatformCometLake;
    }

    if (platformFamily == kPlatformUnknown) {
        if (bootArg("-rpldmicforce") || bootArg("-tgldmicforce")) {
            platformFamily = kPlatformRaptorLake;
            IOLog("RPLDmic: probe: forced attach on unlisted PCI ID 8086:%04x (-rpldmicforce)\n", device);
        } else {
            IOLog("RPLDmic: probe: unrecognised PCI id 8086:%04x (id %08x), not attaching (use -rpldmicforce to override)\n",
                  device, pciId);
            return nullptr;
        }
    }

    IOLog("RPLDmic: probe: attaching to %s (PCI 8086:%04x, subsystem %04x:%04x%s)\n",
          platformName(), device, subVendor, subDevice,
          (subVendor == 0x17aa && subDevice == 0x230e) ? " [ThinkPad T14 Gen 4]" : "");
    return super::probe(provider, score);
}

void RPLDmic::logLine(const char *fmt, ...) {
    char buf[200];
    va_list ap; va_start(ap, fmt); vsnprintf(buf, sizeof(buf), fmt, ap); va_end(ap);
    IOLog("RPLDmic: %s\n", buf);
    if (!logRing) logRing = OSArray::withCapacity(kLogLines);
    if (!logRing) return;
    if (logRing->getCount() >= kLogLines) logRing->removeObject(0);
    if (auto s = OSString::withCString(buf)) { logRing->setObject(s); s->release(); }
}

bool RPLDmic::memoryDecoded() {
    return pci->configRead16(kIOPCIConfigCommand) & kIOPCICommandMemorySpace;
}

// Only trust BAR0 once memory decoding is on, the device is in D0 and GCAP looks sane.
bool RPLDmic::tryInit() {
    if (ready) return true;
    if (!memoryDecoded() || !inD0()) return false;
    if (!(r32(HDA::GCTL) & 1)) {                     // CRST=0: HDA driver idle; registers read 0 until it wakes
        if (!resetLogged) { LOG("controller held in reset (GCTL 0x%08x) - HDA driver idle", r32(HDA::GCTL)); resetLogged = true; }
        return false;
    }
    uint16_t gcap = r16(HDA::GCAP);
    if (gcap == 0xFFFF || gcap == 0) { badReads++; return false; }
    if (!(r32(HDA::LLCH) & HDA::CAP_NEXT_MASK)) { badReads++; return false; }   // capability list not readable yet
    numOut = (gcap >> 12) & 0xF; numIn = (gcap >> 8) & 0xF; numBidi = (gcap >> 3) & 0x1F;
    LOG("GCAP 0x%04x: %u in, %u out, %u bidi; HDA %u.%u; GCTL 0x%08x STATESTS 0x%04x (after %u bad reads)",
        gcap, numIn, numOut, numBidi, r8(HDA::VMAJ), r8(HDA::VMIN), r32(HDA::GCTL), r16(HDA::STATESTS), badReads);
    walkCapabilities();
    if (!ppOffset) {                                  // controller went away mid-walk (D3/reset): try again
        if (++capRetries <= 3) LOG("capability list unreadable (LLCH 0x%08x) - retrying", memoryDecoded() ? r32(HDA::LLCH) : 0);
        mlOffset = spbOffset = drsmOffset = 0;
        return false;
    }
    capInIndex = (numIn > 6) ? 6 : (numIn > 0 ? numIn - 1 : 0);
    int inArg = -1;
    if ((PE_parse_boot_argn("rpldmicin", &inArg, sizeof(inArg)) ||
         PE_parse_boot_argn("tgldmicin", &inArg, sizeof(inArg))) && inArg >= 0 && (uint32_t)inArg < numIn)
        capInIndex = (uint32_t)inArg;
    capStreamTag = capInIndex + 1;
    LOG("cap: configured input stream %u, tag %u", capInIndex, capStreamTag);
    ready = true;
    snapshot(true);
    return true;
}

bool RPLDmic::inD0() {
    uint8_t pm = 0;
    if (!pci->findPCICapability(kIOPCIPowerManagementCapability, &pm)) return true;
    return (pci->configRead16(pm + 4) & 0x3) == 0;   // PMCSR.PowerState
}

bool RPLDmic::start(IOService *provider) {
    if (!super::start(provider)) return false;
    pci = OSDynamicCast(IOPCIDevice, provider);
    if (!pci) return false;
    pci->retain();
    readDsp = bootArg("-rpldmicdsp") || bootArg("-tgldmicdsp");
    captureRequested = bootArg("-rpldmiccap") || bootArg("-tgldmiccap");
    serviceMode = (bootArg("-rpldmic") || bootArg("-tgldmic")) && !captureRequested;
    bootRequested = bootArg("-rpldmicboot") || bootArg("-tgldmicboot") || captureRequested || serviceMode;
    if (serviceMode) { keepRunning = false; bootDelaySec = 10; }   // boot-time boot = self-test, then power down
    uint32_t delay = 0;
    if ((PE_parse_boot_argn("rpldmicdelay", &delay, sizeof(delay)) ||
         PE_parse_boot_argn("tgldmicdelay", &delay, sizeof(delay))) && delay >= 10 && delay <= 170)
        bootDelaySec = delay;
    keepRunning = bootArg("-rpldmickeep") || bootArg("-tgldmickeep");

    LOG("RPLDmic v%s on %s (Darwin %d.%d), platform=%s, dsp-reads=%s, dsp-boot=%s%s",
        kRPLDmicVersionString, provider->getName(), version_major, version_minor, platformName(),
        readDsp ? "on" : "off", bootRequested ? "ON" : "off", keepRunning ? " (keep running)" : "");
    if (bootRequested) LOG("DSP boot%s scheduled %u s after the controller is ready%s", captureRequested ? " + capture" : "",
                           bootDelaySec, serviceMode ? " (service mode: DSP stays up, mic exposed to Core Audio)" : "");

    bar0 = pci->mapDeviceMemoryWithRegister(kIOPCIConfigBaseAddress0);
    if (!bar0) { LOG("cannot map BAR0"); return false; }
    hda = reinterpret_cast<volatile uint8_t *>(bar0->getVirtualAddress());
    LOG("BAR0 phys 0x%llx len 0x%llx", (unsigned long long)bar0->getPhysicalAddress(),
        (unsigned long long)bar0->getLength());

    if (readDsp) {
        bar4 = pci->mapDeviceMemoryWithRegister(kIOPCIConfigBaseAddress4);
        if (bar4) {
            dsp = reinterpret_cast<volatile uint8_t *>(bar4->getVirtualAddress());
            LOG("BAR4 phys 0x%llx len 0x%llx", (unsigned long long)bar4->getPhysicalAddress(),
                (unsigned long long)bar4->getLength());
        } else LOG("cannot map BAR4");
    }

    LOG("at start: PCI CMD 0x%04x, D0=%d", pci->configRead16(kIOPCIConfigCommand), inD0());
    if (!tryInit()) LOG("controller not decoded yet (AppleHDA/SimpleHDA not started?) - retrying from timer");

    workLoop = IOWorkLoop::workLoop();      // own loop: boot polling must not block the provider's
    if (workLoop) {
        gate = IOCommandGate::commandGate(this);
        if (gate && workLoop->addEventSource(gate) != kIOReturnSuccess) OSSafeReleaseNULL(gate);
        timer = IOTimerEventSource::timerEventSource(this, timerFired);
        if (timer && workLoop->addEventSource(timer) == kIOReturnSuccess)
            timer->setTimeoutMS(kPollMs);
    }
    publish();
    registerService();
    return true;
}

void RPLDmic::walkCapabilities() {
    uint32_t off = r32(HDA::LLCH) & HDA::CAP_NEXT_MASK;
    for (int n = 0; off && off < bar0->getLength() && n < 10; n++) {
        uint32_t hdr = r32(off);
        uint32_t id = (hdr & HDA::CAP_ID_MASK) >> HDA::CAP_ID_SHIFT;
        switch (id) {
            case HDA::CAP_PP:   ppOffset = off; break;
            case HDA::CAP_ML:   mlOffset = off; break;
            case HDA::CAP_SPB:  spbOffset = off; break;
            case HDA::CAP_DRSM: drsmOffset = off; break;
        }
        LOG("ext cap @0x%04x id %u hdr 0x%08x", off, id, hdr);
        off = hdr & HDA::CAP_NEXT_MASK;
    }
    if (ppOffset)
        LOG("PP: PPCH 0x%08x PPCTL 0x%08x PPSTS 0x%08x", r32(ppOffset + HDA::PP_PPCH),
            r32(ppOffset + HDA::PP_PPCTL), r32(ppOffset + HDA::PP_PPSTS));
}

void RPLDmic::snapshot(bool verbose) {
    uint32_t total = numIn + numOut + numBidi;
    if (total > 30) total = 30;
    // Decoupled descriptors (PPCTL PROCEN) feed the DSP: those are RPLDmic's own streams, never the
    // HDA driver's link streams. Also skip our capture descriptor while we own it.
    uint32_t ours = ppOffset ? (r32(ppOffset + HDA::PP_PPCTL) & 0x3FFFFFFF) : 0;
    if (ours == 0x3FFFFFFF) ours = 0;                    // all-ones read: ignore
    if (streaming || setupDone) ours |= 1u << capInIndex;
    for (uint32_t i = 0; i < total; i++) {
        if (ours & (1u << i)) continue;
        uint32_t base = HDA::SD_BASE + i * HDA::SD_STRIDE;
        uint32_t ctl = r32(base + HDA::SD_CTL);
        if (ctl == 0xFFFFFFFF) { badReads++; return; }   // controller went away (D3/reset): skip this sample
        uint32_t tag = (ctl >> HDA::SD_CTL_TAG_SHIFT) & 0xF;
        bool run = ctl & HDA::SD_CTL_RUN;
        if (tag) tagsSeen[i] = tag;
        if (run && !(everRunning & (1u << i))) {
            everRunning |= 1u << i;
            LOG("stream %u (%s%u) started: CTL 0x%08x tag %u FMT 0x%04x CBL %u LVI %u",
                i, i < numIn ? "in" : "out", i < numIn ? i : i - numIn, ctl, tag,
                r16(base + HDA::SD_FMT), r32(base + HDA::SD_CBL), r16(base + HDA::SD_LVI));
        } else if (verbose) {
            LOG("stream %u (%s%u): CTL 0x%08x tag %u", i, i < numIn ? "in" : "out",
                i < numIn ? i : i - numIn, ctl, tag);
        }
    }
    if (dsp && verbose)
        LOG("DSP: ADSPCS 0x%08x ADSPIS 0x%08x HIPCIDR 0x%08x HIPCIDA 0x%08x",
            d32(DSP::ADSPCS), d32(DSP::ADSPIS), d32(DSP::HIPCIDR), d32(DSP::HIPCIDA));
}

void RPLDmic::publish() {
    setProperty("RPLDmicVersion", kRPLDmicVersionString);
    setProperty("RPLDmicInterface", (unsigned long long)kRPLDmicInterfaceVersion, 32);
    // Backward compatibility property for legacy tools
    setProperty("TGLDmicVersion", kRPLDmicVersionString);
    setProperty("TGLDmicInterface", (unsigned long long)kRPLDmicInterfaceVersion, 32);
    setProperty("RPLDmicPhase", serviceMode ? 4ULL : captureRequested ? 3ULL : bootRequested ? 2ULL : 1ULL, 32);
    if (serviceMode) {
        setProperty("ServiceClients", startCount, 32);
        setProperty("Streaming", streaming);
        setProperty("StreamGeneration", generation, 64);
        setProperty("PowerHold", pmState == 1);
    }
    setProperty("StreamsIn", numIn, 32);
    setProperty("StreamsOut", numOut, 32);
    setProperty("UsedStreamMask", everRunning, 32);
    setProperty("PPOffset", ppOffset, 32);
    setProperty("MLOffset", mlOffset, 32);
    setProperty("Samples", samples, 32);
    setProperty("Ready", ready);
    setProperty("BadReads", badReads, 32);
    setProperty("BootState", bootState, 32);
    if (bootResult[0]) setProperty("BootResult", bootResult);
    if (captureRequested) {
        setProperty("CaptureState", captureState, 32);
        if (captureResult[0]) setProperty("CaptureResult", captureResult);
        setProperty("CaptureBytes", capBytes, 64);
        if (captureState) {
            if (auto d = OSData::withBytes(chPeak, sizeof(chPeak))) { setProperty("CapturePeak", d); d->release(); }
            if (auto d = OSData::withBytes(chMeanAbs, sizeof(chMeanAbs))) { setProperty("CaptureMeanAbs", d); d->release(); }
        }
        if (capSnap && capSnap->getLength()) setProperty("CaptureSnapshot", capSnap);
        if (envLen) if (auto d = OSData::withBytes(env, envLen * 4)) { setProperty("CaptureEnvelope", d); d->release(); }
    }
    setProperty("PlatformFamily", platformName());
    setProperty("PciVendorDeviceId", pciId, 32);
    setProperty("PciSubsystemId", subId, 32);
    if (logRing) { if (auto copy = OSArray::withArray(logRing)) { setProperty("Log", copy); copy->release(); } }
    if (ready && ppOffset && hda) setProperty("PPCTL", r32(ppOffset + HDA::PP_PPCTL), 32);
    if (ready && dsp) setProperty("ADSPCS", d32(DSP::ADSPCS), 32);
    if (!ready) return;
    int spareIn = -1, spareOut = -1;
    for (int i = (int)numIn - 1; i >= 0; i--) if (!(everRunning & (1u << (uint32_t)i))) { spareIn = i; break; }
    for (int i = (int)numOut - 1; i >= 0; i--) if (!(everRunning & (1u << (numIn + (uint32_t)i)))) { spareOut = i; break; }
    setProperty("SpareInputStream", (unsigned long long)(spareIn < 0 ? 0xFF : spareIn), 32);
    setProperty("SpareOutputStream", (unsigned long long)(spareOut < 0 ? 0xFF : spareOut), 32);
}

void RPLDmic::watchdog() {
    wdTicks++;
    uint8_t pmCap = 0;
    uint16_t pm = pci->findPCICapability(kIOPCIPowerManagementCapability, &pmCap) ? (pci->configRead16(pmCap + 4) & 3) : 0;
    uint32_t gctl = 0, cs = 0;
    if (pm == 0 && memoryDecoded()) { gctl = r32(HDA::GCTL); if (dsp) cs = d32(DSP::ADSPCS); }
    if (pm != wdPm || gctl != wdGctl || cs != wdAdspcs)
        LOG("wd: t=%us D%u GCTL 0x%08x ADSPCS 0x%08x streaming %d clients %u", 180 + wdTicks * 10, pm, gctl, cs,
            streaming, startCount);
    wdPm = pm; wdGctl = gctl; wdAdspcs = cs;
}

void RPLDmic::timerFired(OSObject *owner, IOTimerEventSource *sender) {
    auto self = OSDynamicCast(RPLDmic, owner);
    if (!self) return;
    if (self->serviceMode && !self->pmJoined && self->pmSearchTicks < 1000) self->joinPowerParent();
    if (self->tryInit() && self->memoryDecoded() && self->inD0())
        self->snapshot(false);
    if (self->bootRequested && self->ready && self->bootState == 0 && self->samples * (kPollMs / 1000) >= self->bootDelaySec) {
        self->bootDsp();
        self->publish();
    }
    self->samples++;
    self->publish();
    if (self->samples < kPollCount) sender->setTimeoutMS(kPollMs);
    else {
        if (self->samples == kPollCount) self->logLine("observation finished: used stream mask 0x%08x", self->everRunning);
        if (self->serviceMode) { self->watchdog(); self->publish(); sender->setTimeoutMS(10000); }
        else self->publish();
    }
}

IOReturn RPLDmic::gatedShutdown(OSObject *o, void *, void *, void *, void *) {
    auto self = OSDynamicCast(RPLDmic, o);
    if (!self) return kIOReturnBadArgument;
    if (self->streaming || self->setupDone) self->pipelineStop();
    self->startCount = 0;
    if (self->bootState == 1 && self->keepRunning) self->corePowerDown();
    self->gating(true);
    self->releaseCaptureBuffers();
    return kIOReturnSuccess;
}

void RPLDmic::stop(IOService *provider) {
    if (gate) gate->runAction(gatedShutdown); else gatedShutdown(this, nullptr, nullptr, nullptr, nullptr);
    if (pmJoined) { PMstop(); pmJoined = false; }
    OSSafeReleaseNULL(pmParent);
    if (gate) { if (workLoop) workLoop->removeEventSource(gate); OSSafeReleaseNULL(gate); }
    if (timer) {
        timer->cancelTimeout();
        if (workLoop) workLoop->removeEventSource(timer);
        OSSafeReleaseNULL(timer);
    }
    OSSafeReleaseNULL(workLoop);
    OSSafeReleaseNULL(bar4);
    OSSafeReleaseNULL(bar0);
    hda = dsp = nullptr;
    super::stop(provider);
}

void RPLDmic::free() {
    OSSafeReleaseNULL(capSnap);
    OSSafeReleaseNULL(logRing);
    OSSafeReleaseNULL(pci);
    super::free();
}
