// Dayloft contributors. SPDX-License-Identifier: GPL-3.0-or-later
#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "SCSettings.h"
#import "SCUtility.h"

@interface SCSettings (IsolationTests)
- (void)onSettingChanged:(NSNotification*)notification;
+ (NSString*)testForbiddenSettingsPath;
@end
@implementation SCSettings (IsolationTests)
+ (NSString*)testForbiddenSettingsPath {
    @throw [NSException exceptionWithName:@"LiveSettingsAccess" reason:@"Tests must never access the live store" userInfo:nil];
}
@end

static NSUInteger notificationPosts;
@interface NSDistributedNotificationCenter (IsolationTests)
- (void)testCapturePost:(NSString*)name object:(NSString*)object userInfo:(NSDictionary*)info options:(NSUInteger)options;
@end
@implementation NSDistributedNotificationCenter (IsolationTests)
- (void)testCapturePost:(NSString*)name object:(NSString*)object userInfo:(NSDictionary*)info options:(NSUInteger)options {
    // Intentionally never forward to the real center, even if a regression occurs.
    notificationPosts++;
}
@end

@interface SCSettingsIsolationTests : XCTestCase
@end
@implementation SCSettingsIsolationTests
- (void)testCleanupFinalizesFocusHistory {
    SCSettings* settings = SCSettings.sharedSettings;
    settings.readOnly = NO;
    NSDate* start = [NSDate dateWithTimeIntervalSinceNow:-60];
    [settings setValue:@[@{@"start": start, @"end": [NSDate dateWithTimeIntervalSinceNow:3600], @"breaks": @[]}] forKey:@"DayloftFocusSessions"];
    [SCBlockUtilities removeBlockFromSettings];
    NSDate* recordedEnd = [[settings valueForKey:@"DayloftFocusSessions"] lastObject][@"end"];
    XCTAssertEqualWithAccuracy(recordedEnd.timeIntervalSinceNow, 0, 2);
    XCTAssertFalse([settings boolForKey:@"BlockIsRunning"]);
    [settings resetAllSettingsToDefaults];
}
- (void)testStoreNeverReadsOrWritesLiveSettings {
    Method real = class_getClassMethod(SCSettings.class, @selector(securedSettingsFilePath));
    Method trap = class_getClassMethod(SCSettings.class, @selector(testForbiddenSettingsPath));
    method_exchangeImplementations(real, trap);
    @try {
        SCSettings* settings = [SCSettings new];
        settings.readOnly = NO;
        XCTAssertFalse([settings boolForKey:@"BlockIsRunning"]);
        [settings setValue:@YES forKey:@"BlockIsRunning"];
        XCTAssertNoThrow([settings reloadSettings]);
        XCTAssertNoThrow([settings writeSettings]);
        XCTAssertNoThrow([settings synchronizeSettings]);
        XCTAssertTrue([settings boolForKey:@"BlockIsRunning"]);
    } @finally {
        method_exchangeImplementations(real, trap);
    }
}
- (void)testMutationsNeverBroadcastToRunningApps {
    Method real = class_getInstanceMethod(NSDistributedNotificationCenter.class, @selector(postNotificationName:object:userInfo:options:));
    Method capture = class_getInstanceMethod(NSDistributedNotificationCenter.class, @selector(testCapturePost:object:userInfo:options:));
    notificationPosts = 0;
    method_exchangeImplementations(real, capture);
    @try {
        SCSettings* settings = [SCSettings new];
        settings.readOnly = NO;
        [settings setValue:@YES forKey:@"BlockIsRunning"];
        [settings resetAllSettingsToDefaults];
        [settings synchronizeSettings];
        XCTAssertEqual(notificationPosts, 0u);
    } @finally {
        method_exchangeImplementations(real, capture);
    }
}
- (void)testAuthoritativeWriterRejectsUntrustedNotification {
    SCSettings* settings = [SCSettings new];
    settings.readOnly = NO;
    [settings setValue:@YES forKey:@"BlockIsRunning"];
    NSDictionary* before = settings.dictionaryRepresentation;
    NSNotification* forged = [NSNotification notificationWithName:@"org.dayloft.Dayloft.SCSettingsValueChanged" object:@"other-process"
        userInfo:@{@"key": @"BlockIsRunning", @"value": @NO, @"versionNumber": @(INT_MAX), @"date": [NSDate distantFuture]}];
    [settings onSettingChanged:forged];
    XCTAssertEqualObjects(settings.dictionaryRepresentation, before);
}
@end
