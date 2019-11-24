//
//	SynopsisHAPPlayerLayer.m
//	Synopsis Inspector
//
//	Created by vade on 7/24/17.
//	Copyright © 2017 v002. All rights reserved.
//

#import "HapInAVFoundation.h"
#import "AVPlayerHapLayer.h"
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import "VVSizingTool.h"




@interface AVPlayerHapLayer ()	{
	CGLContextObj context;
	
	CVOpenGLTextureRef			currentTextureRef;
	CVOpenGLTextureCacheRef		textureCache;
	
	HapPixelBufferTexture		*hapTex;
	
	CGSize					hapImageSize;
	CGAffineTransform		currentTransform;
	float					currentAngle;
}

@property (readwrite) AVPlayer* player;
@property (readwrite) AVPlayerItemVideoOutput* videoOutput;
@property (readwrite) AVPlayerItemHapDXTOutput* hapOutput;
@property (readwrite) HapDecoderFrame* currentDXTFrame;
@property (nonatomic, readwrite, getter=isReadyForDisplay) BOOL readyForDisplay;
@property (readwrite) BOOL useHAP;
@property (nonatomic, readwrite) CGRect videoRect;
@end




@implementation AVPlayerHapLayer


- (instancetype) init	{
	self = [super init];
	if(self)	{
		self.player = [[AVPlayer alloc] init];
		self.player.volume = 0;
		
		hapImageSize = CGSizeZero;
		hapTex = nil;
	}
	
	return self;
}

- (void) dealloc	{
	if (context != NULL)	{
		[self releaseGLResources:context];
		CGLReleaseContext(context);
		context = NULL;
	}
	
	[self.player release];
	self.player = nil;
	self.videoOutput = nil;
	self.hapOutput = nil;
	if (self.currentDXTFrame != nil)	{
		[self.currentDXTFrame release];
		self.currentDXTFrame = nil;
	}
	
	[super dealloc];
}

- (CGLPixelFormatObj) copyCGLPixelFormatForDisplayMask:(uint32_t)mask	{
	const CGLPixelFormatAttribute attributes[] = {
		kCGLPFAOpenGLProfile, kCGLOGLPVersion_Legacy,
		kCGLPFADoubleBuffer,
		kCGLPFAAccelerated,
		kCGLPFAColorSize, 32,
		kCGLPFADepthSize, 24,
		kCGLPFANoRecovery,
		kCGLPFADisplayMask, mask,
		(CGLPixelFormatAttribute)0,
	};
	
	CGLPixelFormatObj pf;
	GLint npix;
	CGLChoosePixelFormat(attributes, &pf, &npix);
	return pf;
}

- (CGLContextObj) copyCGLContextForPixelFormat:(CGLPixelFormatObj)pf	{
	if(context != NULL)	{
		[self releaseGLResources:context];
		CGLReleaseContext(context);
		context = NULL;
	}
	
	CGLCreateContext(pf, NULL, &context);

	
	NSDictionary* cacheAttributes = @{ (NSString*)kCVOpenGLTextureCacheChromaSamplingModeKey : (NSString*)kCVOpenGLTextureCacheChromaSamplingModeBestPerformance};
	
	CVOpenGLTextureCacheCreate(
		kCFAllocatorDefault,
		(__bridge CFDictionaryRef _Nullable)(cacheAttributes),
		context,
		pf,
		NULL,
		&textureCache);

	CGLSetCurrentContext(context);
	
	return context;
}

- (void)releaseCGLContext:(CGLContextObj)ctx	{
	assert(context == ctx);

	[self releaseGLResources:ctx];
	[super releaseCGLContext:ctx];
}

