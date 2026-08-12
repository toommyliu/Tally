#import "ReminderKitBridge.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const TallyReminderKitErrorDomain = @"Tally.ReminderKit";

typedef NS_ENUM(NSInteger, TallyReminderKitErrorCode) {
    TallyReminderKitErrorUnavailable = 1,
    TallyReminderKitErrorIncompatibleRuntime,
    TallyReminderKitErrorInvalidMetadata,
    TallyReminderKitErrorSaveFailed,
    TallyReminderKitErrorException
};

static BOOL TallyReminderKitFail(
    NSError * _Nullable * _Nullable error,
    TallyReminderKitErrorCode code,
    NSString *description
) {
    if (error != NULL) {
        *error = [NSError errorWithDomain:TallyReminderKitErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: description}];
    }
    return NO;
}

static BOOL TallyLoadReminderKit(void) {
    static BOOL loaded = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *reminderKit = dlopen(
            "/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit",
            RTLD_NOW | RTLD_LOCAL
        );
        void *reminderKitInternal = dlopen(
            "/System/Library/PrivateFrameworks/ReminderKitInternal.framework/ReminderKitInternal",
            RTLD_NOW | RTLD_LOCAL
        );
        loaded = reminderKit != NULL && reminderKitInternal != NULL;
    });
    return loaded;
}

/// Searches superclasses because ReminderKit moves private storage between releases.
static Ivar TallyFindIvar(Class objectClass, const char *name) {
    while (objectClass != Nil) {
        Ivar ivar = class_getInstanceVariable(objectClass, name);
        if (ivar != NULL) {
            return ivar;
        }
        objectClass = class_getSuperclass(objectClass);
    }
    return NULL;
}

static id _Nullable TallyReminderKitReminder(EKReminder *reminder) {
    SEL backingObjectSelector = NSSelectorFromString(@"backingObject");
    if (![reminder respondsToSelector:backingObjectSelector]) {
        return nil;
    }

    id backingObject = ((id (*)(id, SEL))objc_msgSend)(reminder, backingObjectSelector);
    Ivar reminderIvar = TallyFindIvar([backingObject class], "_remObject");
    if (reminderIvar == NULL) {
        return nil;
    }

    id reminderKitReminder = object_getIvar(backingObject, reminderIvar);
    Class reminderClass = objc_getClass("REMReminder");
    if (reminderClass == Nil || ![reminderKitReminder isKindOfClass:reminderClass]) {
        return nil;
    }
    return reminderKitReminder;
}

static id _Nullable TallyReminderKitStore(id reminderKitReminder) {
    Ivar storeIvar = TallyFindIvar([reminderKitReminder class], "_store");
    id store = storeIvar == NULL ? nil : object_getIvar(reminderKitReminder, storeIvar);

    if (store == nil) {
        SEL storeSelector = NSSelectorFromString(@"store");
        if ([reminderKitReminder respondsToSelector:storeSelector]) {
            store = ((id (*)(id, SEL))objc_msgSend)(reminderKitReminder, storeSelector);
        }
    }

    Class storeClass = objc_getClass("REMStore");
    if (storeClass == Nil || ![store isKindOfClass:storeClass]) {
        return nil;
    }
    return store;
}

static BOOL TallyApplyURL(
    NSURL *url,
    id changeItem,
    NSError * _Nullable * _Nullable error
) {
    SEL contextSelector = NSSelectorFromString(@"attachmentContext");
    if (![changeItem respondsToSelector:contextSelector]) {
        return TallyReminderKitFail(
            error,
            TallyReminderKitErrorIncompatibleRuntime,
            @"This macOS version does not expose the Reminders URL field."
        );
    }

    id context = ((id (*)(id, SEL))objc_msgSend)(changeItem, contextSelector);
    SEL setURLSelector = NSSelectorFromString(@"setURLAttachmentWithURL:");
    if (context == nil || ![context respondsToSelector:setURLSelector]) {
        return TallyReminderKitFail(
            error,
            TallyReminderKitErrorIncompatibleRuntime,
            @"This macOS version does not expose the Reminders URL field."
        );
    }

    ((id (*)(id, SEL, id))objc_msgSend)(context, setURLSelector, url);
    return YES;
}

