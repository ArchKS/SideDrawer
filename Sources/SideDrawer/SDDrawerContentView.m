// ai coding: 拆分出抽屉内容视图与文件卡片实现 2026/09/17: 15:34
#import "SDDrawerContentView.h"
#import "SDDrawerStore.h"
#import <QuartzCore/QuartzCore.h>
#import <QuickLookUI/QuickLookUI.h>

// ai coding: 修正调节方向并允许缩短到单个文件卡片尺寸 2026/09/17: 13:41
@interface SDLengthResizeHandleView : NSView
@property(nonatomic) BOOL horizontal;
@end

@implementation SDLengthResizeHandleView {
    NSRect _startFrame;
    NSPoint _startScreenPoint;
}

- (BOOL)mouseDownCanMoveWindow { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:self.horizontal ? NSCursor.resizeLeftRightCursor : NSCursor.resizeUpDownCursor];
}

- (void)mouseDown:(NSEvent *)event {
    _startFrame = self.window.frame;
    _startScreenPoint = [self.window convertPointToScreen:event.locationInWindow];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint point = [self.window convertPointToScreen:event.locationInWindow];
    NSRect frame = _startFrame;
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    NSRect visible = screen ? screen.visibleFrame : NSMakeRect(0, 0, 1600, 1000);
    if (self.horizontal) {
        CGFloat maximum = MAX(SDHorizontalMinimumLength, NSMaxX(visible) - NSMinX(frame));
        frame.size.width = MAX(SDHorizontalMinimumLength,
                               MIN(maximum, _startFrame.size.width + point.x - _startScreenPoint.x));
    } else {
        CGFloat fixedTop = NSMaxY(_startFrame);
        CGFloat maximum = MAX(SDVerticalMinimumLength, fixedTop - NSMinY(visible));
        frame.size.height = MAX(SDVerticalMinimumLength,
                                 MIN(maximum, _startFrame.size.height - (point.y - _startScreenPoint.y)));
        frame.origin.y = fixedTop - frame.size.height;
    }
    [self.window setFrame:frame display:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [[NSColor.secondaryLabelColor colorWithAlphaComponent:0.55] setStroke];
    NSBezierPath *path = [NSBezierPath bezierPath];
    path.lineWidth = 1.2;
    for (NSInteger index = -1; index <= 1; index++) {
        if (self.horizontal) {
            CGFloat x = NSMidX(self.bounds) + index * 2.5;
            [path moveToPoint:NSMakePoint(x, NSMidY(self.bounds) - 6)];
            [path lineToPoint:NSMakePoint(x, NSMidY(self.bounds) + 6)];
        } else {
            CGFloat y = NSMidY(self.bounds) + index * 2.5;
            [path moveToPoint:NSMakePoint(NSMidX(self.bounds) - 6, y)];
            [path lineToPoint:NSMakePoint(NSMidX(self.bounds) + 6, y)];
        }
    }
    [path stroke];
}
@end

// ai coding: 让 Quick Look 预览窗口接收鼠标进入和离开事件，支持在预览内滚动长文本 2026/09/17: 13:58
@interface SDHoverPreviewView : NSVisualEffectView
@property(nonatomic, copy) void (^enteredHandler)(void);
@property(nonatomic, copy) void (^exitedHandler)(void);
@end

@implementation SDHoverPreviewView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
              options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
                      NSTrackingInVisibleRect
                owner:self
             userInfo:nil];
    [self addTrackingArea:trackingArea];
    return self;
}

- (void)mouseEntered:(NSEvent *)event {
    [super mouseEntered:event];
    if (self.enteredHandler) self.enteredHandler();
}

- (void)mouseExited:(NSEvent *)event {
    [super mouseExited:event];
    if (self.exitedHandler) self.exitedHandler();
}
@end

// ai coding: 压缩横向文件项并增加文件悬停预览能力 2026/09/17: 13:50
@interface SDFileTileView : NSView <NSDraggingSource>
@property(nonatomic, getter=isSelected) BOOL selected;
@property(nonatomic, readonly) NSURL *url;
- (instancetype)initWithURL:(NSURL *)url iconOnTop:(BOOL)iconOnTop completion:(void (^)(void))completion
                moveHandler:(void (^)(NSURL *itemURL, NSURL *directoryURL))moveHandler
            selectionHandler:(void (^)(NSURL *itemURL, BOOL toggle))selectionHandler
           dragURLsProvider:(NSArray<NSURL *> *(^)(NSURL *itemURL))dragURLsProvider;
@end

@implementation SDFileTileView {
    NSURL *_url;
    BOOL _iconOnTop;
    NSImageView *_iconView;
    NSTextField *_label;
    void (^_completion)(void);
    void (^_moveHandler)(NSURL *, NSURL *);
    void (^_selectionHandler)(NSURL *, BOOL);
    NSArray<NSURL *> *(^_dragURLsProvider)(NSURL *);
    BOOL _selected;
    BOOL _isDirectory;
    NSPanel *_previewPanel;
    QLPreviewView *_previewView;
    BOOL _tileHovered;
    BOOL _previewHovered;
    BOOL _draggedAfterMouseDown;
    BOOL _collapseSelectionOnMouseUp;
}

// ai coding: 文件卡片销毁时关闭 Quick Look，避免悬停预览窗口残留 2026/09/17: 14:01
- (void)dealloc {
    [_previewPanel orderOut:nil];
    [_previewView close];
}

