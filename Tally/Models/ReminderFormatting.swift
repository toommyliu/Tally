import SwiftUI

extension DateComponents {
    var shortDisplayTitle: String {
        guard let date = Calendar.current.date(from: self) else {
            return "Due"
        }

        let timeTitle = timeDisplayTitle

        if Calendar.current.isDateInToday(date) {
            return ["Today", timeTitle].compactMap(\.self).joined(separator: " ")
        }

        if Calendar.current.isDateInTomorrow(date) {
            return ["Tomorrow", timeTitle].compactMap(\.self).joined(separator: " ")
        }

        let dateTitle = date.formatted(.dateTime.month(.abbreviated).day())
        return [dateTitle, timeTitle].compactMap(\.self).joined(separator: " ")
    }

    private var timeDisplayTitle: String? {
        guard hour != nil || minute != nil else {
            return nil
        }

        guard let date = Calendar.current.date(from: self) else {
            return nil
        }

        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits))
    }
}

extension Int {
    var reminderPriorityTitle: String {
        switch self {
        case 1:
            return "High"
        case 5:
            return "Medium"
        case 9:
            return "Low"
        default:
            return "None"
        }
    }

    var priorityColor: Color {
        switch self {
        case 1:
            return .red
        case 5:
            return .orange
        case 9:
            return .blue
        default:
            return .secondary
        }
    }
}

extension ReminderItem {
    var menuTitle: String {
        formattedMenuTitle(maxLength: 30)
    }

    func formattedMenuTitle(maxLength: Int) -> String {
        let titleWithDueDate: String
        if let dueDate {
            titleWithDueDate = "\(title) - \(dueDate.shortDisplayTitle)"
        } else {
            titleWithDueDate = title
        }

        return titleWithDueDate.truncatedForMenu(maxLength: maxLength)
    }
}

extension String {
    func truncatedForMenu(maxLength: Int) -> String {
        guard maxLength > 3, count > maxLength else {
            return self
        }

        return String(prefix(maxLength - 3)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
