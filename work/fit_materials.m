// ai coding: 用两组输入拟合各材质的透光模型，并预测 Dock 底色以选出最接近的材质（自查用） 2026/09/17: 17:24
#import <Cocoa/Cocoa.h>

static NSColor *SRGB(NSColor *c) { return [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: c; }
static NSString *Hex(NSColor *c) { NSColor *r = SRGB(c);
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(r.redComponent*255), (int)lround(r.greenComponent*255), (int)lround(r.blueComponent*255)]; }
static NSBitmapImageRep *Rep(NSString *p) { return [[NSBitmapImageRep alloc] initWithData:[NSData dataWithContentsOfFile:p]]; }
static NSColor *Px(NSBitmapImageRep *rep, CGFloat x, CGFloat yTop) {
    NSInteger px = (NSInteger)lround(x*2), py = (NSInteger)lround(yTop*2);
    if (px < 0 || py < 0 || px >= rep.pixelsWide || py >= rep.pixelsHigh) return nil;
    return [rep colorAtX:px y:py]; }
static CGFloat Channel(NSColor *c, int i) { NSColor *r = SRGB(c); return i == 0 ? r.redComponent : (i == 1 ? r.greenComponent : r.blueComponent); }

// 第一组测量：纯 #808080 底上的输出（早前一次探针运行结果）。
static NSDictionary<NSString *, NSString *> *GrayRun(void) {
    return @{@"hudWindow": @"#BBBEC0", @"menu": @"#D5D6D9", @"popover": @"#C7CACC", @"sidebar": @"#E0E3E4",
             @"headerView": @"#E9E9E9", @"toolTip": @"#E0E2E4", @"contentBackground": @"#FFFFFF",
             @"underWindowBackground": @"#E0E3E5", @"fullScreenUI": @"#BBBEC0", @"selection": @"#CCCFD1",
             @"titlebar": @"#E1E4E5", @"windowBackground": @"#FFFFFF", @"underPageBackground": @"#E7E9EC",
             @"sheet": @"#FFFFFF"};
}
static NSColor *FromHex(NSString *hex) {
    unsigned int value = 0; [[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&value];
    return [NSColor colorWithSRGBRed:((value >> 16) & 0xFF)/255.0 green:((value >> 8) & 0xFF)/255.0 blue:(value & 0xFF)/255.0 alpha:1];
}

int main(void) { @autoreleasepool {
    NSBitmapImageRep *hidden = Rep(@"work/corner-check/dock-hidden.png");
    NSBitmapImageRep *visible = Rep(@"work/corner-check/dock-visible.png");
    NSBitmapImageRep *swatches = Rep(@"work/corner-check/swatches.png");
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"/tmp/material_probe.json"] options:0 error:nil];
    NSDictionary<NSString *, NSString *> *grayRun = GrayRun();
    CGFloat grayIn = 128.0 / 255.0;

    // Dock 观测样本：输入取同位置壁纸，输出取面板底色。
    NSMutableArray<NSArray *> *dockSamples = [NSMutableArray array];
    for (CGFloat x = 420; x <= 1500; x += 60) {
        NSColor *in = Px(hidden, x, 1074), *out = Px(visible, x, 1074);
        if (in && out) [dockSamples addObject:@[in, out]];
    }
    printf("Dock samples: %lu\n", (unsigned long)dockSamples.count);

    // 每个材质：用灰底组和壁纸组两点拟合 out = in*(1-a) + C*a，再预测 Dock 位置的颜色。
    double errors[64]; NSString *names[64]; int n = 0;
    printf("%-22s %-8s %-8s %-10s %-10s %s\n", "material", "alpha", "panelC", "predicted", "dockActual", "err");
    for (NSDictionary *item in json) {
        NSString *name = item[@"name"];
        NSColor *grayOut = FromHex(grayRun[name] ?: @"#000000");
        NSArray *rect = item[@"rect"];
        CGFloat x = [rect[0] doubleValue], y = [rect[1] doubleValue], w = [rect[2] doubleValue], h = [rect[3] doubleValue];
        CGFloat topLeftY = 1080 - (y + h);
        NSColor *in2 = Px(hidden, x + w/2, topLeftY + h/2), *out2 = Px(swatches, x + w/2, topLeftY + h/2);
        if (!in2 || !out2) continue;

        double alpha[3], panel[3];
        for (int c = 0; c < 3; c++) {
            double o1 = Channel(grayOut, c), o2 = Channel(out2, c), i2 = Channel(in2, c);
            double denom = grayIn - i2;
            double oneMinusA = fabs(denom) > 1e-4 ? (o1 - o2) / denom : 1.0;
            alpha[c] = 1.0 - oneMinusA;
            panel[c] = fabs(alpha[c]) > 1e-4 ? (o1 - grayIn * oneMinusA) / alpha[c] : 1.0;
        }
        double totalError = 0; int samples = 0;
        NSColor *lastPredicted = nil, *lastActual = nil;
        for (NSArray *sample in dockSamples) {
            NSColor *in = sample[0], *actual = sample[1];
            double predicted[3];
            for (int c = 0; c < 3; c++) {
                predicted[c] = Channel(in, c) * (1 - alpha[c]) + panel[c] * alpha[c];
                totalError += pow(predicted[c] - Channel(actual, c), 2);
            }
            samples += 3;
            lastPredicted = [NSColor colorWithSRGBRed:predicted[0] green:predicted[1] blue:predicted[2] alpha:1];
            lastActual = actual;
        }
        double rms = samples ? sqrt(totalError / samples) : 0;
        printf("%-22s %-8.3f %-8.3f %-10s %-10s %.4f\n", name.UTF8String,
               (alpha[0]+alpha[1]+alpha[2])/3, (panel[0]+panel[1]+panel[2])/3,
               Hex(lastPredicted).UTF8String, Hex(lastActual).UTF8String, rms);
        if (n < 64) { errors[n] = rms; names[n] = name; n++; }
    }

    int best = 0;
    for (int i = 1; i < n; i++) if (errors[i] < errors[best]) best = i;
    printf("\n最接近 Dock 底色的材质: %s (rms=%.4f)\n", names[best].UTF8String, errors[best]);
} return 0; }