- (instancetype)initWithURL:(NSURL *)url iconOnTop:(BOOL)iconOnTop completion:(void (^)(void))completion
                moveHandler:(void (^)(NSURL *, NSURL *))moveHandler
            selectionHandler:(void (^)(NSURL *, BOOL))selectionHandler
           dragURLsProvider:(NSArray<NSURL *> *(^)(NSURL *))dragURLsProvider {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    _url = url;
    _iconOnTop = iconOnTop;
    _completion = [completion copy];
    _moveHandler = [moveHandler copy];
    _selectionHandler = [selectionHandler copy];
    _dragURLsProvider = [dragURLsProvider copy];
    BOOL isDirectory = NO;
    [NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&isDirectory];
    _isDirectory = isDirectory;
    self.wantsLayer = YES;
    // ai coding: 文件卡片改用连续圆角曲线 2026/09/17: 16:40
    self.layer.cornerRadius = 9;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.backgroundColor = [NSColor.controlBackgroundColor colorWithAlphaComponent:0.38].CGColor;
    self.toolTip = url.path;
    _iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _iconView.image = [NSWorkspace.sharedWorkspace iconForFile:url.path];
    _iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [self addSubview:_iconView];
    _label = [NSTextField labelWithString:url.lastPathComponent];
    _label.alignment = iconOnTop ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    _label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _label.font = [NSFont systemFontOfSize:_iconOnTop ? 9 : 10 weight:NSFontWeightMedium];
    [self addSubview:_label];
    // ai coding: 监听文件卡片悬停并延迟显示 Quick Look，避免拖拽时误触预览 2026/09/17: 13:50
    NSTrackingArea *trackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
              options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways |
                      NSTrackingInVisibleRect
                owner:self
             userInfo:nil];
    [self addTrackingArea:trackingArea];
    return self;
}

- (BOOL)isSelected { return _selected; }
- (NSURL *)url { return _url; }

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    self.layer.backgroundColor = selected
        ? [NSColor.controlAccentColor colorWithAlphaComponent:0.28].CGColor
        : [NSColor.controlBackgroundColor colorWithAlphaComponent:0.38].CGColor;
    self.layer.borderWidth = selected ? 2.0 : 0.0;
    self.layer.borderColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.95].CGColor;
}

- (NSSize)intrinsicContentSize { return _iconOnTop ? NSMakeSize(72, 42) : NSMakeSize(79, 46); }

// ai coding: 创建紧凑磨砂 Quick Look 预览窗口并根据抽屉位置自动避让屏幕边缘 2026/09/17: 13:50
- (void)showHoverPreview {
    if (_isDirectory || ![NSFileManager.defaultManager fileExistsAtPath:_url.path]) return;
    NSScreen *screen = self.window.screen ?: NSScreen.mainScreen;
    if (!screen) return;
    if (!_previewPanel) {
        _previewPanel = [[NSPanel alloc]
            initWithContentRect:NSMakeRect(0, 0, 320, 240)
                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                        backing:NSBackingStoreBuffered
                          defer:NO];
        _previewPanel.opaque = NO;
        _previewPanel.backgroundColor = NSColor.clearColor;
        _previewPanel.hasShadow = YES;
        _previewPanel.level = NSStatusWindowLevel;
        _previewPanel.floatingPanel = YES;
        _previewPanel.hidesOnDeactivate = NO;
        _previewPanel.becomesKeyOnlyIfNeeded = YES;
        _previewPanel.ignoresMouseEvents = NO;
        _previewPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                            NSWindowCollectionBehaviorFullScreenAuxiliary;
        SDHoverPreviewView *background = [[SDHoverPreviewView alloc]
            initWithFrame:NSMakeRect(0, 0, 320, 240)];
        background.material = NSVisualEffectMaterialPopover;
        background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        background.state = NSVisualEffectStateActive;
        background.wantsLayer = YES;
        // ai coding: 悬停预览窗口改用连续圆角曲线 2026/09/17: 16:40
        background.layer.cornerRadius = 14;
        background.layer.cornerCurve = kCACornerCurveContinuous;
        background.layer.masksToBounds = YES;
        _previewView = [[QLPreviewView alloc]
            initWithFrame:NSMakeRect(8, 8, 304, 224)
                    style:QLPreviewViewStyleCompact];
        _previewView.autostarts = NO;
        [background addSubview:_previewView];
        _previewPanel.contentView = background;
        __weak typeof(self) weakSelf = self;
        background.enteredHandler = ^{ [weakSelf previewDidEnter]; };
        background.exitedHandler = ^{ [weakSelf previewDidExit]; };
    }
    _previewView.previewItem = _url;
    NSRect tileInWindow = [self convertRect:self.bounds toView:nil];
    NSRect tileRect = [self.window convertRectToScreen:tileInWindow];
    NSRect visible = screen.visibleFrame;
    NSSize previewSize = _previewPanel.frame.size;
    NSPoint origin = NSMakePoint(NSMidX(tileRect) - previewSize.width / 2,
                                 NSMaxY(tileRect) + 8);
    if (_iconOnTop) {
        if (NSMinY(tileRect) > NSMidY(visible)) origin.y = NSMinY(tileRect) - previewSize.height - 8;
    } else if (NSMinX(tileRect) > NSMidX(visible)) {
        origin.x = NSMinX(tileRect) - previewSize.width - 8;
        origin.y = NSMidY(tileRect) - previewSize.height / 2;
    } else {
        origin.x = NSMaxX(tileRect) + 8;
        origin.y = NSMidY(tileRect) - previewSize.height / 2;
    }
    origin.x = MAX(NSMinX(visible) + 8, MIN(origin.x, NSMaxX(visible) - previewSize.width - 8));
    origin.y = MAX(NSMinY(visible) + 8, MIN(origin.y, NSMaxY(visible) - previewSize.height - 8));
    [_previewPanel setFrame:NSMakeRect(origin.x, origin.y, previewSize.width, previewSize.height) display:NO];
    [_previewPanel orderFrontRegardless];
}

// ai coding: 在文件卡片和预览窗口之间保持悬停状态，允许滚动长文本内容 2026/09/17: 13:58
- (void)previewDidEnter {
    _previewHovered = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideHoverPreviewIfPointerLeft) object:nil];
}

- (void)previewDidExit {
    _previewHovered = NO;
    [self performSelector:@selector(hideHoverPreviewIfPointerLeft) withObject:nil afterDelay:0.18];
}

- (void)hideHoverPreviewIfPointerLeft {
    if (_tileHovered || _previewHovered) return;
    [_previewPanel orderOut:nil];
}

// ai coding: 鼠标离开文件卡片或开始拖拽时关闭悬停预览 2026/09/17: 13:58
- (void)hideHoverPreview {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showHoverPreview) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideHoverPreviewIfPointerLeft) object:nil];
    _tileHovered = NO;
    _previewHovered = NO;
    [_previewPanel orderOut:nil];
}

- (void)mouseEntered:(NSEvent *)event {
    [super mouseEntered:event];
    if (_isDirectory) return;
    _tileHovered = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideHoverPreviewIfPointerLeft) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showHoverPreview) object:nil];
    [self performSelector:@selector(showHoverPreview) withObject:nil afterDelay:0.22];
}

