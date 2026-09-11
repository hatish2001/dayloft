// Compatibility hooks for the inherited engine. Dayloft sends no telemetry.
// GPL-3.0-or-later; see COPYING and the original SelfControl copyright notices.
#import "SCSentry.h"
@implementation SCSentry
+ (void)startSentry:(NSString*)componentId {}
+ (void)addBreadcrumb:(NSString*)message category:(NSString*)category {}
+ (void)captureError:(NSError*)error {}
+ (void)captureMessage:(NSString*)message withScopeBlock:(void (^)(SentryScope*))block {}
+ (void)captureMessage:(NSString*)message {}
+ (BOOL)showErrorReportingPromptIfNeeded { return NO; }
@end