- (void) releaseGLResources:(CGLContextObj)ctx	{
	assert(context == ctx);

	CGLSetCurrentContext(ctx);
	
	if(textureCache)	{
		CVOpenGLTextureCacheRelease(textureCache);
		textureCache = NULL;
	}
	
	if(currentTextureRef)	{
		CVOpenGLTextureRelease(currentTextureRef);
		currentTextureRef = NULL;
	}
	
	if (hapTex != nil)	{
		[hapTex release];
		hapTex = nil;
	}
	
	hapImageSize = CGSizeZero;
	
}

- (void) replacePlayerItemWithItem:(AVPlayerItem*)item	{
	self.useHAP = NO;
	
	[self commonReplaceItem:item];
	
	self.hapOutput = nil;
	self.videoOutput = (AVPlayerItemVideoOutput*)[item.outputs lastObject];	   
}

- (void) replacePlayerItemWithHAPItem:(AVPlayerItem*)item	{
	self.useHAP = YES;

	[self commonReplaceItem:item];
	
	self.videoOutput = nil;
	self.hapOutput = (AVPlayerItemHapDXTOutput*)[item.outputs lastObject];
}

- (void) commonReplaceItem:(AVPlayerItem*)item	{
	self.readyForDisplay = NO;
	
	if(currentTextureRef)	{
		CGLSetCurrentContext(context);
		CVOpenGLTextureRelease(currentTextureRef);
		currentTextureRef = NULL;
	}
	
	if (self.currentDXTFrame != nil)	{
		[self.currentDXTFrame release];
		self.currentDXTFrame = nil;
	}
	
	if(self.player.currentItem)
		[self.player.currentItem removeObserver:self forKeyPath:@"status"];
	

	[item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
	
	[self.player replaceCurrentItemWithPlayerItem:item];
}

// lame optimization hack
- (void) display	{
//	  if(!self.readyForDisplay)
//		  return;
	
	[super display];
}



- (void)drawInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts	{
	//NSLog(@"%s",__func__);
	assert(context == ctx);
	
	if(!self.readyForDisplay)
		return;
	/*
	NSRect		tmpRect = NSRectFromCGRect([self frame]);
	NSLog(@"\tframe is %@",NSStringFromRect(tmpRect));
	tmpRect = NSRectFromCGRect([self bounds]);
	NSLog(@"\tbounds are %@",NSStringFromRect(tmpRect));
	NSSize		tmpSize = NSSizeFromCGSize([self preferredFrameSize]);
	NSLog(@"\tpreferredFrameSize is %@",NSStringFromSize(tmpSize));
	*/
	glClearColor(0.0, 0.0, 0.0, 0.0);
	glClear(GL_COLOR_BUFFER_BIT);
	
	glPushAttrib(GL_TEXTURE_BIT);
	
	{
		if(self.useHAP)	{
			[self drawHAPInCGLContext:ctx pixelFormat:pf forLayerTime:t displayTime:ts];
		}
		else	{
			[self drawPixelBufferInCGLContext:ctx pixelFormat:pf forLayerTime:t displayTime:ts];
		}
	}
	
	glPopAttrib();
	
	[super drawInCGLContext:ctx pixelFormat:pf forLayerTime:t displayTime:ts];
	
	[self glErrCheck];
}
- (BOOL) glErrCheck	{
	int			err = glGetError();
	if (err != 0)	{
		NSString		*humanReadable = nil;
		switch(err){
		case 0x0: humanReadable = @"no error"; break;
		case 0x500: humanReadable = @"invalid enum"; break;
		case 0x501: humanReadable = @"invalid value"; break;
		case 0x502: humanReadable = @"invalid operation"; break;
		case 0x503: humanReadable = @"stack overflow"; break;
		case 0x504: humanReadable = @"stack underflow"; break;
		case 0x505: humanReadable = @"out of memory"; break;
		case 0x506: humanReadable = @"invalid framebuffer"; break;
		case 0x507: humanReadable = @"context lost"; break;
		case 0x8031: humanReadable = @"table too large"; break;
		default: break;
		}
		NSLog(@"encountered GL error %@",humanReadable);
		return YES;
	}
	return NO;
}

- (void) drawPixelBufferInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts	{
	//NSLog(@"%s",__func__);
	CMTime time = [self.videoOutput itemTimeForHostTime:t];
	
	if ([self.videoOutput hasNewPixelBufferForItemTime:time])	{
		CVPixelBufferRef currentPixelBuffer = [self.videoOutput copyPixelBufferForItemTime:time itemTimeForDisplay:NULL];
		
		if(currentTextureRef != NULL)	{
			CVOpenGLTextureRelease(currentTextureRef);
			currentTextureRef = NULL;
		}

		CVOpenGLTextureCacheFlush(textureCache, 0);
		CVOpenGLTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
												   textureCache,
												   currentPixelBuffer,
												   NULL,
												   &currentTextureRef);
		
		CVPixelBufferRelease(currentPixelBuffer);
	}
	
	if(currentTextureRef != NULL)	{
		GLfloat texCoords[8];
		
		glUseProgram(0);
		
		GLuint texture = CVOpenGLTextureGetName(currentTextureRef);
		GLenum target = CVOpenGLTextureGetTarget(currentTextureRef);
		
		BOOL flipped = CVImageBufferIsFlipped(currentTextureRef);
		
		glEnable(target);
		glBindTexture(target, texture);
		
		CVOpenGLTextureGetCleanTexCoords(currentTextureRef,
										 (!flipped ? &texCoords[6] : &texCoords[0]), // lower left
										 (!flipped ? &texCoords[4] : &texCoords[2]), // lower right
										 (!flipped ? &texCoords[2] : &texCoords[4]), // upper right
										 (!flipped ? &texCoords[0] : &texCoords[6])	 // upper left
										 );
		
		GLfloat width = texCoords[2] - texCoords[0];
		GLfloat height = texCoords[7] - texCoords[1];
		
		GLfloat _width = self.frame.size.width;
		GLfloat _height = self.frame.size.height;
		GLfloat _ox = self.bounds.origin.x;
		GLfloat _oy = self.bounds.origin.y;
		
		GLfloat _bwidth = self.bounds.size.width;
		GLfloat _bheight = self.bounds.size.height;
		
		GLfloat xRatio = width / _width;
		GLfloat yRatio = height / _height;
		GLfloat xoffset = _ox * xRatio;
		GLfloat yoffset = _oy * yRatio;
		GLfloat xinset = ((GLfloat)_width - (_ox + _bwidth)) * xRatio;
		GLfloat yinset = ((GLfloat)_height - (_oy + _bheight)) * yRatio;
		
		texCoords[0] += xoffset;
		texCoords[1] += yoffset;
		texCoords[2] -= xinset;
		texCoords[3] += yoffset;
		texCoords[4] -= xinset;
		texCoords[5] -= yinset;
		texCoords[6] += xoffset;
		texCoords[7] -= yinset;
		
		glColor4f(1.0, 1.0, 1.0, 1.0);
		
		CGSize displaySize = CVImageBufferGetDisplaySize(currentTextureRef);
		
		self.videoRect = CGRectApplyAffineTransform( AVMakeRectWithAspectRatioInsideRect(displaySize, self.bounds), currentTransform);

		GLfloat aspect = displaySize.height/displaySize.width;
		
		//GLfloat vertexCoords[8] =
		//{
		//	-1.0,	-aspect,
		//	1.0,	-aspect,
		//	1.0,	 aspect,
		//	-1.0,	 aspect
		//};
		GLfloat		vertexCoords[8] = {
			-1., -1.,
			1., -1.,
			1., 1.,
			-1., 1.
		};
		
		glPushMatrix();
		
		glRotatef(-currentAngle, 0, 0, 1);

		glEnableClientState( GL_TEXTURE_COORD_ARRAY );
		glTexCoordPointer(2, GL_FLOAT, 0, texCoords );
		glEnableClientState(GL_VERTEX_ARRAY);
		glVertexPointer(2, GL_FLOAT, 0, vertexCoords );
		glDrawArrays( GL_TRIANGLE_FAN, 0, 4 );
		glDisableClientState( GL_TEXTURE_COORD_ARRAY );
		glDisableClientState(GL_VERTEX_ARRAY);
		
		glPopMatrix();

	}
}


