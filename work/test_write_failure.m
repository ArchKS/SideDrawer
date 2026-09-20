// ai coding: 验证元数据写盘失败会发出通知，避免静默丢失布局 2026/09/17: 15:46
#import "SDCommon.h"
#import "SDDrawerStore.h"

int main(void) {
    @autoreleasepool {
        __block NSInteger failures = 0;
        [NSNotificationCenter.defaultCenter addObserverForName:SDMetadataWriteFailedNotification
                                                        object:nil
                                                         queue:nil
                                                    usingBlock:^(NSNotification *note __unused) { failures += 1; }];
        NSError *error = nil;
        SDDrawerStore *store = [[SDDrawerStore alloc] initWithError:&error];
        if (!store) { fprintf(stderr, "store init failed: %s\n", error.localizedDescription.UTF8String); return 1; }
        [store updateDrawerID:store.drawers.firstObject[@"id"] locked:YES];
        NSString *root = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/SideDrawer"];
        chmod(root.UTF8String, 0500);
        [store updateDrawerID:store.drawers.firstObject[@"id"] locked:NO];
        chmod(root.UTF8String, 0700);
        fprintf(stdout, failures > 0 ? "WRITE_FAILURE_NOTIFIED=%ld\n" : "WRITE_FAILURE_SILENT=%ld\n", (long)failures);
        return failures > 0 ? 0 : 1;
    }
}
