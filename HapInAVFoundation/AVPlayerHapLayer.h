//
//  SynopsisHAPPlayerLayer.h
//  Synopsis Inspector
//
//  Created by vade on 7/24/17.
//  Copyright © 2017 v002. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>

@interface AVPlayerHapLayer : CAOpenGLLayer

@property (readonly) AVPlayer* player;

@property (nonatomic, readonly, getter=isReadyForDisplay) BOOL readyForDisplay;

@property (nonatomic, readonly) CGRect videoRect;


- (void) replacePlayerItemWithItem:(AVPlayerItem*)item;
- (void) replacePlayerItemWithHAPItem:(AVPlayerItem*)item;

- (void) play;
- (void) pause;

- (void) beginOptimize;
- (void) endOptimize;
@end
