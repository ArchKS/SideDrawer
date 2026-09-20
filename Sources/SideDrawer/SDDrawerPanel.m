// ai coding: 拆分出抽屉面板与其控制器实现，保持原有行为 2026/09/17: 15:34
#import "SDDrawerPanel.h"
#import "SDDrawerContentView.h"
#import "SDDrawerStore.h"

@implementation SDDrawerPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }

- (BOOL)isEditingDrawerName {
    return [self.firstResponder isKindOfClass:NSTextView.class] &&
        [(NSTextView *)self.firstResponder isFieldEditor];
}

- (BOOL)handleDrawerShortcutEvent:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) return NO;
    NSEventModifierFlags relevantFlags = event.modifierFlags &
        (NSEventModifierFlagCommand | NSEventModifierFlagShift |
         NSEventModifierFlagControl | NSEventModifierFlagOption);
    NSString *key = event.charactersIgnoringModifiers.lowercaseString;
    if (relevantFlags == NSEventModifierFlagCommand) {
        if ([key isEqualToString:@"a"] && self.selectAllHandler) {
            self.selectAllHandler();
            return YES;
        }
        if ([key isEqualToString:@"n"] && self.createDrawerHandler) {
            self.createDrawerHandler();
            return YES;
        }
        if ([key isEqualToString:@"s"] && self.saveDrawerHandler) {
            self.saveDrawerHandler();
            return YES;
        }
        // ai coding: 抽屉激活时拦截 Command+V，将文件或内容直接粘贴为收纳盒项目 2026/09/17: 14:10
        if ([key isEqualToString:@"v"] && ![self isEditingDrawerName] && self.pasteHandler) {
            self.pasteHandler();
            return YES;
        }
    }
    BOOL isDelete = relevantFlags == 0 && (event.keyCode == 51 || event.keyCode == 117);
    if (isDelete && ![self isEditingDrawerName] && self.deleteSelectedHandler) {
        self.deleteSelectedHandler();
        return YES;
    }
    return NO;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if ([self handleDrawerShortcutEvent:event]) return YES;
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    if ([self handleDrawerShortcutEvent:event]) return;
    [super keyDown:event];
}
@end

@implementation SDDrawerPanelController {
    SDDrawerStore *_store;
    SDDrawerContentView *_contentView;
    NSString *_edge;
    BOOL _adjustingFrame;
}

// ai coding: 按方向读取长边长度和菜单设置的上下高度或左右宽度 2026/09/17: 14:10
- (instancetype)initWithStore:(SDDrawerStore *)store drawerID:(NSString *)drawerID {
    self = [super init];
    if (!self) return nil;
    _store = store;
    _drawerID = [drawerID copy];
    NSDictionary *drawer = [store drawerForID:drawerID];
    _edge = [drawer[@"edge"] ?: SDEdgeRight copy];
    NSSize size = [self sizeForEdge:_edge];
    _panel = [[SDDrawerPanel alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height)
                                              styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered defer:NO];
    _panel.delegate = self;
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.level = NSStatusWindowLevel;
    _panel.hidesOnDeactivate = NO;
    BOOL locked = [drawer[@"locked"] boolValue];
    _panel.movable = !locked;
    _panel.movableByWindowBackground = !locked;
    // ai coding: 允许点击无标题抽屉后稳定成为按键目标窗口 2026/09/17: 09:51
    _panel.becomesKeyOnlyIfNeeded = NO;
    _panel.animationBehavior = NSWindowAnimationBehaviorUtilityWindow;
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                NSWindowCollectionBehaviorFullScreenAuxiliary |
                                NSWindowCollectionBehaviorStationary;
    _contentView = [[SDDrawerContentView alloc] initWithStore:store drawerID:drawerID edge:_edge];
    __weak typeof(self) weakSelf = self;
    _contentView.deleteHandler = ^(NSString *identifier) {
        if (weakSelf.deleteHandler) weakSelf.deleteHandler(identifier);
    };
    _contentView.newDrawerHandler = ^{ if (weakSelf.newDrawerHandler) weakSelf.newDrawerHandler(); };
    _contentView.lockHandler = ^(BOOL lockedState) { [weakSelf setLocked:lockedState]; };
    // ai coding: 将抽屉窗口快捷键连接到新建、全选、保存和删除所选项目操作 2026/09/17: 09:51
    _panel.selectAllHandler = ^{
        SDDrawerPanelController *strongSelf = weakSelf;
        [strongSelf->_contentView selectAllItems];
    };
    _panel.createDrawerHandler = ^{
        SDDrawerPanelController *strongSelf = weakSelf;
        if (strongSelf.newDrawerHandler) strongSelf.newDrawerHandler();
    };
    _panel.saveDrawerHandler = ^{
        SDDrawerPanelController *strongSelf = weakSelf;
        [strongSelf->_contentView saveDrawerAsFolder];
    };
    _panel.deleteSelectedHandler = ^{
        SDDrawerPanelController *strongSelf = weakSelf;
        [strongSelf->_contentView deleteSelectedItems];
    };
    // ai coding: 将 Command+V 路由到当前抽屉内容视图的剪贴板导入逻辑 2026/09/17: 14:10
    _panel.pasteHandler = ^{
        SDDrawerPanelController *strongSelf = weakSelf;
        [strongSelf->_contentView pasteFromPasteboard];
    };
    // ai coding: 普通显示时把默认键盘焦点放在抽屉本体而不是名称输入框 2026/09/17: 10:33
    _panel.contentView = _contentView;
    _panel.initialFirstResponder = _contentView;
    [_panel makeFirstResponder:_contentView];
    return self;
}

