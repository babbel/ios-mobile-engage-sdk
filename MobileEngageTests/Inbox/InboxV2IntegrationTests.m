//
// Copyright (c) 2018 Emarsys. All rights reserved.
//

#import "Kiwi.h"
#import "MobileEngage.h"
#import "MEConfigBuilder.h"
#import "MEConfig.h"
#import "MENotificationInboxStatus.h"
#import "MEExperimental+Test.h"
#import "FakeStatusDelegate.h"
#import "MERequestContext.h"

#define DB_PATH [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"EMSSQLiteQueueDB.db"]

SPEC_BEGIN(InboxV2IntegrationTests)


        beforeEach(^{
            [[NSFileManager defaultManager] removeItemAtPath:DB_PATH
                                                       error:nil];
            NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
            [userDefaults removeObjectForKey:kMEID];
            [userDefaults synchronize];

            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:@"14C19-A121F"
                                       applicationPassword:@"PaNkfOD90AVpYimMBuZopCpm8OWCrREu"];
                [builder setExperimentalFeatures:@[INBOX_V2, INAPP_MESSAGING]];
            }];
            [MobileEngage setupWithConfig:config
                            launchOptions:nil];

            FakeStatusDelegate *statusDelegate = [FakeStatusDelegate new];

            [MobileEngage setStatusDelegate:statusDelegate];

            [MobileEngage appLoginWithContactFieldId:@3
                                   contactFieldValue:@"test@test.com"];

            [statusDelegate waitForNextSuccess];
        });

        afterEach(^{
            [MEExperimental reset];
        });

        describe(@"Notification Inbox", ^{

            it(@"fetchNotificationsWithResultBlock", ^{
                __block MENotificationInboxStatus *_inboxStatus;

                XCTestExpectation *exp = [[XCTestExpectation alloc] initWithDescription:@"waitForResult"];

                [MobileEngage.inbox fetchNotificationsWithResultBlock:^(MENotificationInboxStatus *inboxStatus) {
                            _inboxStatus = inboxStatus;
                            [exp fulfill];
                        }
                                                           errorBlock:^(NSError *error) {
                                                               fail(@"Unexpected error");
                                                           }];

                [XCTWaiter waitForExpectations:@[exp] timeout:30];

                [[_inboxStatus shouldNot] beNil];
            });


            it(@"resetBadgeCount", ^{
                __block BOOL _success = NO;

                XCTestExpectation *exp = [[XCTestExpectation alloc] initWithDescription:@"waitForResult"];

                [MobileEngage.inbox resetBadgeCountWithSuccessBlock:^{
                            _success = YES;
                            [exp fulfill];
                        }
                                                         errorBlock:^(NSError *error) {
                                                             fail(@"Unexpected error");
                                                         }];

                [XCTWaiter waitForExpectations:@[exp] timeout:30];

                [[theValue(_success) should] beYes];
            });

        });

SPEC_END
