// ai coding: 拆分出应用委托实现，保持原有行为 2026/09/17: 15:34
#import "SDAppDelegate.h"
#import "SDDrawerChoicePanel.h"
#import "SDDrawerPanel.h"
#import "SDDrawerStore.h"
#import "SDShortcutRecorder.h"
#import <Carbon/Carbon.h>

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
    // ai coding: 保存快捷键选择面板和目标映射以支持点击即移动 2026/09/17: 11:05
    SDDrawerChoicePanel *_drawerChoicePanel;
    NSArray<NSString *> *_drawerChoiceIDs;
    NSString *_selectedDrawerChoiceID;
    // ai coding: 记录状态菜单构建状态与写盘失败提示的节流标记 2026/09/17: 15:42
    BOOL _buildingStatusMenu;
    BOOL _metadataFailureAlertVisible;
    NSTimeInterval _lastMetadataFailureAlertAt;
}

- (void)configureApplicationIcon {
    // ai coding: 启动时显式加载 bundle 图标，确保 Dock 和快捷键面板都能显示 2026/09/17: 11:44
    NSString *iconPath = [NSBundle.mainBundle pathForResource:@"SideDrawer" ofType:@"icns"];
    if (iconPath.length == 0) return;
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
    if (icon) NSApp.applicationIconImage = icon;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    // ai coding: 启用标准 Dock 图标并在启动时主动刷新应用图标 2026/09/17: 11:44
    [self configureApplicationIcon];
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
    // ai coding: 订阅收纳盒元数据写盘失败通知并立即提示用户 2026/09/17: 15:42
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(metadataWriteDidFail:)
                                              name:SDMetadataWriteFailedNotification
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
    // ai coding: 快捷键设置弹窗标题去掉收纳箱说法，与菜单文案一致  2026/09/17: 16:06
    alert.messageText = @"设置移动快捷键";
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

// ai coding: 用共享菜单表集中定义收纳盒与全局操作，消除状态菜单和主菜单的文案漂移 2026/09/17: 15:42
- (NSArray<NSDictionary *> *)drawerMenuItems {
    unichar deleteCharacter = NSDeleteCharacter;
    NSString *deleteKey = [NSString stringWithCharacters:&deleteCharacter length:1];
    return @[
        @{@"title": SDMenuTitleNewDrawer, @"action": @"createDrawer:", @"key": @"n", @"modifiers": @(NSEventModifierFlagCommand)},
        @{@"title": SDMenuTitleBatchNewDrawer, @"action": @"batchCreateDrawers:"},
        @{@"title": SDMenuTitleClearEmptyDrawers, @"action": @"deleteEmptyDrawers:"},
        @{@"title": SDMenuTitleSetDimension, @"action": @"setCurrentDrawerDimension:"},
        @{@"title": SDMenuTitlePaste, @"action": @"pasteCurrentDrawer:", @"key": @"v", @"modifiers": @(NSEventModifierFlagCommand)},
        @{@"title": SDMenuTitleSaveDrawer, @"action": @"saveCurrentDrawer:", @"key": @"s", @"modifiers": @(NSEventModifierFlagCommand)},
        @{@"title": SDMenuTitleSelectAll, @"action": @"selectAllCurrentDrawer:", @"key": @"a", @"modifiers": @(NSEventModifierFlagCommand)},
        @{@"title": SDMenuTitleDeleteSelected, @"action": @"deleteSelectedInCurrentDrawer:", @"key": deleteKey, @"modifiers": @0}
    ];
}

// ai coding: 集中定义菜单栏状态菜单独有的全局操作，避免进入收纳盒子菜单 2026/09/17: 15:42
- (NSArray<NSDictionary *> *)applicationMenuItems {
    return @[
        @{@"title": SDMenuTitleShortcutConfiguration, @"action": @"showShortcutConfiguration:", @"identifier": @"shortcut-configuration"},
        @{@"title": SDMenuTitleShowAll, @"action": @"showAll:"},
        @{@"title": SDMenuTitleHideAll, @"action": @"hideAll:"},
        @{@"title": SDMenuTitleRevealApplication, @"action": @"revealApplication:"},
        @{@"title": SDMenuTitleQuit, @"action": @"quit:", @"key": @"q", @"modifiers": @(NSEventModifierFlagCommand), @"terminate": @YES}
    ];
}

// ai coding: 按菜单项描述构建菜单项并统一挂载目标与修饰键 2026/09/17: 15:42
- (void)addMenuItems:(NSArray<NSDictionary *> *)items toMenu:(NSMenu *)menu {
    for (NSDictionary *item in items) {
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:item[@"title"]
                                                          action:NSSelectorFromString(item[@"action"])
                                                   keyEquivalent:item[@"key"] ?: @""];
        if (item[@"modifiers"]) menuItem.keyEquivalentModifierMask = [item[@"modifiers"] unsignedIntegerValue];
        menuItem.target = [item[@"terminate"] boolValue] ? NSApp : self;
        [menu addItem:menuItem];
        if (_buildingStatusMenu && [item[@"identifier"] isEqualToString:@"shortcut-configuration"]) {
            _shortcutConfigurationItem = menuItem;
        }
    }
}

