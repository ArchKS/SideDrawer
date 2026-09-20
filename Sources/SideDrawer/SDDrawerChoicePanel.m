// ai coding: 让抽屉选择面板支持多行多列选项与键盘导航 2026/09/20: 09:54
#import "SDDrawerChoicePanel.h"

@implementation SDDrawerChoiceButton
- (instancetype)initWithName:(NSString *)name shortcut:(NSString *)shortcut {
    self = [super initWithFrame:NSZeroRect];
    if (!self) return nil;
    self.title = @"";
    self.bordered = YES;
    self.bezelStyle = NSBezelStyleRounded;
    self.buttonType = NSButtonTypePushOnPushOff;
    self.refusesFirstResponder = YES;
    _nameLabel = [NSTextField labelWithString:name];
    _nameLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _shortcutLabel = [NSTextField labelWithString:shortcut];
    _shortcutLabel.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    _shortcutLabel.alignment = NSTextAlignmentRight;
    _shortcutLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_nameLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                         forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_shortcutLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                             forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_nameLabel];
    [self addSubview:_shortcutLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_nameLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:9],
        [_nameLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_shortcutLabel.leadingAnchor constant:-5],
        [_shortcutLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_shortcutLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
    [self setKeyboardSelected:NO];
    return self;
}

- (NSView *)hitTest:(NSPoint)point {
    return NSPointInRect(point, self.bounds) ? self : nil;
}

- (void)setKeyboardSelected:(BOOL)selected {
    self.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
    _nameLabel.textColor = selected ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor;
    _shortcutLabel.textColor = selected ? NSColor.alternateSelectedControlTextColor : NSColor.secondaryLabelColor;
}
@end

@implementation SDDrawerChoicePanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }

// ai coding: 更新网格中的键盘选中状态，所有选项常驻显示无需滚动 2026/09/20: 09:54
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (self.choiceButtons.count == 0) {
        _selectedIndex = NSNotFound;
        return;
    }
    _selectedIndex = MAX(0, MIN(selectedIndex, (NSInteger)self.choiceButtons.count - 1));
    [self.choiceButtons enumerateObjectsUsingBlock:^(SDDrawerChoiceButton *button, NSUInteger index, BOOL *stop __unused) {
        [button setKeyboardSelected:index == (NSUInteger)self->_selectedIndex];
    }];
}

// ai coding: 按网格行列处理上下左右键，单列时保持原有上下选择体验 2026/09/20: 09:54
- (BOOL)handleChoiceShortcut:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) return NO;
    NSEventModifierFlags modifiers = event.modifierFlags &
        (NSEventModifierFlagCommand | NSEventModifierFlagOption |
         NSEventModifierFlagControl | NSEventModifierFlagShift);
    NSString *characters = event.charactersIgnoringModifiers;
    if (modifiers == NSEventModifierFlagOption || modifiers == NSEventModifierFlagCommand) {
        if (characters.length != 1) return NO;
        unichar character = [characters characterAtIndex:0];
        if (character < '1' || character > '9') return NO;
        NSInteger index = character - '1';
        if (index >= (NSInteger)self.choiceButtons.count) {
            NSBeep();
            return YES;
        }
        self.selectedIndex = index;
        if (self.selectionHandler) self.selectionHandler(index);
        return YES;
    }
    if (modifiers != 0) return NO;
    NSUInteger columnCount = MAX((NSUInteger)1, self.choiceColumnCount);
    NSInteger currentIndex = _selectedIndex == NSNotFound ? 0 : _selectedIndex;
    NSInteger targetIndex = currentIndex;
    if (event.keyCode == 126) {
        targetIndex -= (NSInteger)columnCount;
    } else if (event.keyCode == 125) {
        targetIndex += (NSInteger)columnCount;
    } else if (event.keyCode == 123) {
        if ((NSUInteger)currentIndex % columnCount > 0) targetIndex -= 1;
    } else if (event.keyCode == 124) {
        if ((NSUInteger)currentIndex % columnCount + 1 < columnCount) targetIndex += 1;
    } else {
        targetIndex = NSNotFound;
    }
    if (targetIndex != NSNotFound) {
        if (targetIndex >= 0 && targetIndex < (NSInteger)self.choiceButtons.count) {
            self.selectedIndex = targetIndex;
        }
        return YES;
    }
    if (event.keyCode == 36 || event.keyCode == 76 || [characters isEqualToString:@"\r"]) {
        if (_selectedIndex != NSNotFound && self.selectionHandler) self.selectionHandler(_selectedIndex);
        return YES;
    }
    return NO;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if ([self handleChoiceShortcut:event]) return YES;
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    if ([self handleChoiceShortcut:event]) return;
    [super keyDown:event];
}

- (void)sendEvent:(NSEvent *)event {
    if ([self handleChoiceShortcut:event]) return;
    [super sendEvent:event];
}
@end
