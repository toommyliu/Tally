import Foundation

struct QuickAddFields: Equatable {
    var title: String
    var listName: String?
    var tags: [String]
    var dueDate: DateComponents?
    var priority: Int
    var usedTokens: [QuickAddToken]
}

struct QuickAddToken: Equatable {
    enum Kind: Equatable {
        case list
        case tag
        case date
        case time
        case priority
    }

    var kind: Kind
    var range: NSRange
}

enum QuickAddParser {
    static func parse(
        _ input: String,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> QuickAddFields {
        var titleTokens: [String] = []
        var listName: String?
        var tags: [String] = []
        var dueDate: DateComponents?
        var priority = 0
        var usedTokens: [QuickAddToken] = []
        let tokens = scanTokens(in: input)
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if token.text.hasPrefix("#"), token.text.count > 1 {
                listName = String(token.text.dropFirst())
                usedTokens.append(QuickAddToken(kind: .list, range: token.range))
                index += 1
                continue
            }

            if token.text.hasPrefix("@"), token.text.count > 1 {
                tags.append(String(token.text.dropFirst()))
                usedTokens.append(QuickAddToken(kind: .tag, range: token.range))
                index += 1
                continue
            }

            if let parsedPriority = parsePriority(token.text) {
                priority = parsedPriority
                usedTokens.append(QuickAddToken(kind: .priority, range: token.range))
                index += 1
                continue
            }

            if dueDate == nil,
               var parsedDueDate = parseDueDate(token.text, calendar: calendar, now: now) {
                usedTokens.append(QuickAddToken(kind: .date, range: token.range))

                if let nextToken = nextTimeToken(after: index, in: tokens),
                   let parsedTime = parseTime(nextToken.text) {
                    parsedDueDate.hour = parsedTime.hour
                    parsedDueDate.minute = parsedTime.minute
                    usedTokens.removeLast()
                    usedTokens.append(QuickAddToken(kind: .time, range: union(token.range, nextToken.range)))
                    index = nextToken.index + 1
                } else {
                    index += 1
                }

                dueDate = parsedDueDate
                continue
            }

            titleTokens.append(token.text)
            index += 1
        }

        return QuickAddFields(
            title: titleTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines),
            listName: listName,
            tags: tags,
            dueDate: dueDate,
            priority: priority,
            usedTokens: usedTokens
        )
    }

    private struct ScannedToken {
        var text: String
        var range: NSRange
    }

    private static func scanTokens(in input: String) -> [ScannedToken] {
        var tokens: [ScannedToken] = []
        var index = input.startIndex

        while index < input.endIndex {
            while index < input.endIndex, input[index].isWhitespace {
                index = input.index(after: index)
            }

            guard index < input.endIndex else {
                break
            }

            let start = index

            while index < input.endIndex, !input[index].isWhitespace {
                index = input.index(after: index)
            }

            let text = String(input[start..<index])
            let location = input.utf16.distance(from: input.utf16.startIndex, to: start.samePosition(in: input.utf16)!)
            let length = text.utf16.count
            tokens.append(ScannedToken(text: text, range: NSRange(location: location, length: length)))
        }

        return tokens
    }

    private static func parsePriority(_ token: String) -> Int? {
        switch token.lowercased() {
        case "p1":
            return 1
        case "p2":
            return 5
        case "p3":
            return 9
        case "p4":
            return 0
        default:
            return nil
        }
    }

    private static func parseDueDate(
        _ token: String,
        calendar: Calendar,
        now: Date
    ) -> DateComponents? {
        let normalized = token.lowercased()

        switch normalized {
        case "today":
            return dateOnlyComponents(from: now, calendar: calendar)
        case "tomorrow", "tmr":
            guard let date = calendar.date(byAdding: .day, value: 1, to: now) else {
                return nil
            }
            return dateOnlyComponents(from: date, calendar: calendar)
        default:
            return nil
        }
    }

    private static func nextTimeToken(
        after index: Int,
        in tokens: [ScannedToken]
    ) -> (index: Int, text: String, range: NSRange)? {
        let nextIndex = index + 1

        guard nextIndex < tokens.count else {
            return nil
        }

        if tokens[nextIndex].text.lowercased() == "at" {
            let timeIndex = nextIndex + 1

            guard timeIndex < tokens.count else {
                return nil
            }

            return (timeIndex, tokens[timeIndex].text, tokens[timeIndex].range)
        }

        return (nextIndex, tokens[nextIndex].text, tokens[nextIndex].range)
    }

    private static func union(_ lhs: NSRange, _ rhs: NSRange) -> NSRange {
        let start = min(lhs.location, rhs.location)
        let end = max(NSMaxRange(lhs), NSMaxRange(rhs))
        return NSRange(location: start, length: end - start)
    }

    private static func parseTime(_ token: String) -> (hour: Int, minute: Int)? {
        let normalized = token
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))

        guard let match = normalized.firstMatch(of: /^(\d{1,2})(?::(\d{2}))?(am|pm)?$/) else {
            return nil
        }

        guard var hour = Int(match.1) else {
            return nil
        }

        let minute = match.2.flatMap { Int($0) } ?? 0
        let meridiem = match.3.map(String.init)

        guard (0...59).contains(minute) else {
            return nil
        }

        if let meridiem {
            guard (1...12).contains(hour) else {
                return nil
            }

            if meridiem == "pm", hour < 12 {
                hour += 12
            } else if meridiem == "am", hour == 12 {
                hour = 0
            }
        } else {
            guard (0...23).contains(hour) else {
                return nil
            }
        }

        return (hour, minute)
    }

    private static func dateOnlyComponents(from date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.calendar, .timeZone, .year, .month, .day], from: date)
    }
}
