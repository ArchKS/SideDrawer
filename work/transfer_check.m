// ai coding: 用“同位置输入/输出”对比各材质与 Dock 面板的透光程度（自查用） 2026/09/17: 17:20
#import <Cocoa/Cocoa.h>

static NSColor *SRGB(NSColor *c) { return [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: c; }
static NSString *Hex(NSColor *c) { NSColor *r = SRGB(c);
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(r.redComponent*255), (int)lround(r.greenComponent*255), (int)lround(r.blueComponent*255)]; }
static NSBitmapImageRep *Rep(NSString *p) { return [[NSBitmapImageRep alloc] initWithData:[NSData dataWithContentsOfFile:p]]; }
static NSColor *Px(NSBitmapImageRep *rep, CGFloat x, CGFloat yTop) {
    NSInteger px = (NSInteger)lround(x * 2), py = (NSInteger)lround(yTop * 2);
    if (px < 0 || py < 0 || px >= rep.pixelsWide || py >= rep.pixelsHigh) return nil;
    return [rep colorAtX:px y:py]; }

int main(void) { @autoreleasepool {
    NSBitmapImageRep *hidden = Rep(@"work/corner-check/dock-hidden.png");
    NSBitmapImageRep *visible = Rep(@"work/corner-check/dock-visible.png");
    NSBitmapImageRep *swatches = Rep(@"work/corner-check/swatches.png");
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"/tmp/material_probe.json"] options:0 error:nil];

    printf("Dock 面板透光（y=1074，输入=同位置壁纸）:\n");
    double dockDelta[3] = {0,0,0}; int dockN = 0;
    for (CGFloat x = 420; x <= 1500; x += 60) {
        NSColor *in = SRGB(Px(hidden, x, 1074)), *out = SRGB(Px(visible, x, 1074));
        if (!in || !out) continue;
        dockDelta[0] += out.redComponent - in.redComponent;
        dockDelta[1] += out.greenComponent - in.greenComponent;
        dockDelta[2] += out.blueComponent - in.blueComponent;
        dockN++;
        if (((NSInteger)x - 420) % 180 == 0)
            printf("  x=%-4.0f in=%s out=%s\n", x, Hex(in).UTF8String, Hex(out).UTF8String);
    }
    if (dockN) printf("  Dock 平均增亮: R%+.3f G%+.3f B%+.3f  (n=%d)\n\n",
                      dockDelta[0]/dockN, dockDelta[1]/dockN, dockDelta[2]/dockN, dockN);

    printf("%-22s %-9s %-9s %-22s\n", "material", "input", "swatch", "delta(R,G,B)");
    for (NSDictionary *item in json) {
        NSArray *rect = item[@"rect"];
        CGFloat x = [rect[0] doubleValue], y = [rect[1] doubleValue], w = [rect[2] doubleValue], h = [rect[3] doubleValue];
        CGFloat topLeftY = 1080 - (y + h);
        NSColor *in = SRGB(Px(hidden, x + w/2, topLeftY + h/2));
        NSColor *out = SRGB(Px(swatches, x + w/2, topLeftY + h/2));
        if (!in || !out) continue;
        printf("%-22s %-9s %-9s (%+.3f,%+.3f,%+.3f)\n", [item[@"name"] UTF8String], Hex(in).UTF8String, Hex(out).UTF8String,
               out.redComponent - in.redComponent, out.greenComponent - in.greenComponent, out.blueComponent - in.blueComponent);
    }
} return 0; }
