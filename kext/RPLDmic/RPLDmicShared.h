// Interface shared by RPLDmic.kext (RPLDmicUserClient) and RPLDmic.driver (HAL plug-in).
#pragma once

#define kRPLDmicServiceClass   "RPLDmic"
#define kRPLDmicUserClientType 0          // IOServiceOpen type
#define kRPLDmicRingMemoryType 0          // IOConnectMapMemory64 type: the 64 KB capture ring (read-only)

// Geometry and stream definitions
#define kRPLDmicRingBytes      0x10000    // 64 KB physically contiguous DMA circular buffer
#define kRPLDmicChannels       4          // 4 interleaved channels (S32_LE)
#define kRPLDmicSampleRate     48000      // 48 kHz
#define kRPLDmicFrameBytes     16         // 4 channels * 4 bytes/channel (S32_LE)
#define kRPLDmicRingFrames     (kRPLDmicRingBytes / kRPLDmicFrameBytes) // 4096 frames

enum {
    kRPLDmicMethodGetInfo     = 0,   // out: version, state bits, rate, channels, ring bytes, frame bytes
    kRPLDmicMethodStart       = 1,   // out: none. Boots the DSP if needed and starts the DMIC pipeline
    kRPLDmicMethodStop        = 2,   // out: none
    kRPLDmicMethodGetPosition = 3,   // out: DMA write position in ring (bytes), mach_absolute_time, generation
    kRPLDmicMethodCount,

    // Backward compatibility aliases
    kTGLDmicMethodGetInfo     = kRPLDmicMethodGetInfo,
    kTGLDmicMethodStart       = kRPLDmicMethodStart,
    kTGLDmicMethodStop        = kRPLDmicMethodStop,
    kTGLDmicMethodGetPosition = kRPLDmicMethodGetPosition,
    kTGLDmicMethodCount       = kRPLDmicMethodCount,
};

enum {
    kRPLDmicStateDspUp     = 1u << 0,
    kRPLDmicStateStreaming = 1u << 1,
    kRPLDmicStateService   = 1u << 2,

    // Backward compatibility aliases
    kTGLDmicStateDspUp     = kRPLDmicStateDspUp,
    kTGLDmicStateStreaming = kRPLDmicStateStreaming,
    kTGLDmicStateService   = kRPLDmicStateService,
};

#define kRPLDmicInterfaceVersion 1
#define kRPLDmicVersionString    "1.0.0"

// Backward compatibility defines
#define kTGLDmicServiceClass     kRPLDmicServiceClass
#define kTGLDmicUserClientType   kRPLDmicUserClientType
#define kTGLDmicRingMemoryType   kRPLDmicRingMemoryType
#define kTGLDmicInterfaceVersion kRPLDmicInterfaceVersion
#define kTGLDmicVersionString    kRPLDmicVersionString

// Ring format: S32_LE, 4 interleaved channels, 48 kHz.
// Front mic array: ch0 (left), ch1 (right). Rear/ambient array: ch2 (left), ch3 (right).
