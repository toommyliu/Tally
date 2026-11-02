#import <EventKit/EventKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TallyReminderKitDeltaUnit) {
    TallyReminderKitDeltaUnitMinute = 0,
    TallyReminderKitDeltaUnitHour = 1,
    TallyReminderKitDeltaUnitDay = 2,
    TallyReminderKitDeltaUnitWeek = 3,
    TallyReminderKitDeltaUnitMonth = 4,
};
FOUNDATION_EXPORT BOOL TallyApplyReminderKitMetadata(
    EKReminder *reminder,
    NSURL * _Nullable url,
    NSInteger earlyReminderAmount,
    TallyReminderKitDeltaUnit earlyReminderUnit,
    NSError * _Nullable * _Nullable error
);

NS_ASSUME_NONNULL_END
