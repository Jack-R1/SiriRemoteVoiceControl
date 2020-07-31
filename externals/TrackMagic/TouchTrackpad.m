//
//  TouchTrackpad.m
//  TrackMagic
//
//  Created by Nathan Vander Wilt on 3/11/10.
//  Copyright 2010 Calf Trail Software, LLC. All rights reserved.
//

#import "TouchTrackpad.h"

#import "Touch.h"
#import <mach/mach_time.h>



static const CGEventTapLocation target = kCGHIDEventTap;
static NSString* TrackpadContext = @"TouchTrackpad KVO context";

static CGEventRef suppressOthers(CGEventTapProxy proxy, CGEventType type,
								 CGEventRef event, void* userInfo);

static inline CGPoint tlCGRectClosestPoint(CGRect r, CGPoint p);
static inline CGFloat tlCGPointDistance(CGPoint p1, CGPoint p2);
static inline NSPoint tlNSDeltaPoint(NSPoint p1, NSPoint p2);


@implementation TouchTrackpad

- (NSNumber *)lastTouchTime
{
    return [NSNumber numberWithDouble: downTime];
}

@synthesize touches;

+ (void)initialize {
	if ([self class] != [TouchTrackpad class]) return;
	[self exposeBinding:@"touches"];
}

- (id)init {
	self = [super init];
	if (self) {
		source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
		CGEventSourceSetUserData(source, (intptr_t)&TrackpadContext);
		
		CGEventMask blockedTypes = (CGEventMaskBit(kCGEventMouseMoved) |
									CGEventMaskBit(kCGEventScrollWheel));
		tap = CGEventTapCreate(target, kCGTailAppendEventTap,
							   kCGEventTapOptionDefault,
							   blockedTypes, suppressOthers, self);
		NSAssert(tap, @"Couldn't create tap!");
        
        //JackR1 - 01/01/2020
        //initialize downTime as its used to determine the last touch
        //time in AppDelgate checkdevice loop for SiriRemote
        downTime = mach_absolute_time();
        
		CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
		CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
		
		[self addObserver:self forKeyPath:@"touches"
				  options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
				  context:&TrackpadContext];
	}
	return self;
}

- (void)unsuppress {
	suppressed = NO;
	//printf("unpause.\n");
}

- (void)suppress {
	if (suppressed) return;
	suppressed = YES;
	static const NSTimeInterval suppressLength = 0.25;
	[self performSelector:@selector(unsuppress) withObject:nil afterDelay:suppressLength];
	//printf("pause...");
}

+ (NSPoint)averagePostion:(NSSet*)theTouches {
	NSUInteger numTouches = [theTouches count];
	if (!numTouches) {
		return NSZeroPoint;
	}
	else if (numTouches == 1) {
		return [[theTouches anyObject] normalizedPosition];
	}
	
	NSPoint avgPos = NSZeroPoint;
	for (Touch* touch in theTouches) {
		NSPoint pos = [touch normalizedPosition];
		avgPos.x += pos.x;
		avgPos.y += pos.y;
	}
	avgPos.x /= numTouches;
	avgPos.y /= numTouches;
	return avgPos;
}

+ (CGPoint)currentCursorPosition {
	CGEventRef e = CGEventCreate(NULL);
	CGPoint cursor = CGEventGetLocation(e);
	CFRelease(e);
	return cursor;
}

+ (CGPoint)constrainPointToVisible:(CGPoint)p {
	uint32_t numDisplays;
	CGDisplayErr err;
	err = CGGetDisplaysWithPoint(p, 0, NULL, &numDisplays);
	NSAssert1(!err, @"Unexpected error %i from CGGetDisplaysWithPoint", err);
	if (numDisplays) {
		return p;
	}
	
	uint32_t maxDisplays = 16;
	CGDirectDisplayID activeDisplays[maxDisplays];
	err = CGGetActiveDisplayList(maxDisplays, activeDisplays, &numDisplays);
	NSAssert1(!err, @"Unexpected error %i from CGGetActiveDisplayList", err);
	
	CGPoint closestPoint = p;
	CGFloat closestDistance = CGFLOAT_MAX;
	for (uint32_t displayIdx = 0; displayIdx < numDisplays; ++displayIdx) {
		CGRect bounds = CGDisplayBounds(activeDisplays[displayIdx]);
		CGPoint adjustedPoint = tlCGRectClosestPoint(bounds, p);
		CGFloat distance = tlCGPointDistance(p, adjustedPoint);
		if (distance < closestDistance) {
			closestPoint = adjustedPoint;
			closestDistance = distance;
		}
	}
	return closestPoint;
}

+ (NSSet*)filterTouches:(NSSet*)theTouches {
	const CGRect filterRect = CGRectMake(0, 0, 1, 0.8f);
	NSMutableSet* filtered = [NSMutableSet setWithCapacity:[theTouches count]];
	for (Touch* touch in theTouches) {
		CGPoint touchPos = NSPointToCGPoint(touch.normalizedPosition);
		if (CGRectContainsPoint(filterRect, touchPos)) {
			[filtered addObject:touch];
		}
	}
	return filtered;
}

