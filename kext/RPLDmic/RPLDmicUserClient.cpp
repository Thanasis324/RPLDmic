#include "RPLDmicUserClient.hpp"
#include "RPLDmicShared.h"
#include <IOKit/IOLib.h>

#define super IOUserClient
OSDefineMetaClassAndStructors(RPLDmicUserClient, IOUserClient)

const IOExternalMethodDispatch RPLDmicUserClient::sMethods[kRPLDmicMethodCount] = {
    // function       scalarIn structIn scalarOut structOut
    { &RPLDmicUserClient::sGetInfo,     0, 0, 6, 0 },
    { &RPLDmicUserClient::sStart,       0, 0, 0, 0 },
    { &RPLDmicUserClient::sStop,        0, 0, 0, 0 },
    { &RPLDmicUserClient::sGetPosition, 0, 0, 3, 0 },
};

bool RPLDmicUserClient::initWithTask(task_t owningTask, void *securityToken, UInt32 type, OSDictionary *properties) {
    if (type != kRPLDmicUserClientType) return false;
    if (!super::initWithTask(owningTask, securityToken, type, properties)) return false;
    task = owningTask;
    return true;
}

bool RPLDmicUserClient::start(IOService *provider) {
    owner = OSDynamicCast(RPLDmic, provider);
    if (!owner || !super::start(provider)) return false;
    owner->retain();
    return true;
}

void RPLDmicUserClient::stop(IOService *provider) {
    if (started && owner) { owner->clientStop(); started = false; }
    super::stop(provider);
}

IOReturn RPLDmicUserClient::clientClose() {
    if (started && owner) { owner->clientStop(); started = false; }
    OSSafeReleaseNULL(owner);
    if (!isInactive()) terminate();
    return kIOReturnSuccess;
}

void RPLDmicUserClient::free() {
    OSSafeReleaseNULL(owner);
    super::free();
}

IOReturn RPLDmicUserClient::clientDied() {
    return clientClose();
}

IOReturn RPLDmicUserClient::externalMethod(uint32_t selector, IOExternalMethodArguments *args,
                                           IOExternalMethodDispatch *dispatch, OSObject *target, void *reference) {
    if (selector >= kRPLDmicMethodCount) return kIOReturnUnsupported;
    dispatch = const_cast<IOExternalMethodDispatch *>(&sMethods[selector]);
    return super::externalMethod(selector, args, dispatch, this, reference);
}

IOReturn RPLDmicUserClient::sGetInfo(OSObject *target, void *, IOExternalMethodArguments *args) {
    auto self = OSDynamicCast(RPLDmicUserClient, target);
    if (!self || !self->owner) return kIOReturnNotAttached;
    args->scalarOutput[0] = kRPLDmicInterfaceVersion;
    args->scalarOutput[1] = self->owner->stateBits();
    args->scalarOutput[2] = RPLDmic::kRate;
    args->scalarOutput[3] = RPLDmic::kChannels;
    args->scalarOutput[4] = RPLDmic::kRingBytes;
    args->scalarOutput[5] = RPLDmic::kFrameBytes;
    return kIOReturnSuccess;
}

IOReturn RPLDmicUserClient::sStart(OSObject *target, void *, IOExternalMethodArguments *) {
    auto self = OSDynamicCast(RPLDmicUserClient, target);
    if (!self || !self->owner) return kIOReturnNotAttached;
    if (self->started) return kIOReturnSuccess;
    IOReturn r = self->owner->clientStart();
    if (r == kIOReturnSuccess) self->started = true;
    return r;
}

IOReturn RPLDmicUserClient::sStop(OSObject *target, void *, IOExternalMethodArguments *) {
    auto self = OSDynamicCast(RPLDmicUserClient, target);
    if (!self || !self->owner) return kIOReturnNotAttached;
    if (!self->started) return kIOReturnSuccess;
    self->started = false;
    return self->owner->clientStop();
}

IOReturn RPLDmicUserClient::sGetPosition(OSObject *target, void *, IOExternalMethodArguments *args) {
    auto self = OSDynamicCast(RPLDmicUserClient, target);
    if (!self || !self->owner) return kIOReturnNotAttached;
    uint64_t pos = 0, host = 0, gen = 0;
    IOReturn r = self->owner->readPosition(&pos, &host, &gen);
    args->scalarOutput[0] = pos;
    args->scalarOutput[1] = host;
    args->scalarOutput[2] = gen;
    return r;
}

IOReturn RPLDmicUserClient::clientMemoryForType(UInt32 type, IOOptionBits *options, IOMemoryDescriptor **memory) {
    if (type != kRPLDmicRingMemoryType || !owner) return kIOReturnBadArgument;
    IOMemoryDescriptor *md = owner->ringMemory();      // retained; IOUserClient releases it
    if (!md) return kIOReturnNoMemory;
    *options = kIOMapReadOnly;
    *memory = md;
    return kIOReturnSuccess;
}