- (void) drawHAPInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts	{
	//NSLog(@"%s",__func__);
	
	if (hapTex != nil && [hapTex context] != ctx)	{
		[hapTex release];
		hapTex = nil;
	}
	if (hapTex == nil)	{
		hapTex = [[HapPixelBufferTexture alloc] initWithContext:ctx];
	}
	
	if (hapTex == nil)	{
		NSLog(@"ERR: hapTex is nil, bailing, %s",__func__);
		return;
	}
	
	CMTime frameTime = [self.hapOutput itemTimeForHostTime:t];
	
	HapDecoderFrame *dxtFrame = [self.hapOutput allocFrameForTime:frameTime];
	
	if (hapTex != nil)
		[hapTex setDecodedFrame:dxtFrame];
	
	CGSize imageSize = NSSizeToCGSize([self.currentDXTFrame imgSize]);
	
	if(dxtFrame)	{
		if (self.currentDXTFrame != nil)	{
			[self.currentDXTFrame release];
			self.currentDXTFrame = nil;
		}
		self.currentDXTFrame = dxtFrame;
		
		CGSize imageSize = NSSizeToCGSize([self.currentDXTFrame imgSize]);
		if ( !CGSizeEqualToSize(hapImageSize, imageSize) && !CGSizeEqualToSize(CGSizeZero, imageSize)	 )	{
			hapImageSize = imageSize;
			self.videoRect = CGRectApplyAffineTransform( AVMakeRectWithAspectRatioInsideRect(hapImageSize, self.bounds), currentTransform);
		}
	}
	
	if(self.currentDXTFrame != nil
	//&& hapTextureIDs[0] != 0
	&& !CGSizeEqualToSize(CGSizeZero, hapImageSize))
	{
		
		glUseProgram([hapTex shaderProgramObject]);
		for (int i=0; i<[hapTex textureCount]; ++i)	{
			glActiveTexture(GL_TEXTURE0 + i);
			glBindTexture(GL_TEXTURE_2D, [hapTex textureNames][i]);
		}
		
		CGSize		hapTextureSize = CGSizeMake([hapTex textureWidths][0], [hapTex textureHeights][0]);
		
		GLfloat texCoords[8] = {
		//	0.0, 1.0,
		//	1.0, 1.0,
		//	1.0, 0.0,
		//	0.0, 0.0
			0.0, hapImageSize.height/hapTextureSize.height,
			hapImageSize.width/hapTextureSize.width, hapImageSize.height/hapTextureSize.height,
			hapImageSize.width/hapTextureSize.width, 0.0,
			0.0, 0.0
		};
		
		GLfloat		vertexCoords[8] = {
			-1., -1.,
			1., -1.,
			1., 1.,
			-1., 1.
		};
		
		
		glEnable(GL_TEXTURE_2D);
		
		glPushMatrix();
		
		glRotatef(-currentAngle, 0, 0, 1);
		
		glEnableClientState( GL_TEXTURE_COORD_ARRAY );
		glTexCoordPointer(2, GL_FLOAT, 0, texCoords );
		glEnableClientState(GL_VERTEX_ARRAY);
		glVertexPointer(2, GL_FLOAT, 0, vertexCoords );
		glDrawArrays( GL_TRIANGLE_FAN, 0, 4 );
		glDisableClientState( GL_TEXTURE_COORD_ARRAY );
		glDisableClientState(GL_VERTEX_ARRAY);
		
		glPopMatrix();
	}
	else	{
	}

}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void *)c	{
	if([object isKindOfClass:[AVPlayerItem class]])	{
		AVPlayerItem* item = (AVPlayerItem*) object;
		
		AVAssetTrack* videoTrack = [[item.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
		if (videoTrack)	{
			currentTransform = videoTrack.preferredTransform;
		}
		else	{
			currentTransform = CGAffineTransformIdentity;
		}

		currentAngle = [self angleFromAffineTransform:currentTransform];

		if (item.status == AVPlayerItemStatusReadyToPlay)	{
			[self.player
				seekToTime:kCMTimeZero
				toleranceBefore:kCMTimeZero
				toleranceAfter:kCMTimeZero
				completionHandler:^(BOOL finished) {
					self.readyForDisplay = YES;
					[self setNeedsDisplay];
				}];
			[self setNeedsDisplay];
		}
		else
			self.readyForDisplay = NO;
		
	}
	else	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:c];
	}
}

