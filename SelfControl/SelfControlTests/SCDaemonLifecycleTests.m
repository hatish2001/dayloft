// Copyright 2026 Dayloft contributors. GPL-3.0-or-later.
#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "SCDaemon.h"
#import "SCDaemonBlockMethods.h"
#import "SCSettings.h"
#import "SCBlockUtilities.h"
#import "SCHelperToolUtilities.h"
#import "BlockManager.h"
#import "SCMigrationUtilities.h"

// This test target never links the daemon service: no XPC listener, timers,
// authorization, launchd, network rules, cache clearing, or notifications.
static NSUInteger stoppedTimers;
@implementation SCDaemon
+ (instancetype)sharedDaemon { static SCDaemon* d; if (!d) d = [self new]; return d; }
- (void)start {}
- (void)startCheckupTimer {}
- (void)stopCheckupTimer { stoppedTimers++; }
- (void)resetInactivityTimer {}
@end

static NSUInteger attemptedStarts;
static BOOL failScheduledStart;
@interface ScheduledStartProbe : SCDaemonBlockMethods
@end
@implementation ScheduledStartProbe
+ (void)startBlockWithControllingUID:(uid_t)uid blocklist:(NSArray*)list isAllowlist:(BOOL)allowlist endDate:(NSDate*)end blockSettings:(NSDictionary*)config authorization:(NSData*)auth reply:(void(^)(NSError*))reply {
    attemptedStarts++;
    reply(failScheduledStart ? [NSError errorWithDomain:@"Test" code:1 userInfo:nil] : nil);
}
@end

