//
//  SCAppXPC.m
//  SelfControl
//
//  Created by Charlie Stigler on 7/4/20.
//

#import "SCXPCClient.h"
#import "SCDaemonProtocol.h"
#import <ServiceManagement/ServiceManagement.h>
#import <Security/Security.h>
#import "SCXPCAuthorization.h"
#import "SCErr.h"

@interface SCXPCClient () {
    AuthorizationRef    _authRef;
}

@property (atomic, strong, readwrite) NSXPCConnection* daemonConnection;
@property (atomic, copy, readwrite) NSData* authorization;
@property (atomic, assign) BOOL daemonInstallCheckInProgress;
@property (atomic, strong) NSMutableArray* daemonInstallCallbacks;

@end

static NSDictionary* SCSigningInfoForURL(NSURL* codeURL) {
    SecStaticCodeRef staticCode = NULL;
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef)codeURL, kSecCSDefaultFlags, &staticCode);
    if (status != errSecSuccess || staticCode == NULL) return nil;

    status = SecStaticCodeCheckValidity(staticCode, kSecCSStrictValidate | kSecCSCheckAllArchitectures, NULL);
    if (status != errSecSuccess) {
        CFRelease(staticCode);
        return nil;
    }

    CFDictionaryRef signingInfo = NULL;
    status = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &signingInfo);
    CFRelease(staticCode);
    if (status != errSecSuccess || signingInfo == NULL) return nil;
    return CFBridgingRelease(signingInfo);
}

static BOOL SCBundleCanInstallEmbeddedDaemon(void) {
    NSURL* appURL = NSBundle.mainBundle.bundleURL;
    NSURL* helperURL = [appURL URLByAppendingPathComponent:@"Contents/Library/LaunchServices/org.dayloft.focusd"];
    NSDictionary* appInfo = SCSigningInfoForURL(appURL);
    NSDictionary* helperInfo = SCSigningInfoForURL(helperURL);
    NSString* appTeam = appInfo[(__bridge NSString*)kSecCodeInfoTeamIdentifier];
    NSString* helperTeam = helperInfo[(__bridge NSString*)kSecCodeInfoTeamIdentifier];
    NSString* appIdentifier = appInfo[(__bridge NSString*)kSecCodeInfoIdentifier];
    NSString* helperIdentifier = helperInfo[(__bridge NSString*)kSecCodeInfoIdentifier];

    return appTeam.length > 0 &&
        [appTeam isEqualToString:helperTeam] &&
        [appIdentifier isEqualToString:@"org.dayloft.Dayloft"] &&
        [helperIdentifier isEqualToString:@"org.dayloft.focusd"];
}

@implementation SCXPCClient

- (void)setupAuthorization {
    // this is mostly copied from Apple's Even Better Authorization Sample

    // Create our connection to the authorization system.
    //
    // If we can't create an authorization reference then the app is not going to be able
    // to do anything requiring authorization.  Generally this only happens when you launch
    // the app in some wacky, and typically unsupported, way.
    
    // if we've already got an authorization session, no need to make another
    if (self.authorization) {
        return;
    }
    
    AuthorizationRef authRef;
    OSStatus errCode = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, 0, &authRef);
    if (errCode) {
        NSError* err = [NSError errorWithDomain: NSOSStatusErrorDomain code: errCode userInfo: nil];
        NSLog(@"Failed to set up initial authorization with error %@", err);
        [SCSentry captureError: err];
    } else {
        [self updateStoredAuthorization: authRef];
    }
}

- (void)updateStoredAuthorization:(AuthorizationRef)authRef {
    self->_authRef = authRef;
    if (!self->_authRef) {
        self.authorization = nil;
        return;
    }
    
    AuthorizationExternalForm extForm;
    OSStatus errCode = AuthorizationMakeExternalForm(self->_authRef, &extForm);
    if (errCode) {
        NSError* err = [NSError errorWithDomain: NSOSStatusErrorDomain code: errCode userInfo: nil];
        NSLog(@"Failed to update stored authorization with error %@", err);
        [SCSentry captureError: err];
    } else {
        self.authorization = [[NSData alloc] initWithBytes: &extForm length: sizeof(extForm)];
    }

    // If we successfully connected to Authorization Services, add definitions for our default
    // rights (unless they're already in the database).
    [SCXPCAuthorization setupAuthorizationRights: self->_authRef];
}