// ai coding: 用共享菜单表构建状态菜单，并在快捷键设置项后插入快捷键状态行 2026/09/17: 15:42
- (void)configureStatusItem {
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.image = [NSImage imageWithSystemSymbolName:@"rectangle.stack.fill" accessibilityDescription:@"SideDrawer"];
    // ai coding: 标记当前正在构建状态菜单，保证快捷键设置项只绑定状态菜单实例 2026/09/17: 15:42
    _buildingStatusMenu = YES;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"SideDrawer"];
    [self addMenuItems:[self drawerMenuItems] toMenu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    [self addMenuItems:[self applicationMenuItems] toMenu:menu];
    _buildingStatusMenu = NO;
    _shortcutStatusItem = [[NSMenuItem alloc] initWithTitle:SDMenuTitleShortcutReady action:nil keyEquivalent:@""];
    NSUInteger insertIndex = _shortcutConfigurationItem ? [menu indexOfItem:_shortcutConfigurationItem] + 1 : menu.numberOfItems;
    [menu insertItem:_shortcutStatusItem atIndex:insertIndex];
    [self refreshShortcutStatusItem];
    _statusItem.menu = menu;
}

// ai coding: 主菜单收纳盒子菜单与状态菜单共用同一条目来源，标题和快捷键保持一致 2026/09/17: 15:42
- (void)configureMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *applicationItem = [[NSMenuItem alloc] initWithTitle:@"SideDrawer" action:nil keyEquivalent:@""];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"SideDrawer"];
    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:SDMenuTitleAbout
                                                   action:@selector(orderFrontStandardAboutPanel:)
                                            keyEquivalent:@""];
    about.target = NSApp;
    [applicationMenu addItem:about];
    NSMenuItem *shortcut = [[NSMenuItem alloc] initWithTitle:SDMenuTitleShortcutConfiguration
                                                      action:@selector(showShortcutConfiguration:)
                                               keyEquivalent:@""];
    shortcut.target = self;
    [applicationMenu addItem:shortcut];
    NSMenuItem *reveal = [[NSMenuItem alloc] initWithTitle:SDMenuTitleRevealApplication
                                                    action:@selector(revealApplication:)
                                             keyEquivalent:@""];
    reveal.target = self;
    [applicationMenu addItem:reveal];
    [applicationMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:SDMenuTitleQuit
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];
    quit.target = NSApp;
    [applicationMenu addItem:quit];
    applicationItem.submenu = applicationMenu;
    [mainMenu addItem:applicationItem];

    NSMenuItem *drawerMenuItem = [[NSMenuItem alloc] initWithTitle:SDMenuTitleDrawerMenu action:nil keyEquivalent:@""];
    NSMenu *drawerMenu = [[NSMenu alloc] initWithTitle:SDMenuTitleDrawerMenu];
    [self addMenuItems:[self drawerMenuItems] toMenu:drawerMenu];
    drawerMenuItem.submenu = drawerMenu;
    [mainMenu addItem:drawerMenuItem];
    NSApp.mainMenu = mainMenu;
}
// ai coding: 元数据写盘失败时弹出一次提示并说明受影响内容，避免静默丢失布局 2026/09/17: 15:42
- (void)metadataWriteDidFail:(NSNotification *)notification {
    NSString *reason = [notification.userInfo[@"error"] localizedDescription] ?: @"磁盘写入被拒绝或空间不足。";
    // ai coding: 写盘线程不固定，统一切回主线程弹窗，避免后台线程触碰界面 2026/09/17: 15:56
    dispatch_async(dispatch_get_main_queue(), ^{
        // ai coding: 用 60 秒节流代替一次性标记，写入持续失败或再次失败时仍能提示 2026/09/17: 15:46
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        if (self->_metadataFailureAlertVisible || now - self->_lastMetadataFailureAlertAt < 60) return;
        self->_lastMetadataFailureAlertAt = now;
        self->_metadataFailureAlertVisible = YES;
        NSAlert *alert = [[NSAlert alloc] init];
    // ai coding: 写盘失败提示与正文统一使用“抽屉”  2026/09/17: 16:06
        alert.messageText = @"抽屉设置没有保存到磁盘";
        alert.informativeText = [NSString stringWithFormat:
            @"抽屉名称、位置或尺寸的改动未能写入 %@。\n原因：%@\n请检查磁盘空间或文件权限后重试。",
            @"~/Library/Application Support/SideDrawer/drawers.json", reason];
        [alert addButtonWithTitle:@"好"];
        NSWindow *host = self->_controllers.allValues.firstObject.panel;
        if (!host) {
            self->_metadataFailureAlertVisible = NO;
            [alert runModal];
            return;
        }
        [alert beginSheetModalForWindow:host completionHandler:^(NSModalResponse response __unused) {
            self->_metadataFailureAlertVisible = NO;
        }];
    });
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

// ai coding: 弹出数字输入框并按吸附方向设置当前抽屉的高度或宽度 2026/09/17: 14:10
- (void)setCurrentDrawerDimension:(id)sender {
    SDDrawerPanelController *controller = [self activeDrawerController];
    if (!controller) return;
    [controller show];
    NSDictionary *drawer = [_store drawerForID:controller.drawerID];
    NSString *edge = drawer[@"edge"] ?: SDEdgeRight;
    BOOL horizontal = SDEdgeIsHorizontal(edge);
    NSString *dimensionName = horizontal ? @"高度" : @"宽度";
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 210, 26)];
    input.stringValue = [NSString stringWithFormat:@"%.0f", [controller currentDrawerThickness]];
    input.alignment = NSTextAlignmentRight;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"设置当前抽屉%@", dimensionName];
    alert.informativeText = @"单位：像素。上下贴边输入高度，左右贴边输入宽度。";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"应用"];
    [alert addButtonWithTitle:@"取消"];
    alert.window.initialFirstResponder = input;
    dispatch_async(dispatch_get_main_queue(), ^{ [alert.window makeFirstResponder:input]; });
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    CGFloat value = input.doubleValue;
    if (!isfinite(value) || value <= 0) {
        [self showError:SDError(13, @"请输入大于 0 的数字。") window:controller.panel];
        return;
    }
    [controller setDrawerThickness:value];
}

