//
//  main.m
//  SiriRemoteVoiceControl
//
//  Created by Jack on 12/1/20.
//

#import <Foundation/Foundation.h>
#import "OKDecoder.h"

// EZAudio header
#include <EZAudioOSX/EZAudio.h>

//Below is to decode into circular buffer
#import "TPCircularBuffer.h"
#import "AudioController.h"

@interface NSData (Hexadecimal)
- (NSData *)initWithHexadecimalString:(NSString *)string;
+ (NSData *)dataWithHexadecimalString:(NSString *)string;
@end

unsigned char _hexCharToInteger(unsigned char hexChar) {
    if (hexChar >= '0' && hexChar <= '9') {
        return (hexChar - '0') & 0xF;
    } else {
        return ((hexChar - 'A')+10) & 0xF;
    }
}

@implementation NSData (Hexadecimal)
- (id)initWithHexadecimalString:(NSString *)string {
    const char * hexstring = [string UTF8String];
    int dataLength = [string length] / 2;
    unsigned char * data = malloc(dataLength);
    if (data == nil) {
        return nil;
    }
    int i = 0;
    for (i = 0; i < dataLength; i++) {
        unsigned char firstByte = hexstring[2*i];
        unsigned char secondByte = hexstring[2*i+1];
        unsigned char byte = (_hexCharToInteger(firstByte) << 4) + _hexCharToInteger(secondByte);
        data[i] = byte;
    }
    self = [self initWithBytes:data length:dataLength];
    free(data);
    return self;
}

+ (NSData *)dataWithHexadecimalString:(NSString *)string {
    return [[self alloc] initWithHexadecimalString:string];
}
@end

@implementation NSString (TrimmingAdditions)

- (NSString *)stringByTrimmingLeadingCharactersInSet:(NSCharacterSet *)characterSet {
    NSUInteger location = 0;
    NSUInteger length = [self length];
    unichar charBuffer[length];
    [self getCharacters:charBuffer];
    
    for (location; location < length; location++) {
        if (![characterSet characterIsMember:charBuffer[location]]) {
            break;
        }
    }
    
    return [self substringWithRange:NSMakeRange(location, length - location)];
}

- (NSString *)stringByTrimmingTrailingCharactersInSet:(NSCharacterSet *)characterSet {
    NSUInteger location = 0;
    NSUInteger length = [self length];
    unichar charBuffer[length];
    [self getCharacters:charBuffer];
    
    for (length; length > 0; length--) {
        if (![characterSet characterIsMember:charBuffer[length - 1]]) {
            break;
        }
    }
    
    return [self substringWithRange:NSMakeRange(location, length - location)];
}
@end

void c_print(NSString* prnt)
{
    printf("%s", [prnt cStringUsingEncoding:NSUTF8StringEncoding]);
    //fflush(stdout);
}

void c_print_ln(NSString* prnt)
{
    printf("%s\n", [prnt cStringUsingEncoding:NSUTF8StringEncoding]);
    //fflush(stdout);
}

