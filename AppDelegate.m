//
//  AppDelegate.m
//  TrackMagic
//
//  Created by Nathan Vander Wilt on 3/11/10.
//  Copyright 2010 Calf Trail Software, LLC. All rights reserved.
//

#import "AppDelegate.h"

#import "TouchDevice.h"
#import "TouchTrackpad.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification {
	(void)aNotification;
	trackpad = [TouchTrackpad new];
	device = [[TouchDevice defaultTouchDevice] retain];
	[trackpad bind:@"touches" toObject:device withKeyPath:@"touches" options:nil];
	[device start];
}

@end