// ai coding: 将菜单中的粘贴命令路由到当前激活的收纳盒 2026/09/17: 14:10
- (void)pasteCurrentDrawer:(id)sender {
    SDDrawerPanelController *controller = [self activeDrawerController];
    if (!controller) return;
    [controller show];
    [controller pasteFromPasteboard];
}

// ai coding: 执行菜单中的一键清空空收纳盒并同步剩余窗口 2026/09/17: 11:30
- (void)deleteEmptyDrawers:(id)sender {
    NSError *error = nil;
    NSUInteger removedCount = [_store deleteEmptyDrawers:&error];
    if (removedCount > 0) [self syncPanels];
    if (error) [self showError:error window:nil];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (action == @selector(deleteEmptyDrawers:)) return [_store hasDeletableEmptyDrawers];
    if (action == @selector(setCurrentDrawerDimension:) || action == @selector(pasteCurrentDrawer:)) {
        SDDrawerPanelController *controller = [self activeDrawerController];
        if (!controller) return NO;
        if (action == @selector(pasteCurrentDrawer:) && [controller isEditingDrawerName]) return NO;
    }
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
    SDDrawerPanelController *sourceController = [self activeDrawerController];
    // ai coding: 单个新建复制当前激活抽屉尺寸，并在完成后直接聚焦名称 2026/09/17: 11:14
    NSString *drawerID = [_store addDrawerWithName:nil
                    copyingDimensionsFromDrawerID:sourceController.drawerID
                                             error:&error];
    if (!drawerID) {
        [self showError:error window:nil];
        return;
    }
    [self syncPanels];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_controllers[drawerID] beginRenaming];
    });
}

// ai coding: 将中英文逗号分隔的输入清理为非空收纳盒名称列表 2026/09/17: 11:14
- (NSArray<NSString *> *)drawerNamesFromBatchInput:(NSString *)input {
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",，"];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *component in [input componentsSeparatedByCharactersInSet:separators]) {
        NSString *name = [component stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (name.length > 0) [names addObject:name];
    }
    return names;
}

