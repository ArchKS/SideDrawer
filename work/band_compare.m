// ai coding: 同一段壁纸上逐点比较各材质与 Dock 面板底色（自查用） 2026/09/17: 17:34
#import <Cocoa/Cocoa.h>
static NSColor *SRGB(NSColor *c) { return [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace] ?: c; }
static NSString *Hex(NSColor *c) { NSColor *r = SRGB(c);
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)lround(r.redComponent*255), (int)lround(r.greenComponent*255), (int)lround(r.blueComponent*255)]; }
static NSBitmapImageRep *Rep(NSString *p) { return [[NSBitmapImageRep alloc] initWithData:[NSData dataWithContentsOfFile:p]]; }
static NSColor *Px(NSBitmapImageRep *rep, CGFloat x, CGFloat yTop) {
    NSInteger px = (NSInteger)lround(x*2), py = (NSInteger)lround(yTop*2);
    if (px < 0 || py < 0 || px >= rep.pixelsWide || py >= rep.pixelsHigh) return nil;
    return [rep colorAtX:px y:py]; }
static double Dist(NSColor *a, NSColor *b) { NSColor *x=SRGB(a),*y=SRGB(b);
    return sqrt(pow(x.redComponent-y.redComponent,2)+pow(x.greenComponent-y.greenComponent,2)+pow(x.blueComponent-y.blueComponent,2)); }
int main(void) { @autoreleasepool {
    NSBitmapImageRep *band = Rep(@"work/corner-check/panel_band.png");
    NSBitmapImageRep *visible = Rep(@"work/corner-check/dock-visible.png");
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@"/tmp/material_probe.json"] options:0 error:nil];
    printf("%-22s %-9s %-9s %s\n", "material", "swatch", "dockPanel", "distance");
    NSMutableArray *rank = [NSMutableArray array];
    for (NSDictionary *item in json) {
        NSArray *rect = item[@"rect"];
        CGFloat x = [rect[0] doubleValue], y = [rect[1] doubleValue], w = [rect[2] doubleValue], h = [rect[3] doubleValue];
        CGFloat centerYFromTop = 1080 - (y + h) + h/2;
        NSColor *swatch = Px(band, x + w/2, centerYFromTop);
        NSColor *dock = Px(visible, x + w/2, centerYFromTop);
        if (!swatch || !dock) continue;
        double d = Dist(swatch, dock);
        printf("%-22s %-9s %-9s %.4f\n", [item[@"name"] UTF8String], Hex(swatch).UTF8String, Hex(dock).UTF8String, d);
        [rank addObject:@[@(d), item[@"name"]]];
    }
    [rank sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [a[0] compare:b[0]]; }];
    printf("\n最接近 Dock 面板底色: ");
    for (NSUInteger i = 0; i < MIN((NSUInteger)5, rank.count); i++) printf("%s(%.4f) ", [rank[i][1] UTF8String], [rank[i][0] doubleValue]);
    printf("\n");
} return 0; }
