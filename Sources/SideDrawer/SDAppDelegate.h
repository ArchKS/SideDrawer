// ai coding: 拆分出应用委托接口 2026/09/17: 15:34
#import "SDCommon.h"
#import <ApplicationServices/ApplicationServices.h>

@class SDDrawerChoicePanel;

@interface SDAppDelegate : NSObject <NSApplicationDelegate, NSMenuItemValidation>
- (void)handleGlobalMoveHotKey;
- (BOOL)shouldHandleGlobalMoveHotKey;
- (BOOL)matchesMoveShortcutKeyCode:(CGKeyCode)keyCode modifiers:(CGEventFlags)modifiers;
// ai coding: 声明标准应用菜单和访达定位入口 2026/09/17: 09:06
- (void)configureMainMenu;
- (void)configureStatusItem;
- (NSArray<NSDictionary *> *)drawerMenuItems;
- (NSArray<NSDictionary *> *)applicationMenuItems;
- (void)revealApplication:(id)sender;
// ai coding: 声明批量名称解析、四边分布及批量新建菜单操作 2026/09/17: 11:23
- (NSArray<NSString *> *)drawerNamesFromBatchInput:(NSString *)input;
- (NSArray<NSDictionary *> *)batchPlacementsForCount:(NSUInteger)count;
- (void)batchCreateDrawers:(id)sender;
// ai coding: 声明快捷键录制、展示和多抽屉目标选择入口 2026/09/17: 09:19
- (void)loadMoveShortcut;
- (void)showShortcutConfiguration:(id)sender;
- (BOOL)moveURLs:(NSArray<NSURL *> *)urls toDrawerID:(NSString *)drawerID;
// ai coding: 声明菜单中的尺寸输入和剪贴板粘贴操作 2026/09/17: 14:10
- (void)setCurrentDrawerDimension:(id)sender;
- (void)pasteCurrentDrawer:(id)sender;
// ai coding: 声明移动后异步刷新 Finder 并定位相邻项目的快捷键流程接口 2026/09/17: 13:22
- (BOOL)chooseDrawerAndMoveURLs:(NSArray<NSURL *> *)urls;
- (NSArray<NSDictionary *> *)finderSelectionSnapshotForURLs:(NSArray<NSURL *> *)urls;
- (NSString *)finderNeighborPathForSelectionSnapshot:(NSArray<NSDictionary *> *)snapshots;
- (void)selectFinderItemAtPath:(NSString *)path;
// ai coding: 声明支持方向键、回车及数字快捷键的多收纳盒选择接口 2026/09/17: 11:23
- (void)selectDrawerAtIndex:(NSInteger)index;
- (void)selectDrawerFromList:(NSButton *)sender;
- (void)cancelDrawerChoice:(id)sender;
@end
