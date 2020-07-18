//
//  AudioController.m
//  SiriRemoteVoiceControl
//
//  Created by Jack on 12/1/20.
//

#import <Foundation/Foundation.h>
#import "AudioController.h"

@implementation AudioController
- (void) dealloc {
    if (_outputBuffer) {
        TPCircularBufferCleanup(_outputBuffer);
        free(_outputBuffer);
    }
}
- (id) init {
    if (self = [super init]) {
        int bufferLength = 1000000;
        [self setupOutput:bufferLength];
    }
    return self;
}

- (id) initWithTPCircularBufferLength: (int) bufferLength {
    if (self = [super init]) {
        [self setupOutput:bufferLength];
    }
    return self;
}

- (void) setupOutput: (int) bufferLength  {
    
    AudioStreamBasicDescription audioFormat;
    
    audioFormat.mSampleRate = 16000.0;
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = 0xc; //kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    audioFormat.mBytesPerPacket = 2;
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mBytesPerFrame = 2;
    audioFormat.mChannelsPerFrame = 1;
    audioFormat.mBitsPerChannel = 16;
    audioFormat.mReserved = 0;
    
    self.output = [EZOutput outputWithDataSource:self];
    [self.output setInputFormat:audioFormat];
    
    self.outputBuffer = malloc(sizeof(TPCircularBuffer));
    BOOL success = TPCircularBufferInit(_outputBuffer, bufferLength); //originally 100000
    if (!success) {
        NSLog(@"Error allocating output buffer");
    }
}

- (OSStatus)
output:(EZOutput *)output
shouldFillAudioBufferList:(AudioBufferList *)audioBufferList
withNumberOfFrames:(UInt32)frames
timestamp:(const AudioTimeStamp *)timestamp {
        
    TPCircularBuffer *circularBuffer = _outputBuffer;
    
    //the below is not needed as AudioBufferList defaults to silence
    if( !circularBuffer ){
        //fill up audio bufferlist with silence
        Float32 *left  = (Float32 *)audioBufferList->mBuffers[0].mData;
        Float32 *right = (Float32 *)audioBufferList->mBuffers[1].mData;
        for(int i = 0; i < frames; i++ ){
            left[  i ] = 0.0f;
            right[ i ] = 0.0f;
        }
        return noErr;
    };
    
    /**
     https://github.com/syedhali/EZAudio/commits/master/EZAudio/EZOutput.m
     syedhali committed on 26 Jun 2015
     https://github.com/syedhali/EZAudio/blob/b21681464c5cb268359f6793dab3313006067242/EZAudio/EZOutput.m
     
     Thank you Michael Tyson (A Tasty Pixel) for writing the TPCircularBuffer, you are amazing!
     */
    
    // Get the desired amount of bytes to copy
    int32_t bytesToCopy = audioBufferList->mBuffers[0].mDataByteSize;
    Float32 *left  = (Float32 *)audioBufferList->mBuffers[0].mData;
    //Float32 *right = (Float32 *)audioBufferList->mBuffers[1].mData;
    
    // Get the available bytes ready for reading in the circular buffer
    int32_t availableBytes;
    Float32 *buffer = TPCircularBufferTail(circularBuffer,&availableBytes);
    
    // Ideally we'd have all the bytes to be copied, but compare it against the available bytes (get min)
    int32_t amount = MIN(bytesToCopy,availableBytes);
    
    //NSLog(@"Bytes To Copy = %d", bytesToCopy);
    //NSLog(@"Available Bytes = %d", availableBytes);
    
    //fill left channel
    memcpy( left,  buffer, amount );
    //memcpy( right, buffer, amount );
    
    // Consume those bytes ( this will internally push the head of the circular buffer )
    TPCircularBufferConsume(circularBuffer,amount);
    
    return noErr;
}

@end
