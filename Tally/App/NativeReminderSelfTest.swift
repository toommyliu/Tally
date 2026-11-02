#if DEBUG
import EventKit
import Foundation

@MainActor
enum NativeReminderSelfTest {
    private struct Delta: Codable, Equatable {
        let unit: Int
        let count: Int
    }

    private struct Expected: Codable {
        let hasHour: Bool
        let deltaAlerts: [Delta]
    }

    private struct Case {
        let name: String
        let input: String
        let expected: Expected
    }

    private struct NativeMetadata: Decodable {
        let deltaAlerts: [Delta]
        let selectors: [String: [String]]
    }

    private struct Alarm: Codable {
        let absoluteDate: Date?
        let relativeOffset: TimeInterval
        let hasLocation: Bool
    }

    private struct Actual: Codable {
        let dueDateComponents: [String: Int]
        let alarms: [Alarm]
        let deltaAlerts: [Delta]
    }

    private struct Result: Codable {
        let name: String
        let input: String
        let expected: Expected
        var actual: Actual?
        var error: String?
        var pass = false

        private enum CodingKeys: String, CodingKey {
            case name, input, expected, actual, error, pass
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
            try container.encode(expected, forKey: .expected)
            try container.encode(actual, forKey: .actual)
            try container.encodeIfPresent(error, forKey: .error)
            try container.encode(pass, forKey: .pass)
        }
    }

    private struct Report: Codable {
        let authorizationStatus: Int
        var listName: String?
        var reminderCalendarCountBefore: Int?
        var selfTestListsBefore: [String]?
        var selfTestListsAfter: [String]?
        var temporaryListDeleted = false
        var selectors: [String: [String]] = [:]
        var cases: [Result] = []
        var errors: [String] = []
        var pass = false
    }

    private static let cases = [
        Case(name: "TimedMinutes", input: "tomorrow 3pm !30m",
             expected: Expected(hasHour: true, deltaAlerts: [Delta(unit: 0, count: -30)])),
        Case(name: "DateOnlyDays", input: "friday !1d",
             expected: Expected(hasHour: false, deltaAlerts: [Delta(unit: 2, count: -1)])),
        Case(name: "CalendarMonths", input: "jan 15 !3mo",
             expected: Expected(hasHour: false, deltaAlerts: [Delta(unit: 4, count: -3)])),
        Case(name: "HoursWithoutTime", input: "friday !1h",
             expected: Expected(hasHour: false, deltaAlerts: [])),
        Case(name: "NoEarlyReminder", input: "tomorrow 3pm",
             expected: Expected(hasHour: true, deltaAlerts: []))
    ]