NSString* read_till(char c)
{
    NSMutableString* ret = [[NSMutableString alloc] initWithString:@""];
    
    char r = getchar();
    while(r!=c && r!= '\0')
    {
        [ret appendFormat:@"%c",r];
        r = getchar();
    }
    return ret;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        //After pairing your apple tv 4/siri remote to your computer,
        //you can find your siriRemote <MAC> address either via system preferences -> bluetooth
        //or by running packetlogger in terminal on its own, the first few lines will be
        //the bluetooth devices it has found
        NSString* siriRemoteMACAddress = [[NSMutableString alloc] initWithString:@""];
        
        //printf("argc: %d\n",argc);
        
        //If you dont pass in the <MAC> address, it will parse all data from packetlogger
        //that look like siri remote data but this is not recommended as the voice data
        //frames can be misinterpreted
        if(argc>1)
        {
            siriRemoteMACAddress = [[NSString alloc] initWithCString:argv[1] encoding:NSUTF8StringEncoding];
            //c_print_ln(siriRemoteMACAddress);
        }
        
        bool voiceStarted = false;
        bool voiceEnded = false;
        int index_data = 54;
        int index_b8 = 54;
        int index_1b = 24;
        
        //frames will contain the concatenation of multiple frame strings
        NSString* frames = [[NSMutableString alloc] initWithString:@""];
        //frame will contain the byte data (sent by packetlogger spanning multiple lines) as a string
        NSString* frame = [[NSMutableString alloc] initWithString:@""];
        
        AudioController * audioController = [[AudioController alloc] initWithTPCircularBufferLength:5000000];
        
        NSArray *outputDevices = [EZAudioDevice outputDevices];
        
        OKDecoder *opusDecoder = [[OKDecoder alloc] initWithSampleRate:16000 numberOfChannels:1];
        
        NSError *error = nil;
        if (![opusDecoder setupDecoderWithError:&error]) {
            NSLog(@"Error setting up opus decoder: %@", error);
        }
        
        bool debug = false;
        
        if(debug)
        {
            //Simulate from voice ended...
            
            //Load frames from file
            //frames.txt file can be created by using SiriRemoteVoiceDecode
            frames = [NSString stringWithContentsOfFile:@"frames.txt"
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
            
            for (NSString * frame in [frames componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
            {
                //make sure its not a corrupted frame and it contains the packetHeader at the first byte
                if([frame length] > (1 * 3))
                {
                    //NSLog(@"frame = %@", [frame stringByReplacingOccurrencesOfString:@" " withString: @""]);
                    
                    NSData * frameData = [NSData dataWithHexadecimalString:[frame stringByReplacingOccurrencesOfString:@" " withString: @""]];
                    NSData * packetHeader = [frameData subdataWithRange:NSMakeRange(0, 1)];
                    
                    int8_t packetLen;
                    [packetHeader getBytes:&packetLen length:sizeof(packetLen)];
                    
                    //NSLog(@"Packet Len = %d", packetLen);
                    
                    //frameData length (which includes the first byte packetHeader) should be greater than packetLen
                    if([frameData length] > packetLen)
                    {
                        NSData * packetData = [frameData subdataWithRange:NSMakeRange(1, packetLen)];
                        
                        [opusDecoder decodePacket:packetData completionBlock:^(NSData *pcmData, NSUInteger numDecodedSamples, NSError *error) {
                            if (error) {
                                NSLog(@"Error decoding packet: %@", error);
                                return;
                            }
                            
                            //at this point when loading frames from file the circular buffer is flooded as the for loop
                            //is processing frames faster than the output playback is clearing the buffer in which case
                            //when testing if your circular buffer is not big enough to slurp all the data frames it will
                            //cause insufficient space errors.
                            //So either make sure TPCircularBufferLength is big enough to hold all the pcm data at once or
                            //alternatively introduce a delay into the for loop as can been seen further down.
                            BOOL success = TPCircularBufferProduceBytes([audioController outputBuffer], pcmData.bytes, pcmData.length);
                            if (!success) {
                                NSLog(@"Error copying output pcm into buffer, insufficient space");
                            }
                        }];
                        
                        if (![audioController output].isPlaying) {
                            [[audioController output] startPlayback];
                        }
                        
                        //we can slow down the for loop by introducing a delay to allow the circular buffer to clear,
                        //too big of a delay and your playback is affected and output slowed down
                        [NSThread sleepForTimeInterval:0.01f];
                    }
                    else
                    {
                        NSLog(@"frame = %@", [frame stringByReplacingOccurrencesOfString:@" " withString: @""]);
                        NSLog(@"packet data: %lu bytes is less than required in packet header: %d bytes", [frameData length]-1, packetLen);
                    }
                }
            }
            
            while(1)
            {
                // Get the available bytes ready for reading in the circular buffer
                // when this drops to 0 that means no more bytes left to output and
                // we can breakout of the loop
                int32_t availableBytes;
                TPCircularBufferTail([audioController outputBuffer], &availableBytes);
                
                //NSLog(@"Available Bytes = %d", availableBytes);
                
                //sleep to let audio play out
                [NSThread sleepForTimeInterval:1.0f];
                
                if(availableBytes == 0)
                {
                    [[audioController output] stopPlayback];
                    break;
                }
            }
            
        }
        else
        {
            //if not debugging set output device to Soundflower (2ch)
            //also set input in System Preferences -> Sound to
            //Soundflower (2ch)
            //this will allow the output to be redirected to input
            //in OSX for system wide use
            for (EZAudioDevice *device in outputDevices)
            {
               //if([device.name isEqualToString:@"Loopback Audio"])
               if([device.name isEqualToString:@"Soundflower (2ch)"])
               {
                   [[audioController output] setDevice:device];
                   NSLog(@"Output device set to: %@", device.name);
               }
            }

            while(1)
            {
                NSString* inputLine = read_till('\n');
                
                if(
                   (
                    [siriRemoteMACAddress isEqualToString:@""] ||      //they did not pass in the mac address or
                    [inputLine containsString:@"00:00:00:00:00:00"] || //packetlogger did not register the correct mac address (it sometimes can do that) or
                    [inputLine containsString:siriRemoteMACAddress]    //the mac address matches
                    ) &&
                   [inputLine containsString:@"RECV"])
                {
                    inputLine = [[inputLine substringFromIndex:index_data] stringByTrimmingTrailingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    
                    //c_print_ln([[NSString alloc] initWithFormat:@"Reading in: %@",inputLine]);
                    
                    //click was pressed
                    if([inputLine length] >= index_1b + 14 &&
                       [inputLine length] <= (17 * 3) - 1 &&
                       [[inputLine substringWithRange:NSMakeRange(index_1b, 14)] isEqual:@"1B 23 00 03 00"])
                    {
                        printf("Click...\n");
                    }
                    //volume up
                    else if([inputLine hasSuffix: @"1B 23 00 00 02"])
                    {
                    }
                    //volume down
                    else if([inputLine hasSuffix: @"1B 23 00 00 04"])
                    {
                    }
                    //start of voice command
                    else if([inputLine hasSuffix: @"1B 23 00 00 10"])
                    {
                        printf("Voice started...\n");
                        
                        frame = [[NSMutableString alloc] initWithString:@""];
                        
                        voiceStarted = true;
                        voiceEnded = false;
                    }
                    //end of voice command
                    else if([inputLine hasSuffix: @"1B 23 00 10 00"])
                    {
                        printf("Voice ended...\n");
                        
                        voiceStarted = false;
                        voiceEnded = true;
                        
                        //we will reach here before the voice is completely sent to output
                        //this is identified by testing dictation on notes app, so
                        //we need to wait until the buffer is clear before stopping.
                        //Leaving the output playing is not an option as it does not
                        //trigger dictation to stop, it thinks there is more coming in
                        /*
                        if ([audioController output].isPlaying) {
                            [NSThread sleepForTimeInterval:0.8f];
                            [[audioController output] stopPlayback];
                        }
                        */
                        if ([audioController output].isPlaying) {
                            while(1)
                            {
                                // Get the available bytes ready for reading in the circular buffer
                                // when this drops to 0 that means no more bytes left to output and
                                // we can breakout of the loop
                                int32_t availableBytes;
                                TPCircularBufferTail([audioController outputBuffer], &availableBytes);
                                
                                //NSLog(@"Available Bytes = %d", availableBytes);
                                
                                //sleep to let audio play out
                                [NSThread sleepForTimeInterval:0.8f];
                                
                                if(availableBytes == 0)
                                {
                                    [[audioController output] stopPlayback];
                                    break;
                                }
                            }
                        }
                        
                    }
                    //concatenate data
                    else {
                        if(voiceStarted)
                        {
                            //length of inputLine should be 31 bytes (each byte represented as 2 hex chars followed by a space), less space at the end
                            if([inputLine length] == (31 * 3) - 1 )
                            {
                                //beginning of frame?
                                //Does it start with 40 20 instead of 40 10 and have B8
                                if([inputLine hasPrefix: @"40 20"] &&
                                   [[inputLine substringWithRange:NSMakeRange(index_b8, 2)] isEqual:@"B8"])
                                {
                                    //if the previous frame is not empty and we just started to look at the beginning of a new
                                    //frame then output the last frame
                                    if(![frame isEqualToString:@""])
                                    {
                                        //printf("Frame is: %s\n", [frame cStringUsingEncoding:NSUTF8StringEncoding]);
                                        
                                        //decode the frame and play per frame so that there is no delay
                                        NSData * frameData = [NSData dataWithHexadecimalString:[frame stringByReplacingOccurrencesOfString:@" " withString: @""]];
                                        NSData * packetHeader = [frameData subdataWithRange:NSMakeRange(0, 1)];
                                        
                                        int8_t packetLen;
                                        [packetHeader getBytes:&packetLen length:sizeof(packetLen)];
                                        
                                        //frameData length (which includes the first byte packetHeader) should be greater than packetLen
                                        if([frameData length] > packetLen)
                                        {
                                            NSData * packetData = [frameData subdataWithRange:NSMakeRange(1, packetLen)];
                                            
                                            [opusDecoder decodePacket:packetData completionBlock:^(NSData *pcmData, NSUInteger numDecodedSamples, NSError *error) {
                                                if (error) {
                                                    NSLog(@"Error decoding packet: %@", error);
                                                    return;
                                                }
                                                
                                                BOOL success = TPCircularBufferProduceBytes([audioController outputBuffer], pcmData.bytes, pcmData.length);
                                                
                                                if (!success) {
                                                    NSLog(@"Error copying output pcm into buffer, insufficient space");
                                                }
                                            }];
                                            
                                            if (![audioController output].isPlaying) {
                                                [[audioController output] startPlayback];
                                            }
                                        }
                                        else
                                        {
                                            NSLog(@"frame = %@", [frame stringByReplacingOccurrencesOfString:@" " withString: @""]);
                                            NSLog(@"packet data: %lu bytes is less than required in packet header: %d bytes", [frameData length]-1, packetLen);
                                        }
                                    }
                                    
                                    //the byte before b8 is the length of voice data in 0xhh
                                    frame = [[NSString alloc] initWithFormat:@"%@", [inputLine substringFromIndex:index_b8-3]];
                                }
                                else
                                {
                                    //the rest of the voice data should start after 4th byte and have length of 27 bytes
                                    frame = [[NSString alloc] initWithFormat:@"%@ %@", frame, [inputLine substringFromIndex:4*3]];
                                }
                            }
                        }
                        
                    }
                }
            }
        }
    }
    return 0;
}





