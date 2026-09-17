// ai coding: 将多尺寸 PNG 按标准 ICNS 数据块格式封装为 macOS 图标文件 2026/09/16: 19:13
#import <Foundation/Foundation.h>

static void SDAppendUInt32(NSMutableData *data, uint32_t value) {
    uint32_t bigEndian = CFSwapInt32HostToBig(value);
    [data appendBytes:&bigEndian length:sizeof(bigEndian)];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) return 1;
        NSString *iconsetPath = [NSString stringWithUTF8String:argv[1]];
        NSString *outputPath = [NSString stringWithUTF8String:argv[2]];
        NSArray<NSArray<NSString *> *> *entries = @[
            @[@"icp4", @"icon_16x16.png"],
            @[@"icp5", @"icon_32x32.png"],
            @[@"icp6", @"icon_32x32@2x.png"],
            @[@"ic07", @"icon_128x128.png"],
            @[@"ic08", @"icon_256x256.png"],
            @[@"ic09", @"icon_512x512.png"],
            @[@"ic10", @"icon_512x512@2x.png"]
        ];

        NSMutableData *body = [NSMutableData data];
        for (NSArray<NSString *> *entry in entries) {
            NSData *png = [NSData dataWithContentsOfFile:[iconsetPath stringByAppendingPathComponent:entry[1]]];
            if (!png) return 2;
            [body appendData:[entry[0] dataUsingEncoding:NSASCIIStringEncoding]];
            SDAppendUInt32(body, (uint32_t)(png.length + 8));
            [body appendData:png];
        }

        NSMutableData *icns = [NSMutableData data];
        [icns appendData:[@"icns" dataUsingEncoding:NSASCIIStringEncoding]];
        SDAppendUInt32(icns, (uint32_t)(body.length + 8));
        [icns appendData:body];
        return [icns writeToFile:outputPath atomically:YES] ? 0 : 3;
    }
}