- (void)mouseExited:(NSEvent *)event {
    [super mouseExited:event];
    _tileHovered = NO;
    [self performSelector:@selector(hideHoverPreviewIfPointerLeft) withObject:nil afterDelay:0.18];
}

- (void)layout {
    [super layout];
    if (_iconOnTop) {
        _iconView.frame = NSMakeRect((self.bounds.size.width - 24) / 2, 16, 24, 24);
        _label.frame = NSMakeRect(4, 2, self.bounds.size.width - 8, 12);
    } else {
        _iconView.frame = NSMakeRect(5, 9, 28, 28);
        _label.frame = NSMakeRect(37, 13, self.bounds.size.width - 41, 19);
    }
}

// ai coding: 让首次点击文件即可激活抽屉并接收 Command+A 等快捷键 2026/09/17: 09:53
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)mouseDown:(NSEvent *)event {
    [self hideHoverPreview];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyWindow];
    _draggedAfterMouseDown = NO;
    _collapseSelectionOnMouseUp = NO;
    BOOL commandDown = (event.modifierFlags & NSEventModifierFlagCommand) != 0;
    if (commandDown) {
        if (_selectionHandler) _selectionHandler(_url, YES);
    } else if (!_selected) {
        if (_selectionHandler) _selectionHandler(_url, NO);
    } else {
        _collapseSelectionOnMouseUp = YES;
    }
    if (event.clickCount == 2) {
        _collapseSelectionOnMouseUp = NO;
        [NSWorkspace.sharedWorkspace openURL:_url];
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (_collapseSelectionOnMouseUp && !_draggedAfterMouseDown && event.clickCount == 1 && _selectionHandler) {
        _selectionHandler(_url, NO);
    }
    _collapseSelectionOnMouseUp = NO;
}

- (BOOL)mouseDownCanMoveWindow { return NO; }

- (void)mouseDragged:(NSEvent *)event {
    [self hideHoverPreview];
    _draggedAfterMouseDown = YES;
    NSArray<NSURL *> *urls = _dragURLsProvider ? _dragURLsProvider(_url) : @[_url];
    if (urls.count == 0) return;
    NSMutableArray<NSDraggingItem *> *draggingItems = [NSMutableArray arrayWithCapacity:urls.count];
    [urls enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger index, BOOL *stop __unused) {
        NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:url];
        NSRect frame = NSInsetRect(self.bounds, 5, 5);
        CGFloat offset = MIN(index, (NSUInteger)4) * 3.0;
        frame.origin.x += offset;
        frame.origin.y -= offset;
        NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:url.path];
        [item setDraggingFrame:frame contents:icon];
        [draggingItems addObject:item];
    }];
    [self beginDraggingSessionWithItems:draggingItems event:event source:self];
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationMove;
}

- (BOOL)ignoreModifierKeysForDraggingSession:(NSDraggingSession *)session { return YES; }

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
    if (!_completion) return;
    for (NSNumber *delay in @[@0.0, @0.25, @0.8]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), _completion);
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"文件"];
    NSMenuItem *open = [[NSMenuItem alloc] initWithTitle:@"打开" action:@selector(openItem:) keyEquivalent:@""];
    open.target = self;
    [menu addItem:open];
    // ai coding: 右键菜单统一使用“访达”译名  2026/09/17: 16:06
    NSMenuItem *reveal = [[NSMenuItem alloc] initWithTitle:@"在访达中显示" action:@selector(revealItem:) keyEquivalent:@""];
    reveal.target = self;
    [menu addItem:reveal];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *move = [[NSMenuItem alloc] initWithTitle:@"移动到文件夹…" action:@selector(moveItem:) keyEquivalent:@""];
    move.target = self;
    [menu addItem:move];
    return menu;
}

- (void)openItem:(id)sender { [NSWorkspace.sharedWorkspace openURL:_url]; }
- (void)revealItem:(id)sender { [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[_url]]; }

- (void)moveItem:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.title = @"选择移动位置";
    panel.prompt = @"移动到这里";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK && self->_moveHandler) self->_moveHandler(self->_url, panel.URL);
    }];
}
@end

// ai coding: 同步压缩横向堆叠项，为右侧纵向操作按钮留出空间 2026/09/17: 09:19
@interface SDPileView : NSView <NSDraggingSource>
- (instancetype)initWithURLs:(NSArray<NSURL *> *)urls iconOnTop:(BOOL)iconOnTop completion:(void (^)(void))completion
                  moveHandler:(void (^)(NSURL *, NSURL *))moveHandler
             selectionHandler:(void (^)(NSURL *itemURL, BOOL toggle))selectionHandler
            dragURLsProvider:(NSArray<NSURL *> *(^)(NSURL *itemURL))dragURLsProvider
             selectedProvider:(BOOL (^)(NSURL *itemURL))selectedProvider;
- (void)updateSelectionAppearance;
@end

@implementation SDPileView {
    NSArray<NSURL *> *_urls;
    BOOL _iconOnTop;
    void (^_completion)(void);
    void (^_moveHandler)(NSURL *, NSURL *);
    void (^_selectionHandler)(NSURL *, BOOL);
    NSArray<NSURL *> *(^_dragURLsProvider)(NSURL *);
    BOOL (^_selectedProvider)(NSURL *);
    NSPopover *_popover;
    NSArray<SDFileTileView *> *_popoverTiles;
    BOOL _draggedAfterMouseDown;
}

- (instancetype)initWithURLs:(NSArray<NSURL *> *)urls iconOnTop:(BOOL)iconOnTop completion:(void (^)(void))completion
                  moveHandler:(void (^)(NSURL *, NSURL *))moveHandler
             selectionHandler:(void (^)(NSURL *, BOOL))selectionHandler
            dragURLsProvider:(NSArray<NSURL *> *(^)(NSURL *))dragURLsProvider
             selectedProvider:(BOOL (^)(NSURL *))selectedProvider {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    _urls = [urls copy];
    _iconOnTop = iconOnTop;
    _completion = [completion copy];
    _moveHandler = [moveHandler copy];
    _selectionHandler = [selectionHandler copy];
    _dragURLsProvider = [dragURLsProvider copy];
    _selectedProvider = [selectedProvider copy];
    self.wantsLayer = YES;
    // ai coding: 折叠卡片改用连续圆角曲线 2026/09/17: 16:40
    self.layer.cornerRadius = 9;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.backgroundColor = [NSColor.controlBackgroundColor colorWithAlphaComponent:0.38].CGColor;
    self.toolTip = [NSString stringWithFormat:@"其余 %ld 项", (long)urls.count];
    return self;
}

