#ifndef MultitouchSupport_h
#define MultitouchSupport_h

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

typedef struct { float x; float y; } MTPoint;
typedef struct { MTPoint position; MTPoint velocity; } MTVector;

typedef enum {
    MTTouchStateNotTracking = 0,
    MTTouchStateStartInRange = 1,
    MTTouchStateHoverInRange = 2,
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
    MTTouchStateBreakTouch = 5,
    MTTouchStateLingerInRange = 6,
    MTTouchStateOutOfRange = 7
} MTTouchState;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t pathIndex;
    MTTouchState state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalizedVector;
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absoluteVector;
    int32_t field14;
    int32_t field15;
    float zDensity;
} MTTouch;

typedef CFTypeRef MTDeviceRef;

CFArrayRef MTDeviceCreateList(void);
OSStatus MTDeviceStart(MTDeviceRef device, int mode);
OSStatus MTDeviceStop(MTDeviceRef device);
bool MTDeviceIsRunning(MTDeviceRef device);
bool MTDeviceIsBuiltIn(MTDeviceRef device);
OSStatus MTDeviceGetDeviceID(MTDeviceRef device, uint64_t *deviceID);
OSStatus MTDeviceGetSensorSurfaceDimensions(MTDeviceRef device, int *width, int *height);

typedef void (*MTFrameCallbackRefconFunction)(MTDeviceRef device,
                                              MTTouch touches[],
                                              size_t numTouches,
                                              double timestamp,
                                              size_t frame,
                                              void *refcon);

void MTRegisterContactFrameCallbackWithRefcon(MTDeviceRef device,
                                              MTFrameCallbackRefconFunction callback,
                                              void *refcon);
void MTUnregisterContactFrameCallback(MTDeviceRef device,
                                     MTFrameCallbackRefconFunction callback);

#endif
