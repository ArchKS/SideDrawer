// ai coding: 比较各个毛玻璃材质色块与 Dock 面板底色的差异（自查用） 2026/09/17: 17:15
#import <Cocoa/Cocoa.h>

static NSColor *SRGB(NSColor *c) { return [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: c; }
static NSString *Hex(NSColor *c) { NSColor *r = SRGB(c);
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(r.redComponent*255), (int)lround(r.greenComponent*255), (int)lround(r.blueComponent*255)]; }
static NSBitmapImageRep *Rep(NSString *p) { return [[NSBitmapImageRep alloc] initWithData:[NSData dataWithContentsOfFile:p]]; }
// 屏幕点坐标（左上原点）取像素。
static NSColor *Px(NSBitmapImageRep *rep, CGFloat x, CGFloat y) {
    return [rep colorAtX:(NSInteger)lround(x*2) y:(NSInteger)lround(y*2)]; }
static double Dist(NSColor *a, NSColor *b) { NSColor *x = SRGB(a), *y = SRGB(b);
    return sqrt(pow(x.redComponent-y.redComponent,2)+pow(x.greenComponent-y.greenComponent,2)+pow(x.blueComponent-y.blueComponent,2)); }

int main(void) { @autoreleasepool {
    NSBitmapImageRep *swatches = Rep(@"work/corner-check/swatches.png");
    NSBitmapImageRep *visible = Rep(@"work/corner-check/dock-visible.png");
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"/tmp/material_probe.json"] options:0 error:nil];

    // Dock 面板底部留白条（图标之下、面板之内），背后的输入只有壁纸，便于对比。
    NSString *dockPath = @"work/corner-check/dock-visible.png";
    NSMutableArray *dockSamples = [NSMutableArray array];
    for (CGFloat x = 700; x <= 1200; x += 100) {
        NSColor *c = Px(visible, x, 1073);
        [dockSamples addObject:c];
    }
    printf("Dock 面板底部留白色（y=1073）: ");
    for (NSColor *c in dockSamples) printf("%s ", Hex(c).UTF8String);
    printf("\n\n");

    printf("%-22s %-9s %-9s %s\n", "material", "swatchTop", "swatchBottom", "distanceToDock");
    for (NSDictionary *item in json) {
        NSArray *rect = item[@"rect"];
        CGFloat x = [rect[0] doubleValue], y = [rect[1] doubleValue];
        CGFloat w = [rect[2] doubleValue], h = [rect[3] doubleValue];
        // rect 为 AppKit 坐标（左下原点），换算成左上原点的采样点。
        CGFloat topLeftY = 1080 - (y + h);
        NSColor *top = Px(swatches, x + w/2, topLeftY + 12);
        NSColor *bottom = Px(swatches, x + w/2, 1080 - y - 8);
        double best = 0;
        for (NSColor *d in dockSamples) best = MAX(best, 0);
        double distance = 0;
        for (NSColor *d in dockSamples) distance += Dist(bottom, d);
        distance /= dockSamples.count;
        printf("%-22s %-9s %-9s %.4f\n", [item[@"name"] UTF8String], Hex(top).UTF8String, Hex(bottom).UTF8String, distance);
    }
    printf("\n参考: 与 Dock 同排的壁纸（y=1073 处被 Dock 遮住，改用 y=1000 壁纸带）: ");
    for (CGFloat x = 700; x <= 1200; x += 150) printf("%s ", Hex(Px(visible, x, 1000)).UTF8String);
    printf("\n");
} return 0; }