- (void) play	{
	[self.player play];
	self.asynchronous = YES;
}

- (void) pause	{
	self.asynchronous = NO;
	[self.player pause];
}

- (float) angleFromAffineTransform:(CGAffineTransform)transform	{
	float radians = atan2(transform.b, transform.d);
	return radians * (180 / M_PI);
}

- (CGFloat) xscaleFromAffineTransform:(CGAffineTransform)transform	{
	CGAffineTransform t = transform;
	return sqrt(t.a * t.a + t.c * t.c);
}

- (CGFloat) yscaleFromAffineTransform:(CGAffineTransform)transform	{
	CGAffineTransform t = transform;
	return sqrt(t.b * t.b + t.d * t.d);
}


- (GLuint)loadShaderOfType:(GLenum)type named:(NSString *)name	{
	NSString *extension = (type == GL_VERTEX_SHADER ? @"vert" : @"frag");
	NSString  *path = [[NSBundle bundleForClass:[self class]] pathForResource:name
																	   ofType:extension];
	NSString *source = nil;
	if (path) source = [NSString stringWithContentsOfFile:path usedEncoding:nil error:nil];
	
	GLint shaderCompiled = 0;
	GLuint shaderObject = 0;
	
	if(source != nil)	{
		const GLchar *glSource = [source cStringUsingEncoding:NSASCIIStringEncoding];
		
		shaderObject = glCreateShader(type);
		glShaderSource(shaderObject, 1, &glSource, NULL);
		glCompileShader(shaderObject);
		
		glGetShaderiv(
			shaderObject,
			GL_COMPILE_STATUS,
			&shaderCompiled);
		
		if(shaderCompiled == 0 )	{
			glDeleteShader(shaderObject);
			shaderObject = 0;
		}
	}
	return shaderObject;
}


