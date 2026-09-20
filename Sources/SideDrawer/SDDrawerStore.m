// ai coding: 拆分出抽屉存储层实现，保持原有行为 2026/09/17: 15:34
#import "SDDrawerStore.h"

@implementation SDDrawerStore {
    NSMutableArray<NSMutableDictionary *> *_mutableDrawers;
    NSURL *_rootURL;
    NSURL *_drawersURL;
    NSURL *_metadataURL;
}

- (instancetype)initWithError:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *storageOverride = NSProcessInfo.processInfo.environment[@"SIDEDRAWER_STORAGE_ROOT"];
    if (storageOverride.length > 0) {
        _rootURL = [NSURL fileURLWithPath:storageOverride isDirectory:YES];
    } else {
        NSURL *supportURL = [manager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        if (!supportURL) supportURL = manager.temporaryDirectory;
        _rootURL = [supportURL URLByAppendingPathComponent:@"SideDrawer" isDirectory:YES];
    }
    _drawersURL = [_rootURL URLByAppendingPathComponent:@"Drawers" isDirectory:YES];
    _metadataURL = [_rootURL URLByAppendingPathComponent:@"drawers.json"];
    if (![manager createDirectoryAtURL:_drawersURL withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    [self loadMetadata];
    if (_mutableDrawers.count == 0 && ![self createDefaultDrawer:error]) return nil;
    return self;
}

- (NSArray<NSDictionary *> *)drawers { return [_mutableDrawers copy]; }

- (NSDictionary *)drawerForID:(NSString *)drawerID {
    for (NSDictionary *drawer in _mutableDrawers) {
        if ([drawer[@"id"] isEqualToString:drawerID]) return drawer;
    }
    return nil;
}

- (NSMutableDictionary *)mutableDrawerForID:(NSString *)drawerID {
    for (NSMutableDictionary *drawer in _mutableDrawers) {
        if ([drawer[@"id"] isEqualToString:drawerID]) return drawer;
    }
    return nil;
}

- (NSArray<NSURL *> *)itemsForDrawerID:(NSString *)drawerID {
    NSDictionary *drawer = [self drawerForID:drawerID];
    if (!drawer) return @[];
    NSArray<NSURL *> *urls = [NSFileManager.defaultManager contentsOfDirectoryAtURL:[self directoryForDrawer:drawer]
                                                          includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                               error:nil] ?: @[];
    return [urls sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        NSNumber *leftDirectory = nil;
        NSNumber *rightDirectory = nil;
        [left getResourceValue:&leftDirectory forKey:NSURLIsDirectoryKey error:nil];
        [right getResourceValue:&rightDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (leftDirectory.boolValue != rightDirectory.boolValue) {
            return leftDirectory.boolValue ? NSOrderedAscending : NSOrderedDescending;
        }
        return [left.lastPathComponent localizedStandardCompare:right.lastPathComponent];
    }];
}

- (NSString *)addDrawer:(NSError **)error {
    return [self addDrawerWithName:nil copyingDimensionsFromDrawerID:nil error:error];
}

// ai coding: 统一存储层错误提示与默认名称用词为“抽屉” 2026/09/17: 16:06
// ai coding: 新建抽屉时支持自定义名称，并沿用指定抽屉的方向和完整尺寸 2026/09/17: 11:17
- (NSString *)addDrawerWithName:(NSString *)requestedName
 copyingDimensionsFromDrawerID:(NSString *)sourceDrawerID
                          error:(NSError **)error {
    // ai coding: 新建抽屉的名称与错误提示统一使用“抽屉”  2026/09/17: 16:06
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (NSDictionary *drawer in _mutableDrawers) [names addObject:drawer[@"name"]];
    NSString *name = [self sanitizedName:requestedName ?: @""];
    if (name.length == 0 && requestedName.length > 0) {
        if (error) *error = SDError(9, @"抽屉名称不能为空。");
        return nil;
    }
    if (name.length == 0) {
        NSInteger number = _mutableDrawers.count + 1;
        name = [NSString stringWithFormat:@"%@ %ld", SDNounDrawer, (long)number];
        while ([names containsObject:name]) {
            number += 1;
            name = [NSString stringWithFormat:@"%@ %ld", SDNounDrawer, (long)number];
        }
    }
    NSInteger slot = _mutableDrawers.count % 5;
    NSDictionary *sourceDrawer = sourceDrawerID.length > 0 ? [self drawerForID:sourceDrawerID] : nil;
    NSString *defaultEdge = ((_mutableDrawers.count / 5) % 2 == 0) ? SDEdgeRight : SDEdgeLeft;
    NSString *edge = sourceDrawer[@"edge"] ?: defaultEdge;
    NSNumber *horizontalLength = sourceDrawer[@"horizontalLength"] ?: @580;
    NSNumber *verticalLength = sourceDrawer[@"verticalLength"] ?: @430;
    // ai coding: 新建抽屉时继承当前抽屉的上下高度和左右宽度 2026/09/17: 14:10
    NSNumber *horizontalThickness = sourceDrawer[@"horizontalThickness"] ?: @66;
    NSNumber *verticalThickness = sourceDrawer[@"verticalThickness"] ?: @95;
    // ai coding: 默认抽屉名称改用共享名词常量，避免出现“收纳箱”  2026/09/17: 16:06
    NSMutableDictionary *drawer = [@{
        @"id": NSUUID.UUID.UUIDString,
        @"name": name,
        @"edge": edge,
        @"position": @(0.05 + slot * 0.2),
        @"locked": @NO,
        @"horizontalLength": horizontalLength,
        @"verticalLength": verticalLength,
        @"horizontalThickness": horizontalThickness,
        @"verticalThickness": verticalThickness
    } mutableCopy];
    [_mutableDrawers addObject:drawer];
    if (![NSFileManager.defaultManager createDirectoryAtURL:[self directoryForDrawer:drawer]
                                withIntermediateDirectories:YES attributes:nil error:error]) {
        [_mutableDrawers removeLastObject];
        return nil;
    }
    if (![self writeMetadata:error]) return nil;
    return drawer[@"id"];
}

- (BOOL)renameDrawerID:(NSString *)drawerID name:(NSString *)rawName error:(NSError **)error {
    NSString *name = [self sanitizedName:rawName];
    if (name.length == 0) {
        if (error) *error = SDError(1, @"抽屉名称不能为空。");
        return NO;
    }
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) {
        if (error) *error = SDError(2, @"找不到这个抽屉。");
        return NO;
    }
    drawer[@"name"] = name;
    return [self writeMetadata:error];
}

- (BOOL)deleteDrawerID:(NSString *)drawerID error:(NSError **)error {
    if (_mutableDrawers.count <= 1) {
        if (error) *error = SDError(3, @"至少需要保留一个抽屉。");
        return NO;
    }
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) return YES;
    if ([self itemsForDrawerID:drawerID].count > 0) {
        if (error) *error = SDError(4, @"抽屉里还有文件，请先拖出或保存为文件夹。");
        return NO;
    }
    if (![NSFileManager.defaultManager removeItemAtURL:[self directoryForDrawer:drawer] error:error]) return NO;
    [_mutableDrawers removeObject:drawer];
    return [self writeMetadata:error];
}

