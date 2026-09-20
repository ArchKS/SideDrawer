// ai coding: 拆分出抽屉内容视图接口 2026/09/17: 15:34
#import "SDCommon.h"

@class SDDrawerStore;

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
// ai coding: 暴露 Command+V 粘贴文件、图片和文本到当前收纳盒的入口 2026/09/17: 14:10
- (BOOL)pasteFromPasteboard;
- (void)updateSelectionForURL:(NSURL *)url toggle:(BOOL)toggle;
- (NSArray<NSURL *> *)draggingURLsForAnchorURL:(NSURL *)anchorURL;
- (BOOL)isURLSelected:(NSURL *)url;
- (void)updateSelectionAppearance;
- (void)setDropTargetActive:(BOOL)active;
@end
