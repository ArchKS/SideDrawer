// ai coding: 回归验证快捷键选择面板的多列布局、无滚动容器与方向键导航 2026/09/20: 09:55
#import "../Sources/SideDrawer/SDAppDelegate.h"
#import "../Sources/SideDrawer/SDDrawerChoicePanel.h"

@interface SDAppDelegate (ChoiceGridTest)
- (SDDrawerChoicePanel *)drawerChoicePanelForDrawers:(NSArray<NSDictionary *> *)drawers
                                           itemCount:(NSInteger)itemCount;
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
        NSArray<SDDrawerChoiceButton *> *buttons = panel.choiceButtons;
        BOOL gridReady = panel.choiceColumnCount == 3 && buttons.count == 13 &&
            fabs(panel.frame.size.width - 472) < 0.5 &&
            SDCountViewsOfClass(panel.contentView, NSScrollView.class) == 0;
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

        if (gridReady && rowMajorLayoutReady && rightReady && downReady && leftReady && upReady) {
            fprintf(stdout, "SIDEDRAWER_CHOICE_GRID_TEST_OK\n");
            return 0;
        }
        fprintf(stderr,
                "SIDEDRAWER_CHOICE_GRID_TEST_FAILED grid=%d layout=%d right=%d down=%d left=%d up=%d\n",
                gridReady, rowMajorLayoutReady, rightReady, downReady, leftReady, upReady);
        return 1;
    }
}
