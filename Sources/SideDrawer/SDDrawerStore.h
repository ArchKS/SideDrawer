// ai coding: 拆分出抽屉存储层接口 2026/09/17: 15:34
#import "SDCommon.h"

@interface SDDrawerStore : NSObject
@property(nonatomic, readonly) NSArray<NSDictionary *> *drawers;
- (instancetype)initWithError:(NSError **)error;
- (NSDictionary *)drawerForID:(NSString *)drawerID;
- (NSArray<NSURL *> *)itemsForDrawerID:(NSString *)drawerID;
- (NSString *)addDrawer:(NSError **)error;
// ai coding: 声明可指定名称并复制现有抽屉尺寸的新建接口 2026/09/17: 11:14
- (NSString *)addDrawerWithName:(NSString *)requestedName
 copyingDimensionsFromDrawerID:(NSString *)sourceDrawerID
                          error:(NSError **)error;
- (BOOL)renameDrawerID:(NSString *)drawerID name:(NSString *)name error:(NSError **)error;
- (BOOL)deleteDrawerID:(NSString *)drawerID error:(NSError **)error;
// ai coding: 声明检测并批量删除空收纳盒的安全操作 2026/09/17: 11:30
- (BOOL)hasDeletableEmptyDrawers;
- (NSUInteger)deleteEmptyDrawers:(NSError **)error;
- (BOOL)importURLs:(NSArray<NSURL *> *)urls drawerID:(NSString *)drawerID error:(NSError **)error;
- (BOOL)moveItem:(NSURL *)itemURL toDirectory:(NSURL *)directory error:(NSError **)error;
- (NSURL *)saveDrawerID:(NSString *)drawerID inDirectory:(NSURL *)directory error:(NSError **)error;
- (void)updateDrawerID:(NSString *)drawerID edge:(NSString *)edge position:(CGFloat)position;
- (void)updateDrawerID:(NSString *)drawerID locked:(BOOL)locked;
// ai coding: 声明按吸附方向保存用户自定义抽屉长度的接口 2026/09/17: 09:01
- (void)updateDrawerID:(NSString *)drawerID length:(CGFloat)length forEdge:(NSString *)edge;
// ai coding: 声明按吸附方向保存菜单输入的抽屉高度或宽度 2026/09/17: 14:10
- (void)updateDrawerID:(NSString *)drawerID thickness:(CGFloat)thickness forEdge:(NSString *)edge;
@end
