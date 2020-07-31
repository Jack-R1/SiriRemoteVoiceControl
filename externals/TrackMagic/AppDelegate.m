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
#import <mach/mach_time.h>

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification {
	(void)aNotification;
	trackpad = [TouchTrackpad new];
    
    if(trackpad)
    {
        device = [[TouchDevice siriRemoteTouchDevice] retain];
        
        if(device)
        {
            [trackpad bind:@"touches" toObject:device withKeyPath:@"touches" options:nil];
            [device start];
        }
        
        //JackR1 - 01/01/2020
        //repeat every x seconds to check if device is still active
        //if we dont do this the SiriRemote ble disconnects (I'm
        //guessing for energy efficiency) around the 1:30 to 2:00
        //minute mark and when reconnection is established by pressing
        //a button on the remote (e.g. volume up or down) the
        //device reference is no longer valid and needs to be released
        //and re instantiated
        [NSTimer scheduledTimerWithTimeInterval:2.0
                                         target:self
                                       selector:@selector(checkDevice:)
                                       userInfo:nil
                                        repeats:YES];
    }
}

//JackR1 - 01/01/2020
- (void)checkDevice:(NSTimer*)timer {
    
    NSTimeInterval duration = (mach_absolute_time() - [[trackpad lastTouchTime] doubleValue]) / 1000000000.0;
    
    const NSTimeInterval maxTimeout = 90.00; //seconds
  
    //if we hit the timeout and the device exists then stop and release the device
    //since most likely the remote ble has d/c anyway, then try reconnecting
    if(duration > maxTimeout
       && [TouchDevice touchDeviceCount] > 1)
    {

        if(device)
        {
            [device stop];
            CFRelease(device);
        }
        
        device = [[TouchDevice siriRemoteTouchDevice] retain];
        
        if(device)
        {
            [trackpad bind:@"touches" toObject:device withKeyPath:@"touches" options:nil];
            [device start];
        }
    }
}

@end
