//
//  KCLH264DecoderBuffer.h
//  H264Decoder
//
//  Created by Chentao on 2017/11/28.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>

@class KCLH264DecoderBuffer;
@protocol KCLH264DecoderBufferDelegate <NSObject>

@required
- (void)decoderBuffer:(KCLH264DecoderBuffer *)decoderBuffer receiveNaluPacketData:(NSData *)packetData naluType:(int)naluType;

@end

@interface KCLH264DecoderBuffer : NSObject

@property (nonatomic, weak) id<KCLH264DecoderBufferDelegate> delegate;

- (void)pushData:(NSData *)data;

- (void)clear;

@end
