// ai coding: 拆分出收纳盒选择面板与选项按钮接口 2026/09/17: 15:34
#import "SDCommon.h"

@interface SDDrawerChoiceButton : NSButton
@property(nonatomic, readonly) NSTextField *nameLabel;
@property(nonatomic, readonly) NSTextField *shortcutLabel;
- (instancetype)initWithName:(NSString *)name shortcut:(NSString *)shortcut;
- (void)setKeyboardSelected:(BOOL)selected;
@end

@interface SDDrawerChoicePanel : NSPanel
@property(nonatomic, copy) void (^selectionHandler)(NSInteger index);
@property(nonatomic, copy) NSArray<SDDrawerChoiceButton *> *choiceButtons;
@property(nonatomic) NSInteger selectedIndex;
@end
