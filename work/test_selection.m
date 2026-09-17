// ai coding: 验证方向键选择、快捷键提示、四边散开及既有功能 2026/09/17: 11:23
#define main SideDrawerProductMain
#import "../Sources/SideDrawer/main.m"
#undef main

static NSButton *SDButtonWithHelp(NSView *view, NSString *help) {
    if ([view isKindOfClass:NSButton.class] && [view.toolTip isEqualToString:help]) return (NSButton *)view;
    for (NSView *subview in view.subviews) {
        NSButton *button = SDButtonWithHelp(subview, help);
        if (button) return button;
    }
    return nil;
}

static NSView *SDViewWithToolTip(NSView *view, NSString *toolTip) {
    if ([view.toolTip isEqualToString:toolTip]) return view;
    for (NSView *subview in view.subviews) {
        NSView *match = SDViewWithToolTip(subview, toolTip);
        if (match) return match;
    }
    return nil;
}

static NSMenuItem *SDMenuItemWithTitle(NSMenu *menu, NSString *title) {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.title isEqualToString:title]) return item;
    }
    return nil;
}

static NSInteger SDCountViewsOfClass(NSView *view, Class viewClass) {
    NSInteger count = [view isKindOfClass:viewClass] ? 1 : 0;
    for (NSView *subview in view.subviews) count += SDCountViewsOfClass(subview, viewClass);
    return count;
}

static NSButton *SDButtonWithTitle(NSView *view, NSString *title) {
    if ([view isKindOfClass:NSButton.class] && [((NSButton *)view).title isEqualToString:title]) return (NSButton *)view;
    for (NSView *subview in view.subviews) {
        NSButton *button = SDButtonWithTitle(subview, title);
        if (button) return button;
    }
    return nil;
}

