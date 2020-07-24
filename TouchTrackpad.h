//
//  TouchTrackpad.h
//  TrackMagic
//
//  Created by Nathan Vander Wilt on 3/11/10.
//  Copyright 2010 Calf Trail Software, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface TouchTrackpad : NSObject {
@private
	NSSet* touches;
	CGEventSourceRef source;
	CFMachPortRef tap;
	
	NSPoint firstDown;
	uint64_t downTime;
@public // (not really)
	BOOL suppressed;
}

@property (copy) NSSet* touches;

@end
