// ai coding: 把鼠标移到屏幕上方，避免触发 Dock 自动显示（自查用） 2026/09/17: 17:10
#import <Cocoa/Cocoa.h>
int main(void) { @autoreleasepool { CGWarpMouseCursorPosition(CGPointMake(960, 60)); } return 0; }
