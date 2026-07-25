import Foundation

struct ReminderListInfo: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
}

struct ReminderCreationRequest: Equatable {
    let title: String
    let userNotes: String?
    let inlineNotes: String?
    let tags: [String]
    let listIdentifier: String?
    let listName: String?
    let dueDate: DateComponents?
    let priority: Int

    var requiresSpecificList: Bool {
        listIdentifier != nil || listName != nil
    }

    var combinedNotes: String? {
        var parts: [String] = []

        if let userNotes = Self.cleaned(userNotes) {
            parts.append(userNotes)
        }

        if let inlineNotes = Self.cleaned(inlineNotes), inlineNotes != parts.last {
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
