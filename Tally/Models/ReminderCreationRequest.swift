import Foundation

struct ReminderCreationRequest: Equatable {
    let title: String
    let userNotes: String?
    let inlineNotes: String?
    let tags: [String]
    let listIdentifier: String?
    let listName: String?
    let dueDate: DateComponents?
    let recurrence: ReminderRecurrence?
    let earlyReminder: ReminderEarlyReminder?
    let url: URL?
    let priority: Int

    var destination: CalendarDestinationQuery {
        CalendarDestinationQuery(identifier: listIdentifier, name: listName)
    }

    var combinedNotes: String? {
        CombinedNotes.text(userNotes: userNotes, inlineNotes: inlineNotes, tags: tags)
    }
}