- (void)updateSelectionAppearance {
    BOOL hasSelection = NO;
    for (NSURL *url in _urls) {
        if (_selectedProvider && _selectedProvider(url)) {
            hasSelection = YES;
            break;
        }
    }
    self.layer.backgroundColor = hasSelection
        ? [NSColor.controlAccentColor colorWithAlphaComponent:0.28].CGColor
        : [NSColor.controlBackgroundColor colorWithAlphaComponent:0.38].CGColor;
    self.layer.borderWidth = hasSelection ? 2.0 : 0.0;
    self.layer.borderColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.95].CGColor;
    for (NSUInteger index = 0; index < _popoverTiles.count && index < _urls.count; index++) {
        _popoverTiles[index].selected = _selectedProvider && _selectedProvider(_urls[index]);
    }
}

- (NSSize)intrinsicContentSize { return _iconOnTop ? NSMakeSize(72, 42) : NSMakeSize(79, 46); }

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    CGFloat iconSize = _iconOnTop ? 24 : 28;
    CGFloat baseX = _iconOnTop ? (self.bounds.size.width - iconSize) / 2 - 4 : 6;
    CGFloat baseY = _iconOnTop ? 14 : 8;
    NSInteger layers = MIN(3, _urls.count);
    for (NSInteger index = layers - 1; index >= 0; index--) {
        NSImage *icon = [NSWorkspace.sharedWorkspace iconForFile:_urls[(NSUInteger)index].path];
        [icon drawInRect:NSMakeRect(baseX + index * 5, baseY + index * 3, iconSize, iconSize)];
    }
    NSString *count = [NSString stringWithFormat:@"+%ld", (long)_urls.count];
    NSDictionary *attributes = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:9], NSForegroundColorAttributeName: NSColor.labelColor};
    NSSize size = [count sizeWithAttributes:attributes];
    NSPoint point = _iconOnTop ? NSMakePoint((self.bounds.size.width - size.width) / 2, 1)
                               : NSMakePoint(43, (self.bounds.size.height - size.height) / 2);
    [count drawAtPoint:point withAttributes:attributes];
}

// ai coding: 让首次点击文件堆即可激活抽屉并接收键盘命令 2026/09/17: 09:53
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)mouseDown:(NSEvent *)event {
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyWindow];
    _draggedAfterMouseDown = NO;
}

- (void)mouseUp:(NSEvent *)event {
    if (!_draggedAfterMouseDown) [self showPopover];
}

- (BOOL)mouseDownCanMoveWindow { return NO; }

- (void)mouseDragged:(NSEvent *)event {
    _draggedAfterMouseDown = YES;
    NSURL *selectedAnchor = nil;
    for (NSURL *url in _urls) {
        if (_selectedProvider && _selectedProvider(url)) {
            selectedAnchor = url;
            break;
        }
    }
    NSArray<NSURL *> *urls = selectedAnchor && _dragURLsProvider ? _dragURLsProvider(selectedAnchor) : _urls;
    if (urls.count == 0) return;
    NSMutableArray<NSDraggingItem *> *draggingItems = [NSMutableArray arrayWithCapacity:urls.count];
    [urls enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger index, BOOL *stop __unused) {
        NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:url];
        NSRect frame = NSInsetRect(self.bounds, 5, 5);
        CGFloat offset = MIN(index, (NSUInteger)4) * 3.0;
        frame.origin.x += offset;
        frame.origin.y -= offset;
        [item setDraggingFrame:frame contents:[NSWorkspace.sharedWorkspace iconForFile:url.path]];
        [draggingItems addObject:item];
    }];
    [self beginDraggingSessionWithItems:draggingItems event:event source:self];
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
    return NSDragOperationMove;
}

- (BOOL)ignoreModifierKeysForDraggingSession:(NSDraggingSession *)session { return YES; }

- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
    if (!_completion) return;
    for (NSNumber *delay in @[@0.0, @0.25, @0.8]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), _completion);
    }
}

- (void)showPopover {
    _popover = [[NSPopover alloc] init];
    _popover.behavior = NSPopoverBehaviorTransient;
    CGFloat documentHeight = MAX(58, _urls.count * 58);
    SDFlippedView *document = [[SDFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 250, documentHeight)];
    __weak typeof(self) weakSelf = self;
    void (^moveHandler)(NSURL *, NSURL *) = _moveHandler;
    NSMutableArray<SDFileTileView *> *popoverTiles = [NSMutableArray arrayWithCapacity:_urls.count];
    [_urls enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger index, BOOL *stop __unused) {
        SDFileTileView *tile = [[SDFileTileView alloc] initWithURL:url iconOnTop:NO completion:^{
            SDPileView *strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf->_popover close];
            if (strongSelf->_completion) strongSelf->_completion();
        } moveHandler:moveHandler selectionHandler:self->_selectionHandler dragURLsProvider:self->_dragURLsProvider];
        tile.selected = self->_selectedProvider && self->_selectedProvider(url);
        tile.frame = NSMakeRect(8, index * 58 + 2, 234, 54);
        [document addSubview:tile];
        [popoverTiles addObject:tile];
    }];
    _popoverTiles = popoverTiles;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 250, MIN(348, documentHeight))];
    scroll.drawsBackground = NO;
    scroll.hasVerticalScroller = documentHeight > 348;
    scroll.documentView = document;
    NSViewController *controller = [[NSViewController alloc] init];
    controller.view = scroll;
    _popover.contentViewController = controller;
    _popover.contentSize = scroll.frame.size;
    [_popover showRelativeToRect:self.bounds ofView:self preferredEdge:NSRectEdgeMinX];
}
@end

