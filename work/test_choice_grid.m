// ai coding: 回归验证快捷键选择面板的网格布局、键盘导航与真实鼠标点击响应 2026/09/20: 10:05
#import "../Sources/SideDrawer/SDAppDelegate.h"
#import "../Sources/SideDrawer/SDDrawerChoicePanel.h"

@interface SDAppDelegate (ChoiceGridTest)
- (SDDrawerChoicePanel *)drawerChoicePanelForDrawers:(NSArray<NSDictionary *> *)drawers
                                           itemCount:(NSInteger)itemCount;
@end

// ai coding: 增加鼠标点击动作接收器以验证选项会实际发送选择事件 2026/09/20: 10:05
@interface SDChoiceClickTarget : NSObject
@property(nonatomic) NSInteger clickCount;
- (void)chooseDrawer:(id)sender;
@end

@implementation SDChoiceClickTarget
- (void)chooseDrawer:(id)sender __unused {
    self.clickCount += 1;
}
@end

static NSInteger SDCountViewsOfClass(NSView *view, Class viewClass) {
    NSInteger count = [view isKindOfClass:viewClass] ? 1 : 0;
    for (NSView *subview in view.subviews) count += SDCountViewsOfClass(subview, viewClass);
    return count;
}

static NSEvent *SDArrowEvent(CGKeyCode keyCode, unichar character, NSInteger windowNumber) {
    NSString *characters = [NSString stringWithCharacters:&character length:1];
    return [NSEvent keyEventWithType:NSEventTypeKeyDown
                            location:NSZeroPoint
                       modifierFlags:0
                           timestamp:0
                        windowNumber:windowNumber
                             context:nil
                          characters:characters
         charactersIgnoringModifiers:characters
                           isARepeat:NO
                             keyCode:keyCode];
}

// ai coding: 向指定选项发送完整的鼠标按下和抬起事件并检查动作调用 2026/09/20: 10:05
static BOOL SDClickChoiceButton(SDDrawerChoicePanel *panel, SDDrawerChoiceButton *button) {
    SDChoiceClickTarget *target = [[SDChoiceClickTarget alloc] init];
    button.target = target;
    button.action = @selector(chooseDrawer:);
    NSPoint location = [button convertPoint:NSMakePoint(NSMidX(button.bounds), NSMidY(button.bounds))
                                       toView:nil];
    NSEvent *mouseUp = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                           location:location
                                      modifierFlags:0
                                          timestamp:0
                                       windowNumber:panel.windowNumber
                                            context:nil
                                        eventNumber:2
                                         clickCount:1
                                           pressure:0];
    NSEvent *mouseDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                             location:location
                                        modifierFlags:0
                                            timestamp:0
                                         windowNumber:panel.windowNumber
                                              context:nil
                                          eventNumber:1
                                           clickCount:1
                                             pressure:1];
    NSPoint contentLocation = [panel.contentView convertPoint:location fromView:nil];
    NSView *hitView = [panel.contentView hitTest:contentLocation];
    BOOL hitReady = hitView == button;
    [NSApp postEvent:mouseUp atStart:YES];
    [panel sendEvent:mouseDown];
    if (!hitReady || target.clickCount != 1) {
        fprintf(stderr,
                "SIDEDRAWER_MOUSE_DETAIL hit=%d hitClass=%s clicks=%ld window=(%.1f,%.1f) content=(%.1f,%.1f) button=(%.1f,%.1f,%.1f,%.1f)\n",
                hitReady, NSStringFromClass(hitView.class).UTF8String, (long)target.clickCount,
                location.x, location.y, contentLocation.x, contentLocation.y,
                button.frame.origin.x, button.frame.origin.y,
                button.frame.size.width, button.frame.size.height);
    }
    return hitReady && target.clickCount == 1;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSMutableArray<NSDictionary *> *drawers = [NSMutableArray arrayWithCapacity:13];
        for (NSInteger index = 0; index < 13; index++) {
            [drawers addObject:@{
                @"id": [NSString stringWithFormat:@"drawer-%ld", (long)index],
                @"name": [NSString stringWithFormat:@"抽屉 %ld", (long)index + 1]
            }];
        }

        SDAppDelegate *delegate = [[SDAppDelegate alloc] init];
        SDDrawerChoicePanel *panel = [delegate drawerChoicePanelForDrawers:drawers itemCount:2];
        [panel makeKeyAndOrderFront:nil];
        NSArray<SDDrawerChoiceButton *> *buttons = panel.choiceButtons;
        BOOL gridReady = panel.choiceColumnCount == 3 && buttons.count == 13 &&
            fabs(panel.frame.size.width - 472) < 0.5 &&
            SDCountViewsOfClass(panel.contentView, NSScrollView.class) == 0;
        NSPoint fifthButtonPoint = NSMakePoint(NSMidX(buttons[4].frame), NSMidY(buttons[4].frame));
        BOOL mouseReady = [buttons[4] hitTest:fifthButtonPoint] == buttons[4] &&
            [buttons[0] acceptsFirstMouse:nil] &&
            buttons[0].target == delegate &&
            buttons[0].action == @selector(selectDrawerFromList:);
        BOOL mouseActionReady = SDClickChoiceButton(panel, buttons[4]);
        BOOL rowMajorLayoutReady = fabs(buttons[0].frame.origin.x - 0) < 0.5 &&
            fabs(buttons[1].frame.origin.x - 152) < 0.5 &&
            fabs(buttons[3].frame.origin.x - 0) < 0.5 &&
            fabs(buttons[3].frame.origin.y - 46) < 0.5;

        unichar rightCharacter = NSRightArrowFunctionKey;
        unichar downCharacter = NSDownArrowFunctionKey;
        unichar leftCharacter = NSLeftArrowFunctionKey;
        unichar upCharacter = NSUpArrowFunctionKey;
        [panel keyDown:SDArrowEvent(124, rightCharacter, panel.windowNumber)];
        BOOL rightReady = panel.selectedIndex == 1;
        [panel keyDown:SDArrowEvent(125, downCharacter, panel.windowNumber)];
        BOOL downReady = panel.selectedIndex == 4;
        [panel keyDown:SDArrowEvent(123, leftCharacter, panel.windowNumber)];
        BOOL leftReady = panel.selectedIndex == 3;
        [panel keyDown:SDArrowEvent(126, upCharacter, panel.windowNumber)];
        BOOL upReady = panel.selectedIndex == 0;

        if (gridReady && mouseReady && mouseActionReady && rowMajorLayoutReady &&
            rightReady && downReady && leftReady && upReady) {
            fprintf(stdout, "SIDEDRAWER_CHOICE_GRID_TEST_OK\n");
            return 0;
        }
        fprintf(stderr,
                "SIDEDRAWER_CHOICE_GRID_TEST_FAILED grid=%d mouse=%d action=%d layout=%d right=%d down=%d left=%d up=%d\n",
                gridReady, mouseReady, mouseActionReady, rowMajorLayoutReady,
                rightReady, downReady, leftReady, upReady);
        return 1;
    }
}
