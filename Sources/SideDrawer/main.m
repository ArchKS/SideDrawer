// ai coding: 增加可发现的快捷键权限入口并仅在授权后监听 Finder 的 Command+M 2026/09/16: 20:36
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
// ai coding: 引入 Carbon 原生热键接口以避免辅助功能键盘监听失效 2026/09/17: 09:44
#import <Carbon/Carbon.h>
// ai coding: 引入 QuartzCore 以实现拖入落点的脉冲动画 2026/09/17: 08:41
#import <QuartzCore/QuartzCore.h>

static NSString * const SDErrorDomain = @"com.codex.sidedrawer";
static NSString * const SDEdgeLeft = @"left";
static NSString * const SDEdgeRight = @"right";
static NSString * const SDEdgeTop = @"top";
static NSString * const SDEdgeBottom = @"bottom";

static NSError *SDError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:SDErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL SDEdgeIsHorizontal(NSString *edge) {
    return [edge isEqualToString:SDEdgeTop] || [edge isEqualToString:SDEdgeBottom];
}

// ai coding: 生成不会被自动布局重置的 -45° 旋转系统图标 2026/09/17: 09:19
static NSImage *SDRotatedPinSymbol(BOOL locked) {
    NSString *description = locked ? @"旋转-45度的取消固定" : @"旋转-45度的固定抽屉";
    NSImage *source = [NSImage imageWithSystemSymbolName:locked ? @"pin.fill" : @"pin"
                               accessibilityDescription:description];
    NSImage *rotated = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    [rotated lockFocus];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:8 yBy:8];
    [transform rotateByDegrees:-45];
    [transform concat];
    [source drawInRect:NSMakeRect(-6, -6, 12, 12)
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1
        respectFlipped:NO
                 hints:nil];
    [rotated unlockFocus];
    rotated.template = YES;
    rotated.accessibilityDescription = description;
    return rotated;
}

@interface SDDrawerStore : NSObject
@property(nonatomic, readonly) NSArray<NSDictionary *> *drawers;
- (instancetype)initWithError:(NSError **)error;
- (NSDictionary *)drawerForID:(NSString *)drawerID;
- (NSArray<NSURL *> *)itemsForDrawerID:(NSString *)drawerID;
- (NSString *)addDrawer:(NSError **)error;
- (BOOL)renameDrawerID:(NSString *)drawerID name:(NSString *)name error:(NSError **)error;
- (BOOL)deleteDrawerID:(NSString *)drawerID error:(NSError **)error;
- (BOOL)importURLs:(NSArray<NSURL *> *)urls drawerID:(NSString *)drawerID error:(NSError **)error;
- (BOOL)moveItem:(NSURL *)itemURL toDirectory:(NSURL *)directory error:(NSError **)error;
- (NSURL *)saveDrawerID:(NSString *)drawerID inDirectory:(NSURL *)directory error:(NSError **)error;
- (void)updateDrawerID:(NSString *)drawerID edge:(NSString *)edge position:(CGFloat)position;
- (void)updateDrawerID:(NSString *)drawerID locked:(BOOL)locked;
// ai coding: 声明按吸附方向保存用户自定义抽屉长度的接口 2026/09/17: 09:01
- (void)updateDrawerID:(NSString *)drawerID length:(CGFloat)length forEdge:(NSString *)edge;
@end

@implementation SDDrawerStore {
    NSMutableArray<NSMutableDictionary *> *_mutableDrawers;
    NSURL *_rootURL;
    NSURL *_drawersURL;
    NSURL *_metadataURL;
}

- (instancetype)initWithError:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *storageOverride = NSProcessInfo.processInfo.environment[@"SIDEDRAWER_STORAGE_ROOT"];
    if (storageOverride.length > 0) {
        _rootURL = [NSURL fileURLWithPath:storageOverride isDirectory:YES];
    } else {
        NSURL *supportURL = [manager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        if (!supportURL) supportURL = manager.temporaryDirectory;
        _rootURL = [supportURL URLByAppendingPathComponent:@"SideDrawer" isDirectory:YES];
    }
    _drawersURL = [_rootURL URLByAppendingPathComponent:@"Drawers" isDirectory:YES];
    _metadataURL = [_rootURL URLByAppendingPathComponent:@"drawers.json"];
    if (![manager createDirectoryAtURL:_drawersURL withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    [self loadMetadata];
    if (_mutableDrawers.count == 0 && ![self createDefaultDrawer:error]) return nil;
    return self;
}

- (NSArray<NSDictionary *> *)drawers { return [_mutableDrawers copy]; }

- (NSDictionary *)drawerForID:(NSString *)drawerID {
    for (NSDictionary *drawer in _mutableDrawers) {
        if ([drawer[@"id"] isEqualToString:drawerID]) return drawer;
    }
    return nil;
}

- (NSMutableDictionary *)mutableDrawerForID:(NSString *)drawerID {
    for (NSMutableDictionary *drawer in _mutableDrawers) {
        if ([drawer[@"id"] isEqualToString:drawerID]) return drawer;
    }
    return nil;
}

- (NSArray<NSURL *> *)itemsForDrawerID:(NSString *)drawerID {
    NSDictionary *drawer = [self drawerForID:drawerID];
    if (!drawer) return @[];
    NSArray<NSURL *> *urls = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[self directoryForDrawer:drawer]
                                                          includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                               error:nil] ?: @[];
    return [urls sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        NSNumber *leftDirectory = nil;
        NSNumber *rightDirectory = nil;
        [left getResourceValue:&leftDirectory forKey:NSURLIsDirectoryKey error:nil];
        [right getResourceValue:&rightDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (leftDirectory.boolValue != rightDirectory.boolValue) {
            return leftDirectory.boolValue ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left.lastPathComponent localizedStandardCompare:right.lastPathComponent];
    }];
}

- (NSString *)addDrawer:(NSError **)error {
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (NSDictionary *drawer in _mutableDrawers) [names addObject:drawer[@"name"]];
    NSInteger number = _mutableDrawers.count + 1;
    NSString *name = [NSString stringWithFormat:@"新抽屉 %ld", (long)number];
    while ([names containsObject:name]) {
        number += 1;
        name = [NSString stringWithFormat:@"新抽屉 %ld", (long)number];
    }
    NSInteger slot = _mutableDrawers.count % 5;
    NSString *edge = ((_mutableDrawers.count / 5) % 2 == 0) ? SDEdgeRight : SDEdgeLeft;
    // ai coding: 为新抽屉保存横向和纵向的独立长度，便于用户手动调整后保持尺寸 2026/09/17: 08:40
    NSMutableDictionary *drawer = [@{
        @"id": NSUUID.UUID.UUIDString,
        @"name": name,
        @"edge": edge,
        @"position": @(0.05 + slot * 0.2),
        @"locked": @NO,
        @"horizontalLength": @580,
        @"verticalLength": @430
    } mutableCopy];
    [_mutableDrawers addObject:drawer];
    if (![NSFileManager.defaultManager createDirectoryAtURL:[self directoryForDrawer:drawer]
                                withIntermediateDirectories:YES attributes:nil error:error]) {
        [_mutableDrawers removeLastObject];
        return nil;
    }
    if (![self writeMetadata:error]) return nil;
    return drawer[@"id"];
}

- (BOOL)renameDrawerID:(NSString *)drawerID name:(NSString *)rawName error:(NSError **)error {
    NSString *name = [self sanitizedName:rawName];
    if (name.length == 0) {
        if (error) *error = SDError(1, @"抽屉名称不能为空。");
        return NO;
    }
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) {
        if (error) *error = SDError(2, @"找不到这个抽屉。");
        return NO;
    }
    drawer[@"name"] = name;
    return [self writeMetadata:error];
}

