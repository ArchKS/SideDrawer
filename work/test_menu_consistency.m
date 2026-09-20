// ai coding: 验证状态菜单与主菜单标题一致且收纳盒子菜单不再混入应用级操作 2026/09/17: 15:50
#import "SDAppDelegate.h"

static NSArray<NSString *> *SDMenuTitles(NSMenu *menu) {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem) continue;
        if (item.submenu) [titles addObjectsFromArray:SDMenuTitles(item.submenu)];
        else [titles addObject:item.title];
    }
    return titles;
}

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        SDAppDelegate *delegate = [[SDAppDelegate alloc] init];
        app.delegate = delegate;
        [delegate configureMainMenu];
        [delegate configureStatusItem];

        NSMenu *mainMenu = NSApp.mainMenu;
        NSMenu *drawerSubmenu = nil;
        for (NSMenuItem *item in mainMenu.itemArray) {
            if ([item.title isEqualToString:SDMenuTitleDrawerMenu]) drawerSubmenu = item.submenu;
        }

        NSArray<NSString *> *drawerTitles = SDMenuTitles(drawerSubmenu);
        NSArray<NSDictionary *> *appItems = [delegate applicationMenuItems];

        BOOL packedQuit = [drawerTitles containsObject:SDMenuTitleQuit];
        BOOL packedShowAll = [drawerTitles containsObject:SDMenuTitleShowAll];
        NSUInteger expectedDrawerCount = 8;
        NSUInteger expectedAppCount = 5;
        BOOL quitIsAppLevel = [mainMenu.itemArray.firstObject.submenu.itemArray.lastObject.title isEqualToString:SDMenuTitleQuit];

        fprintf(stdout, "drawer_items=%ld (expect %ld)\n", (long)drawerTitles.count, (long)expectedDrawerCount);
        fprintf(stdout, "app_items=%ld (expect %ld)\n", (long)appItems.count, (long)expectedAppCount);
        fprintf(stdout, "quit_leaked_into_drawer_menu=%s (expect false)\n", packedQuit ? "true" : "false");
        fprintf(stdout, "showall_leaked_into_drawer_menu=%s (expect false)\n", packedShowAll ? "true" : "false");
        fprintf(stdout, "quit_in_app_menu=%s (expect true)\n", quitIsAppLevel ? "true" : "false");
        // ai coding: 追加菜单文案一致性与旧用词检查，防止抽屉、收纳盒、收纳箱再次混用  2026/09/17: 16:11
        NSArray<NSString *> *appTitles = [appItems valueForKey:@"title"];
        NSArray<NSString *> *statusMenuTitles = SDMenuTitles(((NSStatusItem *)[delegate valueForKey:@"_statusItem"]).menu);
        BOOL appTitlesMatch = [appTitles isEqualToArray:@[SDMenuTitleShortcutConfiguration, SDMenuTitleShowAll,
                                                          SDMenuTitleHideAll, SDMenuTitleRevealApplication, SDMenuTitleQuit]];
        BOOL statusMenuMatchesDrawerMenu = [statusMenuTitles containsObject:SDMenuTitleNewDrawer] &&
                                          [statusMenuTitles containsObject:SDMenuTitleQuit];
        BOOL legacyTermFree = YES;
        for (NSString *title in [drawerTitles arrayByAddingObjectsFromArray:appTitles]) {
            if ([title containsString:@"收纳"]) legacyTermFree = NO;
            if ([title containsString:@"Finder"]) legacyTermFree = NO;
        }
        fprintf(stdout, "app_titles_match_shared_table=%s (expect true)\n", appTitlesMatch ? "true" : "false");
        BOOL statusMenuTitlesMatchApp = [[statusMenuTitles filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF IN %@", appTitles]] count] == appTitles.count;
        BOOL noDuplicatedShortcutTitle = [statusMenuTitles filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"SELF BEGINSWITH %@", SDMenuTitleShortcutConfiguration]].count == 1;
        fprintf(stdout, "status_menu_matches_drawer_menu=%s (expect true)\n", statusMenuMatchesDrawerMenu ? "true" : "false");
        fprintf(stdout, "status_menu_titles=[%s]\n", [[statusMenuTitles componentsJoinedByString:@" / "] UTF8String]);
        fprintf(stdout, "status_menu_contains_all_app_titles=%s (expect true)\n", statusMenuTitlesMatchApp ? "true" : "false");
        fprintf(stdout, "no_duplicated_shortcut_title=%s (expect true)\n", noDuplicatedShortcutTitle ? "true" : "false");
        fprintf(stdout, "legacy_terms_absent=%s (expect true)\n", legacyTermFree ? "true" : "false");

        BOOL ok = drawerTitles.count == expectedDrawerCount && appItems.count == expectedAppCount &&
                  !packedQuit && !packedShowAll && quitIsAppLevel &&
                  appTitlesMatch && statusMenuMatchesDrawerMenu && statusMenuTitlesMatchApp &&
                  noDuplicatedShortcutTitle && legacyTermFree;
        fprintf(stdout, ok ? "MENU_CONSISTENCY_OK\n" : "MENU_CONSISTENCY_FAILED\n");
        return ok ? 0 : 1;
    }
}
