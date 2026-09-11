#import <XCTest/XCTest.h>
#import "SCRecurringSchedule.h"
@interface SCRecurringScheduleTests : XCTestCase
@end
@implementation SCRecurringScheduleTests
- (NSCalendar*)calendar {
    NSCalendar* calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"America/Los_Angeles"];
    return calendar;
}
- (NSDate*)date:(NSString*)string {
    NSISO8601DateFormatter* formatter = [NSISO8601DateFormatter new];
    return [formatter dateFromString:string];
}
- (NSMutableDictionary*)schedule {
    return [@{@"id": @"test", @"name": @"Focus", @"emoji": @"🎯", @"mode": @"Living", @"enabled": @YES,
              @"startMinute": @660, @"endMinute": @900, @"days": @[@2,@3,@4,@5,@6],
              @"breaks": @1, @"domains": @[@"reddit.com"], @"allowlist": @NO} mutableCopy];
}
- (void)testWeekdayWindowAndExactBoundaries {
    NSDictionary* s = self.schedule;
    XCTAssertNil([SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-09-10T10:59:59-07:00"] calendar:self.calendar]);
    XCTAssertNotNil([SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-09-10T11:00:00-07:00"] calendar:self.calendar]);
    NSDateInterval* interval = [SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-09-10T14:00:00-07:00"] calendar:self.calendar];
    XCTAssertEqualObjects(interval.endDate, [self date:@"2026-09-10T15:00:00-07:00"]);
    XCTAssertNil([SCRecurringSchedule activeIntervalForSchedule:s atDate:interval.endDate calendar:self.calendar]);
    XCTAssertNil([SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-09-12T12:00:00-07:00"] calendar:self.calendar]);
}
- (void)testOvernightBelongsToStartDay {
    NSMutableDictionary* s = self.schedule; s[@"days"] = @[@6]; s[@"startMinute"] = @1380; s[@"endMinute"] = @60;
    NSDateInterval* interval = [SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-09-12T00:30:00-07:00"] calendar:self.calendar];
    XCTAssertEqualObjects(interval.startDate, [self date:@"2026-09-11T23:00:00-07:00"]);
    XCTAssertEqualObjects(interval.endDate, [self date:@"2026-09-12T01:00:00-07:00"]);
    XCTAssertNil([SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-09-13T00:30:00-07:00"] calendar:self.calendar]);
}
- (void)testMidnightAndDisabledSchedule {
    NSMutableDictionary* s = self.schedule; s[@"days"] = @[@5]; s[@"startMinute"] = @1380; s[@"endMinute"] = @0;
    XCTAssertNotNil([SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-09-10T23:30:00-07:00"] calendar:self.calendar]);
    XCTAssertNil([SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-09-11T00:00:00-07:00"] calendar:self.calendar]);
    s[@"enabled"] = @NO;
    XCTAssertFalse([SCRecurringSchedule hasEnabledSchedules:@[s]]);
    XCTAssertNil([SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-09-10T23:30:00-07:00"] calendar:self.calendar]);
}
- (void)testDSTSpringForwardUsesWallClockEnd {
    NSMutableDictionary* s = self.schedule; s[@"days"] = @[@1]; s[@"startMinute"] = @60; s[@"endMinute"] = @240;
    NSDateInterval* interval = [SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-03-08T03:30:00-07:00"] calendar:self.calendar];
    XCTAssertEqualWithAccuracy(interval.duration, 7200, 1);
    XCTAssertEqualObjects(interval.endDate, [self date:@"2026-03-08T04:00:00-07:00"]);
}
- (void)testDSTFallBackUsesWallClockEnd {
    NSMutableDictionary* s = self.schedule; s[@"days"] = @[@1]; s[@"startMinute"] = @0; s[@"endMinute"] = @180;
    NSDateInterval* interval = [SCRecurringSchedule activeIntervalForSchedule:s atDate:[self date:@"2026-11-01T01:30:00-08:00"] calendar:self.calendar];
    XCTAssertEqualWithAccuracy(interval.duration, 14400, 1);
    XCTAssertEqualObjects(interval.endDate, [self date:@"2026-11-01T03:00:00-08:00"]);
}
- (void)testValidationRejectsInvalidOrAmbiguousSchedules {
    NSMutableDictionary* s = self.schedule;
    XCTAssertTrue([SCRecurringSchedule validateSchedules:@[s]]);
    XCTAssertFalse(([SCRecurringSchedule validateSchedules:@[s, s]]));
    s[@"days"] = @[]; XCTAssertFalse([SCRecurringSchedule validateSchedules:@[s]]);
    s = self.schedule; s[@"endMinute"] = s[@"startMinute"]; XCTAssertFalse([SCRecurringSchedule validateSchedules:@[s]]);
    s = self.schedule; s[@"startMinute"] = @(-1); XCTAssertFalse([SCRecurringSchedule validateSchedules:@[s]]);
    s = self.schedule; s[@"startMinute"] = @660.5; XCTAssertFalse([SCRecurringSchedule validateSchedules:@[s]]);
    s = self.schedule; s[@"domains"] = @[]; XCTAssertFalse([SCRecurringSchedule validateSchedules:@[s]]);
    s[@"enabled"] = @NO; XCTAssertTrue([SCRecurringSchedule validateSchedules:@[s]]);
    s = self.schedule; s[@"breaks"] = @4; XCTAssertFalse([SCRecurringSchedule validateSchedules:@[s]]);
}
@end