- (BOOL)deleteDrawerID:(NSString *)drawerID error:(NSError **)error {
    if (_mutableDrawers.count <= 1) {
        if (error) *error = SDError(3, @"至少需要保留一个抽屉。");
        return NO;
    }
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) return YES;
    if ([self itemsForDrawerID:drawerID].count > 0) {
        if (error) *error = SDError(4, @"抽屉里还有文件，请先拖出或保存为文件夹。");
        return NO;
    }
    if (![NSFileManager.defaultManager removeItemAtURL:[self directoryForDrawer:drawer] error:error]) return NO;
    [_mutableDrawers removeObject:drawer];
    return [self writeMetadata:error];
}

- (BOOL)importURLs:(NSArray<NSURL *> *)urls drawerID:(NSString *)drawerID error:(NSError **)error {
    NSDictionary *drawer = [self drawerForID:drawerID];
    if (!drawer) {
        if (error) *error = SDError(5, @"找不到这个抽屉。");
        return NO;
    }
    NSString *storagePath = _rootURL.URLByStandardizingPath.path;
    NSURL *destinationDirectory = [self directoryForDrawer:drawer];
    for (NSURL *inputURL in urls) {
        NSURL *sourceURL = inputURL.URLByStandardizingPath;
        if ([sourceURL.path hasPrefix:storagePath]) {
            if (error) *error = SDError(6, @"不能把 SideDrawer 自己的存储目录放进抽屉。");
            return NO;
        }
        BOOL accessed = [sourceURL startAccessingSecurityScopedResource];
        NSURL *destination = [self uniqueDestinationForURL:sourceURL inDirectory:destinationDirectory];
        BOOL moved = [NSFileManager.defaultManager moveItemAtURL:sourceURL toURL:destination error:error];
        if (accessed) [sourceURL stopAccessingSecurityScopedResource];
        if (!moved) return NO;
    }
    return YES;
}

- (BOOL)moveItem:(NSURL *)itemURL toDirectory:(NSURL *)directory error:(NSError **)error {
    BOOL accessed = [directory startAccessingSecurityScopedResource];
    NSURL *destination = [self uniqueDestinationForURL:itemURL inDirectory:directory];
    BOOL moved = [NSFileManager.defaultManager moveItemAtURL:itemURL toURL:destination error:error];
    if (accessed) [directory stopAccessingSecurityScopedResource];
    return moved;
}

- (NSURL *)saveDrawerID:(NSString *)drawerID inDirectory:(NSURL *)directory error:(NSError **)error {
    NSDictionary *drawer = [self drawerForID:drawerID];
    if (!drawer) {
        if (error) *error = SDError(7, @"找不到这个抽屉。");
        return nil;
    }
    BOOL accessed = [directory startAccessingSecurityScopedResource];
    NSURL *destinationFolder = [self uniqueFolderNamed:drawer[@"name"] inDirectory:directory];
    NSFileManager *manager = NSFileManager.defaultManager;
    if (![manager createDirectoryAtURL:destinationFolder withIntermediateDirectories:NO attributes:nil error:error]) {
        if (accessed) [directory stopAccessingSecurityScopedResource];
        return nil;
    }
    for (NSURL *itemURL in [self itemsForDrawerID:drawerID]) {
        NSURL *destination = [self uniqueDestinationForURL:itemURL inDirectory:destinationFolder];
        if (![manager moveItemAtURL:itemURL toURL:destination error:error]) {
            if (accessed) [directory stopAccessingSecurityScopedResource];
            return nil;
        }
    }
    if (accessed) [directory stopAccessingSecurityScopedResource];
    return destinationFolder;
}

- (void)updateDrawerID:(NSString *)drawerID edge:(NSString *)edge position:(CGFloat)position {
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) return;
    drawer[@"edge"] = edge;
    drawer[@"position"] = @(MAX(0, MIN(1, position)));
    [self writeMetadata:nil];
}

- (void)updateDrawerID:(NSString *)drawerID locked:(BOOL)locked {
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) return;
    drawer[@"locked"] = @(locked);
    [self writeMetadata:nil];
}

// ai coding: 按吸附方向持久化抽屉长度，切换方向后可恢复各自尺寸 2026/09/17: 08:40
- (void)updateDrawerID:(NSString *)drawerID length:(CGFloat)length forEdge:(NSString *)edge {
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) return;
    drawer[SDEdgeIsHorizontal(edge) ? @"horizontalLength" : @"verticalLength"] = @(length);
    [self writeMetadata:nil];
}

- (void)loadMetadata {
    NSData *data = [NSData dataWithContentsOfURL:_metadataURL];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    _mutableDrawers = [object isKindOfClass:NSArray.class] ? [object mutableCopy] : [NSMutableArray array];
    NSInteger index = 0;
    for (NSMutableDictionary *drawer in _mutableDrawers) {
        if (!drawer[@"edge"]) drawer[@"edge"] = SDEdgeRight;
        if (!drawer[@"position"]) drawer[@"position"] = @(0.05 + (index % 5) * 0.2);
        // ai coding: 为旧版抽屉补齐可调长度字段并保留原有长边尺寸 2026/09/17: 08:40
        if (!drawer[@"locked"]) drawer[@"locked"] = @NO;
        if (!drawer[@"horizontalLength"]) drawer[@"horizontalLength"] = @580;
        if (!drawer[@"verticalLength"]) drawer[@"verticalLength"] = @430;
        [NSFileManager.defaultManager createDirectoryAtURL:[self directoryForDrawer:drawer]
                               withIntermediateDirectories:YES attributes:nil error:nil];
        index += 1;
    }
    [self writeMetadata:nil];
}

