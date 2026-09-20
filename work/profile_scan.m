// ai coding: 打印指定竖直线上的像素颜色，用于定位 Dock 面板边界（自查用） 2026/09/17: 17:06
#import <Cocoa/Cocoa.h>
static NSString *Hex(NSColor *c) { NSColor *r=[c colorUsingColorSpace:NSColorSpace.sRGBColorSpace]?:c;
  return [NSString stringWithFormat:@"#%02X%02X%02X",(int)lround(r.redComponent*255),(int)lround(r.greenComponent*255),(int)lround(r.blueComponent*255)]; }
int main(int argc, const char *argv[]) { @autoreleasepool {
  NSData *d=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
  NSBitmapImageRep *rep=[[NSBitmapImageRep alloc] initWithData:d];
  CGFloat x=[@(argv[2]) doubleValue];
  for (int y=[@(argv[3]) intValue]; y<=[@(argv[4]) intValue]; y++) {
    NSColor *c=[rep colorAtX:(NSInteger)lround(x*2) y:(NSInteger)lround(y*2)];
    printf("x=%.0f y=%3d  %s\n", x, y, Hex(c).UTF8String);
  }
} return 0; }
