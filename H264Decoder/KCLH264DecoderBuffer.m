

//
//  KCLH264DecoderBuffer.m
//  H264Decoder
//
//  Created by Chentao on 2017/11/28.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import "KCLH264DecoderBuffer.h"
#import "KCLDataReader.h"
#import "KCLDataWriter.h"

static const uint8_t kclLStartCodeLength = 4;
static const int8_t kclLStartCode[] = { 0x00, 0x00, 0x00, 0x01 };

static const uint8_t kclSStartCodeLength = 3;
static const int8_t kclSStartCode[] = { 0x00, 0x00, 0x01 };

#pragma mark - KCLH264Nalu

@interface KCLH264Nalu : NSObject
@property (nonatomic, assign) int startCodeLength;
@property (nonatomic, strong) NSData *naluData;
@property (nonatomic, assign) int naluType;
@property (nonatomic, assign) int nextStartCodeLength;
@property (nonatomic, assign) BOOL bad;
@end

@implementation KCLH264Nalu
@end
#pragma mark -

@interface KCLH264DecoderBuffer ()

@property (nonatomic, strong) NSMutableData *dataBuffer;

@property (nonatomic, strong) NSMutableData *bigNaluPacketData;

@end

@implementation KCLH264DecoderBuffer

- (instancetype)init {
    self = [super init];
    if (self) {
        self.dataBuffer = [[NSMutableData alloc] init];
        self.bigNaluPacketData = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)pushData:(NSData *)data {
    [self.dataBuffer appendData:data];
    NSUInteger dataBufferLength = self.dataBuffer.length;
    if (dataBufferLength >= kclLStartCodeLength) {
        // int startCodeLength = kclLStartCodeLength;

        KCLH264Nalu *nalu = [self subNalu:self.dataBuffer startCode:kclLStartCode startCodeLength:kclLStartCodeLength];
        if (!nalu) {
            // startCodeLength = kclSStartCodeLength;
            nalu = [self subNalu:self.dataBuffer startCode:kclSStartCode startCodeLength:kclSStartCodeLength];
        }
        if (nalu && nalu.naluData.length > 0) {
            self.dataBuffer = [[NSMutableData alloc] initWithData:[self.dataBuffer subdataWithRange:NSMakeRange(nalu.naluData.length, dataBufferLength - nalu.naluData.length)]];
            if (!nalu.bad) {
                [self reorganizationNalu:nalu];
            }
        }
    }
}

- (KCLH264Nalu *)subNalu:(NSData *)sourceData startCode:(uint8_t *)startCode startCodeLength:(uint8_t)startCodeLength {
    NSUInteger location = sourceData.length - startCodeLength;
    NSData *startCodeData = [sourceData subdataWithRange:NSMakeRange(location, startCodeLength)];

    BOOL equalStartCode = [self isEqualStartCode:startCode startCodeLength:startCodeLength targetData:startCodeData];

    if (equalStartCode) {
        KCLH264Nalu *nalu = [[KCLH264Nalu alloc] init];
        nalu.nextStartCodeLength = startCodeLength;
        if (0 != location) {
            NSData *targetData = [self.dataBuffer subdataWithRange:NSMakeRange(0, location)];

            if (targetData.length > kclSStartCodeLength) {
                NSData *targetDataSStartCode = [targetData subdataWithRange:NSMakeRange(0, kclSStartCodeLength)];
                BOOL equalSStartCode = [self isEqualStartCode:kclSStartCode startCodeLength:kclSStartCodeLength targetData:targetDataSStartCode];
                if (equalSStartCode) {
                    nalu.startCodeLength = kclSStartCodeLength;
                } else {
                    if (targetData.length > kclLStartCodeLength) {
                        NSData *targetDataLStartCode = [targetData subdataWithRange:NSMakeRange(0, kclLStartCodeLength)];
                        BOOL equalLStartCode = [self isEqualStartCode:kclLStartCode startCodeLength:kclLStartCodeLength targetData:targetDataLStartCode];
                        if (equalLStartCode) {
                            nalu.startCodeLength = kclLStartCodeLength;
                        }
                    } else {
                        nalu.bad = YES;
                    }
                }

            } else {
                nalu.bad = YES;
            }

            nalu.naluData = targetData;
            return nalu;
        }
        return nalu;
    }
    return nil;
}

- (void)reorganizationNalu:(KCLH264Nalu *)nalu {
    KCLH264Nalu *naluPacket = [self naluConvertToNaluPacketData:nalu];
    //    NSLog(@"startCodeLength:%d nextStartCodeLength:%d naluType:%d", naluPacket.startCodeLength, naluPacket.nextStartCodeLength, naluPacket.naluType);
    switch (naluPacket.naluType) {
        case 6:
        case 7:
        case 8: {
            [self.delegate decoderBuffer:self receiveNaluPacketData:naluPacket.naluData naluType:naluPacket.naluType];
            break;
        }
        default: {
            [self.bigNaluPacketData appendData:naluPacket.naluData];

            if (kclLStartCodeLength == naluPacket.nextStartCodeLength) {
                [self.delegate decoderBuffer:self receiveNaluPacketData:self.bigNaluPacketData naluType:naluPacket.naluType];
                self.bigNaluPacketData = [[NSMutableData alloc] init];
            }
            break;
        }
    }
}

- (KCLH264Nalu *)naluConvertToNaluPacketData:(KCLH264Nalu *)nalu {
    uint32_t naluPacketDataSize = (uint32_t)(nalu.naluData.length - nalu.startCodeLength);
    uint8_t *pNaluPacketDataSize = (uint8_t *)(&naluPacketDataSize);

    NSMutableData *naluPacketData = [[NSMutableData alloc] init];
    KCLDataWriter *naluPacketDataWriter = [[KCLDataWriter alloc] initWithData:naluPacketData];

    ///////////////////
    [naluPacketDataWriter writeByte:*(pNaluPacketDataSize + 3)];
    [naluPacketDataWriter writeByte:*(pNaluPacketDataSize + 2)];
    [naluPacketDataWriter writeByte:*(pNaluPacketDataSize + 1)];
    [naluPacketDataWriter writeByte:*(pNaluPacketDataSize + 0)];
    ///////////////////

    NSData *sourceNaluData = [nalu.naluData subdataWithRange:NSMakeRange(nalu.startCodeLength, naluPacketDataSize)];
    [naluPacketDataWriter writeBytes:sourceNaluData];

    KCLDataReader *sourceNaluDataReader = [[KCLDataReader alloc] initWithData:sourceNaluData];

    int naluType = ([sourceNaluDataReader readByte] & 0x1F);

    KCLH264Nalu *newNalu = [[KCLH264Nalu alloc] init];
    newNalu.startCodeLength = nalu.startCodeLength;
    newNalu.naluData = naluPacketData;
    newNalu.naluType = naluType;
    newNalu.nextStartCodeLength = nalu.nextStartCodeLength;
    return newNalu;
}

- (BOOL)isEqualStartCode:(uint8_t *)startCode startCodeLength:(uint8_t)startCodeLength targetData:(NSData *)targetData {
    KCLDataReader *targetDataReader = [[KCLDataReader alloc] initWithData:targetData];
    BOOL equalStartCode = YES;
    while (targetDataReader.poz <= (startCodeLength - 1)) {
        int8_t pozValue = startCode[targetDataReader.poz];
        int8_t value = [targetDataReader readByte];
        if (value != pozValue) {
            equalStartCode = NO;
            break;
        }
    }
    return equalStartCode;
}

- (void)clear {
    self.dataBuffer = [[NSMutableData alloc] init];
    self.bigNaluPacketData = [[NSMutableData alloc] init];
}

@end
