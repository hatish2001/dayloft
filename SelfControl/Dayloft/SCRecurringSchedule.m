// Copyright 2026 Dayloft contributors. GPL-3.0-or-later. See LICENSE and NOTICE.md.
#import "SCRecurringSchedule.h"
#import "SCMiscUtilities.h"
@implementation SCRecurringSchedule
+ (BOOL)validateSchedules:(NSArray*)schedules {
    if (![schedules isKindOfClass:NSArray.class] || schedules.count > 64) return NO;
    NSMutableSet* ids = [NSMutableSet new];
    for (id value in schedules) {
        if (![value isKindOfClass:NSDictionary.class]) return NO;
        NSDictionary* s = value;
        for (NSString* key in @[@"id", @"name", @"emoji", @"mode"]) {
            if (![s[key] isKindOfClass:NSString.class] || [s[key] length] == 0 || [s[key] length] > 200) return NO;
        }
        if ([ids containsObject:s[@"id"]]) return NO;
        [ids addObject:s[@"id"]];
        for (NSString* key in @[@"startMinute", @"endMinute", @"breaks", @"enabled", @"allowlist"]) {
            if (![s[key] isKindOfClass:NSNumber.class]) return NO;
        }
        for (NSString* key in @[@"startMinute", @"endMinute"]) {
            double minute = [s[key] doubleValue];
            if (!isfinite(minute) || floor(minute) != minute || minute < 0 || minute >= 1440) return NO;
        }
        if ([s[@"startMinute"] isEqual:s[@"endMinute"]]) return NO;
        if ([s[@"breaks"] integerValue] < 0 || [s[@"breaks"] integerValue] > 3) return NO;
        if (![s[@"days"] isKindOfClass:NSArray.class] || [s[@"days"] count] == 0 || [s[@"days"] count] > 7) return NO;
        for (id day in s[@"days"]) {
            if (![day isKindOfClass:NSNumber.class] || [day integerValue] < 1 || [day integerValue] > 7 || [day doubleValue] != [day integerValue]) return NO;
        }
        if (![s[@"domains"] isKindOfClass:NSArray.class] || [s[@"domains"] count] > 10000) return NO;
        for (id domain in s[@"domains"]) if (![domain isKindOfClass:NSString.class]) return NO;
        if ([s[@"enabled"] boolValue] && ![s[@"allowlist"] boolValue] && [SCMiscUtilities cleanBlocklist:s[@"domains"]].count == 0) return NO;
    }
    return YES;
}
+ (BOOL)hasEnabledSchedules:(NSArray*)schedules {
    for (NSDictionary* s in schedules) if ([s[@"enabled"] boolValue]) return YES;
    return NO;
}
+ (NSDateInterval*)activeIntervalForSchedule:(NSDictionary*)s atDate:(NSDate*)date calendar:(NSCalendar*)calendar {
    if (![s[@"enabled"] boolValue]) return nil;
    NSInteger startMinute = [s[@"startMinute"] integerValue], endMinute = [s[@"endMinute"] integerValue];
    NSDate* today = [calendar startOfDayForDate:date];
    for (NSInteger offset = -1; offset <= 0; offset++) {
        NSDate* day = [calendar dateByAddingUnit:NSCalendarUnitDay value:offset toDate:today options:0];
        if (![s[@"days"] containsObject:@([calendar component:NSCalendarUnitWeekday fromDate:day])]) continue;
        NSDate* endDay = endMinute <= startMinute ? [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:day options:0] : day;
        NSDate* start = [calendar dateBySettingHour:startMinute / 60 minute:startMinute % 60 second:0 ofDate:day options:0];
        NSDate* end = [calendar dateBySettingHour:endMinute / 60 minute:endMinute % 60 second:0 ofDate:endDay options:0];
        if (start && end && [date compare:start] != NSOrderedAscending && [date compare:end] == NSOrderedAscending) {
            return [[NSDateInterval alloc] initWithStartDate:start endDate:end];
        }
    }
    return nil;
}
@end