- (void)setLocked:(BOOL)locked {
    _panel.movable = !locked;
    _panel.movableByWindowBackground = !locked;
}

- (void)show {
    NSDictionary *drawer = [_store drawerForID:_drawerID];
    CGFloat position = [drawer[@"position"] doubleValue];
    NSScreen *screen = NSScreen.mainScreen;
    if (screen) [_panel setFrame:[self frameForEdge:_edge position:position screen:screen] display:NO];
    [_contentView reloadContent];
    [_panel orderFrontRegardless];
}

- (void)reloadContent {
    [_contentView reloadContent];
}

// ai coding: 暴露当前抽屉的菜单操作并报告键盘焦点状态 2026/09/17: 10:47
- (void)selectAllItems { [_contentView selectAllItems]; }
- (void)saveDrawerAsFolder { [_contentView saveDrawerAsFolder]; }
- (void)deleteSelectedItems { [_contentView deleteSelectedItems]; }
// ai coding: 将菜单和 Command+V 的粘贴操作转发给当前抽屉内容视图 2026/09/17: 14:10
- (BOOL)pasteFromPasteboard { return [_contentView pasteFromPasteboard]; }

// ai coding: 提供当前抽屉厚度读写，菜单根据吸附方向映射为高度或宽度 2026/09/17: 14:10
- (CGFloat)currentDrawerThickness {
    NSDictionary *drawer = [_store drawerForID:_drawerID];
    return SDEdgeIsHorizontal(_edge)
        ? [drawer[@"horizontalThickness"] doubleValue]
        : [drawer[@"verticalThickness"] doubleValue];
}

- (void)setDrawerThickness:(CGFloat)thickness {
    NSScreen *screen = _panel.screen ?: NSScreen.mainScreen;
    if (!screen) return;
    NSRect visible = screen.visibleFrame;
    if ([_edge isEqualToString:SDEdgeBottom]) {
        NSRect fullFrame = screen.frame;
        visible.origin.y = NSMinY(fullFrame);
        visible.size.height = NSMaxY(fullFrame) - NSMinY(fullFrame);
    }
    CGFloat maximum = SDEdgeIsHorizontal(_edge) ? visible.size.height : visible.size.width;
    CGFloat minimum = SDEdgeIsHorizontal(_edge) ? SDHorizontalMinimumThickness : SDVerticalMinimumThickness;
    CGFloat clamped = MAX(minimum, MIN(maximum, thickness));
    [_store updateDrawerID:_drawerID thickness:clamped forEdge:_edge];
    NSDictionary *drawer = [_store drawerForID:_drawerID];
    CGFloat position = [drawer[@"position"] doubleValue];
    _adjustingFrame = YES;
    [_panel setFrame:[self frameForEdge:_edge position:position screen:screen] display:YES animate:YES];
    _adjustingFrame = NO;
}
- (BOOL)isEditingDrawerName { return [_panel isEditingDrawerName]; }

- (void)beginRenaming {
    [NSApp activateIgnoringOtherApps:YES];
    [_panel orderFrontRegardless];
    // ai coding: 等待新窗口完成激活后再聚焦名称，避免默认响应者覆盖输入焦点 2026/09/17: 10:40
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_panel makeKeyWindow];
        [self->_contentView beginRenaming];
    });
}

- (void)windowDidMove:(NSNotification *)notification {
    if (_adjustingFrame) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(snapToNearestEdge) object:nil];
    [self performSelector:@selector(snapToNearestEdge) withObject:nil afterDelay:0.22];
}

// ai coding: 抽屉成为当前窗口时记录其标识供菜单命令使用 2026/09/17: 10:47
- (void)windowDidBecomeKey:(NSNotification *)notification {
    if (self.activationHandler) self.activationHandler(_drawerID);
}

- (void)windowDidResize:(NSNotification *)notification {
    if (_adjustingFrame) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(persistResizedFrame) object:nil];
    [self performSelector:@selector(persistResizedFrame) withObject:nil afterDelay:0.18];
}

- (void)persistResizedFrame {
    NSScreen *screen = _panel.screen ?: NSScreen.mainScreen;
    if (!screen) return;
    NSRect frame = _panel.frame;
    CGFloat length = SDEdgeIsHorizontal(_edge) ? frame.size.width : frame.size.height;
    [_store updateDrawerID:_drawerID length:length forEdge:_edge];
    NSRect visible = screen.visibleFrame;
    CGFloat available = SDEdgeIsHorizontal(_edge)
        ? MAX(1, visible.size.width - frame.size.width)
        : MAX(1, visible.size.height - frame.size.height);
    CGFloat offset = SDEdgeIsHorizontal(_edge)
        ? NSMinX(frame) - NSMinX(visible)
        : NSMinY(frame) - NSMinY(visible);
    [_store updateDrawerID:_drawerID edge:_edge position:MAX(0, MIN(1, offset / available))];
}

