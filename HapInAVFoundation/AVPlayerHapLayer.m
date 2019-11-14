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

@interface AVPlayerHapLayer ()	{
	CGLContextObj context;
	
	CVOpenGLTextureRef currentTextureRef;
	CVOpenGLTextureCacheRef textureCache;
	
//	  GLhandleARB hapYCogShader;
	GLuint hapYCogShader;
	
	GLuint hapTextureIDs[2];
	CGSize hapTextureSize;
	
	CGAffineTransform currentTransform;
	float currentAngle;
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
		
		hapTextureSize = CGSizeZero;
		hapYCogShader = 0;
		hapTextureIDs[0] = 0;
		hapTextureIDs[1] = 0;
		
	}
	
	return self;
}

- (CGLPixelFormatObj)copyCGLPixelFormatForDisplayMask:(uint32_t)mask	{
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

- (CGLContextObj)copyCGLContextForPixelFormat:(CGLPixelFormatObj)pf	{
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
	hapYCogShader = [self loadShader];
	
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
	
	if(hapTextureIDs)	{
		glDeleteTextures(2, hapTextureIDs);
		hapTextureIDs[0] = 0;
		hapTextureIDs[1] = 0;
	}
	
	if (hapYCogShader != 0)	{
		glDeleteProgram(hapYCogShader);
		hapYCogShader = 0;
	}
	
	hapTextureSize = CGSizeZero;
	
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
	
	if(self.currentDXTFrame)	{
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
	assert(context == ctx);
	
	if(!self.readyForDisplay)
		return;
	
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

	GLenum error = glGetError();
	
	if(error)
	{
		const GLubyte* errorString = glGetString(error);
		NSLog(@"GL Error: %04x %s", error, errorString);
	}
}

- (void) drawPixelBufferInCGLContext:(CGLContextObj)ctx pixelFormat:(CGLPixelFormatObj)pf forLayerTime:(CFTimeInterval)t displayTime:(const CVTimeStamp *)ts	{
	CMTime time = [self.videoOutput itemTimeForHostTime:t];
	
	if([self.videoOutput hasNewPixelBufferForItemTime:time])	{
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
		
		GLfloat vertexCoords[8] =
		{
			-1.0,	-aspect,
			1.0,	-aspect,
			1.0,	 aspect,
			-1.0,	 aspect
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
	
	CMTime frameTime = [self.hapOutput itemTimeForHostTime:t];
	
	HapDecoderFrame *dxtFrame = [self.hapOutput allocFrameClosestToTime:frameTime];
		
	glEnable(GL_TEXTURE_2D);

	if(dxtFrame)	{
		
		self.currentDXTFrame = dxtFrame;
		
		CGSize imageSize = NSSizeToCGSize([self.currentDXTFrame imgSize]);
		
		CGSize dxtSize = NSSizeToCGSize([self.currentDXTFrame dxtImgSize]);
		GLuint roundedWidth = dxtSize.width;
		GLuint roundedHeight = dxtSize.height;
		
		if (roundedWidth % 4 != 0 || roundedHeight % 4 != 0)	{
			return;
		}

		GLenum internalFormat;
		int textureCount = [self.currentDXTFrame dxtPlaneCount];
		void **dxtBaseAddresses = [self.currentDXTFrame dxtDatas];
		size_t *dxtDataSizes = [self.currentDXTFrame dxtDataSizes];
		OSType *dxtPixelFormats = [self.currentDXTFrame dxtPixelFormats];
		
		BOOL needsShader = NO;
		
		for (int texIndex = 0; texIndex < textureCount; ++texIndex)	{
			unsigned int bitsPerPixel = 0;
			
			switch (dxtPixelFormats[texIndex])	{
			case kHapCVPixelFormat_RGB_DXT1:
				internalFormat = HapTextureFormat_RGB_DXT1;
				bitsPerPixel = 4;
				break;
			case kHapCVPixelFormat_RGBA_DXT5:
				internalFormat = HapTextureFormat_RGBA_DXT5;
				bitsPerPixel = 8;
				break;
			case kHapCVPixelFormat_YCoCg_DXT5:
				internalFormat = HapTextureFormat_RGBA_DXT5;
				bitsPerPixel = 8;
				needsShader = true;
				break;
			case kHapCVPixelFormat_CoCgXY:
				if (texIndex==0)
				{
					internalFormat = HapTextureFormat_RGBA_DXT5;
					bitsPerPixel = 8;
				}
				else
				{
					internalFormat = HapTextureFormat_A_RGTC1;
					bitsPerPixel = 4;
				}
				needsShader = true;
				break;
			case kHapCVPixelFormat_YCoCg_DXT5_A_RGTC1:
				if (texIndex==0)
				{
					internalFormat = HapTextureFormat_RGBA_DXT5;
					bitsPerPixel = 8;
				}
				else
				{
					internalFormat = HapTextureFormat_A_RGTC1;
					bitsPerPixel = 4;
				}
				needsShader = true;
				break;
			case kHapCVPixelFormat_A_RGTC1:
				internalFormat = HapTextureFormat_A_RGTC1;
				bitsPerPixel = 4;
				break;
			default:
				return;
				break;
			}
			
			size_t			bytesPerRow = (roundedWidth * bitsPerPixel) / 8;
			GLsizei			newDataLength = (int)(bytesPerRow * roundedHeight);
			size_t			actualBufferSize = dxtDataSizes[texIndex];
			
			GLvoid *baseAddress = dxtBaseAddresses[texIndex];
			if(baseAddress == NULL)
				return;
		
			if(needsShader)
			{
				glUseProgram(hapYCogShader);
			}
			else
				glUseProgram(0);
			
			if ( !CGSizeEqualToSize(hapTextureSize, imageSize) && !CGSizeEqualToSize(CGSizeZero, imageSize)	 )	{
				
				if(hapTextureIDs[texIndex])	{
					glDeleteTextures(1, &hapTextureIDs[texIndex]);
				}
				
				glGenTextures(1, &(hapTextureIDs[texIndex]));
				
				hapTextureSize = imageSize;

				self.videoRect = CGRectApplyAffineTransform( AVMakeRectWithAspectRatioInsideRect(hapTextureSize, self.bounds), currentTransform);
				
				glBindTexture(GL_TEXTURE_2D, hapTextureIDs[texIndex]);

				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
				glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_STORAGE_HINT_APPLE , GL_STORAGE_SHARED_APPLE);
			   
				glTexImage2D(GL_TEXTURE_2D, 0, internalFormat, roundedWidth, roundedHeight, 0, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, NULL);

			}
			
			else	{
				glBindTexture(GL_TEXTURE_2D, hapTextureIDs[texIndex]);

			}
			
			glTextureRangeAPPLE(GL_TEXTURE_2D, newDataLength, baseAddress);
			glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
			
			glCompressedTexSubImage2D(
				GL_TEXTURE_2D,
				0,
				0,
				0,
				roundedWidth,
				roundedHeight,
				internalFormat,
				newDataLength,
				baseAddress);
		}
		
	}
	
	if(self.currentDXTFrame != nil
	&& hapTextureIDs[0] != 0
	&& !CGSizeEqualToSize(CGSizeZero, hapTextureSize))
	{

		glBindTexture(GL_TEXTURE_2D, hapTextureIDs[0]);
		
		GLfloat aspect = (GLfloat)hapTextureSize.height / (GLfloat)hapTextureSize.width;
		GLfloat texCoords[8] = {
			0.0, 1.0,
			1.0, 1.0,
			1.0, 0.0,
			0.0, 0.0
		};
		
		GLfloat vertexCoords[8] = {
			-1.0,	-aspect,
			1.0,	-aspect,
			1.0,	 aspect,
			-1.0,	 aspect
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

		if(item.status == AVPlayerItemStatusReadyToPlay)	{
			self.readyForDisplay = YES;
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
