// ai coding: 在 Dock 原位置并排展示各毛玻璃材质，便于与 Dock 底色逐一比对（自查用，不参与打包） 2026/09/17: 17:12
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;

        struct { const char *name; NSVisualEffectMaterial material; } items[] = {
            {"hudWindow", NSVisualEffectMaterialHUDWindow},
            {"menu", NSVisualEffectMaterialMenu},
            {"popover", NSVisualEffectMaterialPopover},
            {"sidebar", NSVisualEffectMaterialSidebar},
            {"headerView", NSVisualEffectMaterialHeaderView},
            {"toolTip", NSVisualEffectMaterialToolTip},
            {"contentBackground", NSVisualEffectMaterialContentBackground},
            {"underWindowBackground", NSVisualEffectMaterialUnderWindowBackground},
            {"fullScreenUI", NSVisualEffectMaterialFullScreenUI},
            {"selection", NSVisualEffectMaterialSelection},
            {"titlebar", NSVisualEffectMaterialTitlebar},
            {"windowBackground", NSVisualEffectMaterialWindowBackground},
            {"underPageBackground", NSVisualEffectMaterialUnderPageBackground},
            {"sheet", NSVisualEffectMaterialSheet},
        };
        NSInteger count = (NSInteger)(sizeof(items) / sizeof(items[0]));

        // 单排铺在 Dock 面板下沿留白带上（y 1064~1074），背后就是 Dock 面板所模糊的同一段壁纸。
        NSInteger perRow = 14;
        CGFloat gap = 6, swatchWidth = 74, swatchHeight = 10, topY = 1064;
        NSMutableArray *report = [NSMutableArray array];
        for (NSInteger i = 0; i < count; i++) {
            NSRect rect = NSMakeRect(384 + i * (swatchWidth + gap), 1080 - topY - swatchHeight, swatchWidth, swatchHeight);
            NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
                                                           styleMask:NSWindowStyleMaskBorderless
                                                             backing:NSBackingStoreBuffered
                                                               defer:NO];
            window.level = 25;
            window.opaque = NO;
            window.backgroundColor = NSColor.clearColor;
            window.hasShadow = NO;
            NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, swatchWidth, swatchHeight)];
            effect.material = items[i].material;
            effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
            effect.state = NSVisualEffectStateActive;
            effect.wantsLayer = YES;
            effect.layer.masksToBounds = YES;
            window.contentView = effect;
            [window orderFrontRegardless];
            [report addObject:@{@"name": @(items[i].name),
                                @"rect": @[@(NSMinX(rect)), @(NSMinY(rect)), @(rect.size.width), @(rect.size.height)]}];
        }
        (void)perRow;

        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        [json writeToFile:@"/tmp/material_probe.json" atomically:YES];
        printf("swatches ready\n");
        fflush(stdout);
        [app run];
    }
    return 0;
}