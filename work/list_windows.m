// ai coding: 列出当前屏幕窗口用于定位 Dock（自查用） 2026/09/17: 16:57
#import <Cocoa/Cocoa.h>
int main(void) { @autoreleasepool {
    NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    for (NSDictionary *w in windows) {
        NSDictionary *b = w[(id)kCGWindowBounds];
        printf("layer=%-4ld owner=%-22s name=%-28s rect=%.0f,%.0f %.0fx%.0f\n",
               (long)[w[(id)kCGWindowLayer] integerValue],
               [w[(id)kCGWindowOwnerName] UTF8String],
               [[w[(id)kCGWindowName] description] UTF8String],
               [b[@"X"] doubleValue], [b[@"Y"] doubleValue], [b[@"Width"] doubleValue], [b[@"Height"] doubleValue]);
    }
} return 0; }