- (BOOL)createDefaultDrawer:(NSError **)error {
    // ai coding: 默认抽屉同时初始化横向与纵向长度 2026/09/17: 08:40
    NSMutableDictionary *drawer = [@{
        @"id": NSUUID.UUID.UUIDString,
        @"name": @"收纳箱",
        @"edge": SDEdgeRight,
        @"position": @0.5,
        @"locked": @NO,
        @"horizontalLength": @580,
        @"verticalLength": @430
    } mutableCopy];
    _mutableDrawers = [NSMutableArray arrayWithObject:drawer];
    if (![NSFileManager.defaultManager createDirectoryAtURL:[self directoryForDrawer:drawer]
                                withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    return [self writeMetadata:error];
}

- (BOOL)writeMetadata:(NSError **)error {
    NSData *data = [NSJSONSerialization dataWithJSONObject:_mutableDrawers
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    return data && [data writeToURL:_metadataURL options:NSDataWritingAtomic error:error];
}

- (NSURL *)directoryForDrawer:(NSDictionary *)drawer {
    return [_drawersURL URLByAppendingPathComponent:drawer[@"id"] isDirectory:YES];
}

- (NSURL *)uniqueDestinationForURL:(NSURL *)sourceURL inDirectory:(NSURL *)directory {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *candidate = [directory URLByAppendingPathComponent:sourceURL.lastPathComponent];
    if (![manager fileExistsAtPath:candidate.path]) return candidate;
    NSNumber *isDirectory = nil;
    [sourceURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    NSString *extension = isDirectory.boolValue ? @"" : sourceURL.pathExtension;
    NSString *baseName = extension.length ? sourceURL.URLByDeletingPathExtension.lastPathComponent : sourceURL.lastPathComponent;
    NSInteger index = 2;
    do {
        NSString *name = extension.length
            ? [NSString stringWithFormat:@"%@ %ld.%@", baseName, (long)index, extension]
            : [NSString stringWithFormat:@"%@ %ld", baseName, (long)index];
        candidate = [directory URLByAppendingPathComponent:name isDirectory:isDirectory.boolValue];
        index += 1;
    } while ([manager fileExistsAtPath:candidate.path]);
    return candidate;
}

- (NSURL *)uniqueFolderNamed:(NSString *)rawName inDirectory:(NSURL *)directory {
    NSString *name = [self sanitizedName:rawName];
    NSURL *candidate = [directory URLByAppendingPathComponent:name isDirectory:YES];
    NSInteger index = 2;
    while ([NSFileManager.defaultManager fileExistsAtPath:candidate.path]) {
        candidate = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ %ld", name, (long)index]
                                               isDirectory:YES];
        index += 1;
    }
    return candidate;
}

- (NSString *)sanitizedName:(NSString *)name {
    NSString *clean = [name stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    clean = [clean stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    return [clean stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
@end

@interface SDFlippedView : NSView
@end
@implementation SDFlippedView
- (BOOL)isFlipped { return YES; }
@end

// ai coding: 修正调节方向并移除长度调整时预留的屏幕边缘间距 2026/09/17: 10:38
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
        CGFloat maximum = MAX(545, NSMaxX(visible) - NSMinX(frame));
        frame.size.width = MAX(545, MIN(maximum, _startFrame.size.width + point.x - _startScreenPoint.x));
    } else {
        CGFloat fixedTop = NSMaxY(_startFrame);
        CGFloat maximum = MAX(315, fixedTop - NSMinY(visible));
        frame.size.height = MAX(315, MIN(maximum, _startFrame.size.height - (point.y - _startScreenPoint.y)));
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

// ai coding: 压缩横向文件项，为右侧纵向操作按钮留出空间 2026/09/17: 09:19
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
    BOOL _draggedAfterMouseDown;
    BOOL _collapseSelectionOnMouseUp;
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
    self.wantsLayer = YES;
    self.layer.cornerRadius = 9;
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
    NSMenuItem *reveal = [[NSMenuItem alloc] initWithTitle:@"在 Finder 中显示" action:@selector(revealItem:) keyEquivalent:@""];
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
    self.layer.cornerRadius = 9;
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

// ai coding: 隐藏三个操作图标并控制名称输入框仅在新建时自动聚焦 2026/09/17: 10:33
@interface SDDrawerContentView : NSVisualEffectView <NSDraggingDestination, NSTextFieldDelegate>
@property(nonatomic, copy) void (^deleteHandler)(NSString *drawerID);
@property(nonatomic, copy) void (^newDrawerHandler)(void);
@property(nonatomic, copy) void (^lockHandler)(BOOL locked);
- (instancetype)initWithStore:(SDDrawerStore *)store drawerID:(NSString *)drawerID edge:(NSString *)edge;
- (void)setDrawerEdge:(NSString *)edge;
- (void)reloadContent;
- (void)selectAllItems;
- (void)beginRenaming;
// ai coding: 暴露保存和删除所选项目操作供抽屉键盘快捷键调用 2026/09/17: 09:51
- (void)saveDrawerAsFolder;
- (void)deleteSelectedItems;
- (void)updateSelectionForURL:(NSURL *)url toggle:(BOOL)toggle;
- (NSArray<NSURL *> *)draggingURLsForAnchorURL:(NSURL *)anchorURL;
- (BOOL)isURLSelected:(NSURL *)url;
- (void)updateSelectionAppearance;
- (void)setDropTargetActive:(BOOL)active;
@end

@implementation SDDrawerContentView {
    SDDrawerStore *_store;
    NSString *_drawerID;
    NSString *_edge;
    NSTextField *_nameField;
    NSTextField *_countLabel;
    NSStackView *_itemStack;
    NSButton *_lockButton;
    BOOL _locked;
    NSSize _lastMaskSize;
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
    self.layer.cornerRadius = 18;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 0.5;
    self.layer.borderColor = [NSColor.whiteColor colorWithAlphaComponent:0.24].CGColor;
    self.layer.backgroundColor = NSColor.clearColor.CGColor;
    [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    [self rebuildLayout];
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)layout {
    [super layout];
    if (NSEqualSizes(_lastMaskSize, self.bounds.size) || self.bounds.size.width <= 0 || self.bounds.size.height <= 0) return;
    _lastMaskSize = self.bounds.size;
    NSImage *mask = [[NSImage alloc] initWithSize:self.bounds.size];
    [mask lockFocus];
    [NSColor.clearColor setFill];
    NSRectFill(NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height));
    [NSColor.whiteColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height)
                                     xRadius:18
                                     yRadius:18] fill];
    [mask unlockFocus];
    self.maskImage = mask;
}

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
    _countLabel = [NSTextField labelWithString:@"0 项"];
    _countLabel.font = [NSFont systemFontOfSize:9];
    _countLabel.textColor = NSColor.secondaryLabelColor;
    NSStackView *titleRow = [[NSStackView alloc] initWithFrame:NSZeroRect];
    titleRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    titleRow.alignment = NSLayoutAttributeCenterY;
    titleRow.spacing = 3;
    titleRow.translatesAutoresizingMaskIntoConstraints = NO;
    [titleRow addArrangedSubview:_nameField];
    [titleRow addArrangedSubview:_countLabel];
    [_nameField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_countLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_nameField.widthAnchor constraintGreaterThanOrEqualToConstant:horizontal ? 62 : 20].active = YES;
    [self addSubview:titleRow];

    _lockButton = [self iconButton:_locked ? @"pin.fill" : @"pin"
                              help:_locked ? @"取消固定" : @"固定抽屉"
                            action:@selector(toggleLocked:)];
    _lockButton.contentTintColor = _locked ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
    _lockButton.translatesAutoresizingMaskIntoConstraints = NO;
    _lockButton.image = SDRotatedPinSymbol(_locked);
    [self addSubview:_lockButton];

    // ai coding: 在抽屉顶部增加删除当前收纳盒的关闭按钮 2026/09/17: 10:40
    NSButton *closeButton = [self iconButton:@"xmark.circle.fill"
                                       help:@"删除当前收纳盒"
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
        [NSLayoutConstraint activateConstraints:@[
            [_itemStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_itemStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_itemStack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:7],
            [_itemStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-14],
            [resizeHandle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [resizeHandle.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [resizeHandle.widthAnchor constraintEqualToConstant:9],
            [resizeHandle.heightAnchor constraintEqualToConstant:34]
        ]];
    } else {
        // ai coding: 将左右吸附抽屉的长度调节柄放到底部水平居中 2026/09/17: 10:36
        [NSLayoutConstraint activateConstraints:@[
            [_itemStack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_itemStack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_itemStack.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:28],
            [_itemStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-14],
            [resizeHandle.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [resizeHandle.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [resizeHandle.widthAnchor constraintEqualToConstant:34],
            [resizeHandle.heightAnchor constraintEqualToConstant:9]
        ]];
    }

    _dropOverlay = [[NSView alloc] initWithFrame:NSZeroRect];
    _dropOverlay.wantsLayer = YES;
    _dropOverlay.layer.cornerRadius = 15;
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
    _countLabel.stringValue = [NSString stringWithFormat:@"%ld 项", (long)items.count];
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

- (void)createDrawer:(id)sender { if (self.newDrawerHandler) self.newDrawerHandler(); }

- (void)toggleLocked:(id)sender {
    _locked = !_locked;
    [_store updateDrawerID:_drawerID locked:_locked];
    // ai coding: 切换固定状态时继续使用 -45° 旋转图钉 2026/09/17: 09:19
    _lockButton.image = SDRotatedPinSymbol(_locked);
    _lockButton.toolTip = _locked ? @"取消固定" : @"固定抽屉";
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

// ai coding: 为激活的抽屉统一处理快捷键并让 Command+A 始终优先全选文件 2026/09/17: 09:54
@interface SDDrawerPanel : NSPanel
@property(nonatomic, copy) void (^selectAllHandler)(void);
@property(nonatomic, copy) void (^createDrawerHandler)(void);
@property(nonatomic, copy) void (^saveDrawerHandler)(void);
@property(nonatomic, copy) void (^deleteSelectedHandler)(void);
@end
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

@interface SDDrawerPanelController : NSObject <NSWindowDelegate>
@property(nonatomic, readonly) NSString *drawerID;
@property(nonatomic, readonly) SDDrawerPanel *panel;
@property(nonatomic, copy) void (^deleteHandler)(NSString *drawerID);
@property(nonatomic, copy) void (^newDrawerHandler)(void);
// ai coding: 暴露抽屉激活状态和菜单操作接口 2026/09/17: 10:47
@property(nonatomic, copy) void (^activationHandler)(NSString *drawerID);
- (instancetype)initWithStore:(SDDrawerStore *)store drawerID:(NSString *)drawerID;
- (void)show;
- (void)reloadContent;
- (void)beginRenaming;
- (void)selectAllItems;
- (void)saveDrawerAsFolder;
- (void)deleteSelectedItems;
- (BOOL)isEditingDrawerName;
@end

@implementation SDDrawerPanelController {
    SDDrawerStore *_store;
    SDDrawerContentView *_contentView;
    NSString *_edge;
    BOOL _adjustingFrame;
}

// ai coding: 抽屉厚度减半，并让自定义长度调节结果按方向持久保存 2026/09/17: 08:40
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
    NSRect frame = _panel.frame;
    NSDictionary<NSString *, NSNumber *> *distances = @{
        SDEdgeLeft: @(fabs(NSMinX(frame) - NSMinX(visible))),
        SDEdgeRight: @(fabs(NSMaxX(visible) - NSMaxX(frame))),
        SDEdgeBottom: @(fabs(NSMinY(frame) - NSMinY(visible))),
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
        CGFloat length = MAX(545, [drawer[@"horizontalLength"] doubleValue]);
        return NSMakeSize(length, 66);
    }
    CGFloat length = MAX(315, [drawer[@"verticalLength"] doubleValue]);
    return NSMakeSize(95, length);
}

// ai coding: 将四向吸附间距改为零，使抽屉紧贴 macOS 可用屏幕边界 2026/09/17: 10:38
- (NSRect)frameForEdge:(NSString *)edge position:(CGFloat)position screen:(NSScreen *)screen {
    NSRect visible = screen.visibleFrame;
    NSSize size = [self sizeForEdge:edge];
    CGFloat inset = 0;
    if (SDEdgeIsHorizontal(edge)) size.width = MIN(size.width, MAX(545, visible.size.width - inset * 2));
    else size.height = MIN(size.height, MAX(315, visible.size.height - inset * 2));
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

// ai coding: 增加可录制任意组合键的原生快捷键输入控件 2026/09/17: 09:19
static NSString * const SDShortcutKeyCodeDefaultsKey = @"MoveShortcutKeyCode";
static NSString * const SDShortcutModifiersDefaultsKey = @"MoveShortcutModifiers";
static NSString * const SDShortcutKeyNameDefaultsKey = @"MoveShortcutKeyName";

static CGEventFlags SDShortcutModifiersFromEvent(NSEventModifierFlags flags) {
    CGEventFlags result = 0;
    if (flags & NSEventModifierFlagCommand) result |= kCGEventFlagMaskCommand;
    if (flags & NSEventModifierFlagOption) result |= kCGEventFlagMaskAlternate;
    if (flags & NSEventModifierFlagControl) result |= kCGEventFlagMaskControl;
    if (flags & NSEventModifierFlagShift) result |= kCGEventFlagMaskShift;
    return result;
}

static NSString *SDShortcutKeyName(NSEvent *event) {
    switch (event.keyCode) {
        case 36: return @"↩";
        case 48: return @"⇥";
        case 49: return @"空格";
        case 51: return @"⌫";
        case 53: return @"⎋";
        case 123: return @"←";
        case 124: return @"→";
        case 125: return @"↓";
        case 126: return @"↑";
        default: break;
    }
    NSString *characters = event.charactersIgnoringModifiers.uppercaseString;
    return characters.length > 0 ? characters : @"";
}

static NSString *SDShortcutDisplayString(CGEventFlags modifiers, NSString *keyName) {
    NSMutableString *display = [NSMutableString string];
    if (modifiers & kCGEventFlagMaskControl) [display appendString:@"⌃"];
    if (modifiers & kCGEventFlagMaskAlternate) [display appendString:@"⌥"];
    if (modifiers & kCGEventFlagMaskShift) [display appendString:@"⇧"];
    if (modifiers & kCGEventFlagMaskCommand) [display appendString:@"⌘"];
    [display appendString:keyName ?: @""];
    return display;
}

@interface SDShortcutRecorderView : NSView
@property(nonatomic, readonly) CGKeyCode recordedKeyCode;
@property(nonatomic, readonly) CGEventFlags recordedModifiers;
@property(nonatomic, readonly) NSString *recordedKeyName;
@property(nonatomic, readonly) BOOL hasValidShortcut;
- (instancetype)initWithKeyCode:(CGKeyCode)keyCode modifiers:(CGEventFlags)modifiers keyName:(NSString *)keyName;
@end

@implementation SDShortcutRecorderView {
    NSTextField *_label;
    CGKeyCode _recordedKeyCode;
    CGEventFlags _recordedModifiers;
    NSString *_recordedKeyName;
    BOOL _hasValidShortcut;
}

- (instancetype)initWithKeyCode:(CGKeyCode)keyCode modifiers:(CGEventFlags)modifiers keyName:(NSString *)keyName {
    self = [super initWithFrame:NSMakeRect(0, 0, 280, 44)];
    if (!self) return nil;
    _recordedKeyCode = keyCode;
    _recordedModifiers = modifiers;
    _recordedKeyName = [keyName copy];
    _hasValidShortcut = keyName.length > 0;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 9;
    self.layer.borderWidth = 1;
    self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.8].CGColor;
    self.layer.backgroundColor = [NSColor.controlBackgroundColor colorWithAlphaComponent:0.55].CGColor;
    _label = [NSTextField labelWithString:SDShortcutDisplayString(modifiers, keyName)];
    _label.font = [NSFont monospacedSystemFontOfSize:17 weight:NSFontWeightSemibold];
    _label.alignment = NSTextAlignmentCenter;
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_label];
    [NSLayoutConstraint activateConstraints:@[
        [_label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
    return self;
}

- (CGKeyCode)recordedKeyCode { return _recordedKeyCode; }
- (CGEventFlags)recordedModifiers { return _recordedModifiers; }
- (NSString *)recordedKeyName { return _recordedKeyName; }
- (BOOL)hasValidShortcut { return _hasValidShortcut; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }

- (BOOL)becomeFirstResponder {
    self.layer.borderColor = NSColor.controlAccentColor.CGColor;
    return YES;
}

- (BOOL)resignFirstResponder {
    self.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.8].CGColor;
    return YES;
}

- (void)mouseDown:(NSEvent *)event { [self.window makeFirstResponder:self]; }
- (void)keyDown:(NSEvent *)event { [self recordEvent:event]; }
- (BOOL)performKeyEquivalent:(NSEvent *)event { return [self recordEvent:event]; }

- (BOOL)recordEvent:(NSEvent *)event {
    CGEventFlags modifiers = SDShortcutModifiersFromEvent(event.modifierFlags);
    CGEventFlags primaryModifiers = modifiers &
        (kCGEventFlagMaskCommand | kCGEventFlagMaskAlternate | kCGEventFlagMaskControl);
    NSString *keyName = SDShortcutKeyName(event);
    if (primaryModifiers == 0 || keyName.length == 0) {
        NSBeep();
        _label.stringValue = @"请包含 ⌘、⌥ 或 ⌃";
        _hasValidShortcut = NO;
        return YES;
    }
    _recordedKeyCode = event.keyCode;
    _recordedModifiers = modifiers;
    _recordedKeyName = [keyName copy];
    _hasValidShortcut = YES;
    _label.stringValue = SDShortcutDisplayString(modifiers, keyName);
    return YES;
}
@end

@interface SDAppDelegate : NSObject <NSApplicationDelegate, NSMenuItemValidation>
- (void)handleGlobalMoveHotKey;
- (BOOL)shouldHandleGlobalMoveHotKey;
- (BOOL)matchesMoveShortcutKeyCode:(CGKeyCode)keyCode modifiers:(CGEventFlags)modifiers;
// ai coding: 声明标准应用菜单和访达定位入口 2026/09/17: 09:06
- (void)configureMainMenu;
- (void)revealApplication:(id)sender;
// ai coding: 声明快捷键录制、展示和多抽屉目标选择入口 2026/09/17: 09:19
- (void)loadMoveShortcut;
- (void)showShortcutConfiguration:(id)sender;
- (void)moveURLs:(NSArray<NSURL *> *)urls toDrawerID:(NSString *)drawerID;
- (void)chooseDrawerAndMoveURLs:(NSArray<NSURL *> *)urls;
@end

// ai coding: 将用户录制的修饰键转换为 Carbon 全局热键格式 2026/09/17: 09:44
static UInt32 SDCarbonModifiersFromCGEventFlags(CGEventFlags flags) {
    UInt32 result = 0;
    if (flags & kCGEventFlagMaskCommand) result |= cmdKey;
    if (flags & kCGEventFlagMaskShift) result |= shiftKey;
    if (flags & kCGEventFlagMaskAlternate) result |= optionKey;
    if (flags & kCGEventFlagMaskControl) result |= controlKey;
    return result;
}

// ai coding: 使用系统原生热键事件触发 Finder 文件移动，不再依赖辅助功能键盘监听 2026/09/17: 09:44
static OSStatus SDGlobalHotKeyHandler(EventHandlerCallRef nextHandler __unused,
                                      EventRef event,
                                      void *userData) {
    EventHotKeyID identifier = {0};
    OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                                        NULL, sizeof(identifier), NULL, &identifier);
    if (status != noErr || identifier.signature != 'SDRW' || identifier.id != 1) {
        return eventNotHandledErr;
    }
    SDAppDelegate *delegate = (__bridge SDAppDelegate *)userData;
    if (![delegate shouldHandleGlobalMoveHotKey]) return eventNotHandledErr;
    [delegate handleGlobalMoveHotKey];
    return noErr;
}

@implementation SDAppDelegate {
    SDDrawerStore *_store;
    NSMutableDictionary<NSString *, SDDrawerPanelController *> *_controllers;
    NSStatusItem *_statusItem;
    NSMenuItem *_shortcutStatusItem;
    NSMenuItem *_shortcutConfigurationItem;
    EventHandlerRef _hotKeyEventHandler;
    EventHotKeyRef _hotKey;
    OSStatus _hotKeyRegistrationStatus;
    CGKeyCode _moveShortcutKeyCode;
    CGEventFlags _moveShortcutModifiers;
    NSString *_moveShortcutKeyName;
    // ai coding: 保存最后激活的收纳盒标识以路由菜单操作 2026/09/17: 10:47
    NSString *_activeDrawerID;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // ai coding: 改为标准 macOS 应用显示程序坞图标，并提供可发现的退出入口 2026/09/17: 09:06
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self loadMoveShortcut];
    [self configureMainMenu];
    NSError *error = nil;
    _store = [[SDDrawerStore alloc] initWithError:&error];
    if (!_store) {
        [[NSAlert alertWithError:error] runModal];
        [NSApp terminate:nil];
        return;
    }
    _controllers = [NSMutableDictionary dictionary];
    [self installGlobalHotKeyHandler];
    [self updateConditionalKeyboardShortcut];
    [self syncPanels];
    [self configureStatusItem];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                       selector:@selector(frontmostApplicationChanged:)
                                                           name:NSWorkspaceDidActivateApplicationNotification
                                                         object:nil];
}

- (void)syncPanels {
    NSMutableSet<NSString *> *activeIDs = [NSMutableSet set];
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *drawer in _store.drawers) {
        NSString *drawerID = drawer[@"id"];
        [activeIDs addObject:drawerID];
        SDDrawerPanelController *controller = _controllers[drawerID];
        if (!controller) {
            controller = [[SDDrawerPanelController alloc] initWithStore:_store drawerID:drawerID];
            controller.deleteHandler = ^(NSString *identifier) { [weakSelf deleteDrawerID:identifier]; };
            controller.newDrawerHandler = ^{ [weakSelf createDrawer:nil]; };
            // ai coding: 记录最后激活的收纳盒，供顶部菜单操作准确定位目标 2026/09/17: 10:47
            controller.activationHandler = ^(NSString *identifier) {
                SDAppDelegate *strongSelf = weakSelf;
                if (strongSelf) strongSelf->_activeDrawerID = [identifier copy];
            };
            _controllers[drawerID] = controller;
        }
        if (!_activeDrawerID) _activeDrawerID = [drawerID copy];
        [controller show];
    }
    for (NSString *drawerID in _controllers.allKeys.copy) {
        if (![activeIDs containsObject:drawerID]) {
            [_controllers[drawerID].panel close];
            [_controllers removeObjectForKey:drawerID];
            if ([_activeDrawerID isEqualToString:drawerID]) _activeDrawerID = nil;
        }
    }
}

// ai coding: 安装 Carbon 热键处理器，并仅在 Finder 位于前台时注册用户快捷键 2026/09/17: 09:44
- (void)installGlobalHotKeyHandler {
    if (_hotKeyEventHandler) return;
    EventTypeSpec eventType = {kEventClassKeyboard, kEventHotKeyPressed};
    _hotKeyRegistrationStatus = InstallApplicationEventHandler(&SDGlobalHotKeyHandler,
                                                                1,
                                                                &eventType,
                                                                (__bridge void *)self,
                                                                &_hotKeyEventHandler);
}

- (void)updateConditionalKeyboardShortcut {
    if (_hotKey) {
        UnregisterEventHotKey(_hotKey);
        _hotKey = NULL;
    }
    if (![self shouldHandleGlobalMoveHotKey]) {
        [self refreshShortcutStatusItem];
        return;
    }
    EventHotKeyID identifier = {'SDRW', 1};
    _hotKeyRegistrationStatus = RegisterEventHotKey(_moveShortcutKeyCode,
                                                     SDCarbonModifiersFromCGEventFlags(_moveShortcutModifiers),
                                                     identifier,
                                                     GetApplicationEventTarget(),
                                                     0,
                                                     &_hotKey);
    [self refreshShortcutStatusItem];
}

- (void)frontmostApplicationChanged:(NSNotification *)notification {
    [self updateConditionalKeyboardShortcut];
}

- (BOOL)shouldHandleGlobalMoveHotKey {
    BOOL finderIsFrontmost = [NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqualToString:@"com.apple.finder"];
    return _store.drawers.count > 0 && finderIsFrontmost;
}

// ai coding: 读取、匹配并保存用户自定义的 Finder 移动快捷键 2026/09/17: 09:19
- (void)loadMoveShortcut {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:SDShortcutKeyCodeDefaultsKey] == nil) {
        _moveShortcutKeyCode = 46;
        _moveShortcutModifiers = kCGEventFlagMaskCommand;
        _moveShortcutKeyName = @"M";
        return;
    }
    _moveShortcutKeyCode = (CGKeyCode)[defaults integerForKey:SDShortcutKeyCodeDefaultsKey];
    _moveShortcutModifiers = (CGEventFlags)[defaults integerForKey:SDShortcutModifiersDefaultsKey];
    _moveShortcutKeyName = [defaults stringForKey:SDShortcutKeyNameDefaultsKey] ?: @"M";
}

- (BOOL)matchesMoveShortcutKeyCode:(CGKeyCode)keyCode modifiers:(CGEventFlags)modifiers {
    CGEventFlags relevant = modifiers &
        (kCGEventFlagMaskCommand | kCGEventFlagMaskShift | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate);
    return keyCode == _moveShortcutKeyCode && relevant == _moveShortcutModifiers;
}

- (void)showShortcutConfiguration:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    SDShortcutRecorderView *recorder = [[SDShortcutRecorderView alloc] initWithKeyCode:_moveShortcutKeyCode
                                                                             modifiers:_moveShortcutModifiers
                                                                                keyName:_moveShortcutKeyName];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"设置移动到收纳箱的快捷键";
    alert.informativeText = @"点击输入框，然后按下包含 ⌘、⌥ 或 ⌃ 的组合键。默认快捷键是 ⌘M。";
    alert.accessoryView = recorder;
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    [alert addButtonWithTitle:@"恢复 ⌘M"];
    alert.window.initialFirstResponder = recorder;
    dispatch_async(dispatch_get_main_queue(), ^{ [alert.window makeFirstResponder:recorder]; });
    NSModalResponse response = [alert runModal];
    if (response == NSAlertSecondButtonReturn) return;
    if (response == NSAlertThirdButtonReturn) {
        _moveShortcutKeyCode = 46;
        _moveShortcutModifiers = kCGEventFlagMaskCommand;
        _moveShortcutKeyName = @"M";
    } else {
        if (!recorder.hasValidShortcut) {
            [self showError:SDError(8, @"快捷键需要包含 Command、Option 或 Control。") window:nil];
            return;
        }
        _moveShortcutKeyCode = recorder.recordedKeyCode;
        _moveShortcutModifiers = recorder.recordedModifiers;
        _moveShortcutKeyName = recorder.recordedKeyName;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:_moveShortcutKeyCode forKey:SDShortcutKeyCodeDefaultsKey];
    [defaults setInteger:(NSInteger)_moveShortcutModifiers forKey:SDShortcutModifiersDefaultsKey];
    [defaults setObject:_moveShortcutKeyName forKey:SDShortcutKeyNameDefaultsKey];
    [self updateConditionalKeyboardShortcut];
}

- (void)configureStatusItem {
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.image = [NSImage imageWithSystemSymbolName:@"rectangle.stack.fill" accessibilityDescription:@"SideDrawer"];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"SideDrawer"];
    // ai coding: 在状态菜单显示常用收纳盒操作及对应的原生快捷键 2026/09/17: 10:47
    NSMenuItem *newDrawer = [[NSMenuItem alloc] initWithTitle:@"新建收纳盒" action:@selector(createDrawer:) keyEquivalent:@"n"];
    newDrawer.target = self;
    [menu addItem:newDrawer];
    NSMenuItem *saveDrawer = [[NSMenuItem alloc] initWithTitle:@"保存当前收纳盒为文件夹…"
                                                       action:@selector(saveCurrentDrawer:)
                                                keyEquivalent:@"s"];
    saveDrawer.target = self;
    [menu addItem:saveDrawer];
    NSMenuItem *selectAll = [[NSMenuItem alloc] initWithTitle:@"全选当前收纳盒文件"
                                                      action:@selector(selectAllCurrentDrawer:)
                                               keyEquivalent:@"a"];
    selectAll.target = self;
    [menu addItem:selectAll];
    unichar deleteCharacter = NSDeleteCharacter;
    NSString *deleteKey = [NSString stringWithCharacters:&deleteCharacter length:1];
    NSMenuItem *deleteItems = [[NSMenuItem alloc] initWithTitle:@"将所选项目移到废纸篓"
                                                        action:@selector(deleteSelectedInCurrentDrawer:)
                                                 keyEquivalent:deleteKey];
    deleteItems.keyEquivalentModifierMask = 0;
    deleteItems.target = self;
    [menu addItem:deleteItems];
    [menu addItem:NSMenuItem.separatorItem];
    // ai coding: 在菜单栏展示免辅助功能权限的原生全局快捷键状态 2026/09/17: 09:44
    _shortcutConfigurationItem = [[NSMenuItem alloc] initWithTitle:@"设置移动快捷键…"
                                                            action:@selector(showShortcutConfiguration:)
                                                     keyEquivalent:@""];
    _shortcutConfigurationItem.target = self;
    [menu addItem:_shortcutConfigurationItem];
    _shortcutStatusItem = [[NSMenuItem alloc] initWithTitle:@"快捷键已就绪" action:nil keyEquivalent:@""];
    [menu addItem:_shortcutStatusItem];
    [self refreshShortcutStatusItem];
    NSMenuItem *showAll = [[NSMenuItem alloc] initWithTitle:@"显示全部抽屉" action:@selector(showAll:) keyEquivalent:@""];
    showAll.target = self;
    [menu addItem:showAll];
    NSMenuItem *hideAll = [[NSMenuItem alloc] initWithTitle:@"隐藏全部抽屉" action:@selector(hideAll:) keyEquivalent:@""];
    hideAll.target = self;
    [menu addItem:hideAll];
    NSMenuItem *reveal = [[NSMenuItem alloc] initWithTitle:@"在访达中显示 SideDrawer"
                                                    action:@selector(revealApplication:)
                                             keyEquivalent:@""];
    reveal.target = self;
    [menu addItem:reveal];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出 SideDrawer" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
    _statusItem.menu = menu;
}

// ai coding: 在标准菜单增加带快捷键标识的新建、保存、全选和删除操作 2026/09/17: 10:47
- (void)configureMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *applicationItem = [[NSMenuItem alloc] initWithTitle:@"SideDrawer" action:nil keyEquivalent:@""];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"SideDrawer"];
    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"关于 SideDrawer"
                                                   action:@selector(orderFrontStandardAboutPanel:)
                                            keyEquivalent:@""];
    about.target = NSApp;
    [applicationMenu addItem:about];
    NSMenuItem *shortcut = [[NSMenuItem alloc] initWithTitle:@"设置移动快捷键…"
                                                      action:@selector(showShortcutConfiguration:)
                                               keyEquivalent:@""];
    shortcut.target = self;
    [applicationMenu addItem:shortcut];
    NSMenuItem *reveal = [[NSMenuItem alloc] initWithTitle:@"在访达中显示 SideDrawer"
                                                    action:@selector(revealApplication:)
                                             keyEquivalent:@""];
    reveal.target = self;
    [applicationMenu addItem:reveal];
    [applicationMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出 SideDrawer"
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];
    quit.target = NSApp;
    [applicationMenu addItem:quit];
    applicationItem.submenu = applicationMenu;
    [mainMenu addItem:applicationItem];

    NSMenuItem *drawerMenuItem = [[NSMenuItem alloc] initWithTitle:@"收纳盒" action:nil keyEquivalent:@""];
    NSMenu *drawerMenu = [[NSMenu alloc] initWithTitle:@"收纳盒"];
    NSMenuItem *newDrawer = [[NSMenuItem alloc] initWithTitle:@"新建收纳盒"
                                                      action:@selector(createDrawer:)
                                               keyEquivalent:@"n"];
    newDrawer.target = self;
    [drawerMenu addItem:newDrawer];
    NSMenuItem *saveDrawer = [[NSMenuItem alloc] initWithTitle:@"保存当前收纳盒为文件夹…"
                                                       action:@selector(saveCurrentDrawer:)
                                                keyEquivalent:@"s"];
    saveDrawer.target = self;
    [drawerMenu addItem:saveDrawer];
    [drawerMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *selectAll = [[NSMenuItem alloc] initWithTitle:@"全选当前收纳盒文件"
                                                      action:@selector(selectAllCurrentDrawer:)
                                               keyEquivalent:@"a"];
    selectAll.target = self;
    [drawerMenu addItem:selectAll];
    unichar deleteCharacter = NSDeleteCharacter;
    NSString *deleteKey = [NSString stringWithCharacters:&deleteCharacter length:1];
    NSMenuItem *deleteItems = [[NSMenuItem alloc] initWithTitle:@"将所选项目移到废纸篓"
                                                        action:@selector(deleteSelectedInCurrentDrawer:)
                                                 keyEquivalent:deleteKey];
    deleteItems.keyEquivalentModifierMask = 0;
    deleteItems.target = self;
    [drawerMenu addItem:deleteItems];
    drawerMenuItem.submenu = drawerMenu;
    [mainMenu addItem:drawerMenuItem];
    NSApp.mainMenu = mainMenu;
}

