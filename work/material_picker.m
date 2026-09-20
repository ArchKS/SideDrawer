// ai coding: 在 Dock 右侧并排展示 14 种毛玻璃材质色块，供人工比对选择（自查用，不参与打包） 2026/09/17: 17:40
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

        // 放在 Dock 右侧、与 Dock 同一水平带内，背后的壁纸与 Dock 面板所模糊的一致。
        NSInteger columns = 7;
        CGFloat swatchWidth = 50, swatchHeight = 26, gapX = 2, gapY = 2;
        CGFloat originX = 1552, topY = 1024;
        for (NSInteger i = 0; i < count; i++) {
            NSInteger column = i % columns, row = i / columns;
            NSRect rect = NSMakeRect(originX + column * (swatchWidth + gapX),
                                     1080 - (topY + row * (swatchHeight + gapY) + swatchHeight),
                                     swatchWidth, swatchHeight);
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
            effect.layer.cornerRadius = 7;
            effect.layer.cornerCurve = kCACornerCurveContinuous;
            effect.layer.masksToBounds = YES;
            window.contentView = effect;
            [window orderFrontRegardless];
            printf("row %ld col %ld -> %s\n", (long)row + 1, (long)column + 1, items[i].name);
        }
        fflush(stdout);
        [app run];
    }
    return 0;
}