// ai coding: 验证移动后刷新访达前窗口的脚本能够正常执行 2026/09/17: 15:46
#import "SDCommon.h"

int main(void) {
    @autoreleasepool {
        NSError *error = nil;
        BOOL refreshed = SDRefreshFrontFinderWindow(&error);
        fprintf(stdout, "finder_refresh=%s error=%s\n", refreshed ? "true" : "false",
                error.localizedDescription.UTF8String ?: "none");
        return error ? 1 : 0;
    }
}
