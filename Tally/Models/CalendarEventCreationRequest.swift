import Foundation

/// When an event happens. All-day events use date-only components and an
/// inclusive last day; timed events carry hours and minutes.
struct CalendarEventTiming: Equatable {
    static let defaultDurationMinutes = 60

    let start: DateComponents
    let end: DateComponents
    let isAllDay: Bool

    var durationMinutes: Int? {
        let calendar = Calendar.current
        guard let startDate = calendar.date(from: start),
              let endDate = calendar.date(from: end) else {
            return nil
        }

        return Int(endDate.timeIntervalSince(startDate) / 60)
    }
}

struct CalendarEventCreationRequest: Equatable {
    let title: String
    let userNotes: String?
    let inlineNotes: String?
    let tags: [String]
    let calendarIdentifier: String?
    let calendarName: String?
    let timing: CalendarEventTiming
    let recurrence: ReminderRecurrence?
    let alert: ReminderEarlyReminder?
    let url: URL?

    var destination: CalendarDestinationQuery {
        CalendarDestinationQuery(identifier: calendarIdentifier, name: calendarName)
    }

    var combinedNotes: String? {
        CombinedNotes.text(userNotes: userNotes, inlineNotes: inlineNotes, tags: tags)
    }
}

/// Joins typed notes, `//` inline notes, and tags into one notes field, since
/// neither EventKit reminders nor events expose tags publicly.
enum CombinedNotes {
    static func text(userNotes: String?, inlineNotes: String?, tags: [String]) -> String? {
        var parts: [String] = []

        if let userNotes = cleaned(userNotes) {
            parts.append(userNotes)
        }

        if let inlineNotes = cleaned(inlineNotes), inlineNotes != parts.last {
            parts.append(inlineNotes)
        }

        if !tags.isEmpty {
            parts.append("Tags: " + tags.map { "@\($0)" }.joined(separator: " "))
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static func cleaned(_ value: String?) -> String? {
        let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }
}
