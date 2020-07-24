//
//  Touch.h
//  TrackMagic
//
//  Created by Nathan Vander Wilt on 3/11/10.
//  Copyright 2010 Calf Trail Software, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface Touch : NSObject {
@private
	id device;
	id identity;
	NSTouchPhase phase;
	NSPoint normalizedPosition;
	BOOL isResting;
}

@property(readonly, retain) id<NSObject, NSCopying> identity; 
@property(readonly) NSTouchPhase phase;
@property(readonly) NSPoint normalizedPosition;
@property(readonly) BOOL isResting;

@property(readonly, retain) id device;
@property(readonly) NSSize  deviceSize;

@end
