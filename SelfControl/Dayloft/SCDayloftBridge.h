// Copyright 2026 Dayloft contributors. GPL-3.0-or-later. See LICENSE and NOTICE.md.
#import <Foundation/Foundation.h>
@class AppController;
NS_ASSUME_NONNULL_BEGIN
// A narrow native boundary. Firewall and authorization remain owned by SelfControl.
@interface SCDayloftBridge : NSObject
- (instancetype)initWithController:(AppController*)controller;
- (NSDictionary*)snapshot;
- (NSArray<NSString*>*)cleanDomains:(NSString*)text;
- (void)configureDomains:(NSArray<NSString*>*)domains allowlist:(BOOL)allowlist duration:(NSInteger)minutes mode:(NSString*)mode;
- (void)startBlock;
- (void)takeBreakWithCompletion:(void(^)(NSError* _Nullable error))completion;
- (void)extendSession:(NSInteger)minutes completion:(void(^)(NSError* _Nullable error))completion;
- (void)addBlockedWebsites:(NSString*)text completion:(void(^)(NSError* _Nullable error))completion;
- (void)showAdvancedSettings;
- (void)showActiveBlockTools;
- (void)manageLegacySchedule;
- (void)saveSchedules:(NSArray<NSDictionary*>*)schedules completion:(void(^)(NSError* _Nullable error))completion;
@end
NS_ASSUME_NONNULL_END
