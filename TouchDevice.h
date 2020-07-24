//
//  TouchDevice.h
//  TrackMagic
//
//  Created by Nathan Vander Wilt on 3/11/10.
//  Copyright 2010 Calf Trail Software, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface TouchDevice : NSObject {
@private
	CFTypeRef device;
	NSMutableDictionary* identityState;
	NSSet* touches;
}

+ (id)defaultTouchDevice;

@property (readonly, copy) NSSet* touches;
- (void)start;
- (void)stop;

@end