- (void)snapToNearestEdge {
    NSScreen *screen = _panel.screen ?: NSScreen.mainScreen;
    if (!screen) return;
    NSRect visible = screen.visibleFrame;
    NSRect fullFrame = screen.frame;
    NSRect frame = _panel.frame;
    NSDictionary<NSString *, NSNumber *> *distances = @{
        SDEdgeLeft: @(fabs(NSMinX(frame) - NSMinX(visible))),
        SDEdgeRight: @(fabs(NSMaxX(visible) - NSMaxX(frame))),
        SDEdgeBottom: @(fabs(NSMinY(frame) - NSMinY(fullFrame))),
        SDEdgeTop: @(fabs(NSMaxY(visible) - NSMaxY(frame)))
    };
    NSString *nearest = SDEdgeLeft;
    for (NSString *candidate in distances) {
        if (distances[candidate].doubleValue < distances[nearest].doubleValue) nearest = candidate;
    }
    NSSize nextSize = [self sizeForEdge:nearest];
    CGFloat position;
    if (SDEdgeIsHorizontal(nearest)) {
        CGFloat available = MAX(1, visible.size.width - nextSize.width);
        position = (NSMidX(frame) - NSMinX(visible) - nextSize.width / 2) / available;
    } else {
        CGFloat available = MAX(1, visible.size.height - nextSize.height);
        position = (NSMidY(frame) - NSMinY(visible) - nextSize.height / 2) / available;
    }
    position = MAX(0, MIN(1, position));
    _edge = nearest;
    [_contentView setDrawerEdge:nearest];
    [_store updateDrawerID:_drawerID edge:nearest position:position];
    _adjustingFrame = YES;
    [_panel setFrame:[self frameForEdge:nearest position:position screen:screen] display:YES animate:YES];
    _adjustingFrame = NO;
}

- (NSSize)sizeForEdge:(NSString *)edge {
    NSDictionary *drawer = [_store drawerForID:_drawerID];
    if (SDEdgeIsHorizontal(edge)) {
        CGFloat length = MAX(SDHorizontalMinimumLength, [drawer[@"horizontalLength"] doubleValue]);
        CGFloat thickness = MAX(SDHorizontalMinimumThickness, [drawer[@"horizontalThickness"] doubleValue]);
        return NSMakeSize(length, thickness);
    }
    CGFloat length = MAX(SDVerticalMinimumLength, [drawer[@"verticalLength"] doubleValue]);
    CGFloat thickness = MAX(SDVerticalMinimumThickness, [drawer[@"verticalThickness"] doubleValue]);
    return NSMakeSize(thickness, length);
}

// ai coding: 将四向吸附间距改为零并允许底部抽屉落到 Dock 所在的屏幕底边 2026/09/17: 13:41
- (NSRect)frameForEdge:(NSString *)edge position:(CGFloat)position screen:(NSScreen *)screen {
    NSRect visible = screen.visibleFrame;
    if ([edge isEqualToString:SDEdgeBottom]) {
        NSRect fullFrame = screen.frame;
        visible.origin.y = NSMinY(fullFrame);
        visible.size.height = NSMaxY(fullFrame) - NSMinY(fullFrame);
    }
    NSSize size = [self sizeForEdge:edge];
    CGFloat inset = 0;
    if (SDEdgeIsHorizontal(edge)) size.width = MIN(size.width, MAX(SDHorizontalMinimumLength, visible.size.width - inset * 2));
    else size.height = MIN(size.height, MAX(SDVerticalMinimumLength, visible.size.height - inset * 2));
    // ai coding: 限制菜单输入的抽屉高度或宽度不超过当前屏幕可用范围 2026/09/17: 14:10
    if (SDEdgeIsHorizontal(edge)) size.height = MIN(size.height, MAX(SDHorizontalMinimumThickness, visible.size.height));
    else size.width = MIN(size.width, MAX(SDVerticalMinimumThickness, visible.size.width));
    NSRect frame = NSMakeRect(0, 0, size.width, size.height);
    if ([edge isEqualToString:SDEdgeLeft]) {
        frame.origin.x = NSMinX(visible) + inset;
        frame.origin.y = NSMinY(visible) + position * MAX(0, visible.size.height - size.height);
    } else if ([edge isEqualToString:SDEdgeRight]) {
        frame.origin.x = NSMaxX(visible) - size.width - inset;
        frame.origin.y = NSMinY(visible) + position * MAX(0, visible.size.height - size.height);
    } else if ([edge isEqualToString:SDEdgeTop]) {
        frame.origin.x = NSMinX(visible) + position * MAX(0, visible.size.width - size.width);
        frame.origin.y = NSMaxY(visible) - size.height - inset;
    } else {
        frame.origin.x = NSMinX(visible) + position * MAX(0, visible.size.width - size.width);
        frame.origin.y = NSMinY(visible) + inset;
    }
    return frame;
}
@end
