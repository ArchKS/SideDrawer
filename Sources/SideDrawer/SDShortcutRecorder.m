// ai coding: 拆分出快捷键格式化函数与录制控件实现 2026/09/17: 15:34
#import "SDShortcutRecorder.h"

NSString * const SDShortcutKeyCodeDefaultsKey = @"MoveShortcutKeyCode";
NSString * const SDShortcutModifiersDefaultsKey = @"MoveShortcutModifiers";
NSString * const SDShortcutKeyNameDefaultsKey = @"MoveShortcutKeyName";

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

NSString *SDShortcutDisplayString(CGEventFlags modifiers, NSString *keyName) {
    NSMutableString *display = [NSMutableString string];
    if (modifiers & kCGEventFlagMaskControl) [display appendString:@"⌃"];
    if (modifiers & kCGEventFlagMaskAlternate) [display appendString:@"⌥"];
    if (modifiers & kCGEventFlagMaskShift) [display appendString:@"⇧"];
    if (modifiers & kCGEventFlagMaskCommand) [display appendString:@"⌘"];
    [display appendString:keyName ?: @""];
    return display;
}

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
    // ai coding: 快捷键录制控件改用连续圆角曲线 2026/09/17: 16:40
    self.layer.cornerRadius = 9;
    self.layer.cornerCurve = kCACornerCurveContinuous;
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
