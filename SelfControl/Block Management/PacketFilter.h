//
//  PacketFilter.h
//  SelfControl
//
//  Created by Charles Stigler on 6/29/14.
//
//

#import <Foundation/Foundation.h>

@class SCBlockEntry;

@interface PacketFilter : NSObject {
	NSMutableString* rules;
	BOOL isAllowlist;
    NSFileHandle* appendFileHandle;
}

+ (BOOL)blockFoundInPF;

- (PacketFilter*)initAsAllowlist: (BOOL)allowlist;
- (void)addBlockHeader:(NSMutableString*)configText;
- (void)addAllowlistFooter:(NSMutableString*)configText;
- (void)addRuleWithIP:(NSString*)ip port:(NSInteger)port maskLen:(NSInteger)maskLen;
- (BOOL)writeConfiguration;
- (int)startBlock;
- (int)stopBlock:(BOOL)force;
- (BOOL)addSelfControlConfig;
- (BOOL)containsSelfControlBlock;
- (BOOL)enterAppendMode;
- (void)finishAppending;
- (int)refreshPFRules;

@end
