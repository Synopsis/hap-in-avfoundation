//
//	AVAssetHapImageGenerator.m
//	Synopsis Inspector
//
//	Created by vade on 7/25/17.
//	Copyright © 2017 v002. All rights reserved.
//

#import "AVAssetHapImageGenerator.h"
//#import <Cocoa/Cocoa.h>
#import <AppKit/AppKit.h>
#import "VVSizingTool.h"




@interface AVAssetHapImageGenerator ()
@property (strong,readwrite) AVAsset * asset;
@property (strong,readwrite) AVPlayerItemHapDXTOutput * output;
@end




@implementation AVAssetHapImageGenerator

+ (AVAssetHapImageGenerator*) assetHapImageGeneratorWithAsset:(AVAsset*)asset	{
	return [[AVAssetHapImageGenerator alloc] initWithAsset:asset];
}

- (instancetype) initWithAsset:(AVAsset *)n	{
	self = [super init];
	if (self != nil)	{
		self.asset = n;
	}
	return self;
}

- (void) generateCGImagesAsynchronouslyForTimes:(NSArray<NSValue *> *)requestedTimes completionHandler:(AVAssetImageGeneratorCompletionHandler)handler	{
	//NSLog(@"%s ... %@",__func__,requestedTimes);
	if ([self.asset containsHapVideoTrack])	{
		NSArray				*assetHapTracks = [self.asset hapVideoTracks];
		AVAssetTrack		*hapTrack = assetHapTracks[0];
		//	make a hap output item- doesn't actually need a player...
		if (self.output == nil)	{
			self.output = [[AVPlayerItemHapDXTOutput alloc] initWithHapAssetTrack:hapTrack];
			[self.output setSuppressesPlayerRendering:YES];
			[self.output setOutputAsRGB:YES];
		}
		for (NSValue * requestedTime in requestedTimes)	{
			CMTime		timeVal = [requestedTime CMTimeValue];
			HapDecoderFrame		*decodedFrame = [self.output allocFrameForTime:timeVal];
			if (decodedFrame == nil)	{
				handler(timeVal, NULL, timeVal, AVAssetImageGeneratorFailed, nil);
				continue;
			}
			//	make a bitmap rep & NSImage from the decoded frame
			unsigned char		*rgbPixels = (unsigned char *)[decodedFrame rgbData];
			size_t				rgbPixelsLength = [decodedFrame rgbDataSize];
			NSSize				rgbPixelsSize = [decodedFrame rgbImgSize];
			NSBitmapImageRep	*bitRep = [[NSBitmapImageRep alloc]
				initWithBitmapDataPlanes:&rgbPixels
				pixelsWide:rgbPixelsSize.width
				pixelsHigh:rgbPixelsSize.height
				bitsPerSample:8
				samplesPerPixel:4
				hasAlpha:YES
				isPlanar:NO
				colorSpaceName:NSDeviceRGBColorSpace
				//bitmapFormat:0	//	premultiplied, but alpha is last
				bitmapFormat:0	//	can't use this- graphics contexts cant use non-premultiplied bitmap reps as a backing
				bytesPerRow:rgbPixelsLength/rgbPixelsSize.height
				bitsPerPixel:32];
			if (bitRep==nil)	{
				NSLog(@"\t\terr: couldn't make bitmap rep, %s, asset was %@",__func__,self.asset);
				handler(timeVal, NULL, [decodedFrame presentationTime], AVAssetImageGeneratorFailed, nil);
				continue;
			}
			else	{
				NSImage				*tmpImg = [[NSImage alloc] initWithSize:rgbPixelsSize];
				[tmpImg addRepresentation:bitRep];
				
				NSRect			imgRect = NSMakeRect(0,0,rgbPixelsSize.width,rgbPixelsSize.height);
				NSRect			canvasRect = NSMakeRect(0,0,self.maximumSize.width,self.maximumSize.height);
				NSRect			drawRect = [VVSizingTool rectThatFitsRect:imgRect inRect:canvasRect sizingMode:VVSizingModeFit];
				drawRect.origin = NSMakePoint(0,0);
				drawRect = NSIntegralRect(drawRect);
				
				NSGraphicsContext	*origCtx = [NSGraphicsContext currentContext];
				
				NSBitmapImageRep	*outRep = [[NSBitmapImageRep alloc]
					initWithBitmapDataPlanes:nil
					pixelsWide:drawRect.size.width
					pixelsHigh:drawRect.size.height
					bitsPerSample:8
					samplesPerPixel:4
					hasAlpha:YES
					isPlanar:NO
					colorSpaceName:NSDeviceRGBColorSpace
					bitmapFormat:0
					bytesPerRow:32*drawRect.size.width/8
					bitsPerPixel:32];
				NSGraphicsContext	*gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:outRep];
				[NSGraphicsContext setCurrentContext:gc];
				[tmpImg drawInRect:drawRect];
				
				NSImage				*outImg = [[NSImage alloc] initWithSize:drawRect.size];
				[outImg addRepresentation:outRep];
				
				CGRect				proposedRect = CGRectMake(0,0,drawRect.size.width,drawRect.size.height);
				CGImageRef			outImgRef = [outImg CGImageForProposedRect:&proposedRect context:gc hints:nil];
				
				[NSGraphicsContext setCurrentContext:origCtx];
				
				handler(timeVal, outImgRef, [decodedFrame presentationTime], AVAssetImageGeneratorSucceeded, nil);
			}
		}
		
	}
	else if ([self.asset isReadable])	{
		AVAssetImageGenerator		*gen = [[AVAssetImageGenerator alloc] initWithAsset:self.asset];
		gen.appliesPreferredTrackTransform = YES;
		gen.maximumSize = self.maximumSize;
		NSError				*nsErr = nil;
		//CMTime				time = CMTimeMake(1,60);
		for (NSValue * requestedTime in requestedTimes)	{
			CMTime		timeVal = [requestedTime CMTimeValue];
			CGImageRef			imgRef = [gen copyCGImageAtTime:timeVal actualTime:NULL error:&nsErr];
			handler(timeVal, imgRef, timeVal, AVAssetImageGeneratorSucceeded, nil);
		}
		
	}
	else	{
		for (NSValue * requestedTime in requestedTimes)	{
			CMTime		timeVal = [requestedTime CMTimeValue];
			handler(timeVal, NULL, kCMTimeInvalid, AVAssetImageGeneratorFailed, nil);
		}
	}
	
}

@end