    static func run(outputFileName: String) async -> Never {
        guard !outputFileName.isEmpty,
              (outputFileName as NSString).lastPathComponent == outputFileName,
              outputFileName != ".", outputFileName != ".." else {
            fputs("Native self-test requires an output file name without a directory.\n", stderr)
            exit(1)
        }
        var report = Report(authorizationStatus: Int(EKEventStore.authorizationStatus(for: .reminder).rawValue))
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            await runCases(report: &report)
        } else {
            let message = "Reminders full access is required. No permission was requested."
            report.errors.append(message)
            report.cases = cases.map {
                Result(name: $0.name, input: $0.input, expected: $0.expected, error: message)
            }
        }
        report.pass = report.errors.isEmpty && report.temporaryListDeleted &&
            report.selfTestListsAfter == [] && report.cases.count == cases.count && report.cases.allSatisfy(\.pass)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(outputFileName)
            try encoder.encode(report).write(to: output, options: .atomic)
        } catch {
            fputs("Could not write native self-test result: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        exit(report.pass ? 0 : 1)
    }

    private static func runCases(report: inout Report) async {
        let eventKit = EventKitService(mode: .live)
        let eventStore = eventKit.eventStore
        let calendarsBefore = eventStore.calendars(for: .reminder)
        report.reminderCalendarCountBefore = calendarsBefore.count
        report.selfTestListsBefore = selfTestListNames(in: eventStore)
        guard let source = eventStore.defaultCalendarForNewReminders()?.source else {
            report.errors.append("No default reminder source is available.")
            return
        }
        let list = EKCalendar(for: .reminder, eventStore: eventStore)
        list.title = "Tally Self-Test \(UUID().uuidString)"
        list.source = source
        report.listName = list.title
        do {
            try eventStore.saveCalendar(list, commit: true)
        } catch {
            report.errors.append("Could not create temporary list: \(error.localizedDescription)")
            return
        }
        defer {
            do {
                try eventStore.removeCalendar(list, commit: true)
                let verificationStore = EKEventStore()
                report.temporaryListDeleted = verificationStore.calendar(withIdentifier: list.calendarIdentifier) == nil
                report.selfTestListsAfter = selfTestListNames(in: verificationStore)
                if !report.temporaryListDeleted {
                    report.errors.append("The temporary list still exists after deletion.")
                }
            } catch {
                report.errors.append("Could not delete temporary list \(list.title): \(error.localizedDescription)")
            }
        }
        let reminderStore = ReminderStore(eventKit: eventKit)
        let now = Date()
        for testCase in cases {
            var result = Result(name: testCase.name, input: testCase.input, expected: testCase.expected)
            do {
                let fields = QuickAddParser.parse("\(testCase.name) \(testCase.input)", calendar: .current, now: now)
                let request = ReminderCreationRequest(fields: fields, userNotes: nil, listIdentifier: list.calendarIdentifier)
                guard await reminderStore.addReminder(request) else {
                    throw failure(reminderStore.errorMessage ?? "ReminderStore rejected the reminder.")
                }
                let readStore = EKEventStore()
                guard let readList = readStore.calendar(withIdentifier: list.calendarIdentifier) else {
                    throw failure("The saved list could not be fetched through a fresh EventKit store.")
                }
                let predicate = readStore.predicateForReminders(in: [readList])
                let fetched = await withCheckedContinuation { continuation in
                    readStore.fetchReminders(matching: predicate) { reminders in
                        continuation.resume(returning: reminders)
                    }
                }
                guard let reminders = fetched else {
                    throw failure("EventKit failed to fetch the saved reminders.")
                }
                let matching = reminders.filter { $0.title == request.title }
                guard matching.count == 1, let reminder = matching.first else {
                    throw failure("Expected one saved reminder, found \(matching.count).")
                }
                var readError: NSError?
                guard let native = TallyReadReminderKitMetadata(reminder, &readError) else {
                    throw readError ?? failure("ReminderKit returned no metadata.")
                }
                let metadata = try JSONDecoder().decode(
                    NativeMetadata.self, from: JSONSerialization.data(withJSONObject: native))
                report.selectors = metadata.selectors
                let components = dateComponents(reminder.dueDateComponents)
                result.actual = Actual(
                    dueDateComponents: components,
                    alarms: (reminder.alarms ?? []).map {
                        Alarm(absoluteDate: $0.absoluteDate, relativeOffset: $0.relativeOffset,
                              hasLocation: $0.structuredLocation != nil)
                    },
                    deltaAlerts: metadata.deltaAlerts
                )
                result.pass = Set(["year", "month", "day"]).isSubset(of: components.keys) &&
                    (components["hour"] != nil) == testCase.expected.hasHour &&
                    dateComponents(request.dueDate).allSatisfy { components[$0.key] == $0.value } &&
                    metadata.deltaAlerts == testCase.expected.deltaAlerts
            } catch {
                result.error = error.localizedDescription
            }
            report.cases.append(result)
        }
    }

    private static func dateComponents(_ components: DateComponents?) -> [String: Int] {
        let values: [(String, Int?)] = [
            ("year", components?.year), ("month", components?.month), ("day", components?.day),
            ("hour", components?.hour), ("minute", components?.minute), ("second", components?.second)
        ]
        return Dictionary(uniqueKeysWithValues: values.compactMap { name, value in value.map { (name, $0) } })
    }

    private static func selfTestListNames(in store: EKEventStore) -> [String] {
        store.calendars(for: .reminder).map(\.title).filter { $0.hasPrefix("Tally Self-Test ") }.sorted()
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Tally.NativeSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
