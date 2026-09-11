// Copyright 2026 Dayloft contributors. GPL-3.0-or-later. See LICENSE and NOTICE.md.
#import "SCDayloftBridge.h"
#import "AppController.h"
#import "SCXPCClient.h"
#import "SCUIUtilities.h"
#import "SCRecurringSchedule.h"
@interface AppController (DayloftConfiguration)
- (NSDictionary*)blockSettingsSnapshot;
@end
@interface SCDayloftBridge ()
@property (nonatomic, weak) AppController* controller;
@property (nonatomic, strong) SCXPCClient* client;
@property (nonatomic, strong) NSLock* breakLock;
@end
@implementation SCDayloftBridge
- (instancetype)initWithController:(AppController*)controller {
    if ((self = [super init])) { _controller = controller; _client = [SCXPCClient new]; _breakLock = [NSLock new]; }
    return self;
}
- (NSDictionary*)snapshot {
    SCSettings* settings = SCSettings.sharedSettings;
    [settings reloadSettings];
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    return @{
        @"running": @([SCUIUtilities blockIsRunning]),
        @"paused": @([SCBlockUtilities currentBreakIsActive]),
        @"busy": @(self.controller.addingBlock),
        @"end": [settings valueForKey:@"BlockEndDate"] ?: NSDate.distantPast,
        @"breakEnd": [settings valueForKey:@"BreakEndDate"] ?: NSDate.distantPast,
        @"breaksRemaining": @(MAX(0, [[settings valueForKey:@"MaxBreaksPerBlock"] integerValue] - [[settings valueForKey:@"BreaksUsed"] integerValue])),
        @"domains": [defaults arrayForKey:@"Blocklist"] ?: @[],
        @"activeDomains": [settings valueForKey:@"ActiveBlocklist"] ?: @[],
        @"activeAllowlist": @([settings boolForKey:@"ActiveBlockAsWhitelist"]),
        @"allowlist": @([defaults boolForKey:@"BlockAsWhitelist"]),
        @"duration": @([defaults integerForKey:@"BlockDuration"]),
        @"breaks": @([defaults integerForKey:@"BreaksPerBlock"]),
        @"mode": [defaults stringForKey:@"DayloftMode"] ?: @"Living",
        @"schedules": [settings valueForKey:@"DayloftRecurringSchedules"] ?: @[],
        @"sessions": [settings valueForKey:@"DayloftFocusSessions"] ?: @[],
        @"updated": [settings valueForKey:@"LastSettingsUpdate"] ?: NSDate.distantPast,
        @"enforcementError": [settings valueForKey:@"DayloftEnforcementError"] ?: @"",
        @"scheduleError": [settings valueForKey:@"DayloftScheduleLastError"] ?: @"",
        @"legacyPending": @([settings boolForKey:@"ScheduledBlockPending"]),
        @"legacyDate": [settings valueForKey:@"ScheduledBlockDate"] ?: NSDate.distantPast
    };
}
- (NSArray<NSString*>*)cleanDomains:(NSString*)text { return [SCMiscUtilities cleanBlocklistEntry:text]; }
- (void)configureDomains:(NSArray<NSString*>*)domains allowlist:(BOOL)allowlist duration:(NSInteger)minutes mode:(NSString*)mode {
    if (self.controller.addingBlock || [SCUIUtilities blockIsRunning]) return;
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:[SCMiscUtilities cleanBlocklist:domains] forKey:@"Blocklist"];
    [defaults setBool:allowlist forKey:@"BlockAsWhitelist"];
    [defaults setInteger:MIN(MAX(minutes, 1), 1440) forKey:@"BlockDuration"];
    [defaults setObject:mode forKey:@"DayloftMode"];
    [defaults synchronize];
}
- (void)startBlock { [self.controller addBlock:self]; }
- (void)takeBreakWithCompletion:(void(^)(NSError* _Nullable))completion {
    [self.client takeBreakWithReply:^(NSError* error) { dispatch_async(dispatch_get_main_queue(), ^{ completion(error); }); }];
}
- (void)extendSession:(NSInteger)minutes completion:(void(^)(NSError* _Nullable))completion {
    NSDate* end = [SCSettings.sharedSettings valueForKey:@"BlockEndDate"];
    [self.client updateBlockEndDate:[end dateByAddingTimeInterval:MIN(MAX(minutes, 1), 1440) * 60] reply:^(NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    }];
}
- (void)addBlockedWebsites:(NSString*)text completion:(void(^)(NSError* _Nullable))completion {
    NSMutableOrderedSet* domains = [NSMutableOrderedSet orderedSetWithArray:[SCSettings.sharedSettings valueForKey:@"ActiveBlocklist"] ?: @[]];
    [domains addObjectsFromArray:[self cleanDomains:text]];
    [self.client updateBlocklist:domains.array reply:^(NSError* error) { dispatch_async(dispatch_get_main_queue(), ^{ completion(error); }); }];
}
- (void)showAdvancedSettings { [self.controller openPreferences:self]; }
- (void)showActiveBlockTools { [self.controller showTimerWindow]; }
- (void)manageLegacySchedule { [self.controller scheduleBlock:self]; }
- (void)saveSchedules:(NSArray<NSDictionary*>*)schedules completion:(void(^)(NSError* _Nullable))completion {
    if (![SCRecurringSchedule validateSchedules:schedules]) {
        completion([NSError errorWithDomain:@"Dayloft" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Add websites and choose days and different start and end times."}]); return;
    }
    NSDictionary* config = [self.controller blockSettingsSnapshot];
    [self.client installDaemon:^(NSError* error) {
        if (error) { dispatch_async(dispatch_get_main_queue(), ^{ completion(error); }); return; }
        [self.client refreshConnectionAndRun:^{
            [self.client setRecurringSchedules:schedules controllingUID:getuid() blockSettings:config reply:^(NSError* error) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
            }];
        }];
    }];
}
@end