// Ensures that we're connected to our helper tool
// should only be called from the main thread
// Copied from Apple's EvenBetterAuthorizationSample
- (void)connectToHelperTool {
    assert([NSThread isMainThread]);
    NSLog(@"Connecting to helper tool, daemon connection is %@", self.daemonConnection);
    
    [self setupAuthorization];
    
    if (self.daemonConnection == nil) {
        self.daemonConnection = [[NSXPCConnection alloc] initWithMachServiceName: @"org.dayloft.focusd" options: NSXPCConnectionPrivileged];
        self.daemonConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SCDaemonProtocol)];
    [self.daemonConnection.remoteObjectInterface setClasses:[NSSet setWithObjects:NSArray.class, NSDictionary.class, NSString.class, NSNumber.class, NSDate.class, nil] forSelector:@selector(setRecurringSchedules:controllingUID:blockSettings:authorization:reply:) argumentIndex:0 ofReply:NO];
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-retain-cycles"
        // We can ignore the retain cycle warning because a) the retain taken by the
        // invalidation handler block is released by us setting it to nil when the block
        // actually runs, and b) the retain taken by the block passed to -addOperationWithBlock:
        // will be released when that operation completes and the operation itself is deallocated
        // (notably self does not have a reference to the NSBlockOperation).
        // note we need a local reference to the daemonConnection since there is a race condition where
        // we could reinstantiate a new connection before the handler fires, and we don't want to clear the new connection
        NSXPCConnection* connection = self.daemonConnection;
        connection.invalidationHandler = ^{
            // If the connection gets invalidated then, on the main thread, nil out our
            // reference to it.  This ensures that we attempt to rebuild it the next time around.
            connection.invalidationHandler = connection.interruptionHandler = nil;
                        
            if (connection == self.daemonConnection) {
                // dispatch_sync on main thread would deadlock, so be careful
                if ([NSThread isMainThread]) {
                    self.daemonConnection = nil;
                } else {
                    // running this synchronously ensures that the daemonConnection is nil'd out even if
                    // reinstantiate the connection immediately
                    NSLog(@"About to dispatch_sync");
                    dispatch_sync(dispatch_get_main_queue(), ^{
                        self.daemonConnection = nil;
                    });
                }
                NSLog(@"CONNECTION INVALIDATED");
            }
        };
        // our interruption handler is just our invalidation handler, except we retry afterward
        connection.interruptionHandler = ^{
            NSLog(@"Helper tool connection interrupted");
            if (connection.invalidationHandler != nil) {
                connection.invalidationHandler();
            }

            // interruptions may have happened because the daemon crashed
            // so wait a second and try to reconnect
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSLog(@"Retrying helper tool connection!");
                [self connectToHelperTool];
            });
        };

        #pragma clang diagnostic pop
        [self.daemonConnection resume];
                
        NSLog(@"Started helper connection!");
    }
}

- (BOOL)isConnected {
    return (self.daemonConnection != nil);
}

- (NSString*)installedDaemonVersion {
    NSURL* helperURL = [NSURL fileURLWithPath:@"/Library/PrivilegedHelperTools/org.dayloft.focusd"];
    SecStaticCodeRef staticCode = NULL;
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef)helperURL, kSecCSDefaultFlags, &staticCode);
    if (status != errSecSuccess || staticCode == NULL) return nil;

    CFDictionaryRef signingInfo = NULL;
    status = SecCodeCopySigningInformation(staticCode, kSecCSSigningInformation, &signingInfo);
    CFRelease(staticCode);
    if (status != errSecSuccess || signingInfo == NULL) return nil;

    NSDictionary* info = CFBridgingRelease(signingInfo);
    NSDictionary* plist = info[(__bridge NSString*)kSecCodeInfoPList];
    NSString* version = plist[@"CFBundleShortVersionString"];
    return [version isKindOfClass:NSString.class] ? version : nil;
}