// ai coding: 为批量创建计算上、下、左、右循环分布及同边均匀间距 2026/09/17: 11:23
- (NSArray<NSDictionary *> *)batchPlacementsForCount:(NSUInteger)count {
    NSArray<NSString *> *edges = @[SDEdgeTop, SDEdgeBottom, SDEdgeLeft, SDEdgeRight];
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < count; index++) {
        NSString *edge = edges[index % edges.count];
        counts[edge] = @([counts[edge] unsignedIntegerValue] + 1);
    }
    NSMutableDictionary<NSString *, NSNumber *> *used = [NSMutableDictionary dictionary];
    NSMutableArray<NSDictionary *> *placements = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        NSString *edge = edges[index % edges.count];
        NSUInteger edgeCount = [counts[edge] unsignedIntegerValue];
        NSUInteger edgeIndex = [used[edge] unsignedIntegerValue];
        CGFloat position = edgeCount <= 1 ? 0.5 : (CGFloat)edgeIndex / (CGFloat)(edgeCount - 1);
        [placements addObject:@{@"edge": edge, @"position": @(position)}];
        used[edge] = @(edgeIndex + 1);
    }
    return placements;
}

// ai coding: 批量创建后覆盖默认位置，使新收纳盒立即散布在屏幕四边 2026/09/17: 11:26
- (void)batchCreateDrawers:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 26)];
    input.placeholderString = @"例如：a,b,c";
    NSAlert *alert = [[NSAlert alloc] init];
    // ai coding: 批量新建弹窗与错误提示统一使用“抽屉”  2026/09/17: 16:06
    alert.messageText = @"批量新建抽屉";
    alert.informativeText = @"输入名称并用逗号分隔；中文逗号和英文逗号效果相同。";
    alert.accessoryView = input;
    [alert addButtonWithTitle:@"新建"];
    [alert addButtonWithTitle:@"取消"];
    alert.window.initialFirstResponder = input;
    dispatch_async(dispatch_get_main_queue(), ^{ [alert.window makeFirstResponder:input]; });
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSArray<NSString *> *names = [self drawerNamesFromBatchInput:input.stringValue];
    if (names.count == 0) {
        [self showError:SDError(10, @"请至少输入一个抽屉名称。") window:nil];
        return;
    }
    NSString *sourceDrawerID = [self activeDrawerController].drawerID;
    NSMutableArray<NSString *> *createdDrawerIDs = [NSMutableArray arrayWithCapacity:names.count];
    NSArray<NSDictionary *> *placements = [self batchPlacementsForCount:names.count];
    NSError *error = nil;
    for (NSUInteger index = 0; index < names.count; index++) {
        NSString *name = names[index];
        NSString *drawerID = [_store addDrawerWithName:name
                        copyingDimensionsFromDrawerID:sourceDrawerID
                                                 error:&error];
        if (!drawerID) break;
        NSDictionary *placement = placements[index];
        [_store updateDrawerID:drawerID edge:placement[@"edge"] position:[placement[@"position"] doubleValue]];
        [createdDrawerIDs addObject:drawerID];
    }
    if (createdDrawerIDs.count > 0) {
        _activeDrawerID = createdDrawerIDs.lastObject;
        [self syncPanels];
    }
    if (error) [self showError:error window:nil];
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
    // ai coding: 状态菜单不再把快捷键拼进设置项标题，避免与下方状态行重复且和主菜单标题不一致  2026/09/17: 16:11
    if (_shortcutConfigurationItem) {
        _shortcutConfigurationItem.title = SDMenuTitleShortcutConfiguration;
    }
    if (!_shortcutStatusItem) return;
    BOOL failed = _hotKeyRegistrationStatus != noErr;
    _shortcutStatusItem.title = failed
        ? @"快捷键注册失败，请更换组合键…"
        : [NSString stringWithFormat:@"%@：%@", SDMenuTitleShortcutReady, shortcut];
    _shortcutStatusItem.target = failed ? self : nil;
    _shortcutStatusItem.action = failed ? @selector(showShortcutConfiguration:) : nil;
    _shortcutStatusItem.enabled = failed;
}

