//
//  SCDaemonXPC.m
//  selfcontrold
//
//  Created by Charlie Stigler on 5/30/20.
//

#import "SCDaemonXPC.h"
#import "SCDaemonBlockMethods.h"
#import "SCXPCAuthorization.h"

@implementation SCDaemonXPC

- (void)startBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist endDate:(NSDate*)endDate blockSettings:(NSDictionary*)blockSettings authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: startBlockWithControllingUID");
    
    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: _cmd];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    } else {
        NSLog(@"Authorization accepted for %s", sel_getName(_cmd));
    }

    [SCDaemonBlockMethods startBlockWithControllingUID: controllingUID blocklist: blocklist isAllowlist:isAllowlist endDate: endDate blockSettings:blockSettings authorization: authData reply: reply];
}

- (void)scheduleBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist startDate:(NSDate*)startDate durationSeconds:(NSTimeInterval)durationSeconds blockSettings:(NSDictionary*)blockSettings authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: scheduleBlockWithControllingUID");

    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: _cmd];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    }

    [SCDaemonBlockMethods scheduleBlockWithControllingUID: controllingUID
                                                 blocklist: blocklist
                                               isAllowlist: isAllowlist
                                                 startDate: startDate
                                           durationSeconds: durationSeconds
                                             blockSettings: blockSettings
                                             authorization: authData
                                                     reply: reply];
}

- (void)cancelScheduledBlockWithAuthorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: cancelScheduledBlockWithAuthorization");

    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: _cmd];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    }

    [SCDaemonBlockMethods cancelScheduledBlockWithAuthorization: authData reply: reply];
}

- (void)updateBlocklist:(NSArray<NSString*>*)newBlocklist authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: updateBlocklist");
    
    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: _cmd];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    } else {
        NSLog(@"Authorization accepted for %s", sel_getName(_cmd));
    }
    
    [SCDaemonBlockMethods updateBlocklist: newBlocklist authorization: authData reply: reply];
}

- (void)updateBlockEndDate:(NSDate*)newEndDate authorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: updateBlockEndDate");
    
    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: _cmd];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    } else {
        NSLog(@"Authorization accepted for %s", sel_getName(_cmd));
    }
    
    [SCDaemonBlockMethods updateBlockEndDate: newEndDate authorization: authData reply: reply];
}

- (void)takeBreakWithAuthorization:(NSData *)authData reply:(void(^)(NSError* error))reply {
    NSLog(@"XPC method called: takeBreakWithAuthorization");

    NSError* error = [SCXPCAuthorization checkAuthorization: authData command: _cmd];
    if (error != nil) {
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            NSLog(@"ERROR: XPC authorization failed due to error %@", error);
            [SCSentry captureError: error];
        }
        reply(error);
        return;
    }

    [SCDaemonBlockMethods takeBreakWithAuthorization: authData reply: reply];
}

// Part of the HelperToolProtocol.  Returns the version number of the tool.  Note that never
// requires authorization.
- (void)getVersionWithReply:(void(^)(NSString * version))reply {
    NSLog(@"XPC method called: getVersionWithReply");
    // We specifically don't check for authorization here.  Everyone is always allowed to get
    // the version of the helper tool.
    reply(SELFCONTROL_VERSION_STRING);
}

- (void)setRecurringSchedules:(NSArray<NSDictionary*>*)schedules controllingUID:(uid_t)controllingUID blockSettings:(NSDictionary*)blockSettings authorization:(NSData*)authData reply:(void(^)(NSError* error))reply {
    NSError* error = [SCXPCAuthorization checkAuthorization:authData command:_cmd];
    if (error) { reply(error); return; }
    [SCDaemonBlockMethods setRecurringSchedules:schedules controllingUID:controllingUID blockSettings:blockSettings authorization:authData reply:reply];
}
@end