- (GLuint) loadShader	{
	GLuint program = 0;
	
	GLuint vert = [self loadShaderOfType:GL_VERTEX_SHADER named:@"ScaledCoCgYToRGBA"];
	GLuint frag = [self loadShaderOfType:GL_FRAGMENT_SHADER named:@"ScaledCoCgYToRGBA"];
	
	GLint programLinked = 0;
	if (frag && vert)	{
		program = glCreateProgram();
		glAttachShader(program, vert);
		glAttachShader(program, frag);
		glLinkProgram(program);
		glGetProgramiv(
			program,
			GL_LINK_STATUS,
			&programLinked);
		if(programLinked == 0 )	{
			glDeleteProgram(program);
			program = 0;
		}
		else	{
			glUseProgram(program);
			GLint samplerLoc = -1;
			samplerLoc = glGetUniformLocation(program, "cocgsy_src");
			if (samplerLoc >= 0)
				glUniform1i(samplerLoc,0);
			samplerLoc = -1;
			samplerLoc = glGetUniformLocation(program, "alpha_src");
			if (samplerLoc >= 0)
				glUniform1i(samplerLoc,1);
			glUseProgram(0);
		}
	}
	if (frag)
		glDeleteShader(frag);
	if (vert)
		glDeleteShader(vert);
	
	return program;
}

@end
