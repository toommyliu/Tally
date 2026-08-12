#import <EventKit/EventKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Writes fields that Reminders stores outside EventKit's public reminder model.
FOUNDATION_EXPORT BOOL TallyApplyReminderKitMetadata(
    EKReminder *reminder,
    NSURL * _Nullable url,
    NSInteger earlyReminderAmount,
    NSInteger earlyReminderUnit,
    NSError * _Nullable * _Nullable error
);

NS_ASSUME_NONNULL_END
