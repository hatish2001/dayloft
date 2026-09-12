//
//  SCDaemonBlockMethods.m
//  org.dayloft.focusd
//
//  Created by Charlie Stigler on 7/4/20.
//

#import "SCDaemonBlockMethods.h"
#import "SCSettings.h"
#import "SCHelperToolUtilities.h"
#import "PacketFilter.h"
#import "BlockManager.h"
#import "SCDaemon.h"
#import "LaunchctlHelper.h"
#import "HostFileBlockerSet.h"
#import "SCRecurringSchedule.h"

NSTimeInterval METHOD_LOCK_TIMEOUT = 5.0;
NSTimeInterval CHECKUP_LOCK_TIMEOUT = 0.5; // use a shorter lock timeout for checkups, because we'd prefer not to have tons pile up

@implementation SCDaemonBlockMethods
+ (BOOL)hasRecurringSchedules {
    return [SCRecurringSchedule hasEnabledSchedules:[[SCSettings sharedSettings] valueForKey:@"DayloftRecurringSchedules"]];
}

+ (void)setRecurringSchedules:(NSArray<NSDictionary*>*)schedules controllingUID:(uid_t)controllingUID blockSettings:(NSDictionary*)blockSettings authorization:(NSData*)authData reply:(void(^)(NSError* error))reply {
    if (![self lockOrTimeout:reply]) return;
    if (![SCRecurringSchedule validateSchedules:schedules] || ![blockSettings isKindOfClass:NSDictionary.class]) {
        [self.daemonMethodLock unlock];
        reply([NSError errorWithDomain:@"Dayloft" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Choose valid times, days, and websites for each enabled schedule."}]);
        return;
    }
    SCSettings* settings = [SCSettings sharedSettings];
    NSArray* previous = [settings valueForKey:@"DayloftRecurringSchedules"];
    NSDictionary* previousSettings = [settings valueForKey:@"DayloftScheduleSettings"];
    id previousUID = [settings valueForKey:@"DayloftScheduleUID"];
    [settings setValue:schedules forKey:@"DayloftRecurringSchedules"];
    [settings setValue:blockSettings forKey:@"DayloftScheduleSettings"];
    [settings setValue:@(controllingUID) forKey:@"DayloftScheduleUID"];
    [settings setValue:@"" forKey:@"DayloftScheduleLastError"];
    NSError* error = [settings syncSettingsAndWait:5];
    if (error) {
        [settings setValue:previous forKey:@"DayloftRecurringSchedules"];
        [settings setValue:previousSettings forKey:@"DayloftScheduleSettings"];
        [settings setValue:previousUID forKey:@"DayloftScheduleUID"];
        [settings syncSettingsAndWait:5];
    }
    [self.daemonMethodLock unlock];
    [SCHelperToolUtilities sendConfigurationChangedNotification];
    [[SCDaemon sharedDaemon] resetInactivityTimer];
    // startCheckupTimer can synchronously check; never call it while holding the method lock.
    if (!error && [self hasRecurringSchedules]) [[SCDaemon sharedDaemon] startCheckupTimer];
    reply(error);
}


+ (NSLock*)daemonMethodLock {
    static NSLock* lock = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [[NSLock alloc] init]; });
    return lock;
}

+ (BOOL)lockOrTimeout:(void(^)(NSError* error))reply timeout:(NSTimeInterval)timeout {
    // only run one request at a time, so we avoid weird situations like trying to run a checkup while we're starting a block
    if (![self.daemonMethodLock lockBeforeDate: [NSDate dateWithTimeIntervalSinceNow: timeout]]) {
        // if we couldn't get a lock within 10 seconds, something is weird
        // but we probably shouldn't still run, because that's just unexpected at that point
        // don't capture this error on Sentry because it's very usual for checkups to timeout
        NSError* err = [SCErr errorWithCode: 300];
        NSLog(@"ERROR: Timed out acquiring request lock (after %f seconds)", timeout);

        if (reply != nil) {
            reply(err);
        }
        return NO;
    }
    return YES;
}
+ (BOOL)lockOrTimeout:(void(^)(NSError* error))reply {
    return [self lockOrTimeout: reply timeout: METHOD_LOCK_TIMEOUT];
}

+ (BOOL)scheduledBlockIsPending {
    return [SCBlockUtilities scheduledBlockIsPending];
}

+ (void)clearScheduledBlockFromSettings:(SCSettings*)settings {
    [settings setValue: @NO forKey: @"ScheduledBlockPending"];
    [settings setValue: @NO forKey: @"ScheduledBlockStarting"];
    [settings setValue: [NSDate distantPast] forKey: @"ScheduledBlockDate"];
    [settings setValue: @[] forKey: @"ScheduledBlocklist"];
    [settings setValue: @NO forKey: @"ScheduledBlockAsWhitelist"];
    [settings setValue: @0 forKey: @"ScheduledBlockDurationSeconds"];
    [settings setValue: @{} forKey: @"ScheduledBlockSettings"];
    [settings setValue: @0 forKey: @"ScheduledBlockControllingUID"];
}