// ai coding: 仅删除空收纳盒并始终保留至少一个可用收纳盒 2026/09/17: 11:38
- (BOOL)hasDeletableEmptyDrawers {
    if (_mutableDrawers.count <= 1) return NO;
    NSUInteger emptyCount = 0;
    for (NSDictionary *drawer in _mutableDrawers) {
        if ([self itemsForDrawerID:drawer[@"id"]].count == 0) emptyCount += 1;
    }
    return emptyCount > 0;
}

- (NSUInteger)deleteEmptyDrawers:(NSError **)error {
    if (_mutableDrawers.count <= 1) return 0;
    NSUInteger removedCount = 0;
    NSArray<NSDictionary *> *drawers = [_mutableDrawers copy];
    for (NSDictionary *drawer in drawers) {
        if (_mutableDrawers.count <= 1) break;
        NSString *drawerID = drawer[@"id"];
        if ([self itemsForDrawerID:drawerID].count > 0) continue;
        if (![NSFileManager.defaultManager removeItemAtURL:[self directoryForDrawer:drawer] error:error]) break;
        [_mutableDrawers removeObject:(NSMutableDictionary *)drawer];
        removedCount += 1;
    }
    if (removedCount > 0 && ![self writeMetadata:error]) return removedCount;
    return removedCount;
}

