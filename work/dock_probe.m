// ai coding: 采样 Dock 面板与相邻壁纸颜色，用于挑选匹配的背景材质（自查用，不参与打包） 2026/09/17: 16:55
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

static NSString *HexString(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: color;
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)lround(rgb.redComponent * 255), (int)lround(rgb.greenComponent * 255), (int)lround(rgb.blueComponent * 255)];
}

static NSColor *Sample(NSBitmapImageRep *rep, CGFloat screenX, CGFloat screenYFromTop) {
    // 截图为 2x 像素：把屏幕点坐标换算成像素坐标。
    NSInteger px = (NSInteger)lround(screenX * 2);
    NSInteger py = (NSInteger)lround(screenYFromTop * 2);
    if (px < 0 || py < 0 || px >= rep.pixelsWide || py >= rep.pixelsHigh) return nil;
    return [rep colorAtX:px y:py];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { printf("usage: dock_probe screenshot.png\n"); return 1; }
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        NSBitmapImageRep *rep = data ? [[NSBitmapImageRep alloc] initWithData:data] : nil;
        if (!rep) { printf("failed to load screenshot\n"); return 1; }
        printf("screenshot: %ld x %ld px (%.0f x %.0f pt)\n", (long)rep.pixelsWide, (long)rep.pixelsHigh,
               rep.pixelsWide / 2.0, rep.pixelsHigh / 2.0);

        NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(
            kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
        NSRect dockRect = NSZeroRect;
        for (NSDictionary *window in windows) {
            NSString *owner = window[(id)kCGWindowOwnerName];
            NSNumber *layer = window[(id)kCGWindowLayer];
            if (![owner isEqualToString:@"Dock"]) continue;
            if (layer.integerValue != CGWindowLevelForKey(kCGDockWindowLevelKey)) continue;
            NSDictionary *bounds = window[(id)kCGWindowBounds];
            dockRect = CGRectMake([bounds[@"X"] doubleValue], [bounds[@"Y"] doubleValue],
                                  [bounds[@"Width"] doubleValue], [bounds[@"Height"] doubleValue]);
            break;
        }
        if (NSIsEmptyRect(dockRect)) { printf("Dock window not found\n"); return 1; }
        printf("Dock rect: x=%.0f y=%.0f w=%.0f h=%.0f\n", dockRect.origin.x, dockRect.origin.y,
               dockRect.size.width, dockRect.size.height);

        // 面板边缘通常没有图标：取左右两端和底部条带采样。
        CGFloat yBottomStrip = NSMaxY(dockRect) - 4;
        CGFloat yMid = NSMidY(dockRect);
        NSArray<NSNumber *> *xs = @[@(NSMinX(dockRect) + 8), @(NSMinX(dockRect) + 120),
                                    @(NSMaxX(dockRect) - 120), @(NSMaxX(dockRect) - 8)];
        printf("\nDock panel samples (只取面板自身，避开图标):\n");
        for (NSNumber *x in xs) {
            NSColor *edge = Sample(rep, x.doubleValue, yBottomStrip);
            NSColor *mid = Sample(rep, x.doubleValue, yMid);
            NSColor *wallpaper = Sample(rep, x.doubleValue, NSMinY(dockRect) - 6);
            printf("  x=%.0f  bottomStrip=%s  mid=%s  wallpaperAbove=%s\n",
                   x.doubleValue, HexString(edge).UTF8String, HexString(mid).UTF8String,
                   wallpaper ? HexString(wallpaper).UTF8String : "n/a");
        }

        // 壁纸在 Dock 上方的一条带上取平均，作为对照底色。
        double sumR = 0, sumG = 0, sumB = 0;
        int count = 0;
        for (CGFloat x = NSMinX(dockRect); x < NSMaxX(dockRect); x += 4) {
            NSColor *color = Sample(rep, x, NSMinY(dockRect) - 6);
            if (!color) continue;
            NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            sumR += rgb.redComponent; sumG += rgb.greenComponent; sumB += rgb.blueComponent; count++;
        }
        if (count > 0) {
            NSColor *average = [NSColor colorWithSRGBRed:sumR / count green:sumG / count blue:sumB / count alpha:1];
            printf("\nwallpaper band above Dock average: %s\n", HexString(average).UTF8String);
        }
    }
    return 0;
}