@interface SCDaemonLifecycleTests : XCTestCase
@property NSMutableArray<void(^)(void)>* restorations;
@property BOOL clearSucceeds;
@property NSUInteger clearCalls;
@property NSError* persistenceError;
@end
@implementation SCDaemonLifecycleTests
- (void)replaceMethod:(Method)method withBlock:(id)block {
    NSAssert(method != NULL, @"Missing test interception");
    IMP replacement = imp_implementationWithBlock(block);
    IMP original = method_setImplementation(method, replacement);
    [self.restorations addObject:^{ method_setImplementation(method, original); imp_removeBlock(replacement); }];
}
- (void)setUp {
    [super setUp]; self.restorations = [NSMutableArray new]; self.clearSucceeds = YES;
    stoppedTimers = 0; attemptedStarts = 0; failScheduledStart = YES;
    SCSettings.sharedSettings.readOnly = NO;
    [SCSettings.sharedSettings resetAllSettingsToDefaults];
    [self replaceMethod:class_getClassMethod(SCBlockUtilities.class, @selector(legacyBlockIsRunning)) withBlock:^BOOL(id object) { return NO; }];
    [self replaceMethod:class_getClassMethod(SCMigrationUtilities.class, @selector(legacySettingsFoundForUser:)) withBlock:^BOOL(id object, uid_t uid) { return NO; }];
    [self replaceMethod:class_getInstanceMethod(BlockManager.class, @selector(clearBlock)) withBlock:^BOOL(id object) { self.clearCalls++; return self.clearSucceeds; }];
    [self replaceMethod:class_getInstanceMethod(BlockManager.class, @selector(enterAppendMode)) withBlock:^BOOL(id object) { return YES; }];
    [self replaceMethod:class_getInstanceMethod(BlockManager.class, @selector(addBlockEntriesFromStrings:)) withBlock:^(id object, NSArray* sites) {}];
    [self replaceMethod:class_getInstanceMethod(BlockManager.class, @selector(finishAppending)) withBlock:^BOOL(id object) { return YES; }];
    [self replaceMethod:class_getInstanceMethod(SCSettings.class, @selector(syncSettingsAndWait:)) withBlock:^NSError*(id object, NSInteger timeout) { return self.persistenceError; }];
    for (NSString* selector in @[@"clearCachesIfRequested", @"sendConfigurationChangedNotification", @"playBlockEndSound"]) {
        [self replaceMethod:class_getClassMethod(SCHelperToolUtilities.class, NSSelectorFromString(selector)) withBlock:^(id object) {}];
    }
    [self replaceMethod:class_getClassMethod(SCHelperToolUtilities.class, @selector(installBlockRulesFromSettings)) withBlock:^BOOL(id object) {
        @throw [NSException exceptionWithName:@"UnexpectedNetworkAccess" reason:@"An intentional break must not reinstall rules" userInfo:nil];
    }];
    [self replaceMethod:class_getInstanceMethod(PacketFilter.class, @selector(containsSelfControlBlock)) withBlock:^BOOL(id object) {
        @throw [NSException exceptionWithName:@"UnexpectedNetworkAccess" reason:@"Paused, idle, and expired sessions must skip integrity inspection" userInfo:nil];
    }];
}
- (void)tearDown {
    [SCSettings.sharedSettings resetAllSettingsToDefaults];
    for (void(^restore)(void) in self.restorations.reverseObjectEnumerator) restore();
    self.restorations = nil;
    [super tearDown];
}
- (void)makeActiveSession {
    SCSettings* s = SCSettings.sharedSettings;
    [s setValue:@YES forKey:@"BlockIsRunning"];
    [s setValue:[NSDate dateWithTimeIntervalSinceNow:3600] forKey:@"BlockEndDate"];
    [s setValue:@[@"example.org"] forKey:@"ActiveBlocklist"];
}
- (void)testScheduleChangesAreRejectedDuringFocusAndBreakWithoutChangingSession {
    [self makeActiveSession];
    SCSettings* s = SCSettings.sharedSettings;
    NSArray* previous = @[@{@"id": @"existing", @"enabled": @YES}];
    [s setValue:previous forKey:@"DayloftRecurringSchedules"];
    NSDate* end = [s valueForKey:@"BlockEndDate"];
    for (NSNumber* paused in @[@NO, @YES]) {
        [s setValue:paused forKey:@"BlockPausedForBreak"];
        __block NSUInteger replies = 0;
        [SCDaemonBlockMethods setRecurringSchedules:@[] controllingUID:501 blockSettings:@{} authorization:NSData.data reply:^(NSError* error) {
            replies++; XCTAssertEqualObjects(error.domain, @"Dayloft"); XCTAssertEqual(error.code, 2);
        }];
        XCTAssertEqual(replies, 1u);
        XCTAssertEqualObjects([s valueForKey:@"DayloftRecurringSchedules"], previous);
        XCTAssertEqualObjects([s valueForKey:@"BlockEndDate"], end);
        XCTAssertTrue([s boolForKey:@"BlockIsRunning"]);
        XCTAssertEqualObjects([s valueForKey:@"ActiveBlocklist"], @[@"example.org"]);
        XCTAssertTrue([SCDaemonBlockMethods.daemonMethodLock tryLock]);
        [SCDaemonBlockMethods.daemonMethodLock unlock];
    }
    XCTAssertEqual(self.clearCalls, 0u);
}
- (void)testDeletingLastScheduleAfterSessionEndsPersistsAnAuthoritativeEmptyList {
    [self makeActiveSession];
    [SCSettings.sharedSettings setValue:NSDate.distantPast forKey:@"BlockEndDate"];
    [SCDaemonBlockMethods checkupBlock];
    __block NSUInteger replies = 0;
    [SCDaemonBlockMethods setRecurringSchedules:@[] controllingUID:501 blockSettings:@{} authorization:NSData.data reply:^(NSError* error) {
        replies++; XCTAssertNil(error);
    }];
    XCTAssertEqual(replies, 1u);
    XCTAssertTrue([SCSettings.sharedSettings boolForKey:@"DayloftSchedulesConfigured"]);
    XCTAssertEqualObjects([SCSettings.sharedSettings valueForKey:@"DayloftRecurringSchedules"], @[]);
}
- (void)testFailedScheduleSaveRestoresConfigurationAndError {
    SCSettings* s = SCSettings.sharedSettings;
    [s setValue:@"Existing error" forKey:@"DayloftScheduleLastError"];
    self.persistenceError = [NSError errorWithDomain:@"TestDiskFailure" code:1 userInfo:nil];
    __block NSUInteger replies = 0;
    [SCDaemonBlockMethods setRecurringSchedules:@[] controllingUID:501 blockSettings:@{@"Mode": @"New"} authorization:NSData.data reply:^(NSError* error) {
        replies++; XCTAssertEqualObjects(error, self.persistenceError);
    }];
    XCTAssertEqual(replies, 1u);
    XCTAssertFalse([s boolForKey:@"DayloftSchedulesConfigured"]);
    XCTAssertEqualObjects([s valueForKey:@"DayloftScheduleSettings"], @{});
    XCTAssertEqualObjects([s valueForKey:@"DayloftScheduleUID"], @0);
    XCTAssertEqualObjects([s valueForKey:@"DayloftScheduleLastError"], @"Existing error");
}
- (void)testStartNeverInstallsRulesWithoutDurableEndTime {
    self.persistenceError = [NSError errorWithDomain:@"TestDiskFailure" code:1 userInfo:nil];
    __block NSUInteger replies = 0;
    XCTAssertNoThrow([SCDaemonBlockMethods startBlockWithControllingUID:501 blocklist:@[@"example.org"] isAllowlist:NO
        endDate:[NSDate dateWithTimeIntervalSinceNow:60] blockSettings:@{} authorization:[NSData data] reply:^(NSError* error) {
            replies++; XCTAssertEqualObjects(error, self.persistenceError);
        }]);
    XCTAssertEqual(replies, 1u);
    XCTAssertFalse([SCSettings.sharedSettings boolForKey:@"BlockIsRunning"]);
    XCTAssertEqual(self.clearCalls, 0u);
}
- (void)testRejectedEndDatesReplyOnceAndNeverChangeSession {
    [self makeActiveSession];
    SCSettings* s = SCSettings.sharedSettings;
    NSDate* end = [s valueForKey:@"BlockEndDate"];
    for (NSDate* proposed in @[[end dateByAddingTimeInterval:-1], [end dateByAddingTimeInterval:86401]]) {
        __block NSUInteger replies = 0;
        XCTAssertNoThrow([SCDaemonBlockMethods updateBlockEndDate:proposed authorization:[NSData data] reply:^(NSError* error) { replies++; XCTAssertNotNil(error); }]);
        XCTAssertEqual(replies, 1u);
        XCTAssertEqualObjects([s valueForKey:@"BlockEndDate"], end);
        XCTAssertTrue([SCDaemonBlockMethods.daemonMethodLock tryLock]);
        [SCDaemonBlockMethods.daemonMethodLock unlock];
    }
}
- (void)testAddingSitesDuringBreakPreservesExistingListAndBreak {
    [self makeActiveSession];
    SCSettings* s = SCSettings.sharedSettings;
    NSDictionary* denylistSchedule = @{@"id": @"future", @"enabled": @YES, @"domains": @[@"youtube.com"], @"allowlist": @NO};
    NSDictionary* allowlistSchedule = @{@"id": @"protected", @"enabled": @YES, @"domains": @[@"dayloft.app"], @"allowlist": @YES};
    [s setValue:@[denylistSchedule, allowlistSchedule] forKey:@"DayloftRecurringSchedules"];
    NSDate* breakEnd = [NSDate dateWithTimeIntervalSinceNow:300];
    [s setValue:@YES forKey:@"BlockPausedForBreak"];
    [s setValue:breakEnd forKey:@"BreakEndDate"];
    __block NSUInteger replies = 0;
    [SCDaemonBlockMethods updateBlocklist:@[@"x.com", @"tiktok.com"] authorization:[NSData data] reply:^(NSError* error) { replies++; XCTAssertNil(error); }];
    XCTAssertEqual(replies, 1u);
    XCTAssertEqualObjects([s valueForKey:@"ActiveBlocklist"], (@[@"example.org", @"x.com", @"tiktok.com"]));
    NSArray* schedules = [s valueForKey:@"DayloftRecurringSchedules"];
    XCTAssertEqualObjects(schedules[0][@"domains"], (@[@"youtube.com", @"example.org", @"x.com", @"tiktok.com"]));
    XCTAssertEqualObjects(schedules[1][@"domains"], (@[@"dayloft.app"]));
    XCTAssertTrue([s boolForKey:@"BlockPausedForBreak"]);
    XCTAssertEqualObjects([s valueForKey:@"BreakEndDate"], breakEnd);
    XCTAssertEqual(self.clearCalls, 0u);
}
- (void)testAddingSitesPersistsThemForFutureDenylistSchedules {
    [self makeActiveSession];
    SCSettings* s = SCSettings.sharedSettings;
    NSDictionary* schedule = @{@"id": @"future", @"enabled": @YES, @"domains": @[@"youtube.com"], @"allowlist": @NO};
    [s setValue:@[schedule] forKey:@"DayloftRecurringSchedules"];
    __block NSUInteger replies = 0;
    [SCDaemonBlockMethods updateBlocklist:@[@"x.com", @"tiktok.com"] authorization:NSData.data reply:^(NSError* error) { replies++; XCTAssertNil(error); }];
    XCTAssertEqual(replies, 1u);
    XCTAssertEqualObjects([s valueForKey:@"ActiveBlocklist"], (@[@"example.org", @"x.com", @"tiktok.com"]));
    XCTAssertEqualObjects([s valueForKey:@"DayloftRecurringSchedules"][0][@"domains"], (@[@"youtube.com", @"example.org", @"x.com", @"tiktok.com"]));
}
- (void)testFailedExtensionPersistenceRestoresOriginalEnd {
    [self makeActiveSession];
    NSDate* end = [SCSettings.sharedSettings valueForKey:@"BlockEndDate"];
    self.persistenceError = [NSError errorWithDomain:@"TestDiskFailure" code:1 userInfo:nil];
    __block NSUInteger replies = 0;
    [SCDaemonBlockMethods updateBlockEndDate:[end dateByAddingTimeInterval:60] authorization:[NSData data] reply:^(NSError* error) {
        replies++; XCTAssertEqualObjects(error, self.persistenceError);
    }];
    XCTAssertEqual(replies, 1u);
    XCTAssertEqualObjects([SCSettings.sharedSettings valueForKey:@"BlockEndDate"], end);
}
- (void)testIntegrityNotificationsRespectBreakAndResumeOwnership {
    [self makeActiveSession];
    SCSettings* s = SCSettings.sharedSettings;
    [s setValue:@YES forKey:@"BlockPausedForBreak"];
    // The periodic checkup owns restoration even when the break just expired.
    for (NSDate* date in @[[NSDate dateWithTimeIntervalSinceNow:300], NSDate.distantPast]) {
        [s setValue:date forKey:@"BreakEndDate"];
        XCTAssertNoThrow([SCDaemonBlockMethods checkBlockIntegrity]);
    }
    XCTAssertEqual(self.clearCalls, 0u);
}
- (void)testIntegrityNotificationsNeverReinstallExpiredOrIdleRules {
    XCTAssertNoThrow([SCDaemonBlockMethods checkBlockIntegrity]);
    [self makeActiveSession];
    [SCSettings.sharedSettings setValue:NSDate.distantPast forKey:@"BlockEndDate"];
    XCTAssertNoThrow([SCDaemonBlockMethods checkBlockIntegrity]);
}
- (void)testFailedExpiryCleanupRemainsVisibleAndRetries {
    [self makeActiveSession];
    SCSettings* s = SCSettings.sharedSettings;
    [s setValue:NSDate.distantPast forKey:@"BlockEndDate"];
    self.clearSucceeds = NO;
    [SCDaemonBlockMethods checkupBlock];
    XCTAssertTrue([s boolForKey:@"BlockIsRunning"]);
    XCTAssertEqualObjects([s valueForKey:@"ActiveBlocklist"], @[@"example.org"]);
    XCTAssertTrue([[s valueForKey:@"DayloftEnforcementError"] length] > 0);
    XCTAssertEqual(stoppedTimers, 0u);
    self.clearSucceeds = YES;
    [SCDaemonBlockMethods checkupBlock];
    XCTAssertFalse([s boolForKey:@"BlockIsRunning"]);
    XCTAssertEqualObjects([s valueForKey:@"DayloftEnforcementError"], @"");
    XCTAssertEqual(self.clearCalls, 2u);
    XCTAssertEqual(stoppedTimers, 1u);
}
- (void)testFailedRecurringStartRetriesUntilSuccessful {
    NSDateComponents* parts = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:NSDate.date];
    NSInteger minute = parts.hour * 60 + parts.minute;
    NSDictionary* schedule = @{@"id": @"retry", @"enabled": @YES, @"startMinute": @(minute), @"endMinute": @((minute + 60) % 1440), @"days": @[@1,@2,@3,@4,@5,@6,@7], @"domains": @[@"example.org"], @"allowlist": @NO, @"breaks": @0, @"mode": @"Focus"};
    SCSettings* s = SCSettings.sharedSettings;
    [s setValue:@[schedule] forKey:@"DayloftRecurringSchedules"];
    [ScheduledStartProbe checkupBlock];
    XCTAssertEqual(attemptedStarts, 1u);
    XCTAssertNil([s valueForKey:@"DayloftScheduleOccurrences"][@"retry"]);
    failScheduledStart = NO;
    [ScheduledStartProbe checkupBlock];
    XCTAssertEqual(attemptedStarts, 2u);
    XCTAssertNotNil([s valueForKey:@"DayloftScheduleOccurrences"][@"retry"]);
    XCTAssertEqualObjects([s valueForKey:@"DayloftScheduleLastError"], @"");
    [ScheduledStartProbe checkupBlock];
    XCTAssertEqual(attemptedStarts, 2u);
}
@end