// ai coding: 快捷键先完成文件移动，再异步刷新 Finder 并选中相邻项目 2026/09/17: 13:22
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
    // ai coding: 访达读取失败提示统一使用系统中文译名“访达”  2026/09/17: 16:06
        NSString *message = scriptError[NSAppleScriptErrorMessage] ?: @"无法读取访达中当前选中的项目。";
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
    NSArray<NSDictionary *> *selectionSnapshot = [self finderSelectionSnapshotForURLs:urls];
    BOOL moved = NO;
    if (_store.drawers.count == 1) {
        moved = [self moveURLs:urls toDrawerID:_store.drawers.firstObject[@"id"]];
    } else {
        moved = [self chooseDrawerAndMoveURLs:urls];
    }
    if (!moved) return;
    // ai coding: 移动成功后立即刷新访达前窗口，让原位置的文件即时消失 2026/09/17: 15:42
    SDRefreshFrontFinderWindowAsync();
    NSArray<NSDictionary *> *movedSelectionSnapshot = [selectionSnapshot copy];
    // ai coding: 与刷新脚本共用同一串行队列，保证先刷新原位置再定位相邻项目 2026/09/17: 15:54
    dispatch_async(SDFinderScriptQueue(), ^{
        @autoreleasepool {
            NSString *neighborPath = [self finderNeighborPathForSelectionSnapshot:movedSelectionSnapshot];
            if (neighborPath.length == 0) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self selectFinderItemAtPath:neighborPath];
            });
        }
    });
}

// ai coding: 多个收纳盒选择目标后返回移动结果以便定位相邻 Finder 项目 2026/09/17: 11:51
- (BOOL)chooseDrawerAndMoveURLs:(NSArray<NSURL *> *)urls {
    [NSApp activateIgnoringOtherApps:YES];
    _selectedDrawerChoiceID = nil;
    _drawerChoicePanel = [self drawerChoicePanelForDrawers:_store.drawers itemCount:urls.count];
    [_drawerChoicePanel center];
    [_drawerChoicePanel makeKeyAndOrderFront:nil];
    NSModalResponse response = [NSApp runModalForWindow:_drawerChoicePanel];
    [_drawerChoicePanel orderOut:nil];
    NSString *drawerID = [_selectedDrawerChoiceID copy];
    _drawerChoicePanel = nil;
    _drawerChoiceIDs = nil;
    _selectedDrawerChoiceID = nil;
    if (response != NSModalResponseOK || drawerID.length == 0) return NO;
    return [self moveURLs:urls toDrawerID:drawerID];
}

// ai coding: 在移动前只读取本地文件属性快照，避免等待 Finder 排序脚本后才开始移动 2026/09/17: 13:22
- (NSArray<NSDictionary *> *)finderSelectionSnapshotForURLs:(NSArray<NSURL *> *)urls {
    NSArray<NSURLResourceKey> *keys = @[
        NSURLNameKey, NSURLIsDirectoryKey, NSURLFileSizeKey,
        NSURLContentModificationDateKey, NSURLCreationDateKey,
        NSURLLocalizedTypeDescriptionKey
    ];
    NSMutableArray<NSDictionary *> *snapshots = [NSMutableArray arrayWithCapacity:urls.count];
    for (NSURL *url in urls) {
        NSURL *standardURL = url.URLByStandardizingPath;
        NSDictionary<NSURLResourceKey, id> *values = [standardURL resourceValuesForKeys:keys error:nil];
        NSString *path = standardURL.path;
        NSString *name = values[NSURLNameKey] ?: standardURL.lastPathComponent ?: @"";
        BOOL isDirectory = [values[NSURLIsDirectoryKey] boolValue];
        NSString *kind = values[NSURLLocalizedTypeDescriptionKey];
        if (kind.length == 0) kind = isDirectory ? @"文件夹" : (standardURL.pathExtension.length > 0 ? standardURL.pathExtension : @"文件");
        [snapshots addObject:@{
            @"path": path ?: @"",
            @"directory": standardURL.URLByDeletingLastPathComponent.path ?: @"",
            @"name": name,
            @"kind": kind,
            @"size": values[NSURLFileSizeKey] ?: @0,
            @"modificationDate": values[NSURLContentModificationDateKey] ?: [NSDate distantPast],
            @"creationDate": values[NSURLCreationDateKey] ?: [NSDate distantPast]
        }];
    }
    return snapshots;
}