+ (void)scheduleBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist startDate:(NSDate*)startDate durationSeconds:(NSTimeInterval)durationSeconds blockSettings:(NSDictionary*)blockSettings authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    if (![SCDaemonBlockMethods lockOrTimeout: reply]) {
        return;
    }

    NSError* validationError = nil;
    if ([SCBlockUtilities anyBlockIsRunning]) {
        validationError = [SCErr errorWithCode: 301];
    } else if (startDate == nil || [startDate timeIntervalSinceNow] <= 0 || durationSeconds <= 0) {
        validationError = [SCErr errorWithCode: 315];
    } else if (blocklist.count == 0 && !isAllowlist) {
        validationError = [SCErr errorWithCode: 302];
    }

    if (validationError != nil) {
        [SCSentry captureError: validationError];
        reply(validationError);
        [self.daemonMethodLock unlock];
        return;
    }

    SCSettings* settings = [SCSettings sharedSettings];
    [settings setValue: @YES forKey: @"ScheduledBlockPending"];
    [settings setValue: @NO forKey: @"ScheduledBlockStarting"];
    [settings setValue: startDate forKey: @"ScheduledBlockDate"];
    [settings setValue: [blocklist copy] forKey: @"ScheduledBlocklist"];
    [settings setValue: @(isAllowlist) forKey: @"ScheduledBlockAsWhitelist"];
    [settings setValue: @(durationSeconds) forKey: @"ScheduledBlockDurationSeconds"];
    [settings setValue: [blockSettings copy] forKey: @"ScheduledBlockSettings"];
    [settings setValue: @(controllingUID) forKey: @"ScheduledBlockControllingUID"];
    [settings setValue: @"" forKey: @"ScheduledBlockLastError"];

    NSError* syncErr = [settings syncSettingsAndWait: 5];
    if (syncErr != nil) {
        NSLog(@"WARNING: Sync failed after scheduling block: %@", syncErr);
        [SCSentry captureError: syncErr];
    }

    [[SCDaemon sharedDaemon] startCheckupTimer];
    [[SCDaemon sharedDaemon] resetInactivityTimer];
    [SCHelperToolUtilities sendConfigurationChangedNotification];
    [SCSentry addBreadcrumb: @"Daemon saved a scheduled block" category: @"daemon"];
    reply(syncErr);
    [self.daemonMethodLock unlock];
}

+ (void)cancelScheduledBlockWithAuthorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    if (![SCDaemonBlockMethods lockOrTimeout: reply]) {
        return;
    }

    SCSettings* settings = [SCSettings sharedSettings];
    [self clearScheduledBlockFromSettings: settings];
    [settings setValue: @"" forKey: @"ScheduledBlockLastError"];
    NSError* syncErr = [settings syncSettingsAndWait: 5];
    if (syncErr != nil) {
        NSLog(@"WARNING: Sync failed after cancelling scheduled block: %@", syncErr);
        [SCSentry captureError: syncErr];
    }

    [SCHelperToolUtilities sendConfigurationChangedNotification];
    if (![SCBlockUtilities anyBlockIsRunning]) {
        if (![self hasRecurringSchedules]) [[SCDaemon sharedDaemon] stopCheckupTimer];
    }
    [[SCDaemon sharedDaemon] resetInactivityTimer];
    reply(syncErr);
    [self.daemonMethodLock unlock];
}

