// ai coding: 由灰/白两种底色拟合材质透光模型，预测 Dock 底色并排序（自查用） 2026/09/17: 17:28
#import <Cocoa/Cocoa.h>

static NSColor *SRGB(NSColor *c) { return [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: c; }
static NSString *Hex(NSColor *c) { NSColor *r = SRGB(c);
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(r.redComponent*255), (int)lround(r.greenComponent*255), (int)lround(r.blueComponent*255)]; }
static NSBitmapImageRep *Rep(NSString *p) { return [[NSBitmapImageRep alloc] initWithData:[NSData dataWithContentsOfFile:p]]; }
static NSColor *Px(NSBitmapImageRep *rep, CGFloat x, CGFloat yTop) {
    NSInteger px = (NSInteger)lround(x*2), py = (NSInteger)lround(yTop*2);
    if (px < 0 || py < 0 || px >= rep.pixelsWide || py >= rep.pixelsHigh) return nil;
    return [rep colorAtX:px y:py]; }
static double Ch(NSColor *c, int i) { NSColor *r = SRGB(c); return i == 0 ? r.redComponent : (i == 1 ? r.greenComponent : r.blueComponent); }

int main(void) { @autoreleasepool {
    NSBitmapImageRep *fit = Rep(@"work/corner-check/fit.png");
    NSBitmapImageRep *hidden = Rep(@"work/corner-check/dock-hidden.png");
    NSBitmapImageRep *visible = Rep(@"work/corner-check/dock-visible.png");
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"/tmp/material_probe.json"] options:0 error:nil];

    NSMutableDictionary<NSString *, NSMutableDictionary *> *fits = [NSMutableDictionary dictionary];
    for (NSDictionary *item in json) {
        NSString *name = item[@"name"];
        NSArray *rect = item[@"rect"];
        CGFloat x = [rect[0] doubleValue], y = [rect[1] doubleValue], w = [rect[2] doubleValue], h = [rect[3] doubleValue];
        CGFloat topLeftY = 1080 - (y + h);
        NSColor *out = Px(fit, x + w/2, topLeftY + h/2);
        if (!out) continue;
        NSMutableDictionary *entry = fits[name] ?: [NSMutableDictionary dictionary];
        entry[item[@"backdrop"]] = out;
        fits[name] = entry;
    }

    // Dock 输入：面板下方留白处同位置壁纸的邻域平均（该带只有壁纸，且避开窗口区域）。
    printf("Dock 观测（y=1074）:\n");
    NSMutableArray<NSArray *> *dockSamples = [NSMutableArray array];
    for (CGFloat x = 440; x <= 1480; x += 80) {
        NSColor *out = Px(visible, x, 1074);
        if (!out) continue;
        double sum[3] = {0,0,0}; int n = 0;
        for (CGFloat sx = x - 40; sx <= x + 40; sx += 4) {
            for (CGFloat sy = 1034; sy <= 1077; sy += 4) {
                NSColor *c = Px(hidden, sx, sy);
                if (!c) continue;
                for (int k = 0; k < 3; k++) sum[k] += Ch(c, k);
                n++;
            }
        }
        NSColor *in = [NSColor colorWithSRGBRed:sum[0]/n green:sum[1]/n blue:sum[2]/n alpha:1];
        [dockSamples addObject:@[in, out]];
        if (((NSInteger)x - 440) % 240 == 0) printf("  x=%-4.0f in=%s out=%s\n", x, Hex(in).UTF8String, Hex(out).UTF8String);
    }

    printf("\n%-22s %-7s %-9s %-9s %s\n", "material", "alpha", "panel", "predicted", "rmsError");
    NSMutableArray<NSArray *> *ranking = [NSMutableArray array];
    for (NSString *name in fits) {
        NSDictionary *entry = fits[name];
        NSColor *grayOut = entry[@0.5], *whiteOut = entry[@1.0];
        if (!grayOut || !whiteOut) continue;
        double alpha[3], panel[3];
        for (int c = 0; c < 3; c++) {
            double o1 = Ch(grayOut, c), o2 = Ch(whiteOut, c);
            alpha[c] = 1.0 - (o2 - o1) / 0.5;
            panel[c] = alpha[c] > 1e-3 ? (o2 - 1.0 * (1 - alpha[c])) / alpha[c] : 1.0;
        }
        double total = 0; int n = 0; NSColor *predicted = nil;
        for (NSArray *sample in dockSamples) {
            double p[3];
            for (int c = 0; c < 3; c++) {
                p[c] = Ch(sample[0], c) * (1 - alpha[c]) + panel[c] * alpha[c];
                total += pow(p[c] - Ch(sample[1], c), 2);
                n++;
            }
            predicted = [NSColor colorWithSRGBRed:p[0] green:p[1] blue:p[2] alpha:1];
        }
        double rms = n ? sqrt(total / n) : 0;
        printf("%-22s %-7.3f %-9.3f %-9s %.4f\n", name.UTF8String, (alpha[0]+alpha[1]+alpha[2])/3,
               (panel[0]+panel[1]+panel[2])/3, Hex(predicted).UTF8String, rms);
        [ranking addObject:@[@(rms), name]];
    }
    [ranking sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
    printf("\n排名（最接近 Dock 底色在前）: ");
    for (NSArray *entry in ranking) printf("%s(%.3f) ", [entry[1] UTF8String], [entry[0] doubleValue]);
    printf("\n");
} return 0; }