// ai coding: 移动后在后台刷新 Finder 并按当前视图规则计算下一个或上一个项目 2026/09/17: 13:22
- (NSString *)finderNeighborPathForSelectionSnapshot:(NSArray<NSDictionary *> *)snapshots {
    if (snapshots.count == 0) return @"";
    NSString *sourceDirectoryPath = snapshots.firstObject[@"directory"];
    if (sourceDirectoryPath.length == 0) return @"";
    for (NSDictionary *snapshot in snapshots) {
        if (![snapshot[@"directory"] isEqualToString:sourceDirectoryPath]) return @"";
    }
    NSString *sortSource = @"tell application \"Finder\"\n"
                            "set sortKey to \"name\"\n"
                            "set reversedOrder to false\n"
                            "try\n"
                            "set currentWindow to front Finder window\n"
                            "try\n"
                            "update every item of currentWindow\n"
                            "end try\n"
                            "set currentView to current view of currentWindow\n"
                            "if currentView is list view then\n"
                            "set sortColumnName to name of sort column of list view options of currentWindow as text\n"
                            "if sortColumnName is \"modification date column\" then set sortKey to \"modificationDate\"\n"
                            "if sortColumnName is \"creation date column\" then set sortKey to \"creationDate\"\n"
                            "if sortColumnName is \"size column\" then set sortKey to \"size\"\n"
                            "if sortColumnName is \"kind column\" then set sortKey to \"kind\"\n"
                            "if (sort direction of sort column of list view options of currentWindow) is reversed then set reversedOrder to true\n"
                            "else if currentView is icon view then\n"
                            "set arrangementMode to arrangement of icon view options of currentWindow\n"
                            "if arrangementMode is arranged by modification date then set sortKey to \"modificationDate\"\n"
                            "if arrangementMode is arranged by creation date then set sortKey to \"creationDate\"\n"
                            "if arrangementMode is arranged by size then set sortKey to \"size\"\n"
                            "if arrangementMode is arranged by kind then set sortKey to \"kind\"\n"
                            "end if\n"
                            "end try\n"
                            "return sortKey & \"|\" & (reversedOrder as text)\n"
                            "end tell";
    NSAppleScript *sortScript = [[NSAppleScript alloc] initWithSource:sortSource];
    NSAppleEventDescriptor *sortResult = [sortScript executeAndReturnError:nil];
    NSArray<NSString *> *sortParts = [sortResult.stringValue componentsSeparatedByString:@"|"];
    NSString *sortKey = sortParts.firstObject.length > 0 ? sortParts.firstObject : @"name";
    BOOL reversedOrder = sortParts.count > 1 && [sortParts[1] boolValue];
    NSURL *directoryURL = [NSURL fileURLWithPath:sourceDirectoryPath isDirectory:YES];
    NSArray<NSURLResourceKey> *keys = @[
        NSURLNameKey, NSURLIsDirectoryKey, NSURLFileSizeKey,
        NSURLContentModificationDateKey, NSURLCreationDateKey,
        NSURLLocalizedTypeDescriptionKey
    ];
    NSArray<NSURL *> *directoryURLs = [NSFileManager.defaultManager
        contentsOfDirectoryAtURL:directoryURL
        includingPropertiesForKeys:keys
        options:NSDirectoryEnumerationSkipsHiddenFiles
        error:nil];
    if (directoryURLs.count == 0) return @"";
    NSMutableArray<NSDictionary *> *records = [[self finderSelectionSnapshotForURLs:directoryURLs] mutableCopy];
    [records addObjectsFromArray:snapshots];
    [records sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSComparisonResult result = NSOrderedSame;
        if ([sortKey isEqualToString:@"size"]) {
            unsigned long long leftSize = [left[@"size"] unsignedLongLongValue];
            unsigned long long rightSize = [right[@"size"] unsignedLongLongValue];
            result = leftSize < rightSize ? NSOrderedAscending : (leftSize > rightSize ? NSOrderedDescending : NSOrderedSame);
        } else if ([sortKey isEqualToString:@"modificationDate"] || [sortKey isEqualToString:@"creationDate"]) {
            result = [left[sortKey] compare:right[sortKey]];
        } else {
            result = [left[sortKey] localizedStandardCompare:right[sortKey]];
        }
        if (result == NSOrderedSame && ![sortKey isEqualToString:@"name"]) {
            result = [left[@"name"] localizedStandardCompare:right[@"name"]];
        }
        if (result == NSOrderedSame) result = [left[@"path"] localizedStandardCompare:right[@"path"]];
        return reversedOrder ? (NSComparisonResult)-result : result;
    }];
    NSSet<NSString *> *selectedPaths = [NSSet setWithArray:[snapshots valueForKey:@"path"]];
    NSUInteger minimumPosition = NSNotFound;
    NSUInteger maximumPosition = NSNotFound;
    for (NSUInteger index = 0; index < records.count; index++) {
        if (![selectedPaths containsObject:records[index][@"path"]]) continue;
        if (minimumPosition == NSNotFound) minimumPosition = index;
        maximumPosition = index;
    }
    if (maximumPosition == NSNotFound) return @"";
    if (maximumPosition + 1 < records.count) return records[maximumPosition + 1][@"path"];
    if (minimumPosition > 0) return records[minimumPosition - 1][@"path"];
    return @"";
}

