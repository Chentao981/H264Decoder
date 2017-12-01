//
//  H264DecoderViewController.m
//  H264Decoder
//
//  Created by Chentao on 2017/11/28.
//  Copyright © 2017年 Chentao. All rights reserved.
//

#import "H264DecoderViewController.h"
#import "KCLH264Decoder.h"
#import "KCLDataReader.h"
#import "KCLFileManager.h"

@interface H264DecoderViewController () <KCLH264DecoderDelegate>

@property (nonatomic, strong) KCLH264Decoder *h264Decoder;

@property (nonatomic, strong) UIImageView *imageView;

@property (nonatomic, strong) KCLDataReader *dataReader;

@property (nonatomic, strong) NSData *fileData;

@property (nonatomic, strong) NSTimer *timer;

@end

@implementation H264DecoderViewController {

    int index;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.h264Decoder = [[KCLH264Decoder alloc] init];
    self.h264Decoder.delegate = self;
    //
    self.imageView = [[UIImageView alloc] init];
    [self.view addSubview:self.imageView];

    NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:@"capture" withExtension:@"h264"];
    self.fileData = [NSData dataWithContentsOfURL:fileUrl];
    self.dataReader = [[KCLDataReader alloc] initWithData:self.fileData];

    UIButton *startButton = [[UIButton alloc] initWithFrame:CGRectMake(50, 50, 100, 50)];
    [startButton addTarget:self action:@selector(startButtonTouchHandler) forControlEvents:UIControlEventTouchUpInside];
    startButton.backgroundColor = [UIColor grayColor];
    [startButton setTitle:@"开始" forState:UIControlStateNormal];
    [self.view addSubview:startButton];

    UIButton *stopButton = [[UIButton alloc] initWithFrame:CGRectMake(50, 200, 100, 50)];
    [stopButton addTarget:self action:@selector(stopButtonTouchHandler) forControlEvents:UIControlEventTouchUpInside];
    stopButton.backgroundColor = [UIColor grayColor];
    [stopButton setTitle:@"停止" forState:UIControlStateNormal];
    [self.view addSubview:stopButton];
}

- (void)startButtonTouchHandler {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.020 target:self selector:@selector(pushData) userInfo:nil repeats:YES];
}

- (void)stopButtonTouchHandler {
    [self.timer invalidate];
    self.timer = nil;

    [self.h264Decoder destroy];

    self.h264Decoder = nil;
}

- (void)pushData {
    int size = 0;
    while (self.dataReader.poz <= self.fileData.length - 1 && size < 4096) {
        NSData *data = [self.dataReader readBytes:1];
        [self.h264Decoder decodeData:data];
        size++;
    }
}

#pragma mark - KCLH264Decoder

- (void)h264Decoder:(KCLH264Decoder *)decoder receiveFrameImage:(UIImage *)frameImage {

    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat viewWidth = CGRectGetWidth(self.view.bounds);
        self.imageView.frame = CGRectMake(0, 0, viewWidth, viewWidth / (frameImage.size.width / frameImage.size.height));

        NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
        self.imageView.image = frameImage;
        NSTimeInterval endTime = [[NSDate date] timeIntervalSince1970];

        NSLog(@"%f", (endTime - startTime) * 1000);

        NSData *imageData = UIImagePNGRepresentation(frameImage);
        NSString *filePath = [[KCLFileManager documentsDir] stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.png", index]];
        [KCLFileManager createFileAtPath:filePath content:imageData];

        index++;
        
    });

}

@end