// ai coding: 将菜单命令路由到最后激活的收纳盒并避免编辑名称时误删文件 2026/09/17: 10:47
- (SDDrawerPanelController *)activeDrawerController {
    SDDrawerPanelController *controller = _activeDrawerID ? _controllers[_activeDrawerID] : nil;
    if (controller) return controller;
    for (SDDrawerPanelController *candidate in _controllers.allValues) {
        if (candidate.panel.isKeyWindow) return candidate;
    }
    return _controllers.allValues.firstObject;
}

- (void)selectAllCurrentDrawer:(id)sender {
    SDDrawerPanelController *controller = [self activeDrawerController];
    [controller show];
    [controller selectAllItems];
}

- (void)saveCurrentDrawer:(id)sender {
    SDDrawerPanelController *controller = [self activeDrawerController];
    [controller show];
    [controller saveDrawerAsFolder];
}

- (void)deleteSelectedInCurrentDrawer:(id)sender {
    [[self activeDrawerController] deleteSelectedItems];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (action == @selector(selectAllCurrentDrawer:) || action == @selector(saveCurrentDrawer:) ||
        action == @selector(deleteSelectedInCurrentDrawer:)) {
        SDDrawerPanelController *controller = [self activeDrawerController];
        if (!controller) return NO;
        if (action == @selector(deleteSelectedInCurrentDrawer:) && [controller isEditingDrawerName]) return NO;
    }
    return YES;
}

