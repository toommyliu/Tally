import EventKit
import Foundation

/// Applies native Reminders fields that aren't represented by public EventKit properties.
enum ReminderKitMetadataWriter {
    static func apply(_ request: ReminderCreationRequest, to reminder: EKReminder) throws {
        guard request.url != nil || request.earlyReminder != nil else {
            return
        }

        var error: NSError?
        let earlyReminderAmount = request.earlyReminder?.amount ?? 0
        let earlyReminderUnit = request.earlyReminder.map { nativeUnit(for: $0.unit) } ?? 0
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

    private static func nativeUnit(for unit: ReminderEarlyReminder.Unit) -> Int {
        switch unit {
        case .minutes:
            return 0
        case .hours:
            return 1
        case .days:
            return 2
        case .weeks:
            return 3
        }
    }
}
