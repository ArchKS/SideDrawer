// ai coding: 绘制磨砂玻璃侧边抽屉与文件堆叠主题的 macOS 应用图标 2026/09/16: 19:11
#import <Cocoa/Cocoa.h>

static NSColor *SDColor(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:alpha];
}

static void SDFillRoundedRect(NSRect rect, CGFloat radius, NSColor *color) {
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
}

static void SDDrawFileCard(NSRect rect, NSColor *topColor, NSColor *bottomColor, CGFloat rotation) {
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:NSMidX(rect) yBy:NSMidY(rect)];
    [transform rotateByDegrees:rotation];
    [transform translateXBy:-NSMidX(rect) yBy:-NSMidY(rect)];
    [transform concat];

    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.22];
    shadow.shadowBlurRadius = 22;
    shadow.shadowOffset = NSMakeSize(0, -10);
    [shadow set];

    NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:46 yRadius:46];
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:topColor endingColor:bottomColor];
    [gradient drawInBezierPath:card angle:-90];

    [NSGraphicsContext restoreGraphicsState];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) return 1;
        CGFloat size = 1024;
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:nil
                          pixelsWide:(NSInteger)size
                          pixelsHigh:(NSInteger)size
                       bitsPerSample:8
                     samplesPerPixel:4
                            hasAlpha:YES
                            isPlanar:NO
                      colorSpaceName:NSCalibratedRGBColorSpace
                         bytesPerRow:0
                        bitsPerPixel:0];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:context];
        CGContextClearRect(context.CGContext, CGRectMake(0, 0, size, size));

        NSRect shellRect = NSMakeRect(64, 64, 896, 896);
        NSBezierPath *shell = [NSBezierPath bezierPathWithRoundedRect:shellRect xRadius:214 yRadius:214];
        NSShadow *shellShadow = [[NSShadow alloc] init];
        shellShadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.34];
        shellShadow.shadowBlurRadius = 48;
        shellShadow.shadowOffset = NSMakeSize(0, -24);
        [shellShadow set];
        NSGradient *shellGradient = [[NSGradient alloc]
            initWithColorsAndLocations:
                SDColor(126, 151, 168, 1), 0.0,
                SDColor(55, 72, 88, 1), 0.52,
                SDColor(25, 35, 48, 1), 1.0,
                nil];
        [shellGradient drawInBezierPath:shell angle:-58];

        [NSGraphicsContext saveGraphicsState];
        [shell addClip];
        NSGradient *glow = [[NSGradient alloc]
            initWithStartingColor:[NSColor.whiteColor colorWithAlphaComponent:0.32]
                      endingColor:[NSColor.whiteColor colorWithAlphaComponent:0.0]];
        [glow drawInRect:NSMakeRect(84, 520, 820, 390) angle:-90];
        [NSGraphicsContext restoreGraphicsState];

        [NSColor.whiteColor setStroke];
        shell.lineWidth = 6;
        [[NSColor.whiteColor colorWithAlphaComponent:0.28] setStroke];
        [shell stroke];

        NSRect glassRect = NSMakeRect(198, 186, 628, 650);
        NSBezierPath *glass = [NSBezierPath bezierPathWithRoundedRect:glassRect xRadius:118 yRadius:118];
        NSShadow *glassShadow = [[NSShadow alloc] init];
        glassShadow.shadowColor = [NSColor.blackColor colorWithAlphaComponent:0.28];
        glassShadow.shadowBlurRadius = 34;
        glassShadow.shadowOffset = NSMakeSize(0, -14);
        [glassShadow set];
        [[NSColor.whiteColor colorWithAlphaComponent:0.18] setFill];
        [glass fill];
        [[NSColor.whiteColor colorWithAlphaComponent:0.48] setStroke];
        glass.lineWidth = 5;
        [glass stroke];

        SDDrawFileCard(NSMakeRect(286, 400, 330, 290),
                       SDColor(156, 215, 236, 0.96), SDColor(56, 132, 174, 0.98), -9);
        SDDrawFileCard(NSMakeRect(344, 362, 330, 290),
                       SDColor(206, 235, 246, 0.98), SDColor(94, 163, 197, 1), 2);
        SDDrawFileCard(NSMakeRect(400, 322, 330, 290),
                       SDColor(245, 250, 252, 1), SDColor(176, 213, 230, 1), 10);

        SDFillRoundedRect(NSMakeRect(454, 480, 188, 24), 12, [NSColor.whiteColor colorWithAlphaComponent:0.74]);
        SDFillRoundedRect(NSMakeRect(468, 432, 154, 18), 9, [NSColor.whiteColor colorWithAlphaComponent:0.46]);

        NSRect railRect = NSMakeRect(724, 254, 74, 516);
        NSBezierPath *rail = [NSBezierPath bezierPathWithRoundedRect:railRect xRadius:37 yRadius:37];
        NSGradient *railGradient = [[NSGradient alloc]
            initWithStartingColor:SDColor(116, 217, 255, 1)
                      endingColor:SDColor(33, 123, 202, 1)];
        [railGradient drawInBezierPath:rail angle:-90];
        [[NSColor.whiteColor colorWithAlphaComponent:0.52] setStroke];
        rail.lineWidth = 4;
        [rail stroke];
        SDFillRoundedRect(NSMakeRect(742, 458, 38, 108), 19, [NSColor.whiteColor colorWithAlphaComponent:0.82]);

        NSRect trayRect = NSMakeRect(278, 240, 454, 98);
        NSBezierPath *tray = [NSBezierPath bezierPathWithRoundedRect:trayRect xRadius:49 yRadius:49];
        NSGradient *trayGradient = [[NSGradient alloc]
            initWithStartingColor:[NSColor.whiteColor colorWithAlphaComponent:0.64]
                      endingColor:[NSColor.whiteColor colorWithAlphaComponent:0.22]];
        [trayGradient drawInBezierPath:tray angle:-90];
        [[NSColor.whiteColor colorWithAlphaComponent:0.48] setStroke];
        tray.lineWidth = 4;
        [tray stroke];

        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 2;
    }
}
