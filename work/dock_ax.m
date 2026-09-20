// ai coding: 尝试通过辅助功能接口读取 Dock 面板位置（自查用） 2026/09/17: 17:05
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

static void Dump(AXUIElementRef element, int depth) {
    if (depth > 3) return;
    CFTypeRef role = NULL; AXUIElementCopyAttributeValue(element, kAXRoleAttribute, &role);
    CFTypeRef position = NULL; AXUIElementCopyAttributeValue(element, kAXPositionAttribute, &position);
    CFTypeRef size = NULL; AXUIElementCopyAttributeValue(element, kAXSizeAttribute, &size);
    CGPoint p = CGPointZero; CGSize s = CGSizeZero;
    if (position) AXValueGetValue(position, kAXValueCGPointType, &p);
    if (size) AXValueGetValue(size, kAXValueCGSizeType, &s);
    printf("%*srole=%s pos=(%.0f,%.0f) size=(%.0f,%.0f)\n", depth * 2, "",
           role ? [(__bridge NSString *)role UTF8String] : "?", p.x, p.y, s.width, s.height);
    if (role) CFRelease(role);
    if (position) CFRelease(position);
    if (size) CFRelease(size);
    CFTypeRef children = NULL;
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &children);
    if (children) {
        for (CFIndex i = 0; i < CFArrayGetCount(children); i++) Dump((AXUIElementRef)CFArrayGetValueAtIndex(children, i), depth + 1);
        CFRelease(children);
    }
}

int main(void) { @autoreleasepool {
    printf("trusted=%d\n", AXIsProcessTrusted());
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"]) {
        AXUIElementRef element = AXUIElementCreateApplication(app.processIdentifier);
        Dump(element, 0);
        CFRelease(element);
    }
} return 0; }
