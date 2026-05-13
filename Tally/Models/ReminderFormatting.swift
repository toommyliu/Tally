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
    var quickAddTitle: String {
        switch self {
        case 1:
            return "P1"
        case 5:
            return "P2"
        case 9:
            return "P3"
        default:
            return "P4"
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