+ (void)startBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist endDate:(NSDate*)endDate blockSettings:(NSDictionary*)blockSettings authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    if (![SCDaemonBlockMethods lockOrTimeout: reply]) {
        return;
    }
    
    // we reset at the _end_ of every method, but we'll also reset at the _start_ here
    // because startBlock can sometimes take a while, and it'd be a shame if the daemon killed itself
    // before we were done
    [[SCDaemon sharedDaemon] resetInactivityTimer];
    
    [SCSentry addBreadcrumb: @"Daemon method startBlock called" category: @"daemon"];
    
    if ([SCBlockUtilities anyBlockIsRunning]) {
        NSLog(@"ERROR: Can't start block since a block is already running");
        NSError* err = [SCErr errorWithCode: 301];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }
    
    // clear any legacy block information - no longer useful and could potentially confuse things
    // but first, copy it over one more time (this should've already happened once in the app, but you never know)
    if ([SCMigrationUtilities legacySettingsFoundForUser: controllingUID]) {
        [SCMigrationUtilities copyLegacySettingsToDefaults: controllingUID];
        [SCMigrationUtilities clearLegacySettingsForUser: controllingUID];
        
        // if we had legacy settings, there's a small chance the old helper tool could still be around
        // make sure it's dead and gone
        [LaunchctlHelper unloadLaunchdJobWithPlistAt: @"/Library/LaunchDaemons/org.dayloft.Dayloft.plist"];
    }

    SCSettings* settings = [SCSettings sharedSettings];
    // Starting a block now consumes any pending one-time schedule so it cannot
    // surprise the user by launching later after a manual start.
    if ([settings boolForKey: @"ScheduledBlockPending"] || [settings boolForKey: @"ScheduledBlockStarting"]) {
        [self clearScheduledBlockFromSettings: settings];
        [settings setValue: @"" forKey: @"ScheduledBlockLastError"];
    }
    // update SCSettings with the blocklist and end date that've been requested
    [settings setValue: blocklist forKey: @"ActiveBlocklist"];
    [settings setValue: @(isAllowlist) forKey: @"ActiveBlockAsWhitelist"];
    [settings setValue: endDate forKey: @"BlockEndDate"];
    NSInteger breakBudget = MIN(MAX([blockSettings[@"BreaksPerBlock"] integerValue], 0), 3);
    [settings setValue: @(breakBudget) forKey: @"MaxBreaksPerBlock"];
    [settings setValue: @0 forKey: @"BreaksUsed"];
    [settings setValue: @5 forKey: @"BreakDurationMinutes"];
    [settings setValue: [NSDate distantPast] forKey: @"BreakEndDate"];
    [settings setValue: @NO forKey: @"BlockPausedForBreak"];
    
    // update all the settings for the block, which we're basically just copying from defaults to settings
    [settings setValue: blockSettings[@"ClearCaches"] forKey: @"ClearCaches"];
    [settings setValue: blockSettings[@"AllowLocalNetworks"] forKey: @"AllowLocalNetworks"];
    [settings setValue: blockSettings[@"EvaluateCommonSubdomains"] forKey: @"EvaluateCommonSubdomains"];
    [settings setValue: blockSettings[@"IncludeLinkedDomains"] forKey: @"IncludeLinkedDomains"];
    [settings setValue: blockSettings[@"StrictDomainBlocking"] forKey: @"StrictDomainBlocking"];
    [settings setValue: blockSettings[@"BlockSoundShouldPlay"] forKey: @"BlockSoundShouldPlay"];
    [settings setValue: blockSettings[@"BlockSound"] forKey: @"BlockSound"];
    [settings setValue: blockSettings[@"EnableErrorReporting"] forKey: @"EnableErrorReporting"];

    if(([blocklist count] <= 0 && !isAllowlist) || [SCBlockUtilities currentBlockIsExpired]) {
        NSLog(@"ERROR: Blocklist is empty, or block end date is in the past");
        NSLog(@"Block End Date: %@ (%@), vs now is %@", [settings valueForKey: @"BlockEndDate"], [[settings valueForKey: @"BlockEndDate"] class], [NSDate date]);
        NSError* err = [SCErr errorWithCode: 302];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }

    [settings setValue:@YES forKey:@"BlockIsRunning"];
    NSError* syncErr = [settings syncSettingsAndWait:5];
    if (syncErr) {
        [SCBlockUtilities removeBlockFromSettings];
        [settings syncSettingsAndWait:5];
        [self.daemonMethodLock unlock];
        reply(syncErr);
        return; // No system rules without a durable end time for recovery.
    }

    NSLog(@"Adding firewall rules...");
    if (![SCHelperToolUtilities installBlockRulesFromSettings]) {
        NSString* message = [settings valueForKey:@"DayloftEnforcementError"];
        if ([[BlockManager new] clearBlock]) {
            [SCBlockUtilities removeBlockFromSettings];
        } else {
            // A partial installation must remain recoverable by the checkup.
            [settings setValue:NSDate.distantPast forKey:@"BlockEndDate"];
        }
        [settings syncSettingsAndWait:5];
        [self.daemonMethodLock unlock];
        [[SCDaemon sharedDaemon] startCheckupTimer];
        reply([NSError errorWithDomain:@"Dayloft" code:710 userInfo:@{NSLocalizedDescriptionKey:message.length ? message : @"Network rules could not be installed."}]);
        return;
    }
    NSMutableArray* sessions = [[settings valueForKey:@"DayloftFocusSessions"] mutableCopy] ?: [NSMutableArray new];
    [sessions addObject:@{@"start": [NSDate date], @"end": endDate, @"breaks": @[], @"mode": blockSettings[@"DayloftMode"] ?: @"Focus", @"uid": @(controllingUID)}];
    if (sessions.count > 2000) [sessions removeObjectsInRange:NSMakeRange(0, sessions.count - 2000)];
    [settings setValue:sessions forKey:@"DayloftFocusSessions"];
    syncErr = [settings syncSettingsAndWait:5];

    NSLog(@"Firewall rules added!");
    
    [SCHelperToolUtilities sendConfigurationChangedNotification];

    // Clear all caches if the user has the correct preference set, so
    // that blocked pages are not loaded from a cache.
    [SCHelperToolUtilities clearCachesIfRequested];

    [SCSentry addBreadcrumb: @"Daemon added block successfully" category: @"daemon"];
    NSLog(@"INFO: Block successfully added.");
    reply(syncErr);

    [[SCDaemon sharedDaemon] resetInactivityTimer];
    [self.daemonMethodLock unlock];
    [[SCDaemon sharedDaemon] startCheckupTimer];
}

