//
//  AudioController.h
//  SiriRemoteVoiceControl
//
//  Created by Jack on 12/1/20.
//

#include <EZAudioOSX/EZAudio.h>
#include <EZAudioOSX/EZAudioUtilities.h>
#import "TPCircularBuffer.h"

@interface AudioController : NSObject <EZOutputDataSource>
- (id) initWithTPCircularBufferLength: (int) bufferLength;
@property (nonatomic, strong) EZOutput *output;
@property (nonatomic) TPCircularBuffer *outputBuffer;
@end
