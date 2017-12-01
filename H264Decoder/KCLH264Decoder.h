//
//  KCLH264Decoder.h
//  H264Decoder
//
//  Created by Chentao on 2017/11/28.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class KCLH264Decoder;
@protocol KCLH264DecoderDelegate <NSObject>

@required
- (void)h264Decoder:(KCLH264Decoder *)decoder receiveFrameImage:(UIImage *)frameImage;

@end

@interface KCLH264Decoder : NSObject

@property (nonatomic, weak) id<KCLH264DecoderDelegate> delegate;

- (void)decodeData:(NSData *)data;

- (void)reset;

- (void)destroy;

@end
