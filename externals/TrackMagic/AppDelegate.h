//
//  AppDelegate.h
//  TrackMagic
//
//  Created by Nathan Vander Wilt on 3/11/10.
//  Copyright 2010 Calf Trail Software, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class TouchDevice, TouchTrackpad;

@interface AppDelegate : NSObject <NSApplicationDelegate> {
@private
	TouchDevice* device;
	TouchTrackpad* trackpad;
}

- (void)checkDevice:(NSTimer*)timer;

@end