- (void)revealApplication:(id)sender {
    [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[NSBundle.mainBundle.bundleURL]];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows {
    if (!hasVisibleWindows) [self showAll:nil];
    return YES;
}

- (void)createDrawer:(id)sender {
    NSError *error = nil;
    // ai coding: 记录新抽屉标识，并在创建完成后直接聚焦其名称输入框 2026/09/17: 10:33
    NSString *drawerID = [_store addDrawer:&error];
    if (!drawerID) {
        [self showError:error window:nil];
        return;
    }
    [self syncPanels];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_controllers[drawerID] beginRenaming];
    });
}

- (void)deleteDrawerID:(NSString *)drawerID {
    NSError *error = nil;
    if (![_store deleteDrawerID:drawerID error:&error]) {
        [self showError:error window:_controllers[drawerID].panel];
        return;
    }
    [self syncPanels];
}

// ai coding: 显示原生快捷键注册结果并在冲突时提供重新设置入口 2026/09/17: 09:44
- (void)refreshShortcutStatusItem {
    NSString *shortcut = SDShortcutDisplayString(_moveShortcutModifiers, _moveShortcutKeyName);
    if (_shortcutConfigurationItem) {
        _shortcutConfigurationItem.title = [NSString stringWithFormat:@"设置移动快捷键…（%@）", shortcut];
    }
    if (!_shortcutStatusItem) return;
    BOOL failed = _hotKeyRegistrationStatus != noErr;
    _shortcutStatusItem.title = failed
        ? @"快捷键注册失败，请更换组合键…"
        : [NSString stringWithFormat:@"快捷键已就绪：%@", shortcut];
    _shortcutStatusItem.target = failed ? self : nil;
    _shortcutStatusItem.action = failed ? @selector(showShortcutConfiguration:) : nil;
    _shortcutStatusItem.enabled = failed;
}