+ (void)updateBlocklist:(NSArray<NSString*>*)newBlocklist authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    if (![SCDaemonBlockMethods lockOrTimeout: reply]) {
        return;
    }
    
    [SCSentry addBreadcrumb: @"Daemon method updateBlocklist called" category: @"daemon"];
    if ([SCBlockUtilities legacyBlockIsRunning]) {
        NSLog(@"ERROR: Can't update blocklist because a legacy block is running");
        NSError* err = [SCErr errorWithCode: 303];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }
    if (![SCBlockUtilities modernBlockIsRunning]) {
        NSLog(@"ERROR: Can't update blocklist since block isn't running");
        NSError* err = [SCErr errorWithCode: 304];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }
    
    SCSettings* settings = [SCSettings sharedSettings];
        
    if ([settings boolForKey: @"ActiveBlockAsWhitelist"]) {
        NSLog(@"ERROR: Attempting to update active blocklist, but this is not possible with an allowlist block");
        NSError* err = [SCErr errorWithCode: 305];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }
    
    NSArray* activeBlocklist = [settings valueForKey: @"ActiveBlocklist"];
    NSMutableArray* added = [NSMutableArray arrayWithArray: newBlocklist];
    [added removeObjectsInArray: activeBlocklist];
    NSMutableArray* removed = [NSMutableArray arrayWithArray: activeBlocklist];
    [removed removeObjectsInArray: newBlocklist];
    
    // throw a warning if something got removed for some reason, since we ignore them
    if (removed.count > 0) {
        NSLog(@"WARNING: Active blocklist has removed items; these will not be updated. Removed items are %@", removed);
    }
    
    BlockManager* blockManager = [[BlockManager alloc] initAsAllowlist: [settings boolForKey: @"ActiveBlockAsWhitelist"]
                                                            allowLocal: [settings boolForKey: @"AllowLocalNetworks"]
                                               includeCommonSubdomains: ([settings boolForKey: @"StrictDomainBlocking"] || [settings boolForKey: @"EvaluateCommonSubdomains"])
                                                  includeLinkedDomains: [settings boolForKey: @"IncludeLinkedDomains"]];
    if (![blockManager enterAppendMode]) {
        reply([NSError errorWithDomain:@"Dayloft" code:711 userInfo:@{NSLocalizedDescriptionKey:@"The website rules could not be opened. Your current block is unchanged; please try again."}]);
        [self.daemonMethodLock unlock];
        return;
    }
    [blockManager addBlockEntriesFromStrings: added];
    if (![blockManager finishAppending]) {
        reply([NSError errorWithDomain:@"Dayloft" code:712 userInfo:@{NSLocalizedDescriptionKey:@"The new websites could not be fully blocked. Please try adding them again."}]);
        [self.daemonMethodLock unlock];
        return;
    }
    // Active denylist updates may only add destinations. Retain omitted entries
    // in persisted state so recovery/restart cannot accidentally unblock them.
    NSMutableOrderedSet* effectiveList = [NSMutableOrderedSet orderedSetWithArray:activeBlocklist];
    [effectiveList addObjectsFromArray:added];
    [settings setValue:effectiveList.array forKey:@"ActiveBlocklist"];
    
    // make sure everyone knows about our new list
    NSError* syncErr = [settings syncSettingsAndWait: 5];
    if (syncErr != nil) {
        NSLog(@"WARNING: Sync failed or timed out with error %@ after updating blocklist", syncErr);
        [SCSentry captureError: syncErr];
    }

    [SCHelperToolUtilities sendConfigurationChangedNotification];

    // Clear all caches if the user has the correct preference set, so
    // that blocked pages are not loaded from a cache.
    [SCHelperToolUtilities clearCachesIfRequested];

    [SCSentry addBreadcrumb: @"Daemon updated blocklist successfully" category: @"daemon"];
    NSLog(@"INFO: Blocklist successfully updated.");
    reply(syncErr);

    [[SCDaemon sharedDaemon] resetInactivityTimer];
    [self.daemonMethodLock unlock];
}