- (void)installDaemon:(void(^)(NSError*))callback {
    // Do not remove a working helper on behalf of an ad-hoc or incomplete
    // development build. SMJobBless cannot install that replacement, so the
    // old remove-first sequence could leave launchd unregistered.
    if (!SCBundleCanInstallEmbeddedDaemon()) {
        NSLog(@"ERROR: Refusing helper installation because the app and embedded helper do not have matching trusted signatures.");
        callback([SCErr errorWithCode:502]);
        return;
    }

    // make sure authorization is set up (if we haven't connected yet)
    [self setupAuthorization];
    
    AuthorizationItem blessRight = {
        kSMRightBlessPrivilegedHelper, 0, NULL, 0
    };
    AuthorizationItem startBlockRight = {
        "org.dayloft.Dayloft.startBlock", 0, NULL, 0
    };
    AuthorizationItem rightsArr[] = { blessRight, startBlockRight };

    AuthorizationRights authRights;
    authRights.count = 2;
    authRights.items = rightsArr;

    AuthorizationFlags myFlags = kAuthorizationFlagDefaults |
    kAuthorizationFlagExtendRights |
    kAuthorizationFlagInteractionAllowed;
    OSStatus status;
    
    status = AuthorizationCopyRights(
                                           self->_authRef,
                                           &authRights,
                                           kAuthorizationEmptyEnvironment,
                                           myFlags,
                                           NULL
                                       );

    if(status) {
        // if it's just the user cancelling, make that obvious
        // to any listeners so they can ignore it appropriately
        if (status == AUTH_CANCELLED_STATUS) {
            callback([SCErr errorWithCode: 1]);
        } else {
            NSLog(@"ERROR: Failed to authorize installing selfcontrold with status %d.", status);

            NSError* err = [SCErr errorWithCode: 501];
            [SCSentry captureError: err];
            
            callback(err);
        }

        return;
    }
    
    CFErrorRef cfError = NULL;

    BOOL result = (BOOL)SMJobBless(
                                   kSMDomainSystemLaunchd,
                                   CFSTR("org.dayloft.focusd"),
                                   self->_authRef,
                                   &cfError);

    NSError* firstBlessError = CFBridgingRelease(cfError);
    cfError = NULL;

    // A stale registered job can make the first bless fail with launchd error
    // 2. Only that known state justifies removing the old registration. Retry
    // immediately so unrelated signing failures cannot destroy a good helper.
    if (!result && [firstBlessError.domain isEqualToString:@"CFErrorDomainLaunchd"] && firstBlessError.code == 2) {
        NSLog(@"WARNING: Retrying helper installation after stale launchd registration: %@", firstBlessError);
        CFErrorRef removeError = NULL;
        SILENCE_OSX10_10_DEPRECATION(
        SMJobRemove(kSMDomainSystemLaunchd, CFSTR("org.dayloft.focusd"), self->_authRef, YES, &removeError);
                                     );
        if (removeError != NULL) {
            NSError* error = CFBridgingRelease(removeError);
            NSLog(@"WARNING: Failed to remove stale Dayloft helper registration: %@", error);
        }
        result = (BOOL)SMJobBless(
                                   kSMDomainSystemLaunchd,
                                   CFSTR("org.dayloft.focusd"),
                                   self->_authRef,
                                   &cfError);
    }

    if(!result) {
        NSError* error = cfError != NULL ? CFBridgingRelease(cfError) : firstBlessError;
        
        NSLog(@"WARNING: Authorized installation of Dayloft helper returned failure status code %d and error %@", (int)status, error);

        NSError* err = [SCErr errorWithCode: 500 subDescription: error.localizedDescription];
        if (![SCMiscUtilities errorIsAuthCanceled: error]) {
            [SCSentry captureError: err];
        }

        callback(err);
        return;
    } else {
        NSLog(@"Daemon installed successfully!");
        callback(nil);
    }
}

- (void)finishDaemonInstallCheck:(NSError*)error {
    NSArray* callbacks;
    @synchronized (self) {
        callbacks = [self.daemonInstallCallbacks copy];
        [self.daemonInstallCallbacks removeAllObjects];
        self.daemonInstallCheckInProgress = NO;
    }
    void (^invokeCallbacks)(void) = ^{
        for (void (^callback)(NSError*) in callbacks) callback(error);
    };
    if ([NSThread isMainThread]) {
        invokeCallbacks();
    } else {
        dispatch_async(dispatch_get_main_queue(), invokeCallbacks);
    }
}

- (void)ensureDaemonInstalled:(void(^)(NSError*))callback {
    @synchronized (self) {
        if (self.daemonInstallCheckInProgress) {
            [self.daemonInstallCallbacks addObject:[callback copy]];
            return;
        }
        self.daemonInstallCheckInProgress = YES;
        self.daemonInstallCallbacks = [NSMutableArray arrayWithObject:[callback copy]];
    }

    [self getVersion:^(NSString *daemonVersion, NSError *versionError) {
        BOOL upToDate = versionError == nil && daemonVersion.length > 0 &&
            [SELFCONTROL_VERSION_STRING compare:daemonVersion options:NSNumericSearch] != NSOrderedDescending;
        if (upToDate) {
            [self finishDaemonInstallCheck:nil];
            return;
        }

        if (versionError == nil) {
            NSLog(@"Daemon version of %@ is out of date (current version is %@).", daemonVersion, SELFCONTROL_VERSION_STRING);
        } else {
            NSLog(@"Helper is unavailable; installing it once before the requested action: %@", versionError);
        }
        [self installDaemon:^(NSError *installError) {
            [self finishDaemonInstallCheck:installError];
        }];
    }];
}

