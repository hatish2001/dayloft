//
//  SCDaemonBlockMethods.h
//  org.dayloft.focusd
//
//  Created by Charlie Stigler on 7/4/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Top-level logic for different methods run by the SelfControl daemon
// these logics can be run by XPC methods, or elsewhere
@interface SCDaemonBlockMethods : NSObject

@property (class, readonly) NSLock* daemonMethodLock;

// Starts a block
+ (void)startBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist endDate:(NSDate*)endDate blockSettings:(NSDictionary*)blockSettings authorization:(nullable NSData *)authData reply:(void(^)(NSError* error))reply;

// Stores one future block snapshot, then starts it from the daemon at its date.
+ (void)scheduleBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist startDate:(NSDate*)startDate durationSeconds:(NSTimeInterval)durationSeconds blockSettings:(NSDictionary*)blockSettings authorization:(NSData *)authData reply:(void(^)(NSError* error))reply;
+ (void)cancelScheduledBlockWithAuthorization:(NSData *)authData reply:(void(^)(NSError* error))reply;
+ (BOOL)scheduledBlockIsPending;

// Checks whether the block is expired or compromised, and takes action to fix
+ (void)checkupBlock;

// updates the blocklist for the currently running block
// (i.e. adds new sites to the list)
+ (void)updateBlocklist:(NSArray<NSString*>*)newBlocklist authorization:(NSData *)authData reply:(void(^)(NSError* error))reply;

// updates the block end date for the currently running block
// (i.e. extends the block)
+ (void)updateBlockEndDate:(NSDate*)newEndDate authorization:(NSData *)authData reply:(void(^)(NSError* error))reply;

// Pauses rules for the fixed break duration when the active block has budget left.
+ (void)takeBreakWithAuthorization:(NSData *)authData reply:(void(^)(NSError* error))reply;

+ (void)checkBlockIntegrity;

+ (void)setRecurringSchedules:(NSArray<NSDictionary*>*)schedules controllingUID:(uid_t)controllingUID blockSettings:(NSDictionary*)blockSettings authorization:(NSData*)authData reply:(void(^)(NSError* error))reply;

@end

NS_ASSUME_NONNULL_END