// ai coding: 移动成功后延迟选中 Finder 相邻项目，避免容器刷新覆盖选择 2026/09/17: 11:51
- (void)selectFinderItemAtPath:(NSString *)path {
    if (path.length == 0) return;
    NSString *escapedPath = SDEscapeAppleScriptString(path);
    NSString *source = [NSString stringWithFormat:
        @"tell application \"Finder\"\n"
         "set targetItem to POSIX file \"%@\" as alias\n"
         "set selection to {targetItem}\n"
         "end tell", escapedPath];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
        [script executeAndReturnError:nil];
    });
}

// ai coding: 将快捷键目标面板改为最多六行的自适应多列网格，一次展示全部抽屉 2026/09/20: 09:54
- (SDDrawerChoicePanel *)drawerChoicePanelForDrawers:(NSArray<NSDictionary *> *)drawers
                                           itemCount:(NSInteger)itemCount {
    CGFloat contentInset = 12;
    CGFloat columnWidth = 144;
    CGFloat columnGap = 8;
    CGFloat rowHeight = 40;
    CGFloat rowGap = 6;
    NSUInteger maximumRowCount = 6;
    NSUInteger columnCount = MAX((NSUInteger)1,
                                 (drawers.count + maximumRowCount - 1) / maximumRowCount);
    NSUInteger rowCount = drawers.count == 0 ? 0 : (drawers.count + columnCount - 1) / columnCount;
    CGFloat gridWidth = columnCount * columnWidth + (columnCount - 1) * columnGap;
    CGFloat gridHeight = rowCount * rowHeight + (rowCount > 0 ? (rowCount - 1) * rowGap : 0);
    CGFloat panelWidth = gridWidth + contentInset * 2;
    CGFloat cancelHeight = 36;
    CGFloat headerHeight = 146;
    CGFloat listBottom = contentInset + cancelHeight + 10;
    CGFloat headerBottom = listBottom + gridHeight + 14;
    CGFloat panelHeight = headerBottom + headerHeight + contentInset;

    SDDrawerChoicePanel *panel = [[SDDrawerChoicePanel alloc]
        initWithContentRect:NSMakeRect(0, 0, panelWidth, panelHeight)
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = YES;
    panel.level = NSFloatingWindowLevel;
    panel.hidesOnDeactivate = NO;
    panel.animationBehavior = NSWindowAnimationBehaviorUtilityWindow;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSVisualEffectView *background = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, panelWidth, panelHeight)];
    background.material = NSVisualEffectMaterialPopover;
    background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    background.state = NSVisualEffectStateActive;
    background.wantsLayer = YES;
    // ai coding: 选择抽屉面板同样改用连续圆角曲线 2026/09/17: 16:40
    background.layer.cornerRadius = 20;
    background.layer.cornerCurve = kCACornerCurveContinuous;
    background.layer.masksToBounds = YES;
    panel.contentView = background;

    NSImageView *iconView = [[NSImageView alloc]
        initWithFrame:NSMakeRect((panelWidth - 42) / 2, headerBottom + 100, 42, 42)];
    iconView.image = NSApp.applicationIconImage ?: [NSImage imageNamed:NSImageNameApplicationIcon];
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [background addSubview:iconView];

    // ai coding: 多抽屉选择面板标题与说明统一使用“抽屉”和“访达”  2026/09/17: 16:06
    NSTextField *titleLabel = [NSTextField labelWithString:@"选择抽屉"];
    titleLabel.frame = NSMakeRect(contentInset, headerBottom + 69, gridWidth, 24);
    titleLabel.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    titleLabel.textColor = NSColor.labelColor;
    titleLabel.alignment = NSTextAlignmentCenter;
    [background addSubview:titleLabel];

    NSTextField *descriptionLabel = [NSTextField wrappingLabelWithString:
        [NSString stringWithFormat:@"点击目标，将访达中选中的 %ld 个项目立即移动过去：", (long)itemCount]];
    descriptionLabel.frame = NSMakeRect(contentInset, headerBottom + 2, gridWidth, 60);
    descriptionLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    descriptionLabel.textColor = NSColor.secondaryLabelColor;
    descriptionLabel.alignment = NSTextAlignmentCenter;
    descriptionLabel.maximumNumberOfLines = 4;
    [background addSubview:descriptionLabel];

    SDFlippedView *grid = [[SDFlippedView alloc]
        initWithFrame:NSMakeRect(contentInset, listBottom, gridWidth, MAX(rowHeight, gridHeight))];
    NSMutableArray<NSString *> *drawerIDs = [NSMutableArray arrayWithCapacity:drawers.count];
    NSMutableArray<SDDrawerChoiceButton *> *choiceButtons = [NSMutableArray arrayWithCapacity:drawers.count];
    [drawers enumerateObjectsUsingBlock:^(NSDictionary *drawer, NSUInteger index, BOOL *stop __unused) {
        NSString *drawerID = drawer[@"id"] ?: @"";
        [drawerIDs addObject:drawerID];
        NSString *drawerName = drawer[@"name"] ?: SDTextUntitledDrawer;
        NSString *shortcut = index < 9
            ? [NSString stringWithFormat:@"⌘/⌥+%lu", (unsigned long)index + 1]
            : @"";
        SDDrawerChoiceButton *button = [[SDDrawerChoiceButton alloc] initWithName:drawerName shortcut:shortcut];
        button.target = self;
        button.action = @selector(selectDrawerFromList:);
        button.tag = (NSInteger)index;
        button.toolTip = index < 9
            ? [NSString stringWithFormat:@"⌥%lu 或 ⌘%lu：%@", (unsigned long)index + 1,
                                                        (unsigned long)index + 1, drawerName]
            : drawerName;
        NSUInteger row = index / columnCount;
        NSUInteger column = index % columnCount;
        button.frame = NSMakeRect(column * (columnWidth + columnGap),
                                  row * (rowHeight + rowGap),
                                  columnWidth,
                                  rowHeight);
        [grid addSubview:button];
        [choiceButtons addObject:button];
    }];
    _drawerChoiceIDs = drawerIDs;
    [background addSubview:grid];

    NSButton *cancelButton = [NSButton buttonWithTitle:@"取消" target:self action:@selector(cancelDrawerChoice:)];
    cancelButton.frame = NSMakeRect(contentInset, contentInset, gridWidth, cancelHeight);
    cancelButton.bordered = YES;
    cancelButton.bezelStyle = NSBezelStyleRounded;
    cancelButton.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    cancelButton.contentTintColor = NSColor.labelColor;
    cancelButton.keyEquivalent = @"\e";
    [background addSubview:cancelButton];
    __weak typeof(self) weakSelf = self;
    panel.selectionHandler = ^(NSInteger index) {
        [weakSelf selectDrawerAtIndex:index];
    };
    panel.choiceButtons = choiceButtons;
    panel.choiceColumnCount = columnCount;
    panel.selectedIndex = 0;
    return panel;
}