+ (void)updateBlockEndDate:(NSDate*)newEndDate authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    if (![SCDaemonBlockMethods lockOrTimeout: reply]) {
        return;
    }
    
    [SCSentry addBreadcrumb: @"Daemon method updateBlockEndDate called" category: @"daemon"];

    if ([SCBlockUtilities legacyBlockIsRunning]) {
        NSLog(@"ERROR: Can't update block end date because a legacy block is running");
        NSError* err = [SCErr errorWithCode: 306];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }
    if (![SCBlockUtilities modernBlockIsRunning]) {
        NSLog(@"ERROR: Can't update block end date since block isn't running");
        NSError* err = [SCErr errorWithCode: 307];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }
    
    SCSettings* settings = [SCSettings sharedSettings];
    
    // this can only be used to *extend* the block end date - not shorten it!
    // and we also won't let them extend by more than 24 hours at a time, for safety...
    // TODO: they should be able to extend up to MaxBlockLength minutes, right?
    NSDate* currentEndDate = [settings valueForKey: @"BlockEndDate"];
    if (![newEndDate isKindOfClass:NSDate.class] || !isfinite([newEndDate timeIntervalSince1970]) || [newEndDate timeIntervalSinceDate: currentEndDate] < 0) {
        NSLog(@"ERROR: Can't update block end date to an earlier date");
        NSError* err = [SCErr errorWithCode: 308];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }
    if ([newEndDate timeIntervalSinceDate: currentEndDate] > 86400) { // 86400 seconds = 1 day
        NSLog(@"ERROR: Can't extend block end date by more than 1 day at a time");
        NSError* err = [SCErr errorWithCode: 309];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }
    
    NSArray* previousSessions = [settings valueForKey:@"DayloftFocusSessions"];
    [settings setValue: newEndDate forKey: @"BlockEndDate"];
    NSMutableArray* sessions = [[settings valueForKey:@"DayloftFocusSessions"] mutableCopy];
    if (sessions.count) {
        NSMutableDictionary* session = [sessions.lastObject mutableCopy];
        session[@"end"] = newEndDate; sessions[sessions.count - 1] = session;
        [settings setValue:sessions forKey:@"DayloftFocusSessions"];
    }
    
    // make sure everyone knows about our new end date
    NSError* syncErr = [settings syncSettingsAndWait: 5];
    if (syncErr != nil) {
        NSLog(@"WARNING: Sync failed or timed out with error %@ after extending block", syncErr);
        [SCSentry captureError: syncErr];
        [settings setValue:currentEndDate forKey:@"BlockEndDate"];
        [settings setValue:previousSessions forKey:@"DayloftFocusSessions"];
        [settings syncSettingsAndWait:5];
        [self.daemonMethodLock unlock];
        reply(syncErr);
        return;
    }

    [SCHelperToolUtilities sendConfigurationChangedNotification];

    [SCSentry addBreadcrumb: @"Daemon extended block successfully" category: @"daemon"];
    NSLog(@"INFO: Block successfully extended.");
    reply(nil);
    
    [[SCDaemon sharedDaemon] resetInactivityTimer];
    [self.daemonMethodLock unlock];
}

+ (void)takeBreakWithAuthorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    if (![SCDaemonBlockMethods lockOrTimeout: reply]) {
        return;
    }

    if (![SCBlockUtilities modernBlockIsRunning] || [SCBlockUtilities currentBlockIsExpired]) {
        NSError* err = [SCErr errorWithCode: 311];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }

    SCSettings* settings = [SCSettings sharedSettings];
    if ([SCBlockUtilities currentBreakIsActive] || [settings boolForKey: @"BlockPausedForBreak"]) {
        NSError* err = [SCErr errorWithCode: 312];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }

    NSInteger maxBreaks = MIN(MAX([[settings valueForKey: @"MaxBreaksPerBlock"] integerValue], 0), 3);
    NSInteger breaksUsed = MAX([[settings valueForKey: @"BreaksUsed"] integerValue], 0);
    if (maxBreaks == 0 || breaksUsed >= maxBreaks) {
        NSError* err = [SCErr errorWithCode: 313];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }

    // Rules are removed only here in the privileged daemon.  The active block
    // remains recorded and the daemon restores the exact same rules at expiry.
    if (![[BlockManager new] clearBlock]) {
        NSError* err = [SCErr errorWithCode: 314];
        [SCSentry captureError: err];
        reply(err);
        [self.daemonMethodLock unlock];
        return;
    }

    NSTimeInterval duration = 5 * 60; // Fixed five-minute break.
    [settings setValue: @(breaksUsed + 1) forKey: @"BreaksUsed"];
    [settings setValue: [NSDate dateWithTimeIntervalSinceNow: duration] forKey: @"BreakEndDate"];
    [settings setValue: @YES forKey: @"BlockPausedForBreak"];
    NSMutableArray* sessions = [[settings valueForKey:@"DayloftFocusSessions"] mutableCopy];
    if (sessions.count) {
        NSMutableDictionary* session = [sessions.lastObject mutableCopy];
        NSMutableArray* breaks = [session[@"breaks"] mutableCopy];
        [breaks addObject:@{@"start": [NSDate date], @"end": [settings valueForKey:@"BreakEndDate"]}];
        session[@"breaks"] = breaks; sessions[sessions.count - 1] = session;
        [settings setValue:sessions forKey:@"DayloftFocusSessions"];
    }

    NSError* syncErr = [settings syncSettingsAndWait: 5];
    if (syncErr != nil) {
        NSLog(@"WARNING: Sync failed after starting break: %@", syncErr);
        [SCSentry captureError: syncErr];
    }

    [SCHelperToolUtilities sendConfigurationChangedNotification];
    [SCSentry addBreadcrumb: @"Daemon started a five-minute focus break" category: @"daemon"];
    reply(syncErr);
    [[SCDaemon sharedDaemon] resetInactivityTimer];
    [self.daemonMethodLock unlock];
}

