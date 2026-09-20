// ai coding: 拆分出抽屉面板与其控制器的接口 2026/09/17: 15:34
#import "SDCommon.h"

@class SDDrawerStore;
@class SDDrawerContentView;

@interface SDDrawerPanel : NSPanel
@property(nonatomic, copy) void (^selectAllHandler)(void);
@property(nonatomic, copy) void (^createDrawerHandler)(void);
@property(nonatomic, copy) void (^saveDrawerHandler)(void);
@property(nonatomic, copy) void (^deleteSelectedHandler)(void);
// ai coding: 为 Command+V 提供当前收纳盒剪贴板导入回调 2026/09/17: 14:10
@property(nonatomic, copy) void (^pasteHandler)(void);
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
// ai coding: 暴露粘贴和菜单尺寸调整接口给应用菜单 2026/09/17: 14:10
- (BOOL)pasteFromPasteboard;
- (CGFloat)currentDrawerThickness;
- (void)setDrawerThickness:(CGFloat)thickness;
- (BOOL)isEditingDrawerName;
@end