// ai coding: 统一处理鼠标、回车和数字快捷键选择，并保留 Escape 关闭 2026/09/17: 11:23
- (void)selectDrawerAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_drawerChoiceIDs.count) return;
    _selectedDrawerChoiceID = [_drawerChoiceIDs[(NSUInteger)index] copy];
    if (NSApp.modalWindow) [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)selectDrawerFromList:(NSButton *)sender {
    [self selectDrawerAtIndex:sender.tag];
}

- (void)cancelDrawerChoice:(id)sender {
    [NSApp stopModalWithCode:NSModalResponseCancel];
}

// ai coding: 让文件移动方法返回成功状态，供快捷键完成后选择相邻项目 2026/09/17: 11:51
- (BOOL)moveURLs:(NSArray<NSURL *> *)urls toDrawerID:(NSString *)drawerID {
    NSError *error = nil;
    if (![_store importURLs:urls drawerID:drawerID error:&error]) {
        [self showError:error window:_controllers[drawerID].panel];
        return NO;
    }
    [_controllers[drawerID] reloadContent];
    // ai coding: 抽屉接收文件后也刷新访达，避免外部视图残留已移动的项目 2026/09/17: 15:42
    SDRefreshFrontFinderWindowAsync();
    return YES;
}

- (void)showAll:(id)sender { for (SDDrawerPanelController *controller in _controllers.allValues) [controller show]; }
- (void)hideAll:(id)sender { for (SDDrawerPanelController *controller in _controllers.allValues) [controller.panel orderOut:nil]; }
- (void)quit:(id)sender { [NSApp terminate:nil]; }

- (void)applicationWillTerminate:(NSNotification *)notification {
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [NSNotificationCenter.defaultCenter removeObserver:self];
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
