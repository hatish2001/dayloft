//
//  SCXPCAuthorization.m
//  SelfControl
//
//  Created by Charlie Stigler on 1/4/21.
//

#import "SCXPCAuthorization.h"

@implementation SCXPCAuthorization

// all of these methods (basically this whole file) copied from Apple's Even Better Authorization Sample code

static NSString * kCommandKeyAuthRightName    = @"authRightName";
static NSString * kCommandKeyAuthRightDefault = @"authRightDefault";
static NSString * kCommandKeyAuthRightDesc    = @"authRightDescription";

static NSDictionary* kAuthorizationRuleAuthenticateAsAdmin2MinTimeout;

// copied from Apple's Even Better Authorization Sample code
+ (NSError *)checkAuthorization:(NSData *)authData command:(SEL)command
    // Check that the client denoted by authData is allowed to run the specified command.
    // authData is expected to be an NSData with an AuthorizationExternalForm embedded inside.
{
    #pragma unused(authData)
    AuthorizationRef            authRef;

    assert(command != nil);
    
    authRef = NULL;

    // First check that authData looks reasonable.
    if ( (authData == nil) || ([authData length] != sizeof(AuthorizationExternalForm)) ) {
        return [NSError errorWithDomain:NSOSStatusErrorDomain code:paramErr userInfo:nil];
    }
    
    // Create an authorization ref from that the external form data contained within.
    OSStatus extFormStatus = AuthorizationCreateFromExternalForm([authData bytes], &authRef);
    if (extFormStatus != errAuthorizationSuccess) {
        return [NSError errorWithDomain: NSOSStatusErrorDomain code: extFormStatus userInfo: nil];
    }

    // Authorize the right associated with the command.

    AuthorizationItem   oneRight = { NULL, 0, NULL, 0 };
    AuthorizationRights rights   = { 1, &oneRight };
    AuthorizationFlags flags = kAuthorizationFlagDefaults | kAuthorizationFlagExtendRights | kAuthorizationFlagInteractionAllowed;

    oneRight.name = [[SCXPCAuthorization authorizationRightForCommand:command] UTF8String];
    assert(oneRight.name != NULL);
    
    OSStatus authStatus = AuthorizationCopyRights(
        authRef,
        &rights,
        kAuthorizationEmptyEnvironment,
        flags,
        NULL
    );
    if (authRef != NULL) {
        AuthorizationFree(authRef, 0);
    }

    if (authStatus != errAuthorizationSuccess) {
        return [NSError errorWithDomain: NSOSStatusErrorDomain code: authStatus userInfo: nil];
    }

    return nil;
}


+ (NSDictionary *)commandInfo
{
    static dispatch_once_t sOnceToken;
    static NSDictionary *  sCommandInfo;
    
    dispatch_once(&sOnceToken, ^{
        // Leave the authentication mechanisms to macOS. Supplying only its UI
        // mechanism skips privileged credential verification and loops forever.
        kAuthorizationRuleAuthenticateAsAdmin2MinTimeout = @{
            @"class": @"user", @"group": @"admin", @"authenticate-user": @YES,
            @"allow-root": @NO, @"shared": @YES, @"timeout": @120, @"version": @2
        };
        #pragma clang diagnostic ignored "-Wundeclared-selector"
        
        
        NSDictionary* startBlockCommandInfo = @{
            kCommandKeyAuthRightName    : @"org.dayloft.Dayloft.startBlock",
            kCommandKeyAuthRightDefault : kAuthorizationRuleAuthenticateAsAdmin2MinTimeout,
            kCommandKeyAuthRightDesc    : NSLocalizedString(
                @"Dayloft needs authorization to start a focus session.",
                @"prompt shown when user is required to authorize to start block"
            )
        };
        NSDictionary* modifyBlockCommandInfo = @{
            kCommandKeyAuthRightName    : @"org.dayloft.Dayloft.modifyBlock",
            kCommandKeyAuthRightDefault : kAuthorizationRuleAuthenticateAsAdmin2MinTimeout,
            kCommandKeyAuthRightDesc    : NSLocalizedString(
                @"Dayloft needs authorization to change your focus session.",
                @"prompt shown when user is required to authorize to modify their block"
            )
        };
        
        sCommandInfo = @{
            NSStringFromSelector(@selector(startBlockWithControllingUID:blocklist:isAllowlist:endDate:blockSettings:authorization:reply:)) : startBlockCommandInfo,
            NSStringFromSelector(@selector(scheduleBlockWithControllingUID:blocklist:isAllowlist:startDate:durationSeconds:blockSettings:authorization:reply:)) : startBlockCommandInfo,
            NSStringFromSelector(@selector(cancelScheduledBlockWithAuthorization:reply:)) : startBlockCommandInfo,
            NSStringFromSelector(@selector(setRecurringSchedules:controllingUID:blockSettings:authorization:reply:)) : startBlockCommandInfo,
            NSStringFromSelector(@selector(updateBlocklist:authorization:reply:)) : modifyBlockCommandInfo,
            NSStringFromSelector(@selector(updateBlockEndDate:authorization:reply:)) : modifyBlockCommandInfo,
            NSStringFromSelector(@selector(takeBreakWithAuthorization:reply:)) : modifyBlockCommandInfo
            #pragma clang diagnostic pop
        };
    });
    return sCommandInfo;
}

