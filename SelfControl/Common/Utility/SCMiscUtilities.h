//
//  SCMiscUtilities.h
//  SelfControl
//
//  Created by Charles Stigler on 07/07/2018.
//

#import <Foundation/Foundation.h>
#import "SCMigrationUtilities.h"

// Holds utility methods for use throughout SelfControl


@interface SCMiscUtilities : NSObject

+ (dispatch_source_t)createDebounceDispatchTimer:(double) debounceTime queue:(dispatch_queue_t)queue block:(dispatch_block_t)block;

+ (NSString *)getSerialNumber;
+ (NSString *)sha1:(NSString*)stringToHash;

+ (BOOL)systemThirdPartyCrashReportingEnabled;

+ (NSArray<NSString*>*)cleanBlocklistEntry:(NSString*)rawEntry;

+ (NSArray<NSString*>*)cleanBlocklist:(NSArray<NSString*>*)blocklist;

// Adds cleaned entries while treating www.example.com and example.com as the
// same website. The first spelling is retained for stable display ordering.
+ (NSArray<NSString*>*)blocklistByAddingEntries:(NSArray<NSString*>*)additions toBlocklist:(NSArray<NSString*>*)blocklist;

+ (NSDictionary*) defaultsDictForUser:(uid_t)controllingUID;

+ (NSArray<NSURL*>*)allUserHomeDirectoryURLs:(NSError**)errPtr;

+ (BOOL)errorIsAuthCanceled:(NSError*)err;

+ (NSString*)killerKeyForDate:(NSDate*)date;

@end