static BOOL TallyApplyEarlyReminder(
    NSInteger amount,
    NSInteger unit,
    id changeItem,
    NSError * _Nullable * _Nullable error
) {
    if (amount <= 0 || unit < 0 || unit > 3) {
        return TallyReminderKitFail(
            error,
            TallyReminderKitErrorInvalidMetadata,
            @"The early reminder interval is invalid."
        );
    }

    Class intervalClass = objc_getClass("REMDueDateDeltaInterval");
    SEL intervalInitializer = NSSelectorFromString(@"initWithUnit:count:");
    id interval = [intervalClass alloc];
    if (intervalClass == Nil || ![interval respondsToSelector:intervalInitializer]) {
        return TallyReminderKitFail(
            error,
            TallyReminderKitErrorIncompatibleRuntime,
            @"This macOS version does not expose the Reminders Early Reminder field."
        );
    }

    // ReminderKit stores an alert before the due date as a negative delta.
    interval = ((id (*)(id, SEL, NSInteger, NSInteger))objc_msgSend)(
        interval,
        intervalInitializer,
        unit,
        -amount
    );

    SEL contextSelector = NSSelectorFromString(@"dueDateDeltaAlertContext");
    if (![changeItem respondsToSelector:contextSelector]) {
        return TallyReminderKitFail(
            error,
            TallyReminderKitErrorIncompatibleRuntime,
            @"This macOS version does not expose the Reminders Early Reminder field."
        );
    }

    id context = ((id (*)(id, SEL))objc_msgSend)(changeItem, contextSelector);
    SEL removeAllSelector = NSSelectorFromString(@"removeAllFetchedDueDateDeltaAlerts");
    SEL addSelector = NSSelectorFromString(@"addDueDateDeltaAlertWithDueDateDelta:");
    if (context == nil ||
        ![context respondsToSelector:removeAllSelector] ||
        ![context respondsToSelector:addSelector]) {
        return TallyReminderKitFail(
            error,
            TallyReminderKitErrorIncompatibleRuntime,
            @"This macOS version does not expose the Reminders Early Reminder field."
        );
    }

    ((void (*)(id, SEL))objc_msgSend)(context, removeAllSelector);
    id alert = ((id (*)(id, SEL, id))objc_msgSend)(context, addSelector, interval);
    if (alert == nil) {
        return TallyReminderKitFail(
            error,
            TallyReminderKitErrorSaveFailed,
            @"Reminders rejected the Early Reminder value."
        );
    }
    return YES;
}

BOOL TallyApplyReminderKitMetadata(
    EKReminder *reminder,
    NSURL * _Nullable url,
    NSInteger earlyReminderAmount,
    NSInteger earlyReminderUnit,
    NSError * _Nullable * _Nullable error
) {
    if (url == nil && earlyReminderAmount == 0) {
        return YES;
    }

    @try {
        if (!TallyLoadReminderKit()) {
            return TallyReminderKitFail(
                error,
                TallyReminderKitErrorUnavailable,
                @"Tally could not load the system Reminders framework."
            );
        }

        id reminderKitReminder = TallyReminderKitReminder(reminder);
        id store = reminderKitReminder == nil ? nil : TallyReminderKitStore(reminderKitReminder);
        if (reminderKitReminder == nil || store == nil) {
            return TallyReminderKitFail(
                error,
                TallyReminderKitErrorIncompatibleRuntime,
                @"Tally could not access the saved reminder's native fields."
            );
        }

        Class saveRequestClass = objc_getClass("REMSaveRequest");
        SEL initializer = NSSelectorFromString(@"initWithStore:");
        id saveRequest = [saveRequestClass alloc];
        if (saveRequestClass == Nil || ![saveRequest respondsToSelector:initializer]) {
            return TallyReminderKitFail(
                error,
                TallyReminderKitErrorIncompatibleRuntime,
                @"This macOS version cannot save native Reminders fields."
            );
        }
        saveRequest = ((id (*)(id, SEL, id))objc_msgSend)(saveRequest, initializer, store);

        SEL updateSelector = NSSelectorFromString(@"updateReminder:");
        if (saveRequest == nil || ![saveRequest respondsToSelector:updateSelector]) {
            return TallyReminderKitFail(
                error,
                TallyReminderKitErrorIncompatibleRuntime,
                @"This macOS version cannot update native Reminders fields."
            );
        }

        id changeItem = ((id (*)(id, SEL, id))objc_msgSend)(
            saveRequest,
            updateSelector,
            reminderKitReminder
        );
        if (changeItem == nil) {
            return TallyReminderKitFail(
                error,
                TallyReminderKitErrorIncompatibleRuntime,
                @"Tally could not prepare the reminder's native fields."
            );
        }

        if (url != nil && !TallyApplyURL(url, changeItem, error)) {
            return NO;
        }
        if (earlyReminderAmount > 0 &&
            !TallyApplyEarlyReminder(earlyReminderAmount, earlyReminderUnit, changeItem, error)) {
            return NO;
        }

        SEL saveSelector = NSSelectorFromString(@"saveSynchronouslyWithError:");
        if (![saveRequest respondsToSelector:saveSelector]) {
            return TallyReminderKitFail(
                error,
                TallyReminderKitErrorIncompatibleRuntime,
                @"This macOS version cannot save native Reminders fields."
            );
        }

        NSError *saveError = nil;
        BOOL saved = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(
            saveRequest,
            saveSelector,
            &saveError
        );
        if (!saved) {
            if (error != NULL) {
                *error = saveError ?: [NSError errorWithDomain:TallyReminderKitErrorDomain
                                                       code:TallyReminderKitErrorSaveFailed
                                                   userInfo:@{
                                                       NSLocalizedDescriptionKey:
                                                           @"Reminders could not save the URL or Early Reminder field."
                                                   }];
            }
            return NO;
        }
        return YES;
    } @catch (NSException *exception) {
        return TallyReminderKitFail(
            error,
            TallyReminderKitErrorException,
            [NSString stringWithFormat:@"Reminders rejected its native fields: %@", exception.reason]
        );
    }
}