- (BOOL)importURLs:(NSArray<NSURL *> *)urls drawerID:(NSString *)drawerID error:(NSError **)error {
    NSDictionary *drawer = [self drawerForID:drawerID];
    if (!drawer) {
        if (error) *error = SDError(5, @"找不到这个抽屉。");
        return NO;
    }
    NSString *storagePath = _rootURL.URLByStandardizingPath.path;
    NSURL *destinationDirectory = [self directoryForDrawer:drawer];
    for (NSURL *inputURL in urls) {
        NSURL *sourceURL = inputURL.URLByStandardizingPath;
        if ([sourceURL.path hasPrefix:storagePath]) {
            if (error) *error = SDError(6, @"不能把 SideDrawer 自己的存储目录放进抽屉。");
            return NO;
        }
        BOOL accessed = [sourceURL startAccessingSecurityScopedResource];
        NSURL *destination = [self uniqueDestinationForURL:sourceURL inDirectory:destinationDirectory];
        BOOL moved = [NSFileManager.defaultManager moveItemAtURL:sourceURL toURL:destination error:error];
        if (accessed) [sourceURL stopAccessingSecurityScopedResource];
        if (!moved) return NO;
    }
    return YES;
}

- (BOOL)moveItem:(NSURL *)itemURL toDirectory:(NSURL *)directory error:(NSError **)error {
    BOOL accessed = [directory startAccessingSecurityScopedResource];
    NSURL *destination = [self uniqueDestinationForURL:itemURL inDirectory:directory];
    BOOL moved = [NSFileManager.defaultManager moveItemAtURL:itemURL toURL:destination error:error];
    if (accessed) [directory stopAccessingSecurityScopedResource];
    return moved;
}

- (NSURL *)saveDrawerID:(NSString *)drawerID inDirectory:(NSURL *)directory error:(NSError **)error {
    NSDictionary *drawer = [self drawerForID:drawerID];
    if (!drawer) {
        if (error) *error = SDError(7, @"找不到这个抽屉。");
        return nil;
    }
    BOOL accessed = [directory startAccessingSecurityScopedResource];
    NSURL *destinationFolder = [self uniqueFolderNamed:drawer[@"name"] inDirectory:directory];
    NSFileManager *manager = NSFileManager.defaultManager;
    if (![manager createDirectoryAtURL:destinationFolder withIntermediateDirectories:NO attributes:nil error:error]) {
        if (accessed) [directory stopAccessingSecurityScopedResource];
        return nil;
    }
    for (NSURL *itemURL in [self itemsForDrawerID:drawerID]) {
        NSURL *destination = [self uniqueDestinationForURL:itemURL inDirectory:destinationFolder];
        if (![manager moveItemAtURL:itemURL toURL:destination error:error]) {
            if (accessed) [directory stopAccessingSecurityScopedResource];
            return nil;
        }
    }
    if (accessed) [directory stopAccessingSecurityScopedResource];
    return destinationFolder;
}

- (void)updateDrawerID:(NSString *)drawerID edge:(NSString *)edge position:(CGFloat)position {
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) return;
    drawer[@"edge"] = edge;
    drawer[@"position"] = @(MAX(0, MIN(1, position)));
    [self writeMetadata:nil];
}

- (void)updateDrawerID:(NSString *)drawerID locked:(BOOL)locked {
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) return;
    drawer[@"locked"] = @(locked);
    [self writeMetadata:nil];
}

// ai coding: 按吸附方向持久化抽屉长度，切换方向后可恢复各自尺寸 2026/09/17: 08:40
- (void)updateDrawerID:(NSString *)drawerID length:(CGFloat)length forEdge:(NSString *)edge {
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) return;
    drawer[SDEdgeIsHorizontal(edge) ? @"horizontalLength" : @"verticalLength"] = @(length);
    [self writeMetadata:nil];
}

// ai coding: 持久化上下贴边高度或左右贴边宽度，供菜单手动设置使用 2026/09/17: 14:10
- (void)updateDrawerID:(NSString *)drawerID thickness:(CGFloat)thickness forEdge:(NSString *)edge {
    NSMutableDictionary *drawer = [self mutableDrawerForID:drawerID];
    if (!drawer) return;
    drawer[SDEdgeIsHorizontal(edge) ? @"horizontalThickness" : @"verticalThickness"] = @(thickness);
    [self writeMetadata:nil];
}

