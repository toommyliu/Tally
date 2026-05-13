import EventKit
import Foundation

struct ReminderItem: Identifiable, Equatable {
    let id: String
    let title: String
    let notes: String?
    let listTitle: String
    let dueDate: DateComponents?
    let priority: Int
}

extension ReminderItem {
    init(reminder: EKReminder) {
        self.id = reminder.calendarItemIdentifier
        self.title = reminder.title
        self.notes = reminder.notes
        self.listTitle = reminder.calendar.title
        self.dueDate = reminder.dueDateComponents
        self.priority = reminder.priority
    }
}