- (BOOL)connectionIsActive {
    return (self.daemonConnection != nil);
}

- (void)refreshConnectionAndRun:(void(^)(void))callback {
    // when we're refreshing the connection, we can end up in a slightly awkward situation:
    // if we call invalidate, but immediately start to reconnect before daemonConnection can be nil'd out
    // then we risk trying to use the invalidated connection
    // the fix? nil out daemonConnection before invalidating it in the refresh case
    
    if (self.daemonConnection == nil) {
        callback();
        return;
    }
    void (^standardInvalidationHandler)(void) = self.daemonConnection.invalidationHandler;
    
    // wait until the invalidation handler runs, then run our callback
    __weak typeof(self) weakSelf = self;
    self.daemonConnection.invalidationHandler = ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (standardInvalidationHandler != nil) {
            standardInvalidationHandler();
        }
        strongSelf.daemonConnection = nil;
        callback();
    };
    
    [self.daemonConnection performSelectorOnMainThread: @selector(invalidate) withObject: nil waitUntilDone: YES];
}

// Also copied from Apple's EvenBetterAuthorizationSample
// Connects to the helper tool and then executes the supplied command block on the
// main thread, passing it an error indicating if the connection was successful.
- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock {
    // Ensure that there's a helper tool connection in place.
    
    [self performSelectorOnMainThread: @selector(connectToHelperTool) withObject:nil waitUntilDone: YES];

    // Run the command block.  Note that we never error in this case because, if there is
    // an error connecting to the helper tool, it will be delivered to the error handler
    // passed to -remoteObjectProxyWithErrorHandler:.  However, I maintain the possibility
    // of an error here to allow for future expansion.

    commandBlock(nil);
}

- (void)getVersion:(void(^)(NSString* version, NSError* error))reply {
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            NSLog(@"Failed to get daemon version with connection error: %@", connectError);
            [SCSentry captureError: connectError];
            reply(nil, connectError);
        } else {
            [[self.daemonConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                NSLog(@"Failed to get daemon version with remote object proxy error: %@", proxyError);
                [SCSentry captureError: proxyError];
                reply(nil, proxyError);
            }] getVersionWithReply:^(NSString * _Nonnull version) {
                reply(version, nil);
            }];
        }
    }];
}

- (void)startBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist endDate:(NSDate*)endDate blockSettings:(NSDictionary*)blockSettings reply:(void(^)(NSError* error))reply {
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            [SCSentry captureError: connectError];
            NSLog(@"Start block command failed with connection error: %@", connectError);
            reply(connectError);
        } else {
            [[self.daemonConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                NSLog(@"Start block command failed with remote object proxy error: %@", proxyError);
                [SCSentry captureError: proxyError];
                reply(proxyError);
            }] startBlockWithControllingUID: controllingUID blocklist: blocklist isAllowlist:isAllowlist endDate:endDate blockSettings: blockSettings authorization: self.authorization reply:^(NSError* error) {
                if (error != nil && ![SCMiscUtilities errorIsAuthCanceled: error]) {
                    NSLog(@"Start block failed with error = %@\n", error);
                    [SCSentry captureError: error];
                }
                reply(error);
            }];
        }
    }];
}

- (void)scheduleBlockWithControllingUID:(uid_t)controllingUID blocklist:(NSArray<NSString*>*)blocklist isAllowlist:(BOOL)isAllowlist startDate:(NSDate*)startDate durationSeconds:(NSTimeInterval)durationSeconds blockSettings:(NSDictionary*)blockSettings reply:(void(^)(NSError* error))reply {
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            [SCSentry captureError: connectError];
            NSLog(@"Schedule block command failed with connection error: %@", connectError);
            reply(connectError);
        } else {
            [[self.daemonConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                NSLog(@"Schedule block failed with remote object proxy error: %@", proxyError);
                [SCSentry captureError: proxyError];
                reply(proxyError);
            }] scheduleBlockWithControllingUID: controllingUID
                                     blocklist: blocklist
                                   isAllowlist: isAllowlist
                                     startDate: startDate
                               durationSeconds: durationSeconds
                                 blockSettings: blockSettings
                                 authorization: self.authorization
                                         reply: reply];
        }
    }];
}