- (void)handleGlobalMoveHotKey {
    if (_store.drawers.count == 0) return;
    NSString *source = @"tell application \"Finder\"\n"
                        "set selectedItems to selection\n"
                        "set posixPaths to {}\n"
                        "repeat with selectedItem in selectedItems\n"
                        "set end of posixPaths to POSIX path of (selectedItem as alias)\n"
                        "end repeat\n"
                        "return posixPaths\n"
                        "end tell";
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
    NSDictionary *scriptError = nil;
    NSAppleEventDescriptor *result = [script executeAndReturnError:&scriptError];
    if (!result) {
        NSString *message = scriptError[NSAppleScriptErrorMessage] ?: @"无法读取 Finder 当前选中的项目。";
        NSError *error = SDError([scriptError[NSAppleScriptErrorNumber] integerValue], message);
        [self showError:error window:_controllers.allValues.firstObject.panel];
        return;
    }
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSInteger index = 1; index <= result.numberOfItems; index++) {
        NSString *path = [result descriptorAtIndex:index].stringValue;
        if (path.length > 0) [urls addObject:[NSURL fileURLWithPath:path]];
    }
    if (urls.count == 0) {
        NSBeep();
        return;
    }
    if (_store.drawers.count == 1) {
        [self moveURLs:urls toDrawerID:_store.drawers.firstObject[@"id"]];
    } else {
        [self chooseDrawerAndMoveURLs:urls];
    }
}

