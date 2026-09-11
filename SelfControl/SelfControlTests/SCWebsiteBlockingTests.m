// Copyright 2026 Dayloft contributors. SPDX-License-Identifier: GPL-3.0-or-later
#import <XCTest/XCTest.h>
#import "BlockManager.h"
#import "SCBlockEntry.h"
#import "HostFileBlockerSet.h"

@interface PacketFilter (TestingRules)
- (NSArray<NSString*>*)ruleStringsForIP:(NSString*)ip port:(NSInteger)port maskLen:(NSInteger)maskLen;
@end

// No test in this file invokes pfctl, changes /etc/hosts, or resolves real sites.
@interface MemoryFirewall : PacketFilter
@property NSMutableSet<NSString*>* addresses;
@property int installationStatus;
@end
@implementation MemoryFirewall
- (instancetype)init { if ((self = [super initAsAllowlist:NO])) _addresses = [NSMutableSet new]; return self; }
- (void)addRuleWithIP:(NSString*)ip port:(NSInteger)port maskLen:(NSInteger)maskLen { @synchronized(self) { [self.addresses addObject:ip ?: @"*"]; } }
- (int)startBlock { return self.installationStatus; }
- (void)finishAppending {}
- (int)refreshPFRules { return self.installationStatus; }
@end

@interface MemoryHosts : HostFileBlockerSet
@property NSMutableSet<NSString*>* hosts;
@property BOOL writeSucceeds;
@end
@implementation MemoryHosts
- (instancetype)init { if ((self = [super init])) { _hosts = [NSMutableSet new]; _writeSucceeds = YES; } return self; }
- (void)addRuleBlockingDomain:(NSString*)domain { @synchronized(self) { [self.hosts addObject:domain]; } }
- (void)addSelfControlBlockFooter {}
- (BOOL)writeNewFileContents { return self.writeSucceeds; }
@end

@interface MemoryBlockManager : BlockManager
@property MemoryFirewall* firewall;
@property MemoryHosts* hosts;
- (void)markAppending;
@end
@implementation MemoryBlockManager
- (instancetype)init {
    if ((self = [super initAsAllowlist:NO allowLocal:YES includeCommonSubdomains:NO includeLinkedDomains:NO])) {
        self.firewall = [MemoryFirewall new]; pf = self.firewall;
        self.hosts = [MemoryHosts new]; hostBlockerSet = self.hosts;
        hostsBlockingEnabled = YES;
    }
    return self;
}
- (void)markAppending { appendMode = YES; }
+ (NSArray*)ipAddressesForDomainName:(NSString*)domain { return @[@"192.0.2.10", @"2001:db8::10"]; }
@end

@interface FailingConfigurationFirewall : PacketFilter
@end
@implementation FailingConfigurationFirewall
- (BOOL)writeConfiguration { return NO; }
@end

