// ai coding: 用截屏测量抽屉圆角曲线，并与系统连续圆角、普通圆弧对比（自查用，不参与打包） 2026/09/17: 16:44
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

static NSBitmapImageRep *LoadRep(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    return data ? [[NSBitmapImageRep alloc] initWithData:data] : nil;
}

static CGFloat ChannelDiff(NSColor *a, NSColor *b, int channel) {
    CGFloat va = channel == 0 ? a.redComponent : (channel == 1 ? a.greenComponent : a.blueComponent);
    CGFloat vb = channel == 0 ? b.redComponent : (channel == 1 ? b.greenComponent : b.blueComponent);
    return fabs(va - vb);
}

/// 逐行用相对阈值定位左边界：先取该行最大差异，再找首个超过 35% 的像素，可避开阴影干扰。
static void ScreenProfile(NSBitmapImageRep *before, NSBitmapImageRep *after, NSInteger topRow,
                          NSInteger rows, NSInteger maxX, CGFloat insideX, NSInteger *out) {
    for (NSInteger i = 0; i < rows; i++) {
        NSInteger y = topRow + i;
        CGFloat values[200];
        CGFloat maximum = 0;
        for (NSInteger x = 0; x < maxX; x++) {
            NSColor *ca = [after colorAtX:x y:y];
            NSColor *cb = [before colorAtX:x y:y];
            CGFloat d = 0;
            for (int c = 0; c < 3; c++) d = MAX(d, ChannelDiff(ca, cb, c));
            values[x] = d;
            maximum = MAX(maximum, d);
        }
        (void)insideX;
        NSInteger found = -1;
        for (NSInteger x = 0; x < maxX; x++) {
            if (values[x] > 0.35 * maximum) { found = x; break; }
        }
        out[i] = found;
    }
}

/// 参考形状：按 alpha 的相对阈值逐行定位左边界，并返回形状自身的左边缘像素列。
static NSInteger ReferenceProfile(NSBitmapImageRep *rep, NSInteger startRow, NSInteger rows, NSInteger maxX, NSInteger *out) {
    NSInteger leftEdge = maxX;
    for (NSInteger i = 0; i < rows; i++) {
        NSInteger y = startRow + i;
        NSInteger found = -1;
        for (NSInteger x = 0; x < maxX; x++) {
            if ([rep colorAtX:x y:y].alphaComponent > 0.5) { found = x; break; }
        }
        out[i] = found;
        if (found >= 0 && found < leftEdge) leftEdge = found;
    }
    return leftEdge;
}

/// 参考形状的顶边行：取 alpha 大于 0.5 的最高行。
static NSInteger ReferenceTopRow(NSBitmapImageRep *rep, NSInteger maxX) {
    for (NSInteger y = 0; y < rep.pixelsHigh; y++) {
        for (NSInteger x = 0; x < maxX; x++) {
            if ([rep colorAtX:x y:y].alphaComponent > 0.5) return y;
        }
    }
    return -1;
}

static NSBitmapImageRep *RenderReference(BOOL continuous, CGFloat scale, NSRect pixelRect, CGFloat radiusPixels) {
    NSInteger width = (NSInteger)pixelRect.size.width;
    NSInteger height = (NSInteger)pixelRect.size.height;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height
                   bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                   colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = context;
    CGContextRef cg = context.CGContext;
    CGContextScaleCTM(cg, scale, scale);
    CALayer *layer = [CALayer layer];
    layer.frame = NSMakeRect(pixelRect.origin.x / scale, pixelRect.origin.y / scale,
                             pixelRect.size.width / scale, pixelRect.size.height / scale);
    layer.backgroundColor = NSColor.whiteColor.CGColor;
    layer.cornerRadius = radiusPixels / scale;
    layer.masksToBounds = YES;
    if (continuous) layer.cornerCurve = kCACornerCurveContinuous;
    [layer renderInContext:cg];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 3) { printf("usage: corner_check before.png after.png\n"); return 1; }
        NSBitmapImageRep *before = LoadRep([NSString stringWithUTF8String:argv[1]]);
        NSBitmapImageRep *after = LoadRep([NSString stringWithUTF8String:argv[2]]);
        if (!before || !after) { printf("failed to load images\n"); return 1; }

        const NSInteger rows = 36;
        NSInteger measured[36];
        ScreenProfile(before, after, 20, rows, 120, 30, measured);
        for (NSInteger i = 0; i < rows; i++) if (measured[i] >= 0) measured[i] -= 12;

        CGFloat radiusPixels = 36; // 18pt @2x
        NSRect pixelRect = NSMakeRect(12, 20, 590, 110);
        NSBitmapImageRep *continuousRep = RenderReference(YES, 2, pixelRect, radiusPixels);
        NSBitmapImageRep *circularRep = RenderReference(NO, 2, pixelRect, radiusPixels);

        NSInteger continuous[36];
        NSInteger circular[36];
        NSInteger continuousTop = ReferenceTopRow(continuousRep, 120);
        NSInteger circularTop = ReferenceTopRow(circularRep, 120);
        printf("reference top rows: continuous=%ld circular=%ld\n", (long)continuousTop, (long)circularTop);
        NSInteger continuousLeft = ReferenceProfile(continuousRep, continuousTop, rows, 120, continuous);
        NSInteger circularLeft = ReferenceProfile(circularRep, circularTop, rows, 120, circular);

        // 导出参考形状，便于和实测截屏做肉眼比对。
        for (NSBitmapImageRep *rep in @[continuousRep, circularRep]) {
            NSString *name = rep == continuousRep ? @"continuous" : @"circular";
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSString *outPath = [NSString stringWithFormat:@"work/corner-check/reference-%@.png", name];
            [png writeToFile:outPath atomically:YES];
        }

        const NSInteger measuredRows = 36;
        printf("row | measured | continuous | circular   (offsets in 2x px, 0 = 直边)\n");
        double totalContinuous = 0, totalCircular = 0;
        int counted = 0;
        for (NSInteger i = 0; i < measuredRows; i++) {
            NSInteger m = measured[i];
            NSInteger c1 = continuous[i] >= 0 ? continuous[i] - continuousLeft : -1;
            NSInteger c2 = circular[i] >= 0 ? circular[i] - circularLeft : -1;
            printf("%3ld | %8ld | %10ld | %8ld\n", (long)i, (long)m, (long)c1, (long)c2);
            if (m >= 0 && c1 >= 0 && c2 >= 0) {
                totalContinuous += labs((long)(m - c1));
                totalCircular += labs((long)(m - c2));
                counted++;
            }
        }
        if (counted > 0) {
            printf("mean deviation: continuous %.2f px, circular %.2f px (n=%d)\n",
                   totalContinuous / counted, totalCircular / counted, counted);
        }
    }
    return 0;
}