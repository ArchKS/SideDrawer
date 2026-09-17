// ai coding: 验证系统是否允许注册 Command+M 全局快捷键 2026/09/16: 20:28
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

int main(void) {
    @autoreleasepool {
        NSApplication.sharedApplication;
        EventHotKeyRef hotKey = NULL;
        EventHotKeyID identifier = {'SDRM', 99};
        OSStatus status = RegisterEventHotKey(kVK_ANSI_M,
                                              cmdKey,
                                              identifier,
                                              GetApplicationEventTarget(),
                                              0,
                                              &hotKey);
        if (hotKey) UnregisterEventHotKey(hotKey);
        printf("COMMAND_M_REGISTRATION_STATUS=%d\n", (int)status);
        return status == noErr ? 0 : 1;
    }
}
