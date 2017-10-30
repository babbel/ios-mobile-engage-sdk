//
// Copyright (c) 2017 Emarsys. All rights reserved.
//

#import "MEJSBridge.h"
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>

@implementation MEJSBridge

#define SYSTEM_VERSION_LESS_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)

- (void)requestPushPermission {
    UIApplication *application = [UIApplication sharedApplication];
    [application registerForRemoteNotifications];

    if (SYSTEM_VERSION_LESS_THAN(@"10.0")) {
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge)
                                                                                 categories:nil];
        [application registerUserNotificationSettings:settings];
    } else {
        [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:UNAuthorizationOptionSound | UNAuthorizationOptionAlert | UNAuthorizationOptionBadge
                                                                            completionHandler:nil];
    }

}

@end