// ai coding: 识别剪贴板文本中的常见 Markdown 结构并给粘贴文件选择扩展名 2026/09/17: 14:10
static BOOL SDStringLooksLikeMarkdown(NSString *text) {
    if (text.length == 0) return NO;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"> "]) return YES;
        NSUInteger headingHashes = 0;
        while (headingHashes < trimmed.length && [trimmed characterAtIndex:headingHashes] == '#') headingHashes += 1;
        if (headingHashes > 0 && headingHashes <= 6 && headingHashes < trimmed.length &&
            [trimmed characterAtIndex:headingHashes] == ' ') return YES;
        if ([trimmed hasPrefix:@"- "] || [trimmed hasPrefix:@"* "] || [trimmed hasPrefix:@"+ "]) return YES;
        NSUInteger digitCount = 0;
        while (digitCount < trimmed.length && [trimmed characterAtIndex:digitCount] >= '0' &&
               [trimmed characterAtIndex:digitCount] <= '9') digitCount += 1;
        if (digitCount > 0 && digitCount + 1 < trimmed.length &&
            [trimmed characterAtIndex:digitCount] == '.' && [trimmed characterAtIndex:digitCount + 1] == ' ') return YES;
        if ([trimmed containsString:@"]("] || [trimmed containsString:@"**"] ||
            [trimmed containsString:@"__"] || [trimmed containsString:@"| "] ||
            ([trimmed hasPrefix:@"|"] && [trimmed containsString:@"|-"])) return YES;
    }
    return [text hasPrefix:@"---\n"] || [text hasPrefix:@"---\r\n"];
}

