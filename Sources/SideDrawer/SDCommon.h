// ai coding: 抽出跨文件共享的常量、工具声明与翻转视图接口 2026/09/17: 15:34
#import <Cocoa/Cocoa.h>

extern NSString * const SDErrorDomain;
extern NSString * const SDEdgeLeft;
extern NSString * const SDEdgeRight;
extern NSString * const SDEdgeTop;
extern NSString * const SDEdgeBottom;

extern const CGFloat SDHorizontalMinimumLength;
extern const CGFloat SDVerticalMinimumLength;
extern const CGFloat SDHorizontalMinimumThickness;
extern const CGFloat SDVerticalMinimumThickness;

// ai coding: 移除重构后已无引用的刷新通知常量，刷新改为直接调用同步方法 2026/09/17: 15:53
/// 抽屉元数据写盘失败时上报错误，供界面提示用户。
extern NSString * const SDMetadataWriteFailedNotification;

/// 同步刷新 Finder 前窗口，让已被移动的项目立刻从原位置消失。
BOOL SDRefreshFrontFinderWindow(NSError **error);
/// 应用内所有 Finder AppleScript 共用的串行队列，避免脚本互相抢占。
dispatch_queue_t SDFinderScriptQueue(void);
/// 在串行队列上刷新 Finder 前窗口，避免阻塞抽屉交互。
void SDRefreshFrontFinderWindowAsync(void);

// ai coding: 抽出抽屉名词与图钉、删除等提示文案，统一全文用词  2026/09/17: 16:06
/// 抽屉统一名词与控件提示文案，避免抽屉、收纳盒、收纳箱混用。
extern NSString * const SDNounDrawer;
extern NSString * const SDNounFinder;
extern NSString * const SDTextPinDrawer;
extern NSString * const SDTextUnpinDrawer;
extern NSString * const SDTextDeleteDrawer;
extern NSString * const SDTextUntitledDrawer;

/// 菜单文案集中定义，保证菜单栏与应用菜单始终一致。
extern NSString * const SDMenuTitleNewDrawer;
extern NSString * const SDMenuTitleBatchNewDrawer;
extern NSString * const SDMenuTitleClearEmptyDrawers;
extern NSString * const SDMenuTitleSetDimension;
extern NSString * const SDMenuTitlePaste;
extern NSString * const SDMenuTitleSaveDrawer;
extern NSString * const SDMenuTitleSelectAll;
extern NSString * const SDMenuTitleDeleteSelected;
extern NSString * const SDMenuTitleShortcutConfiguration;
extern NSString * const SDMenuTitleShortcutReady;
extern NSString * const SDMenuTitleShowAll;
extern NSString * const SDMenuTitleHideAll;
extern NSString * const SDMenuTitleRevealApplication;
extern NSString * const SDMenuTitleQuit;
extern NSString * const SDMenuTitleAbout;
extern NSString * const SDMenuTitleDrawerMenu;

NSError *SDError(NSInteger code, NSString *message);
BOOL SDEdgeIsHorizontal(NSString *edge);
NSString *SDEscapeAppleScriptString(NSString *value);
NSImage *SDRotatedPinSymbol(BOOL locked);

@interface SDFlippedView : NSView
@end
