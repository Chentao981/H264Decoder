

//
//  KCLH264Decoder.m
//  H264Decoder
//
//  Created by Chentao on 2017/11/28.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import "KCLH264Decoder.h"
#import "KCLH264DecoderBuffer.h"
#import <VideoToolbox/VideoToolbox.h>

//#import "H264HwDecoderImpl.h"

//#import "KCLFileManager.h"
//#import <UIKit/UIKit.h>

static const int KCL_HEADER_LENGTH = 4;

@interface KCLH264Decoder () <KCLH264DecoderBufferDelegate>

@property (nonatomic, strong) KCLH264DecoderBuffer *decoderBuffer;

@end

@implementation KCLH264Decoder {
    NSData *spsData;
    BOOL receiveSPS;

    NSData *ppsData;
    BOOL receivePPS;

    VTDecompressionSessionRef deocderSession;
    BOOL deocderSessionInitialize;

    CMVideoFormatDescriptionRef decoderFormatDescription;

    BOOL isInvalidate;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.decoderBuffer = [[KCLH264DecoderBuffer alloc] init];
        self.decoderBuffer.delegate = self;
    }
    return self;
}

- (void)decodeData:(NSData *)data {
    if (!isInvalidate) {
        [self.decoderBuffer pushData:data];
    }
}

- (void)reset {
    [self.decoderBuffer clear];
    receiveSPS = NO;
    receivePPS = NO;
}

- (void)destroy {
    isInvalidate = YES;
    if (deocderSessionInitialize && deocderSession) {
        VTDecompressionSessionInvalidate(deocderSession);
    }
}

- (void)initializeDecoder {
    if (receiveSPS && receivePPS) {
        const uint8_t *const parameterSetPointers[2] = { spsData.bytes, ppsData.bytes };
        const size_t parameterSetSizes[2] = { spsData.length, ppsData.length };
        OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault, 2, parameterSetPointers, parameterSetSizes, KCL_HEADER_LENGTH, &decoderFormatDescription);
        if (noErr == status) {
            CGSize videoSize = CMVideoFormatDescriptionGetPresentationDimensions(decoderFormatDescription, NO, NO);
            NSDictionary *destinationPixelBufferAttributes = @{
                (id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA],
                (id)kCVPixelBufferWidthKey: [NSNumber numberWithInt:videoSize.width],
                (id)kCVPixelBufferHeightKey: [NSNumber numberWithInt:videoSize.height],
                (id)kCVPixelBufferOpenGLCompatibilityKey: [NSNumber numberWithBool:YES]
            };

            VTDecompressionOutputCallbackRecord callBackRecord;
            callBackRecord.decompressionOutputCallback = didDecompress;
            callBackRecord.decompressionOutputRefCon = (__bridge void *)self;

            status = VTDecompressionSessionCreate(kCFAllocatorDefault, decoderFormatDescription, NULL, (__bridge CFDictionaryRef)destinationPixelBufferAttributes, &callBackRecord, &deocderSession);
            if (noErr == status) {
                deocderSessionInitialize = YES;
                VTSessionSetProperty(deocderSession, kVTDecompressionPropertyKey_ThreadCount, (__bridge CFTypeRef)[NSNumber numberWithInt:1]);
                VTSessionSetProperty(deocderSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
                receiveSPS = NO;
                receivePPS = NO;
            } else {
                deocderSessionInitialize = NO;
                NSLog(@"IOS8VT: reset decoder session failed status=%d", (int)status);
            }
        } else {
            deocderSessionInitialize = NO;
            NSLog(@"IOS8VT: reset decoder session failed status=%d", (int)status);
        }
    }
}

- (void)decodeH264Data:(NSData *)data naluType:(int)naluType {
    CMBlockBufferRef blockBuffer = NULL;

    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL, data.bytes, data.length, kCFAllocatorNull, NULL, 0, data.length, FALSE, &blockBuffer);
    if (kCMBlockBufferNoErr == status) {
        CMSampleBufferRef sampleBuffer = NULL;
        const size_t sampleSizeArray[] = { data.length };
        status = CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuffer, decoderFormatDescription, 1, 0, NULL, 1, sampleSizeArray, &sampleBuffer);
        if (kCMBlockBufferNoErr == status && sampleBuffer) {

            // 这里用于设置frame的时间戳
            // CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, CMTimeMake(10, 1));

            CVPixelBufferRef outputPixelBuffer = NULL;
            VTDecodeFrameFlags flags = 0;
            VTDecodeInfoFlags flagOut = 0;
            OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(deocderSession, sampleBuffer, flags, &outputPixelBuffer, &flagOut);
            if (noErr != decodeStatus) {
                NSLog(@"H264 Decoder: decoder failed:%d naluType:%d", (int)decodeStatus, naluType);
            }
            CFRelease(sampleBuffer);
        } else {
            NSLog(@"H264 Decoder: init sampleBuffer failed:%d naluType:%d", (int)status, naluType);
        }
        CFRelease(blockBuffer);
    } else {
        NSLog(@"H264 Decoder: init blockBuffer failed:%d naluType:%d", (int)status, naluType);
    }
}

//解码回调函数
static void didDecompress(void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef pixelBuffer, CMTime presentationTimeStamp, CMTime presentationDuration) {

    KCLH264Decoder *decoder = (__bridge KCLH264Decoder *)decompressionOutputRefCon;

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    size_t width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    size_t height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    void *lumaAddress = CVPixelBufferGetBaseAddress(pixelBuffer);

    CGColorSpaceRef rgbSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(lumaAddress, width, height, 8, bytesPerRow, rgbSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    if (image && decoder.delegate) {
        // NSData *imageData = UIImagePNGRepresentation(image);
        // NSLog(@"imageData.length:%lld", imageData.length);
        [decoder.delegate h264Decoder:decoder receiveFrameImage:image];
    }
    CGImageRelease(imageRef);
}

#pragma mark - KCLH264DecoderBufferDelegate
- (void)decoderBuffer:(KCLH264DecoderBuffer *)decoderBuffer receiveNaluPacketData:(NSData *)packetData naluType:(int)naluType {
    // NSLog(@"packetDataLength:%lu nalutype:%d", packetData.length, naluType);

    switch (naluType) {
        case 7: {
            receiveSPS = YES;
            spsData = [NSData dataWithData:[packetData subdataWithRange:NSMakeRange(KCL_HEADER_LENGTH, packetData.length - KCL_HEADER_LENGTH)]];
            break;
        }
        case 8: {
            receivePPS = YES;
            ppsData = [NSData dataWithData:[packetData subdataWithRange:NSMakeRange(KCL_HEADER_LENGTH, packetData.length - KCL_HEADER_LENGTH)]];
            break;
        }
        default: {
            [self initializeDecoder];
            if (deocderSessionInitialize) {
                [self decodeH264Data:packetData naluType:naluType];
            }
            break;
        }
    }
}
#pragma mark -

@end

