//
//  TouchDevice.m
//  TrackMagic
//
//  Created by Nathan Vander Wilt on 3/11/10.
//  Copyright 2010 Calf Trail Software, LLC. All rights reserved.
//

#import "TouchDevice.h"

#import "Touch.h"
#include "MultitouchSupport.h"

static void receiveFrame(MTDeviceRef device,
						 MTTouch touches[], size_t numTouches,
						 double timestamp, size_t frame, void* refcon);

@interface TouchDevice ()
@property (readwrite, copy) NSSet* touches;
@end


@implementation TouchDevice

@synthesize touches;

- (id)initWithDevice:(MTDeviceRef)theDevice {
	self = [super init];
	if (self) {
		device = CFRetain(theDevice);
		MTRegisterContactFrameCallbackWithRefcon(device, receiveFrame, self);
		identityState = [NSMutableDictionary new];
	}
	return self;
}

- (void)uninit {
	MTUnregisterContactFrameCallback(device, receiveFrame);
	CFRelease(device), device = NULL;
}

- (void)dealloc {
	[self uninit];
	[identityState release];
	[super dealloc];
}

- (void)finalize {
	[self uninit];
	[super finalize];
}


+ (id)defaultTouchDevice {
	MTDeviceRef dev = MTDeviceCreateDefault();
	if (!dev) return nil;
	id touchDevice = [[self alloc] initWithDevice:dev];
	CFRelease(dev);
	return [touchDevice autorelease];
}

//JackR1 - 01/01/2020
+ (id)siriRemoteTouchDevice {
    
    NSMutableArray* deviceList = (__bridge NSMutableArray*)MTDeviceCreateList(); //grab our device list
    
    MTDeviceRef dev;
    
    //assume apple tv remote trackpad is the second one after the default for the system
    //MTDeviceGetDeviceID seems to identify the device, but there is no way of knowing it
    //unless you run this in debug, on my system it almost matches 3 hex pairs of the mac
    //address, not sure if thats a coincidence
    if([deviceList count] > 1)
        dev = [deviceList objectAtIndex:1];
    else
        dev = nil;
           
    if (!dev) return nil;
    
    //NSAssert(dev!=nil, @"Could not find SiriRemote TouchDevice");
    
    uint64_t deviceID;
    MTDeviceGetDeviceID(dev,&deviceID);
    
    NSLog(@"MTDeviceGetDeviceID: %016llX", deviceID);
    
    id touchDevice = [[self alloc] initWithDevice:dev];
    CFRelease(dev);
    return [touchDevice autorelease];
}

//JackR1 - 01/01/2020
+ (NSUInteger)touchDeviceCount {
    
    NSMutableArray* deviceList = (__bridge NSMutableArray*)MTDeviceCreateList(); //grab our device list
    
    return [deviceList count];
}

- (void)start {
	MTDeviceStart(device, 0);
}

- (void)stop {
	self.touches = nil;
	MTDeviceStop(device);
}

- (void)update:(NSSet*)frameTouches {
	self.touches = frameTouches;
}

#pragma mark Used by Touches

- (NSSize)size {
	return NSZeroSize;
}

- (NSMutableDictionary*)identityState {
	return identityState;
}

@end


@interface TouchIdentity : NSObject <NSCopying> {
@private
	void* device;
	NSUInteger identifier;
	NSTouchPhase phase;
	NSPoint normalizedPosition;
}

+ (TouchIdentity*)identityWithDevice:(TouchDevice*)theDevice
						identifier:(NSUInteger)theIdentifier;

@property NSTouchPhase phase;
@property NSPoint normalizedPosition;

@end


@implementation Touch

@synthesize identity;
@synthesize phase;
@synthesize normalizedPosition;
@synthesize isResting;
@synthesize device;