+ (void)checkupBlock {
    if (![SCDaemonBlockMethods lockOrTimeout: nil timeout: CHECKUP_LOCK_TIMEOUT]) {
        return;
    }
    
    [SCSentry addBreadcrumb: @"Daemon method checkupBlock called" category: @"daemon"];

    NSTimeInterval integrityCheckIntervalSecs = 15.0;
    static NSDate* lastBlockIntegrityCheck;
    if (lastBlockIntegrityCheck == nil) {
        lastBlockIntegrityCheck = [NSDate distantPast];
    }

    BOOL shouldRunIntegrityCheck = NO;
    BOOL shouldStartScheduledBlock = NO;
    uid_t scheduledControllingUID = 0;
    NSArray<NSString*>* scheduledBlocklist = nil;
    BOOL scheduledIsAllowlist = NO;
    NSDate* scheduledEndDate = nil;
    NSDictionary* scheduledBlockSettings = nil;
    SCSettings* settings = [SCSettings sharedSettings];

    // A schedule is evaluated before regular block integrity. Without this
    // branch, an idle daemon would interpret the absence of an active block as
    // tampering and remove itself before the scheduled start date.
    if ([self scheduledBlockIsPending]) {
        NSDate* scheduledDate = [settings valueForKey: @"ScheduledBlockDate"];
        NSTimeInterval durationSeconds = [[settings valueForKey: @"ScheduledBlockDurationSeconds"] doubleValue];
        scheduledBlocklist = [settings valueForKey: @"ScheduledBlocklist"];
        scheduledIsAllowlist = [settings boolForKey: @"ScheduledBlockAsWhitelist"];
        scheduledBlockSettings = [settings valueForKey: @"ScheduledBlockSettings"];
        scheduledControllingUID = (uid_t)[[settings valueForKey: @"ScheduledBlockControllingUID"] unsignedIntValue];

        BOOL invalidSchedule = scheduledDate == nil ||
                               durationSeconds <= 0 ||
                               (scheduledBlocklist.count == 0 && !scheduledIsAllowlist) ||
                               ![scheduledBlockSettings isKindOfClass: [NSDictionary class]];
        if (invalidSchedule) {
            [self clearScheduledBlockFromSettings: settings];
            [settings setValue: @"The scheduled block was incomplete and could not start." forKey: @"ScheduledBlockLastError"];
            [settings syncSettingsAndWait: 5];
            [SCHelperToolUtilities sendConfigurationChangedNotification];
        } else if ([scheduledDate timeIntervalSinceNow] <= 0 && ![settings boolForKey: @"ScheduledBlockStarting"]) {
            [settings setValue: @YES forKey: @"ScheduledBlockStarting"];
            NSError* syncErr = [settings syncSettingsAndWait: 5];
            if (syncErr != nil) {
                NSLog(@"WARNING: Sync failed while starting scheduled block: %@", syncErr);
                [SCSentry captureError: syncErr];
            }
            // If the Mac was asleep at the requested time, start immediately
            // on wake and still give the user the full chosen duration.
            scheduledEndDate = [NSDate dateWithTimeIntervalSinceNow: durationSeconds];
            shouldStartScheduledBlock = YES;
        }

        [[SCDaemon sharedDaemon] resetInactivityTimer];
        [self.daemonMethodLock unlock];

        if (shouldStartScheduledBlock) {
            [self startBlockWithControllingUID: scheduledControllingUID
                                      blocklist: scheduledBlocklist
                                    isAllowlist: scheduledIsAllowlist
                                        endDate: scheduledEndDate
                                  blockSettings: scheduledBlockSettings
                                 authorization: nil
                                         reply:^(NSError *error) {
                if (error != nil) {
                    SCSettings* failedSettings = [SCSettings sharedSettings];
                    [self clearScheduledBlockFromSettings: failedSettings];
                    [failedSettings setValue: error.localizedDescription ?: @"The scheduled block could not start." forKey: @"ScheduledBlockLastError"];
                    [failedSettings syncSettingsAndWait: 5];
                    [SCHelperToolUtilities sendConfigurationChangedNotification];
                    [SCSentry captureError: error];
                    if (![self hasRecurringSchedules]) [[SCDaemon sharedDaemon] stopCheckupTimer];
                }
            }];
        } else if (invalidSchedule) {
            if (![self hasRecurringSchedules]) [[SCDaemon sharedDaemon] stopCheckupTimer];
        }
        return;
    }

    // A recurrence is a local calendar window, not a full-duration catch-up.
    // Wake inside a window runs only its remainder; missed windows are skipped.
    // The first enabled row wins overlapping starts, and an active block is never shortened.
    if (![SCBlockUtilities anyBlockIsRunning] && [self hasRecurringSchedules]) {
        NSDate* now = [NSDate date];
        NSDictionary* selected = nil;
        NSDateInterval* selectedInterval = nil;
        NSMutableDictionary* occurrences = [[settings valueForKey:@"DayloftScheduleOccurrences"] mutableCopy];
        for (NSDictionary* schedule in [settings valueForKey:@"DayloftRecurringSchedules"]) {
            NSDateInterval* interval = [SCRecurringSchedule activeIntervalForSchedule:schedule atDate:now calendar:NSCalendar.currentCalendar];
            if (interval && ![occurrences[schedule[@"id"]] isEqual:interval.startDate]) {
                selected = schedule; selectedInterval = interval; break;
            }
        }
        NSMutableDictionary* config = [[settings valueForKey:@"DayloftScheduleSettings"] mutableCopy];
        if (selected) { config[@"BreaksPerBlock"] = selected[@"breaks"]; config[@"DayloftMode"] = selected[@"mode"]; }
        uid_t uid = [[settings valueForKey:@"DayloftScheduleUID"] unsignedIntValue];
        [[SCDaemon sharedDaemon] resetInactivityTimer];
        [self.daemonMethodLock unlock];
        if (selected) {
            [self startBlockWithControllingUID:uid blocklist:[SCMiscUtilities cleanBlocklist:selected[@"domains"]] isAllowlist:[selected[@"allowlist"] boolValue] endDate:selectedInterval.endDate blockSettings:config authorization:nil reply:^(NSError* error) {
                // Commit the occurrence after the start attempt. A crash before rules are
                // installed must leave this window retryable on daemon restart.
                if (!error) {
                    occurrences[selected[@"id"]] = selectedInterval.startDate;
                    [settings setValue:occurrences forKey:@"DayloftScheduleOccurrences"];
                    [settings setValue:@"" forKey:@"DayloftScheduleLastError"];
                    [settings syncSettingsAndWait:5];
                }
                if (error) {
                    [settings setValue:error.localizedDescription forKey:@"DayloftScheduleLastError"];
                    [settings syncSettingsAndWait:5];
                    [SCHelperToolUtilities sendConfigurationChangedNotification];
                }
            }];
        }
        return;
    }

    if(![SCBlockUtilities anyBlockIsRunning]) {
        // No block appears to be running at all in our settings.
        // Most likely, the user removed it trying to get around the block. Boo!
        // but for safety and to avoid permablocks (we no longer know when the block should end)
        // we should clear the block now.
        // but let them know that we noticed their (likely) cheating and we're not happy!
        NSLog(@"INFO: Checkup ran, no active block found.");
        
        [SCSentry captureMessage: @"Checkup ran and no active block found! Removing block, tampering suspected..."];
        
        if (![SCHelperToolUtilities removeBlock]) {
            [self.daemonMethodLock unlock];
            return; // Keep the timer alive and retry cleanup on the next checkup.
        }

        [SCHelperToolUtilities sendConfigurationChangedNotification];
        
        // Temporarily disabled the TamperingDetection flag because it was sometimes causing false positives
        // (i.e. people having the background set repeatedly despite no attempts to cheat)
        // We will try to bring this feature back once we can debug it
        // GitHub issue: https://github.com/SelfControlApp/selfcontrol/issues/621
        // [settings setValue: @YES forKey: @"TamperingDetected"];
        //        [settings synchronizeSettings];
        //
        
        // once the checkups stop, the daemon will clear itself in a while due to inactivity
        if (![self hasRecurringSchedules]) [[SCDaemon sharedDaemon] stopCheckupTimer];
    } else if ([SCBlockUtilities currentBlockIsExpired]) {
        NSLog(@"INFO: Checkup ran, block expired, removing block.");
        
        if (![SCHelperToolUtilities removeBlock]) {
            [self.daemonMethodLock unlock];
            return; // Keep the timer alive and retry cleanup on the next checkup.
        }

        [SCHelperToolUtilities sendConfigurationChangedNotification];

        [SCSentry addBreadcrumb: @"Daemon found and cleared expired block" category: @"daemon"];

        // once the checkups stop, the daemon will clear itself in a while due to inactivity
        if (![self hasRecurringSchedules]) [[SCDaemon sharedDaemon] stopCheckupTimer];
    } else if ([SCBlockUtilities currentBreakIsActive]) {
        // The rules are intentionally absent while a break is active.
    } else if ([settings boolForKey: @"BlockPausedForBreak"]) {
        NSLog(@"INFO: Break ended, restoring block rules.");
        if (![SCHelperToolUtilities installBlockRulesFromSettings]) {
            [settings syncSettingsAndWait:5];
            [SCHelperToolUtilities sendConfigurationChangedNotification];
            [self.daemonMethodLock unlock];
            return; // Keep retrying restoration; never report a successful resume.
        }
        [settings setValue: @NO forKey: @"BlockPausedForBreak"];
        [settings setValue: [NSDate distantPast] forKey: @"BreakEndDate"];
        NSError* syncErr = [settings syncSettingsAndWait: 5];
        if (syncErr != nil) {
            NSLog(@"WARNING: Sync failed after restoring break rules: %@", syncErr);
            [SCSentry captureError: syncErr];
        }
        [SCHelperToolUtilities clearCachesIfRequested];
        [SCHelperToolUtilities sendConfigurationChangedNotification];
    } else if ([[NSDate date] timeIntervalSinceDate: lastBlockIntegrityCheck] > integrityCheckIntervalSecs) {
        lastBlockIntegrityCheck = [NSDate date];
        // The block is still on.  Every once in a while, we should
        // check if anybody removed our rules, and if so
        // re-add them.
        shouldRunIntegrityCheck = YES;
    }
    
    [[SCDaemon sharedDaemon] resetInactivityTimer];
    [self.daemonMethodLock unlock];
    
    // if we need to run an integrity check, we need to do it at the very end after we give up our lock
    // because checkBlockIntegrity requests its own lock, and we don't want it to deadlock
    if (shouldRunIntegrityCheck) {
        [SCDaemonBlockMethods checkBlockIntegrity];
    }
}

+ (void)checkBlockIntegrity {
    if (![SCDaemonBlockMethods lockOrTimeout: nil timeout: CHECKUP_LOCK_TIMEOUT]) {
        return;
    }
    
    [SCSentry addBreadcrumb: @"Daemon method checkBlockIntegrity called" category: @"daemon"];

    SCSettings* settings = [SCSettings sharedSettings];
    // File-watch notifications also arrive for intentional break/expiry writes.
    // Only checkupBlock may transition a paused or expired session.
    if (![settings boolForKey:@"BlockIsRunning"] || [SCBlockUtilities currentBlockIsExpired] ||
        [settings boolForKey:@"BlockPausedForBreak"]) {
        [self.daemonMethodLock unlock];
        return;
    }
    PacketFilter* pf = [[PacketFilter alloc] init];
    HostFileBlockerSet* hostFileBlockerSet = [[HostFileBlockerSet alloc] init];
    if([[settings valueForKey:@"DayloftEnforcementError"] length] || ![pf containsSelfControlBlock] || (![settings boolForKey: @"ActiveBlockAsWhitelist"] && ![hostFileBlockerSet.defaultBlocker containsSelfControlBlock])) {
        NSLog(@"INFO: Block is missing in PF or hosts, re-adding...");
        // The firewall is missing at least the block header.  Let's clear everything
        // before we re-add to make sure everything goes smoothly.

        [pf stopBlock: false];

        [hostFileBlockerSet removeSelfControlBlock];
        BOOL success = [hostFileBlockerSet writeNewFileContents];
        // Revert the host file blocker's file contents to disk so we can check
        // whether or not it still contains the block after our write (aka we messed up).
        [hostFileBlockerSet revertFileContentsToDisk];
        if(!success || [hostFileBlockerSet.defaultBlocker containsSelfControlBlock]) {
            NSLog(@"WARNING: Error removing host file block.  Attempting to restore backup.");

            if([hostFileBlockerSet restoreBackupHostsFile])
                NSLog(@"INFO: Host file backup restored.");
            else
                NSLog(@"ERROR: Host file backup could not be restored.  This may result in a permanent block.");
        }

        // Get rid of the backup file since we're about to make a new one.
        [hostFileBlockerSet deleteBackupHostsFile];

        // Perform the re-add of the rules
        BOOL restored = [SCHelperToolUtilities installBlockRulesFromSettings];
        [settings syncSettingsAndWait:5];
        [SCHelperToolUtilities sendConfigurationChangedNotification];
        if (!restored) {
            [self.daemonMethodLock unlock];
            return;
        }
        [SCHelperToolUtilities clearCachesIfRequested];

        [SCSentry addBreadcrumb: @"Daemon found compromised block integrity and re-added rules" category: @"daemon"];
        NSLog(@"INFO: Integrity check ran; readded block rules.");
    } else NSLog(@"INFO: Integrity check ran; no action needed.");
    
    [self.daemonMethodLock unlock];
}

@end