@interface SCWebsiteBlockingTests : XCTestCase
@end
@implementation SCWebsiteBlockingTests
- (void)testFailedConfigurationWriteNeverStartsFirewall {
    XCTAssertNotEqual([[FailingConfigurationFirewall new] startBlock], 0);
}
- (void)testAppendStateBelongsToEachManager {
    MemoryBlockManager* first = [MemoryBlockManager new];
    MemoryBlockManager* second = [MemoryBlockManager new];
    [first markAppending];
    XCTAssertFalse([second finishAppending]);
    XCTAssertTrue([first finishAppending]);
    XCTAssertFalse([first finishAppending]);
}
- (void)testAppendFailureReachesCaller {
    MemoryBlockManager* manager = [MemoryBlockManager new];
    [manager markAppending]; manager.firewall.installationStatus = 1;
    XCTAssertFalse([manager finishAppending]);
    [manager markAppending]; manager.firewall.installationStatus = 0; manager.hosts.writeSucceeds = NO;
    XCTAssertFalse([manager finishAppending]);
}
- (void)testPastedInstagramURLProtectsParentAndEndpoints {
    MemoryBlockManager* manager = [MemoryBlockManager new];
    [manager addBlockEntryFromString:@"https://www.instagram.com/reels/example/?next=home"];
    XCTAssertTrue([manager finalizeBlock]);
    for (NSString* name in @[@"instagram.com", @"www.instagram.com", @"i.instagram.com", @"b.i.instagram.com", @"api.instagram.com", @"graph.instagram.com", @"m.instagram.com"]) {
        XCTAssertTrue([manager.hosts.hosts containsObject:name], @"Missing %@", name);
    }
    XCTAssertFalse([manager.hosts.hosts containsObject:@"api.www.instagram.com"]);
    XCTAssertEqualObjects(manager.firewall.addresses, ([NSSet setWithArray:@[@"192.0.2.10", @"2001:db8::10"]]));
}
- (void)testInstagramSubdomainProtectsParent {
    BlockManager* manager = [[BlockManager alloc] initAsAllowlist:NO];
    for (NSString* input in @[@"instagram.com", @"I.Instagram.com.", @"graph.instagram.com"]) {
        NSArray* hosts = [manager commonSubdomainsForHostName:input];
        XCTAssertTrue([hosts containsObject:@"instagram.com"]);
        XCTAssertTrue([hosts containsObject:@"www.instagram.com"]);
    }
}
- (void)testDomainFamilyMatchingRequiresLabelBoundary {
    BlockManager* manager = [[BlockManager alloc] initAsAllowlist:NO];
    XCTAssertFalse([[manager commonSubdomainsForHostName:@"notinstagram.com"] containsObject:@"instagram.com"]);
    XCTAssertFalse([[manager commonSubdomainsForHostName:@"instagram.com.example.org"] containsObject:@"instagram.com"]);
    XCTAssertFalse([[manager commonSubdomainsForHostName:@"notyoutube.com"] containsObject:@"youtu.be"]);
}
- (void)testWWWExpansionKeepsMultiLabelParent {
    NSArray* hosts = [[BlockManager new] commonSubdomainsForHostName:@"www.example.co.uk"];
    XCTAssertTrue([hosts containsObject:@"example.co.uk"]);
    XCTAssertTrue([hosts containsObject:@"api.example.co.uk"]);
    XCTAssertFalse([hosts containsObject:@"co.uk"]);
}
- (void)testYouTubeStillIncludesParentAndAliases {
    NSArray* hosts = [[BlockManager new] commonSubdomainsForHostName:@"www.youtube.com"];
    for (NSString* name in @[@"youtube.com", @"www.youtube.com", @"youtu.be", @"m.youtube.com", @"music.youtube.com"]) XCTAssertTrue([hosts containsObject:name]);
}
- (void)testAllowlistDoesNotGrantInstagramParentFromAPI {
    BlockManager* manager = [[BlockManager alloc] initAsAllowlist:YES];
    XCTAssertFalse([[manager commonSubdomainsForHostName:@"i.instagram.com"] containsObject:@"instagram.com"]);
}
- (void)testIPv6LiteralReachesFirewall {
    MemoryBlockManager* manager = [MemoryBlockManager new];
    [manager addBlockEntry:[SCBlockEntry entryWithHostname:@"2001:db8::123"]];
    XCTAssertTrue([manager.firewall.addresses containsObject:@"2001:db8::123"]);
}
- (void)testFirewallRulesCoverTCPAndUDPForBothAddressFamilies {
    PacketFilter* pf = [[PacketFilter alloc] initAsAllowlist:NO];
    for (NSString* ip in @[@"192.0.2.10", @"2001:db8::10"]) {
        NSArray* rules = [pf ruleStringsForIP:ip port:0 maskLen:0];
        XCTAssertEqualObjects(rules, (@[[NSString stringWithFormat:@"block return out proto tcp from any to %@\n", ip], [NSString stringWithFormat:@"block return out proto udp from any to %@\n", ip]]));
    }
}
- (void)testFailedFirewallInstallIsNotSuccess {
    MemoryBlockManager* manager = [MemoryBlockManager new]; manager.firewall.installationStatus = 1;
    XCTAssertFalse([manager finalizeBlock]);
}
- (void)testFailedHostsWriteIsNotSuccess {
    MemoryBlockManager* manager = [MemoryBlockManager new]; manager.hosts.writeSucceeds = NO;
    XCTAssertFalse([manager finalizeBlock]);
}
@end