- (void)loadMetadata {
    NSData *data = [NSData dataWithContentsOfURL:_metadataURL];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    _mutableDrawers = [object isKindOfClass:NSArray.class] ? [object mutableCopy] : [NSMutableArray array];
    NSInteger index = 0;
    for (NSMutableDictionary *drawer in _mutableDrawers) {
        if (!drawer[@"edge"]) drawer[@"edge"] = SDEdgeRight;
        if (!drawer[@"position"]) drawer[@"position"] = @(0.05 + (index % 5) * 0.2);
        // ai coding: 为旧版抽屉补齐可调长度字段并保留原有长边尺寸 2026/09/17: 08:40
        if (!drawer[@"locked"]) drawer[@"locked"] = @NO;
        if (!drawer[@"horizontalLength"]) drawer[@"horizontalLength"] = @580;
        if (!drawer[@"verticalLength"]) drawer[@"verticalLength"] = @430;
        // ai coding: 为旧版抽屉补齐菜单尺寸字段并保留原有默认厚度 2026/09/17: 14:10
        if (!drawer[@"horizontalThickness"]) drawer[@"horizontalThickness"] = @66;
        if (!drawer[@"verticalThickness"]) drawer[@"verticalThickness"] = @95;
        [NSFileManager.defaultManager createDirectoryAtURL:[self directoryForDrawer:drawer]
                               withIntermediateDirectories:YES attributes:nil error:nil];
        index += 1;
    }
    [self writeMetadata:nil];
}

- (BOOL)createDefaultDrawer:(NSError **)error {
    // ai coding: 默认抽屉同时初始化横向与纵向长度 2026/09/17: 08:40
    NSMutableDictionary *drawer = [@{
        @"id": NSUUID.UUID.UUIDString,
        @"name": [NSString stringWithFormat:@"%@ 1", SDNounDrawer],
        @"edge": SDEdgeRight,
        @"position": @0.5,
        @"locked": @NO,
        @"horizontalLength": @580,
        @"verticalLength": @430,
        @"horizontalThickness": @66,
        @"verticalThickness": @95
    } mutableCopy];
    _mutableDrawers = [NSMutableArray arrayWithObject:drawer];
    if (![NSFileManager.defaultManager createDirectoryAtURL:[self directoryForDrawer:drawer]
                                withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    return [self writeMetadata:error];
}

- (BOOL)writeMetadata:(NSError **)error {
    NSError *writeError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:_mutableDrawers
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:&writeError];
    BOOL written = data && [data writeToURL:_metadataURL options:NSDataWritingAtomic error:&writeError];
    if (!written) {
        if (error) *error = writeError;
        // ai coding: 元数据写盘失败时上报通知，让界面立即提示用户而不是静默丢失布局 2026/09/17: 15:42
        [[NSNotificationCenter defaultCenter] postNotificationName:SDMetadataWriteFailedNotification
                                                           object:self
                                                         userInfo:writeError ? @{@"error": writeError} : @{}];
        return NO;
    }
    return YES;
}

- (NSURL *)directoryForDrawer:(NSDictionary *)drawer {
    return [_drawersURL URLByAppendingPathComponent:drawer[@"id"] isDirectory:YES];
}

- (NSURL *)uniqueDestinationForURL:(NSURL *)sourceURL inDirectory:(NSURL *)directory {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *candidate = [directory URLByAppendingPathComponent:sourceURL.lastPathComponent];
    if (![manager fileExistsAtPath:candidate.path]) return candidate;
    NSNumber *isDirectory = nil;
    [sourceURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    NSString *extension = isDirectory.boolValue ? @"" : sourceURL.pathExtension;
    NSString *baseName = extension.length ? sourceURL.URLByDeletingPathExtension.lastPathComponent : sourceURL.lastPathComponent;
    NSInteger index = 2;
    do {
        NSString *name = extension.length
            ? [NSString stringWithFormat:@"%@ %ld.%@", baseName, (long)index, extension]
            : [NSString stringWithFormat:@"%@ %ld", baseName, (long)index];
        candidate = [directory URLByAppendingPathComponent:name isDirectory:isDirectory.boolValue];
        index += 1;
    } while ([manager fileExistsAtPath:candidate.path]);
    return candidate;
}

- (NSURL *)uniqueFolderNamed:(NSString *)rawName inDirectory:(NSURL *)directory {
    NSString *name = [self sanitizedName:rawName];
    NSURL *candidate = [directory URLByAppendingPathComponent:name isDirectory:YES];
    NSInteger index = 2;
    while ([NSFileManager.defaultManager fileExistsAtPath:candidate.path]) {
        candidate = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@ %ld", name, (long)index]
                                               isDirectory:YES];
        index += 1;
    }
    return candidate;
}

- (NSString *)sanitizedName:(NSString *)name {
    NSString *clean = [name stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    clean = [clean stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    return [clean stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
@end
