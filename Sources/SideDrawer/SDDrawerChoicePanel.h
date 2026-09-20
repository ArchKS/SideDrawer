// ai coding: 为抽屉选择面板增加多列网格导航接口 2026/09/20: 09:54
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
@property(nonatomic) NSUInteger choiceColumnCount;
@end