static NSTextField *SDTextFieldContaining(NSView *view, NSString *text) {
    if ([view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue containsString:text]) {
        return (NSTextField *)view;
    }
    for (NSView *subview in view.subviews) {
        NSTextField *field = SDTextFieldContaining(subview, text);
        if (field) return field;
    }
    return nil;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *rootPath = NSProcessInfo.processInfo.environment[@"SIDEDRAWER_SELECTION_TEST_ROOT"];
        if (rootPath.length == 0) return 2;

        NSFileManager *manager = NSFileManager.defaultManager;
        NSURL *rootURL = [NSURL fileURLWithPath:rootPath isDirectory:YES];
        NSURL *sourceURL = [rootURL URLByAppendingPathComponent:@"source" isDirectory:YES];
        [manager createDirectoryAtURL:sourceURL withIntermediateDirectories:YES attributes:nil error:nil];
        NSMutableArray<NSURL *> *inputs = [NSMutableArray array];
        for (NSInteger index = 1; index <= 5; index++) {
            NSURL *url = [sourceURL URLByAppendingPathComponent:[NSString stringWithFormat:@"文件-%ld.txt", (long)index]];
            [@"test" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [inputs addObject:url];
        }
        NSURL *folderURL = [sourceURL URLByAppendingPathComponent:@"目录" isDirectory:YES];
        [manager createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];
        [inputs addObject:folderURL];

        NSError *error = nil;
        SDDrawerStore *store = [[SDDrawerStore alloc] initWithError:&error];
        NSString *drawerID = store.drawers.firstObject[@"id"];
        if (!store || ![store importURLs:inputs drawerID:drawerID error:&error]) return 3;

        SDDrawerContentView *content = [[SDDrawerContentView alloc] initWithStore:store drawerID:drawerID edge:SDEdgeRight];
        content.frame = NSMakeRect(0, 0, 95, 430);
        [content layoutSubtreeIfNeeded];
        NSTextField *nameField = [content valueForKey:@"nameField"];
        BOOL countHidden = SDTextFieldContaining(content, @"6 项") == nil;
        BOOL titleBorderless = !nameField.isBordered && !nameField.isBezeled &&
            nameField.focusRingType == NSFocusRingTypeNone;
        NSButton *pinButton = SDButtonWithHelp(content, @"固定抽屉");
        NSButton *newButton = SDButtonWithHelp(content, @"新建抽屉");
        NSButton *exportButton = SDButtonWithHelp(content, @"保存为文件夹");
        NSButton *deleteButton = SDButtonWithHelp(content, @"删除空抽屉");
        NSButton *closeButton = SDButtonWithHelp(content, @"删除当前收纳盒");
        BOOL plusRemoved = SDButtonWithHelp(content, @"加入文件或目录") == nil;
        NSRect pinRect = [pinButton.superview convertRect:pinButton.frame toView:content];
        NSRect closeRect = [closeButton.superview convertRect:closeButton.frame toView:content];
        NSView *verticalResizeHandle = SDViewWithToolTip(content, @"拖动调整抽屉长度");
        NSRect verticalResizeRect = [verticalResizeHandle.superview convertRect:verticalResizeHandle.frame toView:content];
        BOOL controlsHidden = newButton == nil && exportButton == nil && deleteButton == nil;
        BOOL controlsPlaced = NSMaxY(pinRect) > 405 && NSMaxY(closeRect) > 405 && controlsHidden &&
            NSMinY(verticalResizeRect) <= 0.5 &&
            fabs(NSMidX(verticalResizeRect) - NSMidX(content.bounds)) <= 0.5;
        BOOL pinRotated = [pinButton.image.accessibilityDescription hasPrefix:@"旋转-45度"];
        NSStackView *centeredStack = [content valueForKey:@"itemStack"];
        BOOL itemsCentered = fabs(NSMidX(centeredStack.frame) - NSMidX(content.bounds)) < 2.0;
        SDDrawerContentView *horizontalContent = [[SDDrawerContentView alloc] initWithStore:store drawerID:drawerID edge:SDEdgeTop];
        horizontalContent.frame = NSMakeRect(0, 0, 650, 66);
        [horizontalContent layoutSubtreeIfNeeded];
        NSButton *horizontalNew = SDButtonWithHelp(horizontalContent, @"新建抽屉");
        NSButton *horizontalExport = SDButtonWithHelp(horizontalContent, @"保存为文件夹");
        NSButton *horizontalDelete = SDButtonWithHelp(horizontalContent, @"删除空抽屉");
        NSButton *horizontalClose = SDButtonWithHelp(horizontalContent, @"删除当前收纳盒");
        NSStackView *horizontalItemStack = [horizontalContent valueForKey:@"itemStack"];
        NSView *horizontalResizeHandle = SDViewWithToolTip(horizontalContent, @"拖动调整抽屉长度");
        NSRect horizontalResizeRect = [horizontalResizeHandle.superview convertRect:horizontalResizeHandle.frame
                                                                             toView:horizontalContent];
        BOOL horizontalControlsReady = horizontalNew == nil && horizontalExport == nil && horizontalDelete == nil &&
            horizontalClose != nil &&
            fabs(NSMidX(horizontalItemStack.frame) - NSMidX(horizontalContent.bounds)) < 2.0 &&
            NSMaxX(horizontalResizeRect) >= NSMaxX(horizontalContent.bounds) - 0.5 &&
            fabs(NSMidY(horizontalResizeRect) - NSMidY(horizontalContent.bounds)) < 0.5;
        SDShortcutRecorderView *recorder = [[SDShortcutRecorderView alloc] initWithKeyCode:46
                                                                                modifiers:kCGEventFlagMaskCommand
                                                                                   keyName:@"M"];
        NSEvent *customShortcut = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                   location:NSZeroPoint
                                              modifierFlags:NSEventModifierFlagCommand | NSEventModifierFlagShift
                                                  timestamp:0
                                               windowNumber:0
                                                    context:nil
                                                 characters:@"k"
                                charactersIgnoringModifiers:@"k"
                                                  isARepeat:NO
                                                    keyCode:40];
        BOOL shortcutRecorderReady = [recorder performKeyEquivalent:customShortcut] &&
            recorder.hasValidShortcut && recorder.recordedKeyCode == 40 &&
            recorder.recordedModifiers == (kCGEventFlagMaskCommand | kCGEventFlagMaskShift) &&
            [recorder.recordedKeyName isEqualToString:@"K"];
        SDAppDelegate *shortcutDelegate = [[SDAppDelegate alloc] init];
        [shortcutDelegate setValue:@40 forKey:@"moveShortcutKeyCode"];
        [shortcutDelegate setValue:@(kCGEventFlagMaskCommand | kCGEventFlagMaskShift) forKey:@"moveShortcutModifiers"];
        BOOL shortcutMatchingReady = [shortcutDelegate matchesMoveShortcutKeyCode:40
                                                                         modifiers:kCGEventFlagMaskCommand | kCGEventFlagMaskShift] &&
            ![shortcutDelegate matchesMoveShortcutKeyCode:40 modifiers:kCGEventFlagMaskCommand];
        BOOL carbonModifiersReady = SDCarbonModifiersFromCGEventFlags(kCGEventFlagMaskCommand |
                                                                      kCGEventFlagMaskShift |
                                                                      kCGEventFlagMaskAlternate) ==
            (cmdKey | shiftKey | optionKey);
        [content setDropTargetActive:YES];
        NSView *dropOverlay = [content valueForKey:@"dropOverlay"];
        BOOL dropAnimationReady = !dropOverlay.hidden && [dropOverlay.layer animationForKey:@"dropPulse"] != nil;
        [content setDropTargetActive:NO];
        [content selectAllItems];
        NSSet *selectedPaths = [content valueForKey:@"selectedPaths"];
        BOOL allItemsSelected = selectedPaths.count == 6;
        NSArray<SDFileTileView *> *visibleTiles = [content valueForKey:@"visibleTiles"];
        SDPileView *pileView = [content valueForKey:@"pileView"];
        BOOL visibleSelected = visibleTiles.count == 4;
        for (SDFileTileView *tile in visibleTiles) visibleSelected = visibleSelected && tile.isSelected;
        BOOL pileSelected = pileView.layer.borderWidth == 2.0;
        NSArray<NSURL *> *items = [store itemsForDrawerID:drawerID];
        BOOL batchDragReady = [content draggingURLsForAnchorURL:items.firstObject].count == 6;

        __block NSInteger commandACount = 0;
        __block NSInteger commandNCount = 0;
        __block NSInteger commandSCount = 0;
        __block NSInteger deleteCount = 0;
        SDDrawerPanel *panel = [[SDDrawerPanel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100)
                                                                styleMask:NSWindowStyleMaskBorderless
                                                                  backing:NSBackingStoreBuffered
                                                                    defer:NO];
        panel.selectAllHandler = ^{ commandACount += 1; };
        panel.createDrawerHandler = ^{ commandNCount += 1; };
        panel.saveDrawerHandler = ^{ commandSCount += 1; };
        panel.deleteSelectedHandler = ^{ deleteCount += 1; };
        NSEvent *commandA = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                             location:NSZeroPoint
                                        modifierFlags:NSEventModifierFlagCommand
                                            timestamp:0
                                         windowNumber:panel.windowNumber
                                              context:nil
                                           characters:@"a"
                          charactersIgnoringModifiers:@"a"
                                            isARepeat:NO
                                              keyCode:0];
        NSEvent *commandN = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                             location:NSZeroPoint
                                        modifierFlags:NSEventModifierFlagCommand
                                            timestamp:0
                                         windowNumber:panel.windowNumber
                                              context:nil
                                           characters:@"n"
                          charactersIgnoringModifiers:@"n"
                                            isARepeat:NO
                                              keyCode:45];
        NSEvent *commandS = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                             location:NSZeroPoint
                                        modifierFlags:NSEventModifierFlagCommand
                                            timestamp:0
                                         windowNumber:panel.windowNumber
                                              context:nil
                                           characters:@"s"
                          charactersIgnoringModifiers:@"s"
                                            isARepeat:NO
                                              keyCode:1];
        unichar deleteCharacter = NSDeleteCharacter;
        NSString *deleteCharacters = [NSString stringWithCharacters:&deleteCharacter length:1];
        NSEvent *deleteKey = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                              location:NSZeroPoint
                                         modifierFlags:0
                                             timestamp:0
                                          windowNumber:panel.windowNumber
                                               context:nil
                                            characters:deleteCharacters
                           charactersIgnoringModifiers:deleteCharacters
                                             isARepeat:NO
                                               keyCode:51];
        BOOL shortcutHandled = [panel performKeyEquivalent:commandA] &&
            [panel performKeyEquivalent:commandN] &&
            [panel performKeyEquivalent:commandS] &&
            [panel performKeyEquivalent:deleteKey] &&
            commandACount == 1 && commandNCount == 1 && commandSCount == 1 && deleteCount == 1;
        SDAppDelegate *menuDelegate = [[SDAppDelegate alloc] init];
        [menuDelegate configureMainMenu];
        NSMenu *drawerMenu = SDMenuItemWithTitle(NSApp.mainMenu, @"收纳盒").submenu;
        NSMenuItem *menuNew = SDMenuItemWithTitle(drawerMenu, @"新建收纳盒");
        NSMenuItem *menuBatchNew = SDMenuItemWithTitle(drawerMenu, @"批量新建收纳盒…");
        NSMenuItem *menuSave = SDMenuItemWithTitle(drawerMenu, @"保存当前收纳盒为文件夹…");
        NSMenuItem *menuSelectAll = SDMenuItemWithTitle(drawerMenu, @"全选当前收纳盒文件");
        NSMenuItem *menuDelete = SDMenuItemWithTitle(drawerMenu, @"将所选项目移到废纸篓");
        BOOL menuShortcutsReady = [menuNew.keyEquivalent isEqualToString:@"n"] &&
            [menuSave.keyEquivalent isEqualToString:@"s"] &&
            [menuSelectAll.keyEquivalent isEqualToString:@"a"] &&
            (menuNew.keyEquivalentModifierMask & NSEventModifierFlagCommand) != 0 &&
            (menuSave.keyEquivalentModifierMask & NSEventModifierFlagCommand) != 0 &&
            (menuSelectAll.keyEquivalentModifierMask & NSEventModifierFlagCommand) != 0 &&
            menuDelete.keyEquivalent.length == 1 && menuDelete.keyEquivalentModifierMask == 0 &&
            menuBatchNew != nil;
        NSArray<NSString *> *batchNames = [menuDelegate drawerNamesFromBatchInput:@" a， b,c ,, "];
        BOOL batchNamesReady = [batchNames isEqualToArray:@[@"a", @"b", @"c"]];
        NSArray<NSDictionary *> *batchPlacements = [menuDelegate batchPlacementsForCount:6];
        BOOL batchPlacementReady = batchPlacements.count == 6 &&
            [batchPlacements[0][@"edge"] isEqualToString:SDEdgeTop] &&
            [batchPlacements[1][@"edge"] isEqualToString:SDEdgeBottom] &&
            [batchPlacements[2][@"edge"] isEqualToString:SDEdgeLeft] &&
            [batchPlacements[3][@"edge"] isEqualToString:SDEdgeRight] &&
            [batchPlacements[0][@"position"] doubleValue] == 0 &&
            [batchPlacements[4][@"position"] doubleValue] == 1 &&
            [batchPlacements[1][@"position"] doubleValue] == 0 &&
            [batchPlacements[5][@"position"] doubleValue] == 1;
        [store updateDrawerID:drawerID edge:SDEdgeBottom position:0.4];
        [store updateDrawerID:drawerID length:712 forEdge:SDEdgeTop];
        [store updateDrawerID:drawerID length:528 forEdge:SDEdgeRight];
        NSString *clonedDrawerID = [store addDrawerWithName:@"尺寸副本"
                             copyingDimensionsFromDrawerID:drawerID
                                                      error:&error];
        NSDictionary *clonedDrawer = [store drawerForID:clonedDrawerID];
        BOOL copiedDimensionsReady = [clonedDrawer[@"name"] isEqualToString:@"尺寸副本"] &&
            [clonedDrawer[@"edge"] isEqualToString:SDEdgeBottom] &&
            [clonedDrawer[@"horizontalLength"] doubleValue] == 712 &&
            [clonedDrawer[@"verticalLength"] doubleValue] == 528;
        if (clonedDrawerID) [store deleteDrawerID:clonedDrawerID error:nil];
        [store updateDrawerID:drawerID edge:SDEdgeRight position:0.5];
        NSArray<NSDictionary *> *choiceDrawers = @[
            @{@"id": @"drawer-a", @"name": @"项目 A"},
            @{@"id": @"drawer-b", @"name": @"项目 B"},
            @{@"id": @"drawer-c", @"name": @"项目 C"}
        ];
        SDDrawerChoicePanel *choicePanel = [menuDelegate drawerChoicePanelForDrawers:choiceDrawers itemCount:2];
        NSView *choiceContent = choicePanel.contentView;
        NSEvent *optionTwo = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                              location:NSZeroPoint
                                         modifierFlags:NSEventModifierFlagOption
                                             timestamp:0
                                          windowNumber:choicePanel.windowNumber
                                               context:nil
                                            characters:@"2"
                           charactersIgnoringModifiers:@"2"
                                             isARepeat:NO
                                               keyCode:19];
        NSEvent *commandThree = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                   location:NSZeroPoint
                                              modifierFlags:NSEventModifierFlagCommand
                                                  timestamp:0
                                               windowNumber:choicePanel.windowNumber
                                                    context:nil
                                                 characters:@"3"
                                charactersIgnoringModifiers:@"3"
                                                  isARepeat:NO
                                                    keyCode:20];
        BOOL optionNumberReady = [choicePanel performKeyEquivalent:optionTwo] &&
            [[menuDelegate valueForKey:@"selectedDrawerChoiceID"] isEqualToString:@"drawer-b"];
        [menuDelegate setValue:nil forKey:@"selectedDrawerChoiceID"];
        BOOL commandNumberReady = [choicePanel performKeyEquivalent:commandThree] &&
            [[menuDelegate valueForKey:@"selectedDrawerChoiceID"] isEqualToString:@"drawer-c"];
        unichar downCharacter = NSDownArrowFunctionKey;
        NSString *downCharacters = [NSString stringWithCharacters:&downCharacter length:1];
        NSEvent *downArrow = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                              location:NSZeroPoint
                                         modifierFlags:0
                                             timestamp:0
                                          windowNumber:choicePanel.windowNumber
                                               context:nil
                                            characters:downCharacters
                           charactersIgnoringModifiers:downCharacters
                                             isARepeat:NO
                                               keyCode:125];
        NSEvent *returnKey = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                              location:NSZeroPoint
                                         modifierFlags:0
                                             timestamp:0
                                          windowNumber:choicePanel.windowNumber
                                               context:nil
                                            characters:@"\r"
                           charactersIgnoringModifiers:@"\r"
                                             isARepeat:NO
                                               keyCode:36];
        choicePanel.selectedIndex = 0;
        [menuDelegate setValue:nil forKey:@"selectedDrawerChoiceID"];
        [choicePanel keyDown:downArrow];
        BOOL arrowSelectionReady = choicePanel.selectedIndex == 1;
        [choicePanel keyDown:returnKey];
        BOOL returnSelectionReady =
            [[menuDelegate valueForKey:@"selectedDrawerChoiceID"] isEqualToString:@"drawer-b"];
        BOOL directChoiceListReady = choicePanel.frame.size.width <= 168 &&
            SDCountViewsOfClass(choiceContent, NSButton.class) == 4 &&
            SDCountViewsOfClass(choiceContent, SDDrawerChoiceButton.class) == 3 &&
            SDCountViewsOfClass(choiceContent, NSPopUpButton.class) == 0 &&
            SDCountViewsOfClass(choiceContent, NSImageView.class) == 1 &&
            SDTextFieldContaining(choiceContent, @"项目 A") != nil &&
            SDTextFieldContaining(choiceContent, @"项目 B") != nil &&
            SDTextFieldContaining(choiceContent, @"项目 C") != nil &&
            SDTextFieldContaining(choiceContent, @"⌘/⌥+1") != nil &&
            SDTextFieldContaining(choiceContent, @"⌘/⌥+2") != nil &&
            SDTextFieldContaining(choiceContent, @"⌘/⌥+3") != nil &&
            SDButtonWithTitle(choiceContent, @"取消") != nil &&
            SDButtonWithTitle(choiceContent, @"确定") == nil &&
            SDTextFieldContaining(choiceContent, @"选择收纳箱") != nil &&
            SDTextFieldContaining(choiceContent, @"2 个项目") != nil &&
            optionNumberReady && commandNumberReady && arrowSelectionReady && returnSelectionReady;
        [store updateDrawerID:drawerID length:500 forEdge:SDEdgeRight];
        SDDrawerPanelController *verticalController = [[SDDrawerPanelController alloc] initWithStore:store drawerID:drawerID];
        BOOL verticalSizeReady = verticalController.panel.frame.size.width == 95 &&
            verticalController.panel.frame.size.height == 500;
        [verticalController show];
        NSScreen *verticalScreen = verticalController.panel.screen ?: NSScreen.mainScreen;
        BOOL verticalEdgeSnapReady = !verticalScreen ||
            fabs(NSMaxX(verticalController.panel.frame) - NSMaxX(verticalScreen.visibleFrame)) < 0.5;
        SDDrawerContentView *verticalContent = [verticalController valueForKey:@"contentView"];
        NSTextField *verticalNameField = [verticalContent valueForKey:@"nameField"];
        BOOL normalNameFocusReady = verticalController.panel.firstResponder == verticalContent;
        [verticalContent beginRenaming];
        NSTextView *nameEditor = (NSTextView *)verticalController.panel.firstResponder;
        BOOL newDrawerNameFocusReady = [nameEditor isKindOfClass:NSTextView.class] &&
            nameEditor.isFieldEditor && nameEditor.selectedRange.location == 0 &&
            nameEditor.selectedRange.length == verticalNameField.stringValue.length;
        NSString *typedDrawerName = @"键盘改名测试";
        [nameEditor insertText:typedDrawerName replacementRange:nameEditor.selectedRange];
        [verticalController.panel makeFirstResponder:verticalContent];
        BOOL keyboardRenameReady = [[store drawerForID:drawerID][@"name"] isEqualToString:typedDrawerName];
        [store updateDrawerID:drawerID edge:SDEdgeTop position:0.5];
        [store updateDrawerID:drawerID length:650 forEdge:SDEdgeTop];
        SDDrawerPanelController *horizontalController = [[SDDrawerPanelController alloc] initWithStore:store drawerID:drawerID];
        BOOL horizontalSizeReady = horizontalController.panel.frame.size.width == 650 &&
            horizontalController.panel.frame.size.height == 66;
        [horizontalController show];
        NSScreen *horizontalScreen = horizontalController.panel.screen ?: NSScreen.mainScreen;
        BOOL horizontalEdgeSnapReady = !horizontalScreen ||
            fabs(NSMaxY(horizontalController.panel.frame) - NSMaxY(horizontalScreen.visibleFrame)) < 0.5;

        NSPanel *resizePanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(100, 100, 95, 500)
                                                         styleMask:NSWindowStyleMaskBorderless
                                                           backing:NSBackingStoreBuffered
                                                             defer:NO];
        SDLengthResizeHandleView *dragHandle = [[SDLengthResizeHandleView alloc] initWithFrame:NSMakeRect(79, 0, 16, 9)];
        dragHandle.horizontal = NO;
        resizePanel.contentView = dragHandle;
        NSEvent *resizeMouseDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                                      location:NSMakePoint(8, 4)
                                                 modifierFlags:0
                                                     timestamp:0
                                                  windowNumber:resizePanel.windowNumber
                                                       context:nil
                                                   eventNumber:1
                                                    clickCount:1
                                                      pressure:1];
        NSEvent *resizeMouseDrag = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged
                                                      location:NSMakePoint(8, 54)
                                                 modifierFlags:0
                                                     timestamp:0.1
                                                  windowNumber:resizePanel.windowNumber
                                                       context:nil
                                                   eventNumber:2
                                                    clickCount:1
                                                      pressure:1];
        NSRect resizeStartFrame = resizePanel.frame;
        [dragHandle mouseDown:resizeMouseDown];
        [dragHandle mouseDragged:resizeMouseDrag];
        NSRect resizeEndFrame = resizePanel.frame;
        BOOL verticalResizeDirectionReady = fabs(resizeEndFrame.size.height - (resizeStartFrame.size.height - 50)) < 0.5 &&
            fabs(NSMaxY(resizeEndFrame) - NSMaxY(resizeStartFrame)) < 0.5;

        [manager removeItemAtURL:items.firstObject error:nil];
        [content reloadContent];
        BOOL staleSelectionRemoved = [[content valueForKey:@"selectedPaths"] count] == 5;

        if (allItemsSelected && visibleSelected && pileSelected && batchDragReady && shortcutHandled &&
            staleSelectionRemoved && countHidden && titleBorderless && plusRemoved && controlsPlaced && pinRotated &&
            itemsCentered && horizontalControlsReady && shortcutRecorderReady && shortcutMatchingReady &&
            carbonModifiersReady && dropAnimationReady && verticalSizeReady && horizontalSizeReady &&
            verticalResizeDirectionReady && normalNameFocusReady && newDrawerNameFocusReady &&
            verticalEdgeSnapReady && horizontalEdgeSnapReady && keyboardRenameReady && menuShortcutsReady &&
            directChoiceListReady && batchNamesReady && batchPlacementReady && copiedDimensionsReady) {
            fprintf(stdout, "SIDEDRAWER_SELECTION_TEST_OK\n");
            return 0;
        }
        fprintf(stderr,
                "SIDEDRAWER_SELECTION_TEST_FAILED all=%d visible=%d pile=%d batch=%d shortcut=%d menu=%d directChoice=%d batchNames=%d batchPlacement=%d copiedSize=%d stale=%d countHidden=%d borderless=%d plus=%d controls=%d pin=%d centered=%d horizontalControls=%d recorder=%d matcher=%d carbon=%d normalFocus=%d renameFocus=%d keyboardRename=%d verticalSnap=%d horizontalSnap=%d items=(%.1f,%.1f,%.1f,%.1f) drop=%d vertical=%d horizontal=%d resizeDirection=%d resizeHandle=(%.1f,%.1f,%.1f,%.1f)\n",
                allItemsSelected, visibleSelected, pileSelected, batchDragReady, shortcutHandled, menuShortcutsReady,
                directChoiceListReady, batchNamesReady, batchPlacementReady, copiedDimensionsReady,
                staleSelectionRemoved, countHidden, titleBorderless, plusRemoved, controlsPlaced, pinRotated,
                itemsCentered, horizontalControlsReady, shortcutRecorderReady, shortcutMatchingReady,
                carbonModifiersReady, normalNameFocusReady, newDrawerNameFocusReady, keyboardRenameReady,
                verticalEdgeSnapReady, horizontalEdgeSnapReady,
                horizontalItemStack.frame.origin.x, horizontalItemStack.frame.origin.y,
                horizontalItemStack.frame.size.width, horizontalItemStack.frame.size.height,
                dropAnimationReady,
                verticalSizeReady, horizontalSizeReady, verticalResizeDirectionReady,
                verticalResizeRect.origin.x, verticalResizeRect.origin.y,
                verticalResizeRect.size.width, verticalResizeRect.size.height);
        return 1;
    }
}