- (void)cancelScheduledBlockWithReply:(void(^)(NSError* error))reply {
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            [SCSentry captureError: connectError];
            NSLog(@"Cancel schedule command failed with connection error: %@", connectError);
            reply(connectError);
        } else {
            [[self.daemonConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                NSLog(@"Cancel schedule failed with remote object proxy error: %@", proxyError);
                [SCSentry captureError: proxyError];
                reply(proxyError);
            }] cancelScheduledBlockWithAuthorization: self.authorization reply: reply];
        }
    }];
}

- (void)updateBlocklist:(NSArray<NSString*>*)newBlocklist reply:(void(^)(NSError* error))reply {
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            NSLog(@"Blocklist update failed with connection error: %@", connectError);
            [SCSentry captureError: connectError];
            reply(connectError);
        } else {
            [[self.daemonConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                NSLog(@"Blocklist update command failed with remote object proxy error: %@", proxyError);
                [SCSentry captureError: proxyError];
                reply(proxyError);
            }] updateBlocklist: newBlocklist authorization: self.authorization reply:^(NSError* error) {
                if (error != nil && ![SCMiscUtilities errorIsAuthCanceled: error]) {
                    NSLog(@"Blocklist update failed with error = %@\n", error);
                    [SCSentry captureError: error];
                }
                reply(error);
            }];
        }
    }];
}

- (void)updateBlockEndDate:(NSDate*)newEndDate reply:(void(^)(NSError* error))reply {
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            NSLog(@"Block end date update failed with connection error: %@", connectError);
            [SCSentry captureError: connectError];
            reply(connectError);
        } else {
            [[self.daemonConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                NSLog(@"Block end date update command failed with remote object proxy error: %@", proxyError);
                [SCSentry captureError: proxyError];
                reply(proxyError);
            }] updateBlockEndDate: newEndDate authorization: self.authorization reply:^(NSError* error) {
                if (error != nil && ![SCMiscUtilities errorIsAuthCanceled: error]) {
                    NSLog(@"Block end date update failed with error = %@\n", error);
                    [SCSentry captureError: error];
                }
                reply(error);
            }];
        }
    }];
}

- (void)takeBreakWithReply:(void(^)(NSError* error))reply {
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            NSLog(@"Break request failed with connection error: %@", connectError);
            [SCSentry captureError: connectError];
            reply(connectError);
        } else {
            [[self.daemonConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                NSLog(@"Break request failed with remote object proxy error: %@", proxyError);
                [SCSentry captureError: proxyError];
                reply(proxyError);
            }] takeBreakWithAuthorization: self.authorization reply:^(NSError* error) {
                if (error != nil && ![SCMiscUtilities errorIsAuthCanceled: error]) {
                    NSLog(@"Break request failed with error = %@", error);
                    [SCSentry captureError: error];
                }
                reply(error);
            }];
        }
    }];
}

- (NSString*)selfControlHelperToolPath {
    static NSString* path;

    // Cache the path so it doesn't have to be searched for again.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle* thisBundle = [NSBundle mainBundle];
        path = [thisBundle.bundlePath stringByAppendingString: @"/Contents/Library/LaunchServices/org.dayloft.focusd"];
    });

    return path;
}

- (char*)selfControlHelperToolPathUTF8String {
    static char* path;

    // Cache the converted path so it doesn't have to be converted again
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        path = malloc(512);
        [[self selfControlHelperToolPath] getCString: path
                                           maxLength: 512
                                            encoding: NSUTF8StringEncoding];
    });

    return path;
}

- (void)setRecurringSchedules:(NSArray<NSDictionary*>*)schedules controllingUID:(uid_t)controllingUID blockSettings:(NSDictionary*)blockSettings reply:(void(^)(NSError* error))reply {
    [self connectAndExecuteCommandBlock:^(NSError* error) {
        if (error) { reply(error); return; }
        [[self.daemonConnection remoteObjectProxyWithErrorHandler:reply]
            setRecurringSchedules:schedules controllingUID:controllingUID blockSettings:blockSettings authorization:self.authorization reply:reply];
    }];
}
@end