+ (NSTouchPhase)phaseUpdatingIdentity:(TouchIdentity*)theIdentity
						 withNewState:(MTTouchState)touchState
							 position:(NSPoint)newPosition
{
	NSTouchPhase newPhase;
	if (touchState == MTTouchStateNotTracking ||
		touchState == MTTouchStateOutOfRange)
	{
		newPhase = NSTouchPhaseEnded;
	}
	else switch (theIdentity.phase) {
		case NSTouchPhaseBegan:
		case NSTouchPhaseMoved:
		case NSTouchPhaseStationary:
			if (NSEqualPoints(theIdentity.normalizedPosition, newPosition)) {
				newPhase = NSTouchPhaseStationary;
			}
			else {
				newPhase = NSTouchPhaseMoved;
			}
			break;
		case NSTouchPhaseEnded:
		case NSTouchPhaseCancelled:
		default:
			newPhase = NSTouchPhaseBegan;
	}
	theIdentity.phase = newPhase;
	theIdentity.normalizedPosition = newPosition;
	return newPhase;
}

- (id)initWithDevice:(id)theDevice privateProperties:(MTTouch*)touchRef {
	self = [super init];
	if (self) {
		device = [theDevice retain];
		identity = [TouchIdentity identityWithDevice:theDevice
										  identifier:(touchRef->fingerID)];
		normalizedPosition = NSMakePoint(touchRef->normalizedVector.position.x,
										 touchRef->normalizedVector.position.y);
		phase = [[self class] phaseUpdatingIdentity:identity
									   withNewState:(touchRef->state)
										   position:normalizedPosition];
	}
	return self;
}

- (NSSize)deviceSize {
	return device ? [device size] : NSZeroSize;
}

@end


void receiveFrame(MTDeviceRef device,
				  MTTouch touches[], size_t numTouches,
				  double timestamp, size_t frame, void* refcon)
{
	(void)device;
	(void)timestamp;
	(void)frame;
	// TODO: refcon is undefined on 32-bit!
	TouchDevice* deviceWrapper = (id)refcon;
	NSLog(@"%p", deviceWrapper);
	NSMutableSet* wrappedTouches = nil;
	if (numTouches) {
		wrappedTouches = [[NSMutableSet alloc] initWithCapacity:numTouches];
	}
	for (size_t touchIdx = 0; touchIdx < numTouches; ++touchIdx) {
		MTTouch touch = touches[touchIdx];
		Touch* touchWrapper = [[Touch alloc] initWithDevice:deviceWrapper
										  privateProperties:&touch];
		[wrappedTouches addObject:touchWrapper];
		[touchWrapper release];
	}
	
	/* NOTE: while this code already assumes non-reentrancy per deviceWrapper,
	 update on main thread for sake of observers or delegates. */
	[deviceWrapper performSelectorOnMainThread:@selector(update:)
									withObject:wrappedTouches
								 waitUntilDone:NO];
	if (!wrappedTouches) {
		// clear singleton cache on TouchIdentity's behalf
		[[deviceWrapper identityState] removeAllObjects];
	}
	[wrappedTouches release];
}


@implementation TouchIdentity

@synthesize phase;
@synthesize normalizedPosition;

- (id)initWithDevice:(void*)theDevice identifier:(NSUInteger)theIdentifier {
	self = [super init];
	if (self) {
		device = theDevice;
		identifier = theIdentifier;
	}
	return self;
}

- (id)copyWithZone:(NSZone*)zone {
	(void)zone;
	return [self retain];
}

+ (TouchIdentity*)identityWithDevice:(TouchDevice*)theDevice
						 identifier:(NSUInteger)theIdentifier
{
	NSNumber* key = [[NSNumber alloc] initWithInteger:theIdentifier];
	TouchIdentity* identity = [[theDevice identityState] objectForKey:key];
	if (!identity) {
		identity = [[self alloc] initWithDevice:theDevice identifier:theIdentifier];
		[[theDevice identityState] setObject:identity forKey:key];
		[identity release];
	}
	[key release];
	return identity;
}

@end
