// ai coding: 抽出跨文件共享的常量、工具函数与翻转视图实现 2026/09/17: 15:34
#import "SDCommon.h"

NSString * const SDErrorDomain = @"com.codex.sidedrawer";
NSString * const SDEdgeLeft = @"left";
NSString * const SDEdgeRight = @"right";
NSString * const SDEdgeTop = @"top";
NSString * const SDEdgeBottom = @"bottom";

// ai coding: 将抽屉长度下限缩为单个文件卡片沿抽屉方向的尺寸 2026/09/17: 13:41
const CGFloat SDHorizontalMinimumLength = 72.0;
const CGFloat SDVerticalMinimumLength = 46.0;
// ai coding: 为菜单手动输入的抽屉厚度设置安全下限，避免内容区无法操作 2026/09/17: 14:10
const CGFloat SDHorizontalMinimumThickness = 32.0;
const CGFloat SDVerticalMinimumThickness = 32.0;

// ai coding: 只保留元数据写盘失败的通知名，移除无引用的刷新通知 2026/09/17: 15:53
NSString * const SDMetadataWriteFailedNotification = @"SDMetadataWriteFailedNotification";

// ai coding: 统一全文用词为“抽屉”和“访达”，并抽出提示文案常量  2026/09/17: 16:06
NSString * const SDNounDrawer = @"抽屉";
NSString * const SDNounFinder = @"访达";
NSString * const SDTextPinDrawer = @"固定抽屉";
NSString * const SDTextUnpinDrawer = @"取消固定抽屉";
NSString * const SDTextDeleteDrawer = @"删除当前抽屉";
NSString * const SDTextUntitledDrawer = @"未命名抽屉";

// ai coding: 集中定义菜单文案，供状态菜单与主菜单共用同一份标题 2026/09/17: 15:50
NSString * const SDMenuTitleNewDrawer = @"新建抽屉";
NSString * const SDMenuTitleBatchNewDrawer = @"批量新建抽屉…";
NSString * const SDMenuTitleClearEmptyDrawers = @"一键清理空抽屉";
NSString * const SDMenuTitleSetDimension = @"设置当前抽屉高度/宽度…";
NSString * const SDMenuTitlePaste = @"粘贴到当前抽屉";
NSString * const SDMenuTitleSaveDrawer = @"保存当前抽屉为文件夹…";
NSString * const SDMenuTitleSelectAll = @"全选当前抽屉文件";
NSString * const SDMenuTitleDeleteSelected = @"将所选项目移到废纸篓";
NSString * const SDMenuTitleShortcutConfiguration = @"设置移动快捷键…";
NSString * const SDMenuTitleShortcutReady = @"快捷键已就绪";
NSString * const SDMenuTitleShowAll = @"显示全部抽屉";
NSString * const SDMenuTitleHideAll = @"隐藏全部抽屉";
NSString * const SDMenuTitleRevealApplication = @"在访达中显示 SideDrawer";
NSString * const SDMenuTitleQuit = @"退出 SideDrawer";
NSString * const SDMenuTitleAbout = @"关于 SideDrawer";
NSString * const SDMenuTitleDrawerMenu = SDNounDrawer;

NSError *SDError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:SDErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

BOOL SDEdgeIsHorizontal(NSString *edge) {
    return [edge isEqualToString:SDEdgeTop] || [edge isEqualToString:SDEdgeBottom];
}

// ai coding: 转义 Finder AppleScript 路径字符串，避免特殊字符破坏选择脚本 2026/09/17: 11:51
NSString *SDEscapeAppleScriptString(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    return [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
}

// ai coding: 生成不会被自动布局重置的 -45° 旋转系统图标 2026/09/17: 09:19
NSImage *SDRotatedPinSymbol(BOOL locked) {
    NSString *description = locked ? SDTextUnpinDrawer : SDTextPinDrawer;
    NSImage *source = [NSImage imageWithSystemSymbolName:locked ? @"pin.fill" : @"pin"
                               accessibilityDescription:description];
    NSImage *rotated = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    [rotated lockFocus];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform translateXBy:8 yBy:8];
    [transform rotateByDegrees:-45];
    [transform concat];
    [source drawInRect:NSMakeRect(-6, -6, 12, 12)
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1
        respectFlipped:NO
                 hints:nil];
    [rotated unlockFocus];
    rotated.template = YES;
    rotated.accessibilityDescription = description;
    return rotated;
}

@implementation SDFlippedView
- (BOOL)isFlipped { return YES; }
@end

// ai coding: 移动文件后立即刷新 Finder 前窗口，让原位置马上消失 2026/09/17: 15:42
BOOL SDRefreshFrontFinderWindow(NSError **error) {
    NSString *source = @"tell application \"Finder\"\n"
                        "if (count of Finder windows) is 0 then return false\n"
                        "try\n"
                        "update every item of front Finder window\n"
                        "end try\n"
                        "return true\n"
                        "end tell";
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
    NSDictionary *scriptError = nil;
    NSAppleEventDescriptor *result = [script executeAndReturnError:&scriptError];
    if (!result) {
        if (error) {
            NSString *message = scriptError[NSAppleScriptErrorMessage] ?: @"刷新访达窗口失败。";
            *error = SDError([scriptError[NSAppleScriptErrorNumber] integerValue], message);
        }
        return NO;
    }
    return result.booleanValue;
}

// ai coding: 统一 Finder 脚本串行队列，避免刷新与相邻项计算同时打扰访达 2026/09/17: 15:54
dispatch_queue_t SDFinderScriptQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.codex.sidedrawer.finder-scripts", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

// ai coding: 在串行队列上执行刷新脚本，避免在拖拽交互中阻塞主线程 2026/09/17: 15:42
void SDRefreshFrontFinderWindowAsync(void) {
    dispatch_async(SDFinderScriptQueue(), ^{
        @autoreleasepool {
            SDRefreshFrontFinderWindow(nil);
        }
    });
}