// ai coding: 将剪贴板图片写入临时 PNG 文件，随后交给现有文件导入流程移动到磁盘 2026/09/17: 14:10
static NSURL *SDWritePastedImage(NSPasteboard *pasteboard, NSError **error) {
    NSData *sourceData = [pasteboard dataForType:NSPasteboardTypePNG];
    if (!sourceData) sourceData = [pasteboard dataForType:NSPasteboardTypeTIFF];
    NSBitmapImageRep *bitmap = sourceData ? [[NSBitmapImageRep alloc] initWithData:sourceData] : nil;
    if (!bitmap) {
        NSImage *image = [[NSImage alloc] initWithPasteboard:pasteboard];
        NSData *tiffData = [image TIFFRepresentation];
        bitmap = tiffData ? [[NSBitmapImageRep alloc] initWithData:tiffData] : nil;
    }
    NSData *pngData = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (pngData.length == 0) {
        if (error) *error = SDError(11, @"剪贴板中的图片无法读取。");
        return nil;
    }
    // ai coding: 将图片粘贴文件前缀统一改为英文 paste 便于识别 2026/09/17: 14:44
    NSString *name = [NSString stringWithFormat:@"paste-%@.png", NSUUID.UUID.UUIDString.lowercaseString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    if (![pngData writeToURL:url options:NSDataWritingAtomic error:error]) return nil;
    return url;
}

// ai coding: 将剪贴板文本按 Markdown 或纯文本保存为临时文件供收纳盒接管 2026/09/17: 14:10
static NSURL *SDWritePastedText(NSString *text, BOOL markdown, NSError **error) {
    NSString *extension = markdown ? @"md" : @"txt";
    // ai coding: 将文本粘贴文件前缀统一改为英文 paste 便于识别 2026/09/17: 14:44
    NSString *name = [NSString stringWithFormat:@"paste-%@.%@", NSUUID.UUID.UUIDString.lowercaseString, extension];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (![data writeToURL:url options:NSDataWritingAtomic error:error]) return nil;
    return url;
}

@implementation SDDrawerContentView {
    SDDrawerStore *_store;
    NSString *_drawerID;
    NSString *_edge;
    NSTextField *_nameField;
    NSStackView *_itemStack;
    NSButton *_lockButton;
    BOOL _locked;
    NSMutableSet<NSString *> *_selectedPaths;
    NSArray<NSURL *> *_itemURLs;
    NSMutableArray<SDFileTileView *> *_visibleTiles;
    SDPileView *_pileView;
    NSView *_dropOverlay;
    BOOL _dropTargetActive;
}

- (instancetype)initWithStore:(SDDrawerStore *)store drawerID:(NSString *)drawerID edge:(NSString *)edge {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    _store = store;
    _drawerID = [drawerID copy];
    _edge = [edge copy];
    _locked = [[store drawerForID:drawerID][@"locked"] boolValue];
    _selectedPaths = [NSMutableSet set];
    _visibleTiles = [NSMutableArray array];
    self.material = NSVisualEffectMaterialHUDWindow;
    self.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.state = NSVisualEffectStateActive;
    self.wantsLayer = YES;
    // ai coding: 抽屉四角改用系统连续圆角曲线（cornerCurve），并移除旧的圆弧遮罩图 2026/09/17: 16:43
    self.layer.cornerRadius = 18;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [NSColor.whiteColor colorWithAlphaComponent:0.24].CGColor;
    self.layer.backgroundColor = NSColor.clearColor.CGColor;
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    [self rebuildLayout];
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)setDrawerEdge:(NSString *)edge {
    if ([_edge isEqualToString:edge]) return;
    _edge = [edge copy];
    [self rebuildLayout];
}

- (void)rebuildLayout {
    for (NSView *view in self.subviews.copy) [view removeFromSuperview];
    BOOL horizontal = SDEdgeIsHorizontal(_edge);
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _nameField.bezeled = NO;
    _nameField.bordered = NO;
    _nameField.drawsBackground = NO;
    _nameField.focusRingType = NSFocusRingTypeNone;
    // ai coding: 明确启用收纳盒名称的键盘编辑和选择能力 2026/09/17: 10:40
    _nameField.editable = YES;
    _nameField.selectable = YES;
    _nameField.enabled = YES;
    _nameField.font = [NSFont boldSystemFontOfSize:11];
    _nameField.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameField.delegate = self;
    NSStackView *titleRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    titleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    titleRow.alignment = NSLayoutAttributeCenterY;
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [titleRow addArrangedSubview:_nameField];
    [_nameField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    // ai coding: 窄抽屉中允许名称压缩，为单个文件卡片保留可用宽度 2026/09/17: 13:41
    [_nameField.widthAnchor constraintGreaterThanOrEqualToConstant:20].active = YES;
    [self addSubview:titleRow];

    // ai coding: 图钉与删除按钮提示改用共享文案常量  2026/09/17: 16:06
    _lockButton = [self iconButton:_locked ? @"pin.fill" : @"pin"
                              help:_locked ? SDTextUnpinDrawer : SDTextPinDrawer
                            action:@selector(toggleLocked:)];
    _lockButton.contentTintColor = _locked ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
    _lockButton.translatesAutoresizingMaskIntoConstraints = NO;
    _lockButton.image = SDRotatedPinSymbol(_locked);
    [self addSubview:_lockButton];

    // ai coding: 在抽屉顶部增加删除当前收纳盒的关闭按钮 2026/09/17: 10:40
    NSButton *closeButton = [self iconButton:@"xmark.circle.fill"
                                       help:SDTextDeleteDrawer
                                     action:@selector(deleteDrawer:)];
    closeButton.contentTintColor = NSColor.secondaryLabelColor;
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:closeButton];

    _itemStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    _itemStack.orientation = horizontal ? NSUserInterfaceLayoutOrientationHorizontal : NSUserInterfaceLayoutOrientationVertical;
    _itemStack.alignment = horizontal ? NSLayoutAttributeCenterY : NSLayoutAttributeCenterX;
    _itemStack.spacing = horizontal ? 4 : 3;
    _itemStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_itemStack];

    SDLengthResizeHandleView *resizeHandle = [[SDLengthResizeHandleView alloc] initWithFrame:NSZeroRect];
    resizeHandle.horizontal = horizontal;
    resizeHandle.toolTip = @"拖动调整抽屉长度";
    resizeHandle.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:resizeHandle];

    [NSLayoutConstraint activateConstraints:@[
        [titleRow.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:7],
        [titleRow.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
        [titleRow.trailingAnchor constraintLessThanOrEqualToAnchor:_lockButton.leadingAnchor constant:-3],
        [_lockButton.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
        [_lockButton.trailingAnchor constraintEqualToAnchor:closeButton.leadingAnchor constant:-1],
        [closeButton.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
        [closeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-4]
    ]];
    if (horizontal) {
        // ai coding: 隐藏操作图标后让横向文件区重新居中并释放右侧空间 2026/09/17: 10:33
        // ai coding: 让单个文件卡片在极窄横向抽屉中仍能完整显示 2026/09/17: 13:41
        NSLayoutConstraint *itemLeading = [_itemStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:0];
        NSLayoutConstraint *itemTrailing = [_itemStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:0];
        itemLeading.priority = NSLayoutPriorityDefaultLow;
        itemTrailing.priority = NSLayoutPriorityDefaultLow;
        [NSLayoutConstraint activateConstraints:@[
            [_itemStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_itemStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            itemLeading,
            itemTrailing,
            [resizeHandle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [resizeHandle.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [resizeHandle.widthAnchor constraintEqualToConstant:9],
            [resizeHandle.heightAnchor constraintEqualToConstant:34]
        ]];
    } else {
        // ai coding: 将左右吸附抽屉的长度调节柄放到底部水平居中 2026/09/17: 10:36
        // ai coding: 极短纵向抽屉优先保持文件卡片尺寸而允许与边缘控件重叠 2026/09/17: 13:41
        NSLayoutConstraint *itemTop = [_itemStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:0];
        NSLayoutConstraint *itemBottom = [_itemStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:0];
        itemTop.priority = NSLayoutPriorityDefaultLow;
        itemBottom.priority = NSLayoutPriorityDefaultLow;
        [NSLayoutConstraint activateConstraints:@[
            [_itemStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_itemStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            itemTop,
            itemBottom,
            [resizeHandle.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [resizeHandle.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [resizeHandle.widthAnchor constraintEqualToConstant:34],
            [resizeHandle.heightAnchor constraintEqualToConstant:9]
        ]];
    }

    _dropOverlay = [[NSView alloc] initWithFrame:NSZeroRect];
    _dropOverlay.wantsLayer = YES;
    // ai coding: 拖拽投放高亮层改用连续圆角曲线 2026/09/17: 16:40
    _dropOverlay.layer.cornerRadius = 15;
    _dropOverlay.layer.cornerCurve = kCACornerCurveContinuous;
    _dropOverlay.layer.backgroundColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.30].CGColor;
    _dropOverlay.layer.borderWidth = 1.5;
    _dropOverlay.layer.borderColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.85].CGColor;
    _dropOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    _dropOverlay.hidden = YES;
    _dropOverlay.alphaValue = 0;
    NSImageView *dropIcon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    dropIcon.image = [NSImage imageWithSystemSymbolName:@"arrow.down.to.line.compact" accessibilityDescription:@"松开放入"];
    dropIcon.contentTintColor = NSColor.labelColor;
    NSTextField *dropLabel = [NSTextField labelWithString:@"松开放入"];
    dropLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    NSStackView *dropMessage = [[NSStackView alloc] initWithFrame:NSZeroRect];
    dropMessage.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    dropMessage.alignment = NSLayoutAttributeCenterY;
    dropMessage.spacing = 5;
    dropMessage.translatesAutoresizingMaskIntoConstraints = NO;
    [dropMessage addArrangedSubview:dropIcon];
    [dropMessage addArrangedSubview:dropLabel];
    [_dropOverlay addSubview:dropMessage];
    [self addSubview:_dropOverlay positioned:NSWindowAbove relativeTo:nil];
    [NSLayoutConstraint activateConstraints:@[
        [_dropOverlay.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3],
        [_dropOverlay.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-3],
        [_dropOverlay.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
        [_dropOverlay.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3],
        [dropMessage.centerXAnchor constraintEqualToAnchor:_dropOverlay.centerXAnchor],
        [dropMessage.centerYAnchor constraintEqualToAnchor:_dropOverlay.centerYAnchor]
    ]];
    _dropTargetActive = NO;
    [self reloadContent];
}

- (NSButton *)iconButton:(NSString *)symbol help:(NSString *)help action:(SEL)action {
    NSButton *button = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:help]
                                          target:self action:action];
    button.bordered = NO;
    button.toolTip = help;
    [button.widthAnchor constraintEqualToConstant:17].active = YES;
    [button.heightAnchor constraintEqualToConstant:17].active = YES;
    return button;
}

- (void)reloadContent {
    NSDictionary *drawer = [_store drawerForID:_drawerID];
    _nameField.stringValue = drawer[@"name"] ?: @"";
    NSArray<NSURL *> *items = [_store itemsForDrawerID:_drawerID];
    _itemURLs = items;
    NSMutableSet<NSString *> *existingPaths = [NSMutableSet setWithCapacity:items.count];
    for (NSURL *url in items) [existingPaths addObject:url.path];
    [_selectedPaths intersectSet:existingPaths];
    for (NSView *view in _itemStack.arrangedSubviews.copy) {
        [_itemStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [_visibleTiles removeAllObjects];
    _pileView = nil;
    BOOL iconOnTop = SDEdgeIsHorizontal(_edge);
    __weak typeof(self) weakSelf = self;
    void (^completion)(void) = ^{ [weakSelf reloadContent]; };
    void (^moveHandler)(NSURL *, NSURL *) = ^(NSURL *itemURL, NSURL *directoryURL) {
        SDDrawerContentView *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSError *error = nil;
        if (![strongSelf->_store moveItem:itemURL toDirectory:directoryURL error:&error]) [strongSelf showError:error];
        [strongSelf reloadContent];
    };
    void (^selectionHandler)(NSURL *, BOOL) = ^(NSURL *itemURL, BOOL toggle) {
        [weakSelf updateSelectionForURL:itemURL toggle:toggle];
    };
    NSArray<NSURL *> *(^dragURLsProvider)(NSURL *) = ^NSArray<NSURL *> *(NSURL *itemURL) {
        return [weakSelf draggingURLsForAnchorURL:itemURL];
    };
    BOOL (^selectedProvider)(NSURL *) = ^BOOL(NSURL *itemURL) {
        return [weakSelf isURLSelected:itemURL];
    };
    if (items.count == 0) {
        NSTextField *empty = [NSTextField labelWithString:@"拖入文件或文件夹"];
        empty.alignment = NSTextAlignmentCenter;
        empty.textColor = NSColor.secondaryLabelColor;
        empty.font = [NSFont systemFontOfSize:10];
        [_itemStack addArrangedSubview:empty];
        return;
    }
    NSUInteger directCount = items.count > 5 ? 4 : items.count;
    for (NSUInteger index = 0; index < directCount; index++) {
        SDFileTileView *tile = [[SDFileTileView alloc] initWithURL:items[index] iconOnTop:iconOnTop
                                                       completion:completion moveHandler:moveHandler
                                                  selectionHandler:selectionHandler dragURLsProvider:dragURLsProvider];
        tile.selected = [_selectedPaths containsObject:items[index].path];
        [_visibleTiles addObject:tile];
        [_itemStack addArrangedSubview:tile];
        [tile.widthAnchor constraintEqualToConstant:iconOnTop ? 72 : 79].active = YES;
        [tile.heightAnchor constraintEqualToConstant:iconOnTop ? 42 : 46].active = YES;
    }
    if (items.count > 5) {
        NSArray<NSURL *> *stackedItems = [items subarrayWithRange:NSMakeRange(4, items.count - 4)];
        SDPileView *pile = [[SDPileView alloc] initWithURLs:stackedItems iconOnTop:iconOnTop
                                                completion:completion moveHandler:moveHandler
                                           selectionHandler:selectionHandler dragURLsProvider:dragURLsProvider
                                            selectedProvider:selectedProvider];
        _pileView = pile;
        [pile updateSelectionAppearance];
        [_itemStack addArrangedSubview:pile];
        [pile.widthAnchor constraintEqualToConstant:iconOnTop ? 72 : 79].active = YES;
        [pile.heightAnchor constraintEqualToConstant:iconOnTop ? 42 : 46].active = YES;
    }
}

- (void)selectAllItems {
    [_selectedPaths removeAllObjects];
    for (NSURL *url in _itemURLs) [_selectedPaths addObject:url.path];
    [self updateSelectionAppearance];
}

// ai coding: 新建抽屉时可靠进入名称编辑并全选默认名称 2026/09/17: 10:40
- (void)beginRenaming {
    if (![self.window makeFirstResponder:_nameField]) return;
    NSTextView *editor = (NSTextView *)_nameField.currentEditor;
    if (editor) editor.selectedRange = NSMakeRange(0, _nameField.stringValue.length);
}

// ai coding: 将当前选中的一个或多个抽屉项目安全移入废纸篓 2026/09/17: 09:51
- (void)deleteSelectedItems {
    NSMutableArray<NSURL *> *selectedURLs = [NSMutableArray array];
    for (NSURL *url in _itemURLs) {
        if ([_selectedPaths containsObject:url.path]) [selectedURLs addObject:url];
    }
    if (selectedURLs.count == 0) {
        NSBeep();
        return;
    }
    [NSWorkspace.sharedWorkspace recycleURLs:selectedURLs
                            completionHandler:^(NSDictionary<NSURL *, NSURL *> *newURLs __unused, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) [self showError:error];
            [self reloadContent];
        });
    }];
}

- (void)updateSelectionForURL:(NSURL *)url toggle:(BOOL)toggle {
    if (!url.path) return;
    if (toggle) {
        if ([_selectedPaths containsObject:url.path]) [_selectedPaths removeObject:url.path];
        else [_selectedPaths addObject:url.path];
    } else {
        [_selectedPaths removeAllObjects];
        [_selectedPaths addObject:url.path];
    }
    [self updateSelectionAppearance];
}

- (NSArray<NSURL *> *)draggingURLsForAnchorURL:(NSURL *)anchorURL {
    if (![_selectedPaths containsObject:anchorURL.path]) return anchorURL ? @[anchorURL] : @[];
    NSMutableArray<NSURL *> *selectedURLs = [NSMutableArray arrayWithCapacity:_selectedPaths.count];
    for (NSURL *url in _itemURLs) {
        if ([_selectedPaths containsObject:url.path]) [selectedURLs addObject:url];
    }
    return selectedURLs;
}

- (BOOL)isURLSelected:(NSURL *)url {
    return url.path && [_selectedPaths containsObject:url.path];
}

- (void)updateSelectionAppearance {
    for (SDFileTileView *tile in _visibleTiles) {
        tile.selected = [self isURLSelected:tile.url];
    }
    [_pileView updateSelectionAppearance];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    NSError *error = nil;
    if (![_store renameDrawerID:_drawerID name:_nameField.stringValue error:&error]) [self showError:error];
    [self reloadContent];
    // ai coding: 名称编辑结束后把焦点移回抽屉本体，清除持续显示的选中和光标状态 2026/09/17: 10:33
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.window.firstResponder != self) [self.window makeFirstResponder:self];
    });
}

// ai coding: 拖入素材悬停时显示脉冲落点提示，离开或完成后平滑收起 2026/09/17: 08:40
- (void)setDropTargetActive:(BOOL)active {
    if (_dropTargetActive == active || !_dropOverlay) return;
    _dropTargetActive = active;
    if (active) {
        _dropOverlay.hidden = NO;
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @0.97;
        pulse.toValue = @1.0;
        pulse.duration = 0.48;
        pulse.autoreverses = YES;
        pulse.repeatCount = HUGE_VALF;
        [_dropOverlay.layer addAnimation:pulse forKey:@"dropPulse"];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.16;
            self->_dropOverlay.animator.alphaValue = 1;
        } completionHandler:nil];
    } else {
        [_dropOverlay.layer removeAnimationForKey:@"dropPulse"];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.14;
            self->_dropOverlay.animator.alphaValue = 0;
        } completionHandler:^{
            if (!self->_dropTargetActive) self->_dropOverlay.hidden = YES;
        }];
    }
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
                                                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (urls.count == 0) return NSDragOperationNone;
    [self setDropTargetActive:YES];
    return NSDragOperationMove;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender { return NSDragOperationMove; }

