// Copyright 2026 Dayloft contributors. GPL-3.0-or-later. See LICENSE and NOTICE.md.
// Dayloft for macOS. GPL-3.0-or-later; see ../COPYING.
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface SCRecurringSchedule : NSObject
+ (BOOL)validateSchedules:(NSArray*)schedules;
+ (BOOL)validateModeConfigurations:(id)configurations;
+ (NSDictionary*)configurationForSchedule:(NSDictionary*)schedule modeConfigurations:(NSDictionary*)configurations;
+ (NSDictionary*)modeConfigurationsByMigratingSchedules:(NSArray*)schedules existingConfigurations:(id)configurations;
+ (BOOL)hasEnabledSchedules:(NSArray*)schedules;
// Weekdays follow Calendar: Sunday = 1. Overnight periods belong to their start day.
+ (nullable NSDateInterval*)activeIntervalForSchedule:(NSDictionary*)schedule atDate:(NSDate*)date calendar:(NSCalendar*)calendar;
@end
NS_ASSUME_NONNULL_END
