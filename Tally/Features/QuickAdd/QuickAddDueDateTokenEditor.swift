import Foundation

struct QuickAddDueDateSelection: Equatable {
    var date: Date
    var includesTime: Bool
}

enum QuickAddDueDateTokenEditor {
    static func applying(
        _ selection: QuickAddDueDateSelection?,
        to input: String,
        calendar: Calendar = .current,
        now: Date = Date(),
        suppressedInferredTokens: [QuickAddSuppressedToken] = []
    ) -> String {
        let fields = QuickAddParser.parse(
            input,
            calendar: calendar,
            now: now,
            suppressedInferredTokens: suppressedInferredTokens
        )
        let existingToken = fields.usedTokens.first { token in
            token.kind == .date || token.kind == .time
        }

        guard let selection else {
            guard let existingToken,
                  let range = Range(existingToken.range, in: input) else {
                return normalized(input)
            }

            var updated = input
            updated.removeSubrange(range)
            return normalized(updated)
        }

        let replacement = token(for: selection, calendar: calendar)

        guard let existingToken,
              let range = Range(existingToken.range, in: input) else {
            let separator = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " "
            return normalized(input + separator + replacement)
        }

        var updated = input
        updated.replaceSubrange(range, with: replacement)
        return normalized(updated)
    }

    static func token(
        for selection: QuickAddDueDateSelection,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: selection.date)
        let dateToken = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )

        guard selection.includesTime else {
            return dateToken
        }

        return "\(dateToken) \(timeToken(hour: components.hour ?? 0, minute: components.minute ?? 0))"
    }

    private static func timeToken(hour: Int, minute: Int) -> String {
        let suffix = hour >= 12 ? "pm" : "am"
        let displayHour = {
            let value = hour % 12
            return value == 0 ? 12 : value
        }()

        return String(format: "%d:%02d%@", displayHour, minute, suffix)
    }

    private static func normalized(_ input: String) -> String {
        input
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