// ai coding: 多个收纳箱时弹出目标选择面板，单个目标沿用直接移动流程 2026/09/17: 09:19
- (void)chooseDrawerAndMoveURLs:(NSArray<NSURL *> *)urls {
    [NSApp activateIgnoringOtherApps:YES];
    NSPopUpButton *drawerPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 28) pullsDown:NO];
    for (NSDictionary *drawer in _store.drawers) {
        [drawerPicker addItemWithTitle:drawer[@"name"] ?: @"未命名收纳箱"];
        drawerPicker.lastItem.representedObject = drawer[@"id"];
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"选择收纳箱";
    alert.informativeText = [NSString stringWithFormat:@"将 Finder 中选中的 %ld 个项目移动到：", (long)urls.count];
    alert.accessoryView = drawerPicker;
    [alert addButtonWithTitle:@"移动"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *drawerID = drawerPicker.selectedItem.representedObject;
    if (drawerID.length > 0) [self moveURLs:urls toDrawerID:drawerID];
}

- (void)moveURLs:(NSArray<NSURL *> *)urls toDrawerID:(NSString *)drawerID {
    NSError *error = nil;
    if (![_store importURLs:urls drawerID:drawerID error:&error]) {
        [self showError:error window:_controllers[drawerID].panel];
        return;
    }
    [_controllers[drawerID] reloadContent];
}

- (void)showAll:(id)sender { for (SDDrawerPanelController *controller in _controllers.allValues) [controller show]; }
- (void)hideAll:(id)sender { for (SDDrawerPanelController *controller in _controllers.allValues) [controller.panel orderOut:nil]; }
- (void)quit:(id)sender { [NSApp terminate:nil]; }

- (void)applicationWillTerminate:(NSNotification *)notification {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    // ai coding: 退出时释放 Carbon 全局热键和事件处理器 2026/09/17: 09:44
    if (_hotKey) UnregisterEventHotKey(_hotKey);
    if (_hotKeyEventHandler) RemoveEventHandler(_hotKeyEventHandler);
}

- (void)showError:(NSError *)error window:(NSWindow *)window {
    if (!error) return;
    NSAlert *alert = [NSAlert alertWithError:error];
    if (window) [alert beginSheetModalForWindow:window completionHandler:nil];
    else [alert runModal];
}
@end

// ai coding: 标记应用入口的系统保留参数，保持严格编译零警告 2026/09/16: 20:50
int main(int argc __unused, const char *argv[] __unused) {
    @autoreleasepool {
        NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
        if ([environment[@"SIDEDRAWER_SELF_TEST"] isEqualToString:@"1"]) {
            NSError *error = nil;
            SDDrawerStore *store = [[SDDrawerStore alloc] initWithError:&error];
            NSString *drawerID = store.drawers.firstObject[@"id"];
            NSURL *source = [NSURL fileURLWithPath:environment[@"SIDEDRAWER_TEST_SOURCE"]];
            NSURL *exportDirectory = [NSURL fileURLWithPath:environment[@"SIDEDRAWER_TEST_EXPORT"] isDirectory:YES];
            BOOL imported = store && [store importURLs:@[source] drawerID:drawerID error:&error];
            BOOL sourceRemoved = ![NSFileManager.defaultManager fileExistsAtPath:source.path];
            NSURL *folder = imported ? [store saveDrawerID:drawerID inDirectory:exportDirectory error:&error] : nil;
            NSURL *exportedFile = [folder URLByAppendingPathComponent:source.lastPathComponent];
            BOOL exported = folder && [NSFileManager.defaultManager fileExistsAtPath:exportedFile.path];
            BOOL drawerEmpty = [store itemsForDrawerID:drawerID].count == 0;
            if (imported && sourceRemoved && exported && drawerEmpty) {
                fprintf(stdout, "SIDEDRAWER_SELF_TEST_OK\n");
                return 0;
            }
            fprintf(stderr, "SIDEDRAWER_SELF_TEST_FAILED: %s\n", error.localizedDescription.UTF8String ?: "unknown");
            return 1;
        }
        NSApplication *application = NSApplication.sharedApplication;
        SDAppDelegate *delegate = [[SDAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
