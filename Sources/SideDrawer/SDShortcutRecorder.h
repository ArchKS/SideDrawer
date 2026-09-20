// ai coding: 拆分出全局快捷键录制控件接口 2026/09/17: 15:34
#import "SDCommon.h"
#import <ApplicationServices/ApplicationServices.h>

@interface SDShortcutRecorderView : NSView
@property(nonatomic, readonly) CGKeyCode recordedKeyCode;
@property(nonatomic, readonly) CGEventFlags recordedModifiers;
@property(nonatomic, readonly) NSString *recordedKeyName;
@property(nonatomic, readonly) BOOL hasValidShortcut;
- (instancetype)initWithKeyCode:(CGKeyCode)keyCode modifiers:(CGEventFlags)modifiers keyName:(NSString *)keyName;
@end

extern NSString * const SDShortcutKeyCodeDefaultsKey;
extern NSString * const SDShortcutModifiersDefaultsKey;
extern NSString * const SDShortcutKeyNameDefaultsKey;

NSString *SDShortcutDisplayString(CGEventFlags modifiers, NSString *keyName);