- (void)draggingExited:(id<NSDraggingInfo>)sender { [self setDropTargetActive:NO]; }

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
                                                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    [self setDropTargetActive:NO];
    if (urls.count == 0) return NO;
    NSError *error = nil;
    if (![_store importURLs:urls drawerID:_drawerID error:&error]) [self showError:error];
    [self reloadContent];
    return error == nil;
}

- (void)concludeDragOperation:(id<NSDraggingInfo>)sender { [self setDropTargetActive:NO]; }

- (void)chooseItems:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.title = @"选择要移入抽屉的文件或目录";
    panel.prompt = @"移入抽屉";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    panel.resolvesAliases = YES;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error = nil;
        if (![self->_store importURLs:panel.URLs drawerID:self->_drawerID error:&error]) [self showError:error];
        [self reloadContent];
    }];
}

// ai coding: 按文件、图片、Markdown、普通文本优先级读取剪贴板并立即导入当前收纳盒 2026/09/17: 14:10
- (BOOL)pasteFromPasteboard {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSArray<NSURL *> *fileURLs = [pasteboard readObjectsForClasses:@[NSURL.class]
                                                           options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    NSError *error = nil;
    if (fileURLs.count > 0) {
        if (![_store importURLs:fileURLs drawerID:_drawerID error:&error]) {
            [self showError:error];
            return NO;
        }
        [self reloadContent];
        return YES;
    }

    if ([pasteboard dataForType:NSPasteboardTypePNG] || [pasteboard dataForType:NSPasteboardTypeTIFF] ||
        [[NSImage alloc] initWithPasteboard:pasteboard]) {
        NSURL *imageURL = SDWritePastedImage(pasteboard, &error);
        if (!imageURL || ![_store importURLs:@[imageURL] drawerID:_drawerID error:&error]) {
            if (imageURL) [NSFileManager.defaultManager removeItemAtURL:imageURL error:nil];
            [self showError:error ?: SDError(11, @"剪贴板中的图片无法读取。")];
            return NO;
        }
        [self reloadContent];
        return YES;
    }

    NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
    if (text.length == 0) {
        NSData *rtfData = [pasteboard dataForType:NSPasteboardTypeRTF];
        if (rtfData.length > 0) {
            NSAttributedString *attributed = [[NSAttributedString alloc] initWithRTF:rtfData
                                                                    documentAttributes:nil];
            text = attributed.string;
        }
    }
    if (text.length == 0) {
        NSData *htmlData = [pasteboard dataForType:NSPasteboardTypeHTML];
        if (htmlData.length > 0) {
            NSAttributedString *attributed = [[NSAttributedString alloc] initWithHTML:htmlData
                                                                      documentAttributes:nil];
            text = attributed.string;
        }
    }
    if (text.length == 0) {
        NSBeep();
        return NO;
    }
    NSURL *textURL = SDWritePastedText(text, SDStringLooksLikeMarkdown(text), &error);
    if (!textURL || ![_store importURLs:@[textURL] drawerID:_drawerID error:&error]) {
        if (textURL) [NSFileManager.defaultManager removeItemAtURL:textURL error:nil];
        [self showError:error ?: SDError(12, @"剪贴板中的文本无法保存。")];
        return NO;
    }
    [self reloadContent];
    return YES;
}

- (void)createDrawer:(id)sender { if (self.newDrawerHandler) self.newDrawerHandler(); }

- (void)toggleLocked:(id)sender {
    _locked = !_locked;
    [_store updateDrawerID:_drawerID locked:_locked];
    // ai coding: 切换固定状态时继续使用 -45° 旋转图钉 2026/09/17: 09:19
    _lockButton.image = SDRotatedPinSymbol(_locked);
    // ai coding: 图钉提示改用共享文案常量  2026/09/17: 16:06
    _lockButton.toolTip = _locked ? SDTextUnpinDrawer : SDTextPinDrawer;
    _lockButton.contentTintColor = _locked ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
    if (self.lockHandler) self.lockHandler(_locked);
}

- (void)exportDrawer:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.title = @"选择保存抽屉文件夹的位置";
    panel.prompt = @"保存到这里";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error = nil;
        NSURL *folder = [self->_store saveDrawerID:self->_drawerID inDirectory:panel.URL error:&error];
        if (!folder) [self showError:error];
        else [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[folder]];
        [self reloadContent];
    }];
}

- (void)saveDrawerAsFolder {
    [self.window makeFirstResponder:nil];
    [self exportDrawer:nil];
}

- (void)deleteDrawer:(id)sender { if (self.deleteHandler) self.deleteHandler(_drawerID); }

- (void)showError:(NSError *)error {
    if (!error) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"操作没有完成";
    alert.informativeText = error.localizedDescription;
    [alert addButtonWithTitle:@"好"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}
@end
