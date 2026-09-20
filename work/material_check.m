// ai coding: 比较 Dock 面板与各材质色块的实际颜色（自查用，不参与打包） 2026/09/17: 17:02
#import <Cocoa/Cocoa.h>

static NSColor *SRGB(NSColor *color) {
    return [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
}

static NSString *Hex(NSColor *color) {
    NSColor *rgb = SRGB(color);
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)lround(rgb.redComponent * 255), (int)lround(rgb.greenComponent * 255), (int)lround(rgb.blueComponent * 255)];
}

static NSColor *PixelAt(NSBitmapImageRep *rep, CGFloat xPoints, CGFloat yFromTopPoints) {
    NSInteger px = (NSInteger)lround(xPoints * 2);
    NSInteger py = (NSInteger)lround(yFromTopPoints * 2);
    if (px < 0 || py < 0 || px >= rep.pixelsWide || py >= rep.pixelsHigh) return nil;
    return [rep colorAtX:px y:py];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { printf("usage: material_check screenshot.png\n"); return 1; }
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSBitmapImageRep *rep = data ? [[NSBitmapImageRep alloc] initWithData:data] : nil;
        if (!rep) { printf("failed to load screenshot\n"); return 1; }
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:
            [NSData dataWithContentsOfFile:@"/tmp/material_probe.json"] options:0 error:nil];
        CGFloat screenHeight = rep.pixelsHigh / 2.0;
        printf("screenshot %ldx%ld px\n\n", (long)rep.pixelsWide, (long)rep.pixelsHigh);

        printf("swatch colors over #808080 backdrop:\n");
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        NSMutableArray<NSString *> *hexes = [NSMutableArray array];
        for (NSDictionary *item in json) {
            NSArray *rect = item[@"rect"];
            CGFloat x = [rect[0] doubleValue], y = [rect[1] doubleValue];
            CGFloat w = [rect[2] doubleValue], h = [rect[3] doubleValue];
            NSColor *color = PixelAt(rep, x + w / 2, screenHeight - y - h / 2);
            printf("  %-22s %s\n", [item[@"name"] UTF8String], color ? Hex(color).UTF8String : "n/a");
            [names addObject:item[@"name"]];
            [hexes addObject:color ? Hex(color) : @"n/a"];
        }

        // Dock 面板颜色：底部条带里出现次数最多的颜色（面板为纯色区，图标占比小）。
        printf("\nmost frequent colors in bottom band (y 1030-1079pt):\n");
        NSCountedSet *counts = [NSCountedSet set];
        for (CGFloat y = 1030; y < 1080; y += 1) {
            for (CGFloat x = 0; x < 1920; x += 1) {
                NSColor *color = PixelAt(rep, x, y);
                if (color) [counts addObject:Hex(color)];
            }
        }
        NSArray *sorted = [[counts allObjects] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [@([counts countForObject:b]) compare:@([counts countForObject:a])];
        }];
        for (NSUInteger i = 0; i < MIN((NSUInteger)6, sorted.count); i++) {
            NSString *hex = sorted[i];
            printf("  %s  x%ld\n", hex.UTF8String, (long)[counts countForObject:hex]);
        }
    }
    return 0;
}