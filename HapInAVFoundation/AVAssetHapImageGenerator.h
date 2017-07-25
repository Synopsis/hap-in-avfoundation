//
//  AVAssetHapImageGenerator.h
//  Synopsis Inspector
//
//  Created by vade on 7/25/17.
//  Copyright © 2017 v002. All rights reserved.
//

#import "HapInAVFoundation.h"
@interface AVAssetHapImageGenerator : NSObject

+ (AVAssetHapImageGenerator*) assetHapImageGeneratorWithAsset:(AVAsset*)asset;

- (void) generateCGImagesAsynchronouslyForTimes:(NSArray<NSValue *> *)requestedTimes completionHandler:(AVAssetImageGeneratorCompletionHandler)handler;

@end

