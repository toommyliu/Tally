import EventKit
import Foundation

/// Applies native Reminders fields that aren't represented by public EventKit properties.
enum ReminderKitMetadataWriter {
    static func apply(_ request: ReminderCreationRequest, to reminder: EKReminder) throws {
        guard request.url != nil || request.earlyReminder != nil else {
            return
        }

        var error: NSError?
        let earlyReminderAmount = request.earlyReminder?.amount.value ?? 0
        let earlyReminderUnit = request.earlyReminder.map { nativeUnit(for: $0.unit) } ?? .minute
        let succeeded = TallyApplyReminderKitMetadata(
            reminder,
            request.url,
            earlyReminderAmount,
            earlyReminderUnit,
            &error
        )

        guard succeeded else {
            throw error ?? NSError(
                domain: "Tally.ReminderKit",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Reminders could not save its native fields."]
            )
        }
    }

    private static func nativeUnit(for unit: ScheduleUnit) -> TallyReminderKitDeltaUnit {
        switch unit {
        case .minutes:
            return .minute
        case .hours:
            return .hour
        case .days:
            return .day
        case .weeks:
            return .week
        case .months:
            return .month
        }
    }
}
