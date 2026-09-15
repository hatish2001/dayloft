//
//  SCHelperToolUtilities.h
//  SelfControl
//
//  Created by Charlie Stigler on 1/19/21.
//

#import <Foundation/Foundation.h>
#include <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

// Utility methods athat are only used by the helper tools
// (i.e. selfcontrold, selfcontrol-cli, and SCKillerHelper)
// note that this is NOT included in SCUtility.h currently!
@interface SCHelperToolUtilities : NSObject

// Reads the domain block list from the settings for SelfControl, and adds deny
// rules for all of the IPs (or the A DNS record IPS for doamin names) to the
// ipfw firewall.
+ (BOOL)installBlockRulesFromSettings;

// Exits an idle helper process while preserving its launchd registration, so
// the next XPC action can start it without another privileged installation.
+ (void)unloadDaemonJob;

// Checks the settings system to see whether the user wants their web browser
// caches cleared, and deletes the specific cache folders for a few common
// web browsers if it is required.
+ (void)clearCachesIfRequested;

// Clear only the caches for browsers
+ (nullable NSError*)clearBrowserCaches;

// Clear only the OS-level DNS cache
+ (void)clearOSDNSCache;

// Restart the controlling user's WebKit network and page processes so Safari
// cannot retain a pre-block connection, cached page, or stale blocked result.
+ (void)resetWebKitNetworkingForControllingUID:(uid_t)controllingUID;

// During a strict denylist session, Safari may launch a new networking process
// long after the block began and restore cached direct connections. Watch for
// that first process and reset it once so its replacement starts behind the
// active DNS rules.
+ (void)maintainWebKitNetworkIsolationForControllingUID:(uid_t)controllingUID;

// Deterministic state-machine hooks used by the test target.
+ (BOOL)shouldResetWebKitNetworkingForControllingUID:(uid_t)controllingUID
                            currentProcessIdentifiers:(NSSet<NSNumber*>*)processIdentifiers
                                                  now:(NSDate*)now;
+ (void)resetWebKitNetworkMonitoringState;

// Removes block via settings, host file rules and ipfw rules,
// deleting user caches if requested, and migrating legacy settings.
+ (BOOL)removeBlock;

+ (void)sendConfigurationChangedNotification;

@end

NS_ASSUME_NONNULL_END
