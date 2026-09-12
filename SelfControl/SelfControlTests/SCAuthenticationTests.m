// Copyright 2026 Dayloft contributors. GPL-3.0-or-later.
#import <XCTest/XCTest.h>
#import "SCXPCAuthorization.h"
@interface SCXPCAuthorization (AuthenticationTests)
+ (NSDictionary*)commandInfo;
+ (BOOL)requiresAuthenticationRepair:(NSDictionary*)rule;
@end
@interface SCAuthenticationTests : XCTestCase
@end
@implementation SCAuthenticationTests
- (NSDictionary*)legacyRule {
    return @{@"identifier": @"org.dayloft.Dayloft", @"class": @"user", @"group": @"admin",
             @"version": @1, @"timeout": @120, @"shared": @YES, @"authenticate-user": @YES,
             @"allow-root": @NO, @"session-owner": @NO, @"mechanisms": @[@"builtin:authenticate"]};
}
- (void)testRulesUseSystemAuthenticationWithoutSkippingCredentialVerification {
    for (NSDictionary* command in SCXPCAuthorization.commandInfo.allValues) {
        NSDictionary* rule = command[@"authRightDefault"];
        XCTAssertEqualObjects(rule[@"class"], @"user");
        XCTAssertEqualObjects(rule[@"group"], @"admin");
        XCTAssertEqualObjects(rule[@"authenticate-user"], @YES);
        XCTAssertEqualObjects(rule[@"allow-root"], @NO);
        XCTAssertEqualObjects(rule[@"timeout"], @120);
        XCTAssertNil(rule[@"mechanisms"]);
        XCTAssertTrue([command[@"authRightDescription"] hasPrefix:@"Dayloft"]);
    }
}
- (void)testRepairIdentifiesInstalledBrokenRule {
    XCTAssertTrue([SCXPCAuthorization requiresAuthenticationRepair:self.legacyRule]);
    XCTAssertFalse([SCXPCAuthorization requiresAuthenticationRepair:nil]);
}
- (void)testRepairPreservesAdministratorCustomizedRules {
    for (NSDictionary* change in @[@{@"identifier": @"another.app"}, @{@"class": @"deny"}, @{@"group": @"wheel"}, @{@"timeout": @0}, @{@"version": @2}, @{@"mechanisms": @[@"builtin:authenticate", @"builtin:authenticate,privileged"]}, @{@"shared": @NO}, @{@"session-owner": @YES}]) {
        NSMutableDictionary* rule = [self.legacyRule mutableCopy]; [rule addEntriesFromDictionary:change];
        XCTAssertFalse([SCXPCAuthorization requiresAuthenticationRepair:rule]);
    }
}
@end
