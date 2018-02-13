#import "Kiwi.h"
#import "EMSRequestManager.h"
#import "MobileEngageInternal.h"
#import "MobileEngageInternal+Private.h"
#import "MEConfigBuilder.h"
#import "MEConfig.h"
#import "EMSRequestModelBuilder.h"
#import "EMSRequestModelMatcher.h"
#import "EMSAuthentication.h"
#import "EMSDeviceInfo.h"
#import "MobileEngageVersion.h"
#import "KiwiMacros.h"
#import "FakeRequestManager.h"
#import "EMSResponseModel.h"
#import "MEIdResponseHandler.h"
#import "MEIAMResponseHandler.h"
#import "MobileEngageInternal+Test.h"
#import "MEExperimental.h"
#import "MERequestRepositoryProxy.h"
#import "MEIAMCleanupResponseHandler.h"
#import "MENotificationCenterManager.h"

#define DB_PATH [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"EMSSQLiteQueueDB.db"]

static NSString *const kAppId = @"kAppId";
static NSString *const kAppSecret = @"kAppSecret";
static NSString *const kMEId = @"kMeId";
static NSString *const kMEIdSignature = @"kMeIdSignature";

MobileEngageInternal *_mobileEngage;

SPEC_BEGIN(MobileEngageInternalTests)

    registerMatchers(@"EMS");

    beforeEach(^{
        [MEExperimental stub:@selector(isFeatureEnabled:)
                   andReturn:theValue(YES)];
        _mobileEngage = [MobileEngageInternal new];
        [[NSFileManager defaultManager] removeItemAtPath:DB_PATH
                                                   error:nil];
        NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
        [userDefaults setObject:nil forKey:kMEID];
        [userDefaults setObject:nil forKey:kMEID_SIGNATURE];
        [userDefaults setObject:nil forKey:kLastAppLoginPayload];
        [userDefaults synchronize];
    });

    id (^requestManagerMock)() = ^id() {
        NSString *applicationCode = kAppId;
        NSString *applicationPassword = @"appSecret";
        NSDictionary *additionalHeaders = @{
                @"Content-Type": @"application/json",
                @"X-MOBILEENGAGE-SDK-VERSION": MOBILEENGAGE_SDK_VERSION,
                @"X-MOBILEENGAGE-SDK-MODE": @"debug"
        };
        id requestManager = [EMSRequestManager mock];

        [[requestManager should] receive:@selector(setAdditionalHeaders:) withCountAtLeast:1 arguments:additionalHeaders];

        MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
            [builder setCredentialsWithApplicationCode:applicationCode
                                   applicationPassword:applicationPassword];
        }];

        [_mobileEngage setupWithRequestManager:requestManager
                                        config:config
                                 launchOptions:nil];
        return requestManager;
    };

    id (^requestModel)(NSString *url, NSDictionary *payload) = ^id(NSString *url, NSDictionary *payload) {
        return [EMSRequestModel makeWithBuilder:^(EMSRequestModelBuilder *builder) {
            [builder setUrl:url];
            [builder setMethod:HTTPMethodPOST];
            [builder setPayload:payload];
            [builder setHeaders:@{@"Authorization": [EMSAuthentication createBasicAuthWithUsername:kAppId
                                                                                          password:@"appSecret"]}];
        }];
    };

    id (^requestModelV3)(NSString *url, NSDictionary *payload) = ^id(NSString *url, NSDictionary *payload) {
        return [EMSRequestModel makeWithBuilder:^(EMSRequestModelBuilder *builder) {
            [builder setUrl:url];
            [builder setMethod:HTTPMethodPOST];
            [builder setPayload:payload];
            [builder setHeaders:@{@"X-ME-ID": kMEID,
                    @"X-ME-ID-SIGNATURE": kMEID_SIGNATURE,
                    @"X-ME-APPLICATIONCODE": kAppId}];
        }];
    };

    describe(@"setupWithConfig:launchOptions:", ^{
        it(@"should setup the RequestManager with base64 auth header", ^{
            requestManagerMock();
        });

        it(@"should register MEIDResponseHandler", ^{
            requestManagerMock();

            BOOL registered = NO;
            for (AbstractResponseHandler *responseHandler in _mobileEngage.responseHandlers) {
                if ([responseHandler isKindOfClass:[MEIdResponseHandler class]]) {
                    registered = YES;
                }
            }

            [[theValue(registered) should] beYes];
        });

        it(@"should register MEIAMResponseHandler", ^{
            requestManagerMock();

            BOOL registered = NO;
            for (AbstractResponseHandler *responseHandler in _mobileEngage.responseHandlers) {
                if ([responseHandler isKindOfClass:[MEIAMResponseHandler class]]) {
                    registered = YES;
                }
            }

            [[theValue(registered) should] beYes];
        });

        it(@"should register MEIAMCleanupResponseHandler", ^{
            requestManagerMock();

            BOOL registered = NO;
            for (AbstractResponseHandler *responseHandler in _mobileEngage.responseHandlers) {
                if ([responseHandler isKindOfClass:[MEIAMCleanupResponseHandler class]]) {
                    registered = YES;
                }
            }

            [[theValue(registered) should] beYes];
        });

        it(@"should call setupWithRequestManager:config:launchOptions: with MERequestRepositoryProxy when INAPP feature turned on", ^{
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:kAppId
                                       applicationPassword:kAppSecret];
                [builder setExperimentalFeatures:@[INAPP_MESSAGING]];
            }];
            MobileEngageInternal *internal = [MobileEngageInternal new];
            KWCaptureSpy *spy = [internal captureArgument:@selector(setupWithRequestManager:config:launchOptions:)
                                                  atIndex:0];
            [internal setupWithConfig:config
                        launchOptions:nil];
            EMSRequestManager *manager = spy.argument;
            [[[manager.repository class] should] equal:[MERequestRepositoryProxy class]];
        });
    });

    describe(@"setPushToken:", ^{
        it(@"should call appLogin with lastAppLogin parameters", ^{
            NSData *deviceToken = [NSData new];
            [[_mobileEngage should] receive:@selector(appLoginWithContactFieldId:contactFieldValue:)
                                  withCount:1
                                  arguments:nil, nil, nil];

            _mobileEngage.lastAppLoginParameters = [MEAppLoginParameters parametersWithContactFieldId:nil contactFieldValue:nil];
            [_mobileEngage setPushToken:deviceToken];
        });

        it(@"should call appLogin with lastAppLogin parameters when there are previous values", ^{
            NSData *deviceToken = [NSData new];
            [[_mobileEngage should] receive:@selector(appLoginWithContactFieldId:contactFieldValue:)
                                  withCount:1
                                  arguments:@12, @"23", nil];

            _mobileEngage.lastAppLoginParameters = [MEAppLoginParameters parametersWithContactFieldId:@12 contactFieldValue:@"23"];
            [_mobileEngage setPushToken:deviceToken];
        });

        it(@"appLogin should save last anonymous AppLogin parameters", ^{
            [[requestManagerMock() should] receive:@selector(submit:)];
            [_mobileEngage appLogin];
            [[_mobileEngage.lastAppLoginParameters shouldNot] beNil];
            [[_mobileEngage.lastAppLoginParameters.contactFieldId should] beNil];
            [[_mobileEngage.lastAppLoginParameters.contactFieldValue should] beNil];
        });

        it(@"appLogin should save last AppLogin parameters", ^{
            [[requestManagerMock() should] receive:@selector(submit:)];
            [_mobileEngage appLoginWithContactFieldId:@42 contactFieldValue:@"99"];
            [[_mobileEngage.lastAppLoginParameters shouldNot] beNil];
            [[_mobileEngage.lastAppLoginParameters.contactFieldId should] equal:@42];
            [[_mobileEngage.lastAppLoginParameters.contactFieldValue should] equal:@"99"];
        });

        it(@"should not call appLogin with setPushToken when there was no previous appLogin call", ^{
            NSData *deviceToken = [NSData new];
            [[_mobileEngage shouldNot] receive:@selector(appLoginWithContactFieldId:contactFieldValue:)];
            [_mobileEngage setPushToken:deviceToken];
        });
    });


    describe(@"anonymous appLogin", ^{
        it(@"must not return with nil", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            NSString *uuid = [_mobileEngage appLogin];
            [[uuid shouldNot] beNil];
        });

        it(@"should return with requestModel's requestId", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            NSString *uuid = [_mobileEngage appLogin];
            EMSRequestModel *actualModel = spy.argument;
            [[uuid should] equal:actualModel.requestId];
        });

        it(@"should submit a corresponding RequestModel", ^{
            id requestManager = requestManagerMock();
            EMSRequestModel *model = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/users/login", @{
                    @"application_id": kAppId,
                    @"platform": @"ios",
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"language": [EMSDeviceInfo languageCode],
                    @"timezone": [EMSDeviceInfo timeZone],
                    @"device_model": [EMSDeviceInfo deviceModel],
                    @"os_version": [EMSDeviceInfo osVersion],
                    @"push_token": @NO,
                    @"application_version": @"1.0",
                    @"ems_sdk": MOBILEENGAGE_SDK_VERSION
            });

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            [_mobileEngage appLogin];

            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });

        it(@"appLogin should save the MEID returned in the response", ^{
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:kAppId
                                       applicationPassword:kAppSecret];
            }];
            MobileEngageInternal *internal = [MobileEngageInternal new];
            [internal setupWithConfig:config
                        launchOptions:nil];
            FakeRequestManager *fakeRequestManager = [FakeRequestManager managerWithSuccessBlock:internal.successBlock
                                                                                      errorBlock:internal.errorBlock];
            internal.requestManager = fakeRequestManager;

            NSNumber *meId = @123456789;
            NSString *meIdSignature = @"signature";
            NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"api_me_id": meId, @"me_id_signature": meIdSignature} options:0 error:nil];
            fakeRequestManager.responseModels = [@[[[EMSResponseModel alloc] initWithStatusCode:200 headers:@{} body:data]] mutableCopy];

            [internal appLogin];

            [fakeRequestManager waitForAllExpectations];

            [[expectFutureValue(internal.meId) shouldEventually] equal:[meId stringValue]];
        });

    });

    describe(@"appLoginWithContactFieldId:contactFieldValue:", ^{
        it(@"must not return with nil", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            NSString *uuid = [_mobileEngage appLoginWithContactFieldId:@0
                                                     contactFieldValue:@"contactFieldValue"];
            [[uuid shouldNot] beNil];
        });

        it(@"should return with requestModel's requestId", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            NSString *uuid = [_mobileEngage appLoginWithContactFieldId:@0
                                                     contactFieldValue:@"contactFieldValue"];
            EMSRequestModel *actualModel = spy.argument;
            [[uuid should] equal:actualModel.requestId];
        });

        it(@"should submit a corresponding RequestModel", ^{
            id requestManager = requestManagerMock();
            EMSRequestModel *model = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/users/login", @{
                    @"application_id": kAppId,
                    @"platform": @"ios",
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"language": [EMSDeviceInfo languageCode],
                    @"timezone": [EMSDeviceInfo timeZone],
                    @"device_model": [EMSDeviceInfo deviceModel],
                    @"os_version": [EMSDeviceInfo osVersion],
                    @"contact_field_id": @0,
                    @"contact_field_value": @"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek",
                    @"push_token": @NO,
                    @"application_version": @"1.0",
                    @"ems_sdk": MOBILEENGAGE_SDK_VERSION
            });

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            [_mobileEngage appLoginWithContactFieldId:@0
                                    contactFieldValue:@"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek"];
            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });
    });

    describe(@"multiple applogin calls", ^{

        it(@"should not result in multiple applogin requests even if the payload is the same", ^{
            FakeRequestManager *requestManager = [FakeRequestManager new];
            NSString *applicationCode = kAppId;
            NSString *applicationPassword = @"appSecret";
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:applicationCode
                                       applicationPassword:applicationPassword];
            }];

            [_mobileEngage setupWithRequestManager:requestManager
                                            config:config
                                     launchOptions:nil];

            EMSRequestModel *firstModel = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/users/login", @{
                    @"application_id": kAppId,
                    @"platform": @"ios",
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"language": [EMSDeviceInfo languageCode],
                    @"timezone": [EMSDeviceInfo timeZone],
                    @"device_model": [EMSDeviceInfo deviceModel],
                    @"os_version": [EMSDeviceInfo osVersion],
                    @"contact_field_id": @0,
                    @"contact_field_value": @"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek",
                    @"push_token": @NO,
                    @"application_version": @"1.0",
                    @"ems_sdk": MOBILEENGAGE_SDK_VERSION
            });


            EMSRequestModel *secondModel = requestModel([NSString stringWithFormat:@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/ems_lastMobileActivity"], @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"contact_field_id": @0,
                    @"contact_field_value": @"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek"
            });


            [_mobileEngage appLoginWithContactFieldId:@0
                                    contactFieldValue:@"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek"];
            [_mobileEngage appLoginWithContactFieldId:@0
                                    contactFieldValue:@"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek"];

            [[requestManager.submittedModels[0] should] beSimilarWithRequest:firstModel];
            [[requestManager.submittedModels[1] should] beSimilarWithRequest:secondModel];
        });

        it(@"should result in multiple applogin requests if the payload is not the same", ^{
            FakeRequestManager *requestManager = [FakeRequestManager new];
            NSString *applicationCode = kAppId;
            NSString *applicationPassword = @"appSecret";
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:applicationCode
                                       applicationPassword:applicationPassword];
            }];

            [_mobileEngage setupWithRequestManager:requestManager
                                            config:config
                                     launchOptions:nil];

            EMSRequestModel *firstModel = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/users/login", @{
                    @"application_id": kAppId,
                    @"platform": @"ios",
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"language": [EMSDeviceInfo languageCode],
                    @"timezone": [EMSDeviceInfo timeZone],
                    @"device_model": [EMSDeviceInfo deviceModel],
                    @"os_version": [EMSDeviceInfo osVersion],
                    @"contact_field_id": @0,
                    @"contact_field_value": @"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek",
                    @"push_token": @NO,
                    @"application_version": @"1.0",
                    @"ems_sdk": MOBILEENGAGE_SDK_VERSION
            });


            EMSRequestModel *secondModel = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/users/login", @{
                    @"application_id": kAppId,
                    @"platform": @"ios",
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"language": [EMSDeviceInfo languageCode],
                    @"timezone": [EMSDeviceInfo timeZone],
                    @"device_model": [EMSDeviceInfo deviceModel],
                    @"os_version": [EMSDeviceInfo osVersion],
                    @"contact_field_id": @0,
                    @"contact_field_value": @"something",
                    @"push_token": @NO,
                    @"application_version": @"1.0",
                    @"ems_sdk": MOBILEENGAGE_SDK_VERSION
            });


            [_mobileEngage appLoginWithContactFieldId:@0
                                    contactFieldValue:@"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek"];
            [_mobileEngage appLoginWithContactFieldId:@0
                                    contactFieldValue:@"something"];

            [[requestManager.submittedModels[0] should] beSimilarWithRequest:firstModel];
            [[requestManager.submittedModels[1] should] beSimilarWithRequest:secondModel];
        });

        it(@"should result in multiple applogin requests if the payload is the same size", ^{
            FakeRequestManager *requestManager = [FakeRequestManager new];
            NSString *applicationCode = kAppId;
            NSString *applicationPassword = @"appSecret";
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:applicationCode
                                       applicationPassword:applicationPassword];
            }];

            [_mobileEngage setupWithRequestManager:requestManager
                                            config:config
                                     launchOptions:nil];

            EMSRequestModel *firstModel = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/users/login", @{
                    @"application_id": kAppId,
                    @"platform": @"ios",
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"language": [EMSDeviceInfo languageCode],
                    @"timezone": [EMSDeviceInfo timeZone],
                    @"device_model": [EMSDeviceInfo deviceModel],
                    @"os_version": [EMSDeviceInfo osVersion],
                    @"contact_field_id": @0,
                    @"contact_field_value": @"contactFieldValue1",
                    @"push_token": @NO,
                    @"application_version": @"1.0",
                    @"ems_sdk": MOBILEENGAGE_SDK_VERSION
            });


            EMSRequestModel *secondModel = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/users/login", @{
                    @"application_id": kAppId,
                    @"platform": @"ios",
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"language": [EMSDeviceInfo languageCode],
                    @"timezone": [EMSDeviceInfo timeZone],
                    @"device_model": [EMSDeviceInfo deviceModel],
                    @"os_version": [EMSDeviceInfo osVersion],
                    @"contact_field_id": @0,
                    @"contact_field_value": @"contactFieldValue2",
                    @"push_token": @NO,
                    @"application_version": @"1.0",
                    @"ems_sdk": MOBILEENGAGE_SDK_VERSION
            });


            [_mobileEngage appLoginWithContactFieldId:@0
                                    contactFieldValue:@"contactFieldValue1"];
            [_mobileEngage appLoginWithContactFieldId:@0
                                    contactFieldValue:@"contactFieldValue2"];

            [[requestManager.submittedModels[0] should] beSimilarWithRequest:firstModel];
            [[requestManager.submittedModels[1] should] beSimilarWithRequest:secondModel];
        });

        it(@"should not result in multiple applogin requests if the payload is the same, even if MobileEngage is re-initialized", ^{
            NSString *applicationCode = kAppId;
            NSString *applicationPassword = @"appSecret";
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:applicationCode
                                       applicationPassword:applicationPassword];
            }];

            FakeRequestManager *requestManager = [FakeRequestManager new];
            [_mobileEngage setupWithRequestManager:requestManager
                                            config:config
                                     launchOptions:nil];

            EMSRequestModel *firstModel = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/users/login", @{
                    @"application_id": kAppId,
                    @"platform": @"ios",
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"language": [EMSDeviceInfo languageCode],
                    @"timezone": [EMSDeviceInfo timeZone],
                    @"device_model": [EMSDeviceInfo deviceModel],
                    @"os_version": [EMSDeviceInfo osVersion],
                    @"contact_field_id": @0,
                    @"contact_field_value": @"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek",
                    @"push_token": @NO,
                    @"application_version": @"1.0",
                    @"ems_sdk": MOBILEENGAGE_SDK_VERSION
            });


            EMSRequestModel *secondModel = requestModel([NSString stringWithFormat:@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/ems_lastMobileActivity"], @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"contact_field_id": @0,
                    @"contact_field_value": @"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek"
            });


            [_mobileEngage appLoginWithContactFieldId:@0
                                    contactFieldValue:@"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek"];

            _mobileEngage = [MobileEngageInternal new];
            [_mobileEngage setupWithRequestManager:requestManager
                                            config:config
                                     launchOptions:nil];

            [_mobileEngage appLoginWithContactFieldId:@0
                                    contactFieldValue:@"vadaszRepulogepAnyahajoKabinHajtogatoKeziKeszulek"];

            [[requestManager.submittedModels[0] should] beSimilarWithRequest:firstModel];
            [[requestManager.submittedModels[1] should] beSimilarWithRequest:secondModel];
        });
    });

    describe(@"applogout", ^{
        it(@"must not return with nil", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            NSString *uuid = [_mobileEngage appLogout];
            [[uuid shouldNot] beNil];
        });

        it(@"should return with requestModel's requestId", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            NSString *uuid = [_mobileEngage appLogout];

            EMSRequestModel *actualModel = spy.argument;
            [[uuid should] equal:actualModel.requestId];
        });

        it(@"should submit a corresponding RequestModel if there is no saved applogin parameters", ^{
            id requestManager = requestManagerMock();
            EMSRequestModel *model = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/users/logout", @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
            });

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            [_mobileEngage appLogout];

            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });

        it(@"should submit a corresponding RequestModel if there is saved applogin parameters", ^{
            id requestManager = requestManagerMock();
            EMSRequestModel *model = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/users/logout", @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"contact_field_id": @123456789,
                    @"contact_field_value": @"contactFieldValue"
            });

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];

            [_mobileEngage setLastAppLoginParameters:[MEAppLoginParameters parametersWithContactFieldId:@123456789
                                                                                      contactFieldValue:@"contactFieldValue"]];
            [_mobileEngage appLogout];

            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });

        it(@"should clear lastAppLoginParameters", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)];

            [_mobileEngage setLastAppLoginParameters:[MEAppLoginParameters parametersWithContactFieldId:@123456789
                                                                                      contactFieldValue:@"contactFieldValue"]];
            [_mobileEngage appLogout];
            [[_mobileEngage.lastAppLoginParameters should] beNil];
        });

        it(@"should clear lastAppLoginPayload", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)];

            [_mobileEngage setLastAppLoginPayload:@{@"t": @"v"}];
            [_mobileEngage appLogout];
            [[_mobileEngage.lastAppLoginPayload should] beNil];
        });

    });

    describe(@"trackMessageOpenWithUserInfo:", ^{
        it(@"must not return with nil", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            NSString *uuid = [_mobileEngage trackMessageOpenWithUserInfo:@{@"u": @"{\"sid\":\"123456789\"}"}];
            [[uuid shouldNot] beNil];
        });

        it(@"should return with requestModel's requestId", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            NSString *uuid = [_mobileEngage trackMessageOpenWithUserInfo:@{@"u": @"{\"sid\":\"123456789\"}"}];

            EMSRequestModel *actualModel = spy.argument;
            [[uuid should] equal:actualModel.requestId];
        });

        it(@"should submit a corresponding RequestModel when there is no contact_field_id and contact_field_value", ^{
            id requestManager = requestManagerMock();

            EMSRequestModel *model = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/message_open", @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"sid": @"123456789"
            });

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            [_mobileEngage trackMessageOpenWithUserInfo:@{@"u": @"{\"sid\":\"123456789\"}"}];

            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });

        it(@"should submit a corresponding RequestModel when there are contact_field_id and contact_field_value", ^{
            id requestManager = requestManagerMock();
            MEAppLoginParameters *appLoginParameters = [MEAppLoginParameters parametersWithContactFieldId:@3
                                                                                        contactFieldValue:@"contactFieldValue"];

            [_mobileEngage stub:@selector(lastAppLoginParameters)
                      andReturn:appLoginParameters];

            EMSRequestModel *model = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/message_open", @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"contact_field_id": @3,
                    @"contact_field_value": @"contactFieldValue",
                    @"sid": @"123456789"
            });

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            [_mobileEngage trackMessageOpenWithUserInfo:@{@"u": @"{\"sid\":\"123456789\"}"}];

            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });
    });

    describe(@"trackMessageOpenWithInboxMessage:", ^{
        it(@"should throw exception when parameter is nil", ^{
            @try {
                [_mobileEngage trackMessageOpenWithInboxMessage:nil];
                fail(@"Expected Exception when inboxMessage is nil!");
            } @catch (NSException *exception) {
                [[theValue(exception) shouldNot] beNil];
            }
        });

        it(@"should submit a corresponding RequestModel when there is no contact_field_id and contact_field_value", ^{
            id requestManager = requestManagerMock();

            EMSRequestModel *model = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/message_open", @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"sid": @"testID",
                    @"source": @"inbox"
            });

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            MENotification *message = [MENotification new];
            message.sid = @"testID";
            [_mobileEngage trackMessageOpenWithInboxMessage:message];

            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });

        it(@"should submit a corresponding RequestModel when there are contact_field_id and contact_field_value", ^{
            id requestManager = requestManagerMock();

            MEAppLoginParameters *appLoginParameters = [MEAppLoginParameters parametersWithContactFieldId:@3
                                                                                        contactFieldValue:@"contactFieldValue"];

            [_mobileEngage stub:@selector(lastAppLoginParameters)
                      andReturn:appLoginParameters];

            EMSRequestModel *model = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/message_open", @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"sid": @"valueOfSid",
                    @"contact_field_id": @3,
                    @"contact_field_value": @"contactFieldValue",
                    @"source": @"inbox"
            });

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            MENotification *message = [MENotification new];
            message.sid = @"valueOfSid";
            [_mobileEngage trackMessageOpenWithInboxMessage:message];

            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });

        it(@"should submit a corresponding RequestModel", ^{
            id requestManager = requestManagerMock();

            EMSRequestModel *model = requestModel(@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/message_open", @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"sid": @"valueOfSid",
                    @"source": @"inbox"
            });

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            MENotification *message = [MENotification new];
            message.sid = @"valueOfSid";
            [_mobileEngage trackMessageOpenWithInboxMessage:message];

            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });

        it(@"should return with the requestModel's requestID", ^{
            id requestManager = requestManagerMock();

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            MENotification *message = [MENotification new];
            message.sid = @"valueOfSid";
            NSString *requestID = [_mobileEngage trackMessageOpenWithInboxMessage:message];

            EMSRequestModel *actualModel = spy.argument;
            [[requestID should] equal:actualModel.requestId];
        });

        it(@"must not return with nil", ^{
            id requestManager = requestManagerMock();
            MENotification *message = [MENotification new];
            message.sid = @"testID";
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            NSString *uuid = [_mobileEngage trackMessageOpenWithInboxMessage:message];

            [[uuid shouldNot] beNil];
        });
    });

    describe(@"trackCustomEvent:eventAttributes:", ^{
        it(@"must not return with nil", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            _mobileEngage.meId = kMEID;
            _mobileEngage.meIdSignature = kMEID_SIGNATURE;
            NSString *uuid = [_mobileEngage trackCustomEvent:@""
                                             eventAttributes:@{}];
            [[uuid shouldNot] beNil];
        });

        it(@"should return with requestModel's requestId", ^{
            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];
            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            _mobileEngage.meId = kMEID;
            _mobileEngage.meIdSignature = kMEID_SIGNATURE;
            NSString *uuid = [_mobileEngage trackCustomEvent:@""
                                             eventAttributes:@{}];

            EMSRequestModel *actualModel = spy.argument;
            [[uuid should] equal:actualModel.requestId];
        });

        it(@"should throw exception when eventName is nil", ^{
            @try {
                [_mobileEngage trackCustomEvent:nil
                                eventAttributes:@{}];
                fail(@"Expected Exception when eventName is nil!");
            } @catch (NSException *exception) {
                [[theValue(exception) shouldNot] beNil];
            }
        });

        it(@"should submit a corresponding RequestModel, when eventAttributes are set", ^{
            id requestManager = requestManagerMock();

            id timeStampProviderMock = [EMSTimestampProvider mock];
            NSString *timeStamp = @"2017-12-07T10:46:09.100Z";
            [[timeStampProviderMock should] receive:@selector(currentTimestampInUTC) andReturn:timeStamp withCountAtLeast:0];
            _mobileEngage.timestampProvider = timeStampProviderMock;

            _mobileEngage.meId = kMEID;
            _mobileEngage.meIdSignature = kMEID_SIGNATURE;
            NSString *eventName = @"testEventName";
            NSDictionary *eventAttributes = @{@"someKey": @"someValue"};

            NSDictionary *payload = @{
                    @"clicks": @[],
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"viewed_messages": @[],
                    @"events": @[
                            @{
                                    @"type": @"custom",
                                    @"name": eventName,
                                    @"attributes": eventAttributes,
                                    @"timestamp": timeStamp
                            }
                    ]
            };

            EMSRequestModel *model = requestModelV3([NSString stringWithFormat:@"https://mobile-events.eservice.emarsys.net/v3/devices/%@/events", kMEID], payload);

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];

            [_mobileEngage trackCustomEvent:eventName
                            eventAttributes:eventAttributes];
            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });

        it(@"should submit a corresponding RequestModel, when eventAttributes are missing", ^{
            id requestManager = requestManagerMock();

            id timeStampProviderMock = [EMSTimestampProvider mock];
            NSString *timeStamp = @"2017-12-07T10:46:09.100Z";
            [[timeStampProviderMock should] receive:@selector(currentTimestampInUTC) andReturn:timeStamp withCountAtLeast:0];
            _mobileEngage.timestampProvider = timeStampProviderMock;

            _mobileEngage.meId = kMEID;
            _mobileEngage.meIdSignature = kMEID_SIGNATURE;
            NSString *eventName = @"testEventName";

            NSDictionary *payload = @{
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"clicks": @[],
                    @"viewed_messages": @[],
                    @"events": @[
                            @{
                                    @"type": @"custom",
                                    @"name": eventName,
                                    @"timestamp": timeStamp
                            }
                    ]
            };

            EMSRequestModel *model = requestModelV3([NSString stringWithFormat:@"https://mobile-events.eservice.emarsys.net/v3/devices/%@/events", kMEID], payload);

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];

            [_mobileEngage trackCustomEvent:eventName
                            eventAttributes:nil];
            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });


        it(@"should submit a corresponding RequestModel, when eventAttributes are set and there is no saved contactFieldId and contactFieldValue", ^{
            [MEExperimental stub:@selector(isFeatureEnabled:)
                       andReturn:theValue(NO)];

            id requestManager = requestManagerMock();

            NSString *eventName = @"testEventName";
            NSDictionary *eventAttributes = @{@"someKey": @"someValue"};

            NSDictionary *payload = @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"attributes": eventAttributes
            };

            EMSRequestModel *model = requestModel([NSString stringWithFormat:@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/%@", eventName], payload);

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            [_mobileEngage trackCustomEvent:eventName
                            eventAttributes:eventAttributes];
            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });

        it(@"should submit a corresponding RequestModel, when eventAttributes are set and there are saved contactFieldId and contactFieldValue", ^{
            [MEExperimental stub:@selector(isFeatureEnabled:)
                       andReturn:theValue(NO)];

            id requestManager = requestManagerMock();

            MEAppLoginParameters *appLoginParameters = [MEAppLoginParameters parametersWithContactFieldId:@3
                                                                                        contactFieldValue:@"contactFieldValue"];

            [_mobileEngage stub:@selector(lastAppLoginParameters)
                      andReturn:appLoginParameters];

            NSString *eventName = @"testEventName";
            NSDictionary *eventAttributes = @{@"someKey": @"someValue"};

            NSDictionary *payload = @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"attributes": eventAttributes,
                    @"contact_field_id": @3,
                    @"contact_field_value": @"contactFieldValue"
            };

            EMSRequestModel *model = requestModel([NSString stringWithFormat:@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/%@", eventName], payload);

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            [_mobileEngage trackCustomEvent:eventName
                            eventAttributes:eventAttributes];
            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });


        it(@"should submit a corresponding RequestModel, when eventAttributes are missing and there is no saved contactFieldId and contactFieldValue", ^{
            [MEExperimental stub:@selector(isFeatureEnabled:)
                       andReturn:theValue(NO)];

            id requestManager = requestManagerMock();

            NSString *eventName = @"testEventName";

            NSDictionary *payload = @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
            };

            EMSRequestModel *model = requestModel([NSString stringWithFormat:@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/%@", eventName], payload);

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            [_mobileEngage trackCustomEvent:eventName
                            eventAttributes:nil];
            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });


        it(@"should submit a corresponding RequestModel, when eventAttributes are missing and there are saved contactFieldId and contactFieldValue", ^{
            [MEExperimental stub:@selector(isFeatureEnabled:)
                       andReturn:theValue(NO)];

            id requestManager = requestManagerMock();

            MEAppLoginParameters *appLoginParameters = [MEAppLoginParameters parametersWithContactFieldId:@3
                                                                                        contactFieldValue:@"contactFieldValue"];

            [_mobileEngage stub:@selector(lastAppLoginParameters)
                      andReturn:appLoginParameters];

            NSString *eventName = @"testEventName";

            NSDictionary *payload = @{
                    @"application_id": kAppId,
                    @"hardware_id": [EMSDeviceInfo hardwareId],
                    @"contact_field_id": @3,
                    @"contact_field_value": @"contactFieldValue"
            };

            EMSRequestModel *model = requestModel([NSString stringWithFormat:@"https://push.eservice.emarsys.net/api/mobileengage/v2/events/%@", eventName], payload);

            [[requestManager should] receive:@selector(submit:)
                               withArguments:any(), any(), any()];

            KWCaptureSpy *spy = [requestManager captureArgument:@selector(submit:)
                                                        atIndex:0];
            [_mobileEngage trackCustomEvent:eventName
                            eventAttributes:nil];
            EMSRequestModel *actualModel = spy.argument;
            [[model should] beSimilarWithRequest:actualModel];
        });


    });


    describe(@"appStart", ^{

        beforeEach(^{

            _mobileEngage = [MobileEngageInternal new];


            _mobileEngage.meId = kMEID;
            _mobileEngage.meIdSignature = kMEID_SIGNATURE;

        });

        it(@"should register UIApplicationDidBecomeActiveNotification", ^{
            id notificationCenterManagerMock = [MENotificationCenterManager mock];
            [_mobileEngage setNotificationCenterManager:notificationCenterManagerMock];

            [[notificationCenterManagerMock should] receive:@selector(addHandlerBlock:forNotification:) withArguments:any(), UIApplicationDidBecomeActiveNotification];
            requestManagerMock();
        });

        it(@"should submit appstart event on UIApplicationDidBecomeActiveNotification", ^{
            id notificationCenterManagerMock = [MENotificationCenterManager mock];
            [_mobileEngage setNotificationCenterManager:notificationCenterManagerMock];
            [_mobileEngage setMeId:@"testMeId"];
            [_mobileEngage setMeIdSignature:@"testMeIdSig"];

            [[notificationCenterManagerMock should] receive:@selector(addHandlerBlock:forNotification:) withArguments:any(), UIApplicationDidBecomeActiveNotification];
            KWCaptureSpy *spy = [notificationCenterManagerMock captureArgument:@selector(addHandlerBlock:forNotification:) atIndex:0];

            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:) withCountAtLeast:1];
            KWCaptureSpy *submitSpy = [requestManager captureArgument:@selector(submit:) atIndex:0];
            MEHandlerBlock block = spy.argument;
            block();


            EMSRequestModel *result = submitSpy.argument;
            [[[result.url absoluteString] should] equal:@"https://mobile-events.eservice.emarsys.net/v3/devices/testMeId/events"];
            [[result.payload[@"events"][0][@"type"] should] equal:@"internal"];
            [[result.payload[@"events"][0][@"name"] should] equal:@"app:start"];
        });

        it(@"should submit inapp:viewed event when trackInAppDisplay: called", ^{
            [_mobileEngage setMeId:@"testMeId"];
            [_mobileEngage setMeIdSignature:@"testMeIdSig"];

            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:) withCountAtLeast:1];
            KWCaptureSpy *submitSpy = [requestManager captureArgument:@selector(submit:) atIndex:0];

            [_mobileEngage trackInAppDisplay:@"testCampaignId"];

            EMSRequestModel *result = submitSpy.argument;
            [[[result.url absoluteString] should] equal:@"https://mobile-events.eservice.emarsys.net/v3/devices/testMeId/events"];
            [[result.payload[@"events"][0][@"type"] should] equal:@"internal"];
            [[result.payload[@"events"][0][@"name"] should] equal:@"inapp:viewed"];
            [[result.payload[@"events"][0][@"attributes"][@"message_id"] should] equal:@"testCampaignId"];
        });

        it(@"should submit inapp:viewed event when trackInAppClick: called", ^{
            [_mobileEngage setMeId:@"testMeId"];
            [_mobileEngage setMeIdSignature:@"testMeIdSig"];

            id requestManager = requestManagerMock();
            [[requestManager should] receive:@selector(submit:) withCountAtLeast:1];
            KWCaptureSpy *submitSpy = [requestManager captureArgument:@selector(submit:) atIndex:0];

            [_mobileEngage trackInAppClick:@"testCampaignId" buttonId:@"123"];

            EMSRequestModel *result = submitSpy.argument;
            [[[result.url absoluteString] should] equal:@"https://mobile-events.eservice.emarsys.net/v3/devices/testMeId/events"];
            [[result.payload[@"events"][0][@"type"] should] equal:@"internal"];
            [[result.payload[@"events"][0][@"name"] should] equal:@"inapp:click"];
            [[result.payload[@"events"][0][@"attributes"][@"message_id"] should] equal:@"testCampaignId"];
            [[result.payload[@"events"][0][@"attributes"][@"button_id"] should] equal:@"123"];
        });

        it(@"should not call submit on RequestManager when there is no meid (no login)", ^{
            id notificationCenterManagerMock = [MENotificationCenterManager mock];
            [_mobileEngage setNotificationCenterManager:notificationCenterManagerMock];
            [_mobileEngage setMeId:nil];

            [[notificationCenterManagerMock should] receive:@selector(addHandlerBlock:forNotification:) withArguments:any(), UIApplicationDidBecomeActiveNotification];
            KWCaptureSpy *spy = [notificationCenterManagerMock captureArgument:@selector(addHandlerBlock:forNotification:) atIndex:0];

            id requestManager = requestManagerMock();
            [[requestManager shouldNot] receive:@selector(submit:)];
            MEHandlerBlock block = spy.argument;
            block();
        });

    });

    describe(@"meID", ^{
        it(@"should store the meID in userDefaults when the setter invoked", ^{
            NSString *meID = @"meIDValue";

            [_mobileEngage setMeId:meID];

            NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
            NSString *returnedValue = [userDefaults stringForKey:kMEID];

            [[returnedValue should] equal:meID];
        });

        it(@"should load the stored value when setup called on MobileEngageInternal", ^{
            NSString *meID = @"StoredValueOfMobileEngageId";

            NSString *applicationCode = kAppId;
            NSString *applicationPassword = @"appSecret";
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:applicationCode
                                       applicationPassword:applicationPassword];
            }];

            NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
            [userDefaults setObject:meID
                             forKey:kMEID];
            [userDefaults synchronize];

            [_mobileEngage setupWithConfig:config
                             launchOptions:nil];

            [[_mobileEngage.meId should] equal:meID];
        });

        it(@"should be cleared from userdefaults on logout", ^{
            NSString *meID = @"NotNil";

            NSString *applicationCode = kAppId;
            NSString *applicationPassword = @"appSecret";
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:applicationCode
                                       applicationPassword:applicationPassword];
            }];
            [_mobileEngage setupWithConfig:config
                             launchOptions:nil];

            NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
            [userDefaults setObject:meID
                             forKey:kMEID];
            [userDefaults synchronize];

            [_mobileEngage appLogout];

            [[_mobileEngage.meId should] beNil];
        });

    });

    describe(@"meIdSignature", ^{
        it(@"should store the meIDSignature in userDefaults when the setter invoked", ^{
            NSString *meIDSignature = @"meIDSignatureValue";

            [_mobileEngage setMeIdSignature:meIDSignature];

            NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
            NSString *returnedValue = [userDefaults stringForKey:kMEID_SIGNATURE];

            [[returnedValue should] equal:meIDSignature];
        });

        it(@"should load the stored value when setup called on MobileEngageInternal", ^{
            NSString *meIDSignature = @"signature";

            NSString *applicationCode = kAppId;
            NSString *applicationPassword = @"appSecret";
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:applicationCode
                                       applicationPassword:applicationPassword];
            }];

            NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
            [userDefaults setObject:meIDSignature
                             forKey:kMEID_SIGNATURE];
            [userDefaults synchronize];

            [_mobileEngage setupWithConfig:config
                             launchOptions:nil];

            [[_mobileEngage.meIdSignature should] equal:meIDSignature];
        });

        it(@"should be cleared from userdefaults on logout", ^{
            NSString *meIdSignature = @"NotNil";

            NSString *applicationCode = kAppId;
            NSString *applicationPassword = @"appSecret";
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:applicationCode
                                       applicationPassword:applicationPassword];
            }];
            [_mobileEngage setupWithConfig:config
                             launchOptions:nil];

            NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
            [userDefaults setObject:meIdSignature
                             forKey:kMEID_SIGNATURE];
            [userDefaults synchronize];

            [_mobileEngage appLogout];

            [[_mobileEngage.meIdSignature should] beNil];
        });
    });

    describe(@"experimental", ^{
        it(@"should enable experimental features based on the features given in the config", ^{
            NSArray<MEFlipperFeature> *features = @[INAPP_MESSAGING];
            NSString *applicationCode = kAppId;
            NSString *applicationPassword = @"appSecret";
            MEConfig *config = [MEConfig makeWithBuilder:^(MEConfigBuilder *builder) {
                [builder setCredentialsWithApplicationCode:applicationCode
                                       applicationPassword:applicationPassword];
                [builder setExperimentalFeatures:features];
            }];
            [_mobileEngage setupWithConfig:config
                             launchOptions:nil];

            for (MEFlipperFeature feature in features) {
                [[theValue([MEExperimental isFeatureEnabled:feature]) should] beYes];
            }

        });
    });

SPEC_END