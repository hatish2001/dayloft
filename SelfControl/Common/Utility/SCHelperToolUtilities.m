//
//  SCHelperToolUtilities.m
//  SelfControl
//
//  Created by Charlie Stigler on 1/19/21.
//

#import "SCHelperToolUtilities.h"
#import "BlockManager.h"
#import <libproc.h>
#include <stdlib.h>
#include <sys/proc_info.h>

static NSTimeInterval const SCWebKitReplacementWindowSeconds = 10.0;
static NSMutableDictionary<NSNumber*, NSMutableDictionary*>* SCWebKitMonitorStates;

static NSSet<NSNumber*>* SCProcessIdentifiersNamedForUser(NSString* executableName, uid_t controllingUID) {
    int byteCount = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (byteCount <= 0) return [NSSet set];

    pid_t* pids = calloc((size_t)byteCount / sizeof(pid_t), sizeof(pid_t));
    if (pids == NULL) return [NSSet set];
    byteCount = proc_listpids(PROC_ALL_PIDS, 0, pids, byteCount);

    NSMutableSet<NSNumber*>* matches = [NSMutableSet set];
    int pidCount = MAX(byteCount, 0) / (int)sizeof(pid_t);
    for (int index = 0; index < pidCount; index++) {
        pid_t pid = pids[index];
        if (pid <= 0) continue;

        struct proc_bsdinfo info = {0};
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info) || info.pbi_uid != controllingUID) continue;

        char executablePath[PROC_PIDPATHINFO_MAXSIZE] = {0};
        if (proc_pidpath(pid, executablePath, sizeof(executablePath)) <= 0) continue;
        NSString* path = [NSString stringWithUTF8String:executablePath];
        if ([path.lastPathComponent isEqualToString:executableName]) [matches addObject:@(pid)];
    }
    free(pids);
    return matches;
}

static void SCNoteWebKitNetworkingReset(uid_t controllingUID, BOOL expectsReplacement) {
    if (controllingUID == 0) return;
    @synchronized(SCHelperToolUtilities.class) {
        if (SCWebKitMonitorStates == nil) SCWebKitMonitorStates = [NSMutableDictionary new];
        SCWebKitMonitorStates[@(controllingUID)] = [@{
            @"trusted": [NSSet set],
            @"awaitingReplacement": @(expectsReplacement),
            @"replacementDeadline": [NSDate dateWithTimeIntervalSinceNow:SCWebKitReplacementWindowSeconds]
        } mutableCopy];
    }
}

static uid_t SCActiveControllingUID(SCSettings* settings) {
    uid_t controllingUID = [[settings valueForKey:@"ActiveBlockControllingUID"] unsignedIntValue];
    if (controllingUID != 0) return controllingUID;

    // Active blocks created by 4.2.6 and earlier did not have the dedicated
    // key, but Dayloft's session record already carried the authenticated UID.
    id sessionRecords = [settings valueForKey:@"DayloftFocusSessions"];
    NSDictionary* session = [sessionRecords isKindOfClass:NSArray.class] ? [sessionRecords lastObject] : nil;
    if ([session isKindOfClass:NSDictionary.class] && [session[@"uid"] respondsToSelector:@selector(unsignedIntValue)]) {
        controllingUID = [session[@"uid"] unsignedIntValue];
        if (controllingUID != 0) [settings setValue:@(controllingUID) forKey:@"ActiveBlockControllingUID"];
    }
    return controllingUID;
}

@implementation SCHelperToolUtilities

+ (BOOL)installBlockRulesFromSettings {
    SCSettings* settings = [SCSettings sharedSettings];
    BOOL shouldEvaluateCommonSubdomains = [settings boolForKey: @"EvaluateCommonSubdomains"];
    BOOL allowLocalNetworks = [settings boolForKey: @"AllowLocalNetworks"];
    BOOL includeLinkedDomains = [settings boolForKey: @"IncludeLinkedDomains"];
    BOOL strictDomainBlocking = [settings boolForKey: @"StrictDomainBlocking"];

    // get value for ActiveBlockAsWhitelist
    BOOL blockAsAllowlist = [settings boolForKey: @"ActiveBlockAsWhitelist"];

    BlockManager* blockManager = [[BlockManager alloc] initAsAllowlist: blockAsAllowlist allowLocal: allowLocalNetworks includeCommonSubdomains: (strictDomainBlocking || shouldEvaluateCommonSubdomains) includeLinkedDomains: includeLinkedDomains];

    NSLog(@"About to run BlockManager commands");
    
    [blockManager prepareToAddBlock];
    // Rebuilding after a break/recovery must resolve public addresses, not a
    // cached 0.0.0.0/:: answer from our previous hosts-file entries.
    [SCHelperToolUtilities clearOSDNSCache];
    [blockManager addBlockEntriesFromStrings: [settings valueForKey: @"ActiveBlocklist"]];
    BOOL installed = [blockManager finalizeBlock];
    [settings setValue:installed ? @"" : @"Dayloft could not install its network rules. Blocking is not fully active. Please reopen Dayloft and try again." forKey:@"DayloftEnforcementError"];
    if (installed) {
        [SCHelperToolUtilities resetWebKitNetworkingForControllingUID:SCActiveControllingUID(settings)];
    }
    return installed;
}

+ (void)unloadDaemonJob {
    NSLog(@"Exiting idle Dayloft helper process...");
    [SCSentry addBreadcrumb: @"Idle daemon process about to exit" category: @"daemon"];
    SCSettings* settings = [SCSettings sharedSettings];

    // Keep the launchd job registered. MachServices will start a fresh process
    // on the next request without asking the user to install the helper again.
    NSError* syncErr = [settings syncSettingsAndWait: 5.0];
    if (syncErr != nil) {
        NSLog(@"WARNING: Sync failed or timed out with error %@ before exiting idle daemon", syncErr);
        [SCSentry captureError: syncErr];
    }
    
    exit(EXIT_SUCCESS);
}

+ (void)clearCachesIfRequested {
    SCSettings* settings = [SCSettings sharedSettings];
    // DNS invalidation is required for enforcement, independently of optional
    // browser-cache deletion. Otherwise a previously resolved site can survive.
    [SCHelperToolUtilities clearOSDNSCache];
    if(![settings boolForKey: @"ClearCaches"]) {
        return;
    }
    
    NSError* err = [SCHelperToolUtilities clearBrowserCaches];
    if (err) {
        NSLog(@"WARNING: Error clearing browser caches: %@", err);
        [SCSentry captureError: err];
    }

}

+ (NSError*)clearBrowserCaches {
    NSFileManager* fileManager = [NSFileManager defaultManager];

    NSError* homeDirErr = nil;
    NSArray<NSURL *>* homeDirectoryURLs = [SCMiscUtilities allUserHomeDirectoryURLs: &homeDirErr];
    if (homeDirectoryURLs == nil) return homeDirErr;
    
    NSArray<NSString*>* cacheDirPathComponents = @[
        // chrome
        @"/Library/Caches/Google/Chrome/Default",
        @"/Library/Caches/Google/Chrome/com.google.Chrome",
        
        // firefox
        @"/Library/Caches/Firefox/Profiles",
        
        // safari
        @"/Library/Caches/com.apple.Safari",
        @"/Library/Containers/com.apple.Safari/Data/Library/Caches" // this one seems to fail due to permissions issues, but not sure how to fix
    ];
    
    
    NSMutableArray<NSURL*>* cacheDirURLs = [NSMutableArray arrayWithCapacity: cacheDirPathComponents.count * homeDirectoryURLs.count];
    for (NSURL* homeDirURL in homeDirectoryURLs) {
        for (NSString* cacheDirPathComponent in cacheDirPathComponents) {
            [cacheDirURLs addObject: [homeDirURL URLByAppendingPathComponent: cacheDirPathComponent isDirectory: YES]];
        }
    }
    
    for (NSURL* cacheDirURL in cacheDirURLs) {
        NSLog(@"Clearing browser cache folder %@", cacheDirURL);
        // removeItemAtURL will return errors if the file doesn't exist
        // so we don't track the errors - best effort is OK
        [fileManager removeItemAtURL: cacheDirURL error: nil];
    }
    
    return nil;
}

+ (void)clearOSDNSCache {
    // no error checks - if it works it works!
    NSTask* flushDsCacheUtil = [[NSTask alloc] init];
    [flushDsCacheUtil setLaunchPath: @"/usr/bin/dscacheutil"];
    [flushDsCacheUtil setArguments: @[@"-flushcache"]];
    [flushDsCacheUtil launch];
    [flushDsCacheUtil waitUntilExit];
    
    NSTask* killResponder = [[NSTask alloc] init];
    [killResponder setLaunchPath: @"/usr/bin/killall"];
    [killResponder setArguments: @[@"-HUP", @"mDNSResponder"]];
    [killResponder launch];
    [killResponder waitUntilExit];
    
    NSTask* killResponderHelper = [[NSTask alloc] init];
    [killResponderHelper setLaunchPath: @"/usr/bin/killall"];
    [killResponderHelper setArguments: @[@"mDNSResponderHelper"]];
    [killResponderHelper launch];
    [killResponderHelper waitUntilExit];
    
    NSLog(@"Cleared OS DNS caches");
}

+ (void)resetWebKitNetworkingForControllingUID:(uid_t)controllingUID {
    if (controllingUID == 0) {
        NSLog(@"WARNING: Cannot reset WebKit networking without a controlling user");
        return;
    }

    NSSet<NSNumber*>* networkingPIDs = SCProcessIdentifiersNamedForUser(@"com.apple.WebKit.Networking", controllingUID);

    // Safari keeps DNS and established connections in its networking process,
    // while page-cache and service-worker state can survive in WebContent.
    // Safari automatically relaunches both services without closing its tabs.
    for (NSString* processName in @[@"com.apple.WebKit.Networking", @"com.apple.WebKit.WebContent"]) {
        NSTask* resetWebKit = [[NSTask alloc] init];
        [resetWebKit setLaunchPath:@"/usr/bin/pkill"];
        [resetWebKit setArguments:@[@"-KILL", @"-U", [NSString stringWithFormat:@"%u", controllingUID], @"-x", processName]];
        @try {
            [resetWebKit launch];
            [resetWebKit waitUntilExit];
            if (resetWebKit.terminationStatus == 0) {
                NSLog(@"Reset %@ for user %u", processName, controllingUID);
            } else {
                // pkill returns 1 when there is no matching process, which is
                // a normal outcome when Safari is closed.
                NSLog(@"No %@ process needed a reset for user %u", processName, controllingUID);
            }
        } @catch (NSException* exception) {
            NSLog(@"WARNING: Could not reset %@ for user %u: %@", processName, controllingUID, exception);
        }
    }
    SCNoteWebKitNetworkingReset(controllingUID, networkingPIDs.count > 0);
}

+ (BOOL)shouldResetWebKitNetworkingForControllingUID:(uid_t)controllingUID
                            currentProcessIdentifiers:(NSSet<NSNumber*>*)processIdentifiers
                                                  now:(NSDate*)now {
    if (controllingUID == 0) return NO;
    NSSet<NSNumber*>* current = [processIdentifiers isKindOfClass:NSSet.class] ? processIdentifiers : [NSSet set];
    NSDate* observationDate = [now isKindOfClass:NSDate.class] ? now : [NSDate date];

    @synchronized(self) {
        if (SCWebKitMonitorStates == nil) SCWebKitMonitorStates = [NSMutableDictionary new];
        NSMutableDictionary* state = SCWebKitMonitorStates[@(controllingUID)];
        if (state == nil) {
            state = [@{
                @"trusted": [NSSet set],
                @"awaitingReplacement": @NO,
                @"replacementDeadline": NSDate.distantPast
            } mutableCopy];
            SCWebKitMonitorStates[@(controllingUID)] = state;
        }

        BOOL awaitingReplacement = [state[@"awaitingReplacement"] boolValue];
        NSDate* replacementDeadline = state[@"replacementDeadline"];
        if (current.count == 0) {
            state[@"trusted"] = [NSSet set];
            if (awaitingReplacement && [observationDate compare:replacementDeadline] == NSOrderedDescending) {
                state[@"awaitingReplacement"] = @NO;
            }
            return NO;
        }

        if (awaitingReplacement && [observationDate compare:replacementDeadline] != NSOrderedDescending) {
            // This process was launched because of our reset, so it has never
            // run without the current hosts rules. Remember it as clean.
            state[@"trusted"] = current;
            state[@"awaitingReplacement"] = @NO;
            return NO;
        }

        state[@"awaitingReplacement"] = @NO;
        NSSet<NSNumber*>* trusted = [state[@"trusted"] isKindOfClass:NSSet.class] ? state[@"trusted"] : [NSSet set];
        if (![current isSubsetOfSet:trusted]) {
            state[@"trusted"] = [NSSet set];
            state[@"awaitingReplacement"] = @YES;
            state[@"replacementDeadline"] = [observationDate dateByAddingTimeInterval:SCWebKitReplacementWindowSeconds];
            return YES;
        }

        // Forget processes that have exited so a recycled PID cannot inherit trust.
        state[@"trusted"] = current;
        return NO;
    }
}

+ (void)maintainWebKitNetworkIsolationForControllingUID:(uid_t)controllingUID {
    if (controllingUID == 0) return;
    NSSet<NSNumber*>* processIdentifiers = SCProcessIdentifiersNamedForUser(@"com.apple.WebKit.Networking", controllingUID);
    if ([self shouldResetWebKitNetworkingForControllingUID:controllingUID currentProcessIdentifiers:processIdentifiers now:NSDate.date]) {
        NSLog(@"A new WebKit networking process appeared during an active block; resetting it for user %u", controllingUID);
        [self resetWebKitNetworkingForControllingUID:controllingUID];
    }
}

+ (void)resetWebKitNetworkMonitoringState {
    @synchronized(self) {
        SCWebKitMonitorStates = nil;
    }
}

+ (void)playBlockEndSound {
    SCSettings* settings = [SCSettings sharedSettings];
    if([settings boolForKey: @"BlockSoundShouldPlay"]) {
        // Map the tags used in interface builder to the sound
        NSArray* systemSoundNames = SCConstants.systemSoundNames;
        NSSound* alertSound = [NSSound soundNamed: systemSoundNames[(NSUInteger)[[settings valueForKey: @"BlockSound"] intValue]]];
        if(!alertSound)
            NSLog(@"WARNING: Alert sound not found.");
        else {
            [alertSound play];
        }
    }
}

+ (BOOL)removeBlock {
    SCSettings* settings = [SCSettings sharedSettings];
    uid_t controllingUID = SCActiveControllingUID(settings);
    if (![[BlockManager new] clearBlock]) {
        // Preserve the end date and running state so cleanup is retried, even
        // when this began as recovery of orphaned rules at daemon startup.
        [settings setValue:@YES forKey:@"BlockIsRunning"];
        [settings setValue:@"Dayloft could not fully remove its network rules. It will keep retrying." forKey:@"DayloftEnforcementError"];
        [settings syncSettingsAndWait:5];
        [self sendConfigurationChangedNotification];
        return NO;
    }
    [SCBlockUtilities removeBlockFromSettings];
    [settings setValue:@"" forKey:@"DayloftEnforcementError"];
    
    [SCHelperToolUtilities clearCachesIfRequested];
    [SCHelperToolUtilities resetWebKitNetworkingForControllingUID:controllingUID];

    // play a sound letting
    [SCHelperToolUtilities playBlockEndSound];
        
    // always synchronize settings ASAP after removing a block to let everybody else know
    // and wait until they're synced before we send the configuration change notification
    // so the app has no chance of reading the data before we update it
    NSError* syncErr = [[SCSettings sharedSettings] syncSettingsAndWait: 5.0];
    if (syncErr != nil) {
        NSLog(@"WARNING: Sync failed or timed out with error %@ after removing block", syncErr);
        [SCSentry captureError: syncErr];
    }

    // let the main app know things have changed so it can update the UI!
    [SCHelperToolUtilities sendConfigurationChangedNotification];

    NSLog(@"INFO: Block cleared.");
    return syncErr == nil;
}

+ (void)sendConfigurationChangedNotification {
    // if you don't include the NSNotificationPostToAllSessions option,
    // it will not deliver when run by launchd (root) to the main app being run by the user
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName: @"DayloftConfigurationChangedNotification"
                                                                   object: nil
                                                                 userInfo: nil
                                                                  options: NSNotificationDeliverImmediately | NSNotificationPostToAllSessions];
}

@end