- (void)updateFrom:(NSSet*)oldTouches to:(NSSet*)newTouches {
	oldTouches = [[self class] filterTouches:oldTouches];
	newTouches = [[self class] filterTouches:newTouches];
	
	NSPoint oldPos = [[self class] averagePostion:oldTouches];
	NSPoint newPos = [[self class] averagePostion:newTouches];
	CGFloat dX = newPos.x - oldPos.x;
	CGFloat dY = newPos.y - oldPos.y;
	
	CGEventRef e = NULL;
    //where previously one finger movement and now one finger movement
	if ([oldTouches count] == 1 && [newTouches count] == 1) {
		const CGFloat scale = 500;
		CGPoint cursor = [[self class] currentCursorPosition];
		cursor.x += dX * scale;
		cursor.y -= dY * scale;
		cursor = [[self class] constrainPointToVisible:cursor];
		e = CGEventCreateMouseEvent(source, kCGEventMouseMoved, cursor, 0);
	}
    //where previously two fingers movement and now two finger movement
	else if ([oldTouches count] == 2 && [newTouches count] == 2) {
		const CGFloat scale = 1000;
		int32_t scrollY = (int32_t)(dY * scale);
		int32_t scrollX = (int32_t)(-dX * scale);
		e = CGEventCreateScrollWheelEvent(source, kCGScrollEventUnitPixel,
										  2, scrollY, scrollX);
	}
    //if no previous touches
	else if ([oldTouches count] == 0 && [newTouches count]) {
		firstDown = newPos;
		downTime = mach_absolute_time();
	}
    //if previous touches and now no touches trigger a tap
	else if ([oldTouches count] && [newTouches count] == 0) {
		uint64_t nanoDuration = mach_absolute_time() - downTime;
		NSPoint movement = tlNSDeltaPoint(firstDown, oldPos);
		CGFloat approxDistance = (CGFloat)MAX(fabs(movement.x), fabs(movement.y));
		NSTimeInterval duration = nanoDuration / 1000000000.0;
		//printf("up - %f @ %fs\n", approxDistance, duration);
		
        //JackR1 - 01/01/2020
        //optimal tapDuration and tapDistance for SiriRemote
		const NSTimeInterval tapDuration = 0.50; //0.35;
		const CGFloat tapDistance = 0.04f; //0.01f;
		if (duration < tapDuration && approxDistance < tapDistance) {
			CGPoint pos = [[self class] currentCursorPosition];
			CGEventRef e0 = CGEventCreateMouseEvent(source, kCGEventLeftMouseDown, pos, 0);
			CGEventPost(target, e0);
			CFRelease(e0);
			e = CGEventCreateMouseEvent(source, kCGEventLeftMouseUp, pos, 0);
		}
	}
	
	if (e) {
		[self suppress];
		CGEventPost(target, e);
		CFRelease(e);
	}
}

//device = [[TouchDevice siriRemoteTouchDevice] retain];
//[trackpad bind:@"touches" toObject:device withKeyPath:@"touches" options:nil];
//the above in AppDelegate.m trigger below when touches dictionary/nsset is updated in touchdevice
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object
						change:(NSDictionary*)change context:(void*)context
{
    if (context == &TrackpadContext) {
		id old = [change objectForKey:NSKeyValueChangeOldKey];
		if (old == [NSNull null]) old = nil;
		id new = [change objectForKey:NSKeyValueChangeNewKey];
		if (new == [NSNull null]) new = nil;
		[self updateFrom:old to:new];
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object
							   change:change context:context];
	}
}

@end


CGEventRef suppressOthers(CGEventTapProxy proxy, CGEventType type,
						  CGEventRef event, void* userInfo)
{
	(void)proxy;
	(void)type;
	TouchTrackpad* trackpad = (id)userInfo;
	if (!trackpad->suppressed) return event;
	int64_t eventInfo = CGEventGetIntegerValueField(event, kCGEventSourceUserData);
	int64_t ourInfo = (intptr_t)&TrackpadContext;
	return (eventInfo == ourInfo) ? event : NULL;
}


//#define CONSTRAIN(X, A, B) MAX(MIN(X, B), A)

#define CONSTRAIN(X, A, B) tlCGFloatConstrain(X, A, B);
static inline CGFloat tlCGFloatConstrain(CGFloat x, CGFloat a, CGFloat b) {
	x = MIN(x, b);
	return MAX(x, a);
}

CGPoint tlCGRectClosestPoint(CGRect r, CGPoint p) {
	CGFloat x = CONSTRAIN(p.x, CGRectGetMinX(r), CGRectGetMaxX(r) - 1);
	CGFloat y = CONSTRAIN(p.y, CGRectGetMinY(r), CGRectGetMaxY(r) - 1);
	return CGPointMake(x, y);
}

CGFloat tlCGPointDistance(CGPoint p1, CGPoint p2) {
	return (CGFloat)hypot(p2.x - p1.x, p2.y - p1.y);
}

NSPoint tlNSDeltaPoint(NSPoint p1, NSPoint p2) {
	return NSMakePoint(p2.x - p1.x, p2.y - p1.y);
}