+ (void)enumerateRightsUsingBlock:(void (^)(NSString * authRightName, id authRightDefault, NSString * authRightDesc))block
    // Calls the supplied block with information about each known authorization right..
{
    [self.commandInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        #pragma unused(key)
        #pragma unused(stop)
        NSDictionary *  commandDict;
        NSString *      authRightName;
        id              authRightDefault;
        NSString *      authRightDesc;
        
        // If any of the following asserts fire it's likely that you've got a bug
        // in sCommandInfo.
        
        commandDict = (NSDictionary *) obj;
        assert([commandDict isKindOfClass:[NSDictionary class]]);

        authRightName = [commandDict objectForKey:kCommandKeyAuthRightName];
        assert([authRightName isKindOfClass:[NSString class]]);

        authRightDefault = [commandDict objectForKey:kCommandKeyAuthRightDefault];
        assert(authRightDefault != nil);

        authRightDesc = [commandDict objectForKey:kCommandKeyAuthRightDesc];
        assert([authRightDesc isKindOfClass:[NSString class]]);

        block(authRightName, authRightDefault, authRightDesc);
    }];
}

// Only migrate our exact broken v1 rule. Preserve administrator-customized rules.
+ (BOOL)requiresAuthenticationRepair:(NSDictionary*)rule {
    return [rule[@"identifier"] isEqual:@"org.dayloft.Dayloft"] &&
        [rule[@"class"] isEqual:@"user"] && [rule[@"group"] isEqual:@"admin"] &&
        [rule[@"version"] isEqual:@1] && [rule[@"timeout"] isEqual:@120] &&
        [rule[@"shared"] boolValue] && [rule[@"authenticate-user"] boolValue] &&
        ![rule[@"allow-root"] boolValue] && ![rule[@"session-owner"] boolValue] &&
        [rule[@"mechanisms"] isEqual:@[@"builtin:authenticate"]];
}

+ (void)setupAuthorizationRights:(AuthorizationRef)authRef {
    if (authRef == NULL) return;
    NSMutableSet* configured = [NSMutableSet new];
    [self enumerateRightsUsingBlock:^(NSString* name, id definition, NSString* description) {
        if ([configured containsObject:name]) return;
        [configured addObject:name];
        CFDictionaryRef existing = NULL;
        OSStatus status = AuthorizationRightGet(name.UTF8String, &existing);
        BOOL repair = status == errAuthorizationSuccess && [self requiresAuthenticationRepair:(__bridge NSDictionary*)existing];
        if (existing) CFRelease(existing);
        if (status == errAuthorizationDenied || repair) {
            status = AuthorizationRightSet(authRef, name.UTF8String, (__bridge CFTypeRef)definition,
                (__bridge CFStringRef)description, NULL, CFSTR("SCXPCAuthorization"));
            if (status != errAuthorizationSuccess) {
                NSLog(@"Unable to configure Dayloft authorization right %@ (status %d)", name, (int)status);
            }
        }
    }];
}

+ (NSString *)authorizationRightForCommand:(SEL)command
    // See comment in header.
{
    return [self commandInfo][NSStringFromSelector(command)][kCommandKeyAuthRightName];
}


@end
