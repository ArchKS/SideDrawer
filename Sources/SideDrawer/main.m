// ai coding: 主文件仅保留入口与自检，其余职责已拆分到独立文件 2026/09/17: 15:34
#import "SDAppDelegate.h"
#import "SDDrawerStore.h"

int main(int argc __unused, const char *argv[] __unused) {
    @autoreleasepool {
        NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
        if ([environment[@"SIDEDRAWER_SELF_TEST"] isEqualToString:@"1"]) {
            NSError *error = nil;
            SDDrawerStore *store = [[SDDrawerStore alloc] initWithError:&error];
            NSString *drawerID = store.drawers.firstObject[@"id"];
            NSURL *source = [NSURL fileURLWithPath:environment[@"SIDEDRAWER_TEST_SOURCE"]];
            NSURL *exportDirectory = [NSURL fileURLWithPath:environment[@"SIDEDRAWER_TEST_EXPORT"] isDirectory:YES];
            BOOL imported = store && [store importURLs:@[source] drawerID:drawerID error:&error];
            BOOL sourceRemoved = ![NSFileManager.defaultManager fileExistsAtPath:source.path];
            NSURL *folder = imported ? [store saveDrawerID:drawerID inDirectory:exportDirectory error:&error] : nil;
            NSURL *exportedFile = [folder URLByAppendingPathComponent:source.lastPathComponent];
            BOOL exported = folder && [NSFileManager.defaultManager fileExistsAtPath:exportedFile.path];
            BOOL drawerEmpty = [store itemsForDrawerID:drawerID].count == 0;
            if (imported && sourceRemoved && exported && drawerEmpty) {
                fprintf(stdout, "SIDEDRAWER_SELF_TEST_OK\n");
                return 0;
            }
            fprintf(stderr, "SIDEDRAWER_SELF_TEST_FAILED: %s\n", error.localizedDescription.UTF8String ?: "unknown");
            return 1;
        }
        NSApplication *application = NSApplication.sharedApplication;
        SDAppDelegate *delegate = [[SDAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
