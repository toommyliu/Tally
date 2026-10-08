import XCTest
@testable import Tally

final class QuickAddEventParserTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    /// Wednesday, Sep 30 2026 at 10:00.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10))!
    }

    // MARK: - Time ranges

    func testCompactRangeSharesTheEndMeridiem() throws {
        let fields = parse("Standup tomorrow 2-3pm")

        XCTAssertEqual(fields.title, "Standup")
        let timing = try XCTUnwrap(fields.eventTiming)
        XCTAssertFalse(timing.isAllDay)
        assert(timing.start, day: 1, month: 10, hour: 14, minute: 0)
        assert(timing.end, day: 1, month: 10, hour: 15, minute: 0)
        XCTAssertTrue(fields.usedTokens.contains { $0.kind == .timeRange })
    }

    func testSpacedRangeWithoutDateUsesTodayWhenStillAhead() throws {
        let fields = parse("Design review 2pm - 4:30pm")

        XCTAssertEqual(fields.title, "Design review")
        let timing = try XCTUnwrap(fields.eventTiming)
        assert(timing.start, day: 30, month: 9, hour: 14, minute: 0)
        assert(timing.end, day: 30, month: 9, hour: 16, minute: 30)
    }

    func testFromToRangeInfersMorningStartBeforeAfternoonEnd() throws {
        let fields = parse("Workshop friday from 11 to 1pm")

        XCTAssertEqual(fields.title, "Workshop")
        let timing = try XCTUnwrap(fields.eventTiming)
        assert(timing.start, day: 2, month: 10, hour: 11, minute: 0)
        assert(timing.end, day: 2, month: 10, hour: 13, minute: 0)
    }

    func testRangeEndWithoutMeridiemFollowsTheStart() throws {
        let timing = try XCTUnwrap(parse("Focus block tomorrow 2pm-4").eventTiming)

        assert(timing.start, day: 1, month: 10, hour: 14, minute: 0)
        assert(timing.end, day: 1, month: 10, hour: 16, minute: 0)
    }

    func testRangeEndingBeforeItStartsRunsPastMidnight() throws {
        let timing = try XCTUnwrap(parse("Launch watch tomorrow 10pm-1am").eventTiming)

        assert(timing.start, day: 1, month: 10, hour: 22, minute: 0)
        assert(timing.end, day: 2, month: 10, hour: 1, minute: 0)
    }

    func testOmittedMeridiemFollowsTheShortestForwardRangeAcrossMidnight() throws {
        for range in ["11pm-1", "11-1am", "11pm to 1", "from 11 to 1am"] {
            let fields = parse("Night shift tomorrow \(range)")
            XCTAssertEqual(fields.title, "Night shift")
            let timing = try XCTUnwrap(fields.eventTiming)
            assert(timing.start, day: 1, month: 10, hour: 23, minute: 0)
            assert(timing.end, day: 2, month: 10, hour: 1, minute: 0)
        }

        let midnight = try XCTUnwrap(parse("Shift tomorrow 11pm-12").eventTiming)
        assert(midnight.end, day: 2, month: 10, hour: 0, minute: 0)
        let noon = try XCTUnwrap(parse("Shift tomorrow 11am-12").eventTiming)
        assert(noon.end, day: 1, month: 10, hour: 12, minute: 0)
    }

    func testBareNumbersAreNotATimeRange() {
        let fields = parse("Shift 9-5")

        XCTAssertEqual(fields.title, "Shift 9-5")
        XCTAssertEqual(fields.eventTiming?.isAllDay, true)
    }

    func testReminderModeLeavesRangesAsText() {
        let fields = QuickAddParser.parse(
            "Standup 2-3pm",
            mode: .reminder,
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(fields.title, "Standup 2-3pm")
        XCTAssertNil(fields.dueDate)
        XCTAssertNil(fields.eventTiming)
    }

    // MARK: - Durations

    func testInvalidDurationNumbersRemainLiteral() throws {
        for duration in ["nan hours", "inf days", "1e309 weeks", "999999999999999999999h"] {
            let fields = parse("Call tomorrow 3pm for \(duration)")

            XCTAssertEqual(fields.title, "Call for \(duration)")
            let timing = try XCTUnwrap(fields.eventTiming)
            assert(timing.start, day: 1, month: 10, hour: 15, minute: 0)
            assert(timing.end, day: 1, month: 10, hour: 16, minute: 0)
            XCTAssertFalse(fields.usedTokens.contains { $0.kind == .duration })
        }
    }

    func testManyInapplicableDurationsRemainLiteral() throws {
        let lengths = Array(repeating: "for 1h", count: 400).joined(separator: " ")
        let fields = parse("Meeting tomorrow \(lengths)")

        XCTAssertEqual(fields.title, "Meeting \(lengths)")
        XCTAssertEqual(fields.eventTiming?.isAllDay, true)
        XCTAssertFalse(fields.usedTokens.contains { $0.kind == .duration })
    }

    func testFirstApplicableDurationWinsWithoutConsumingOtherLengths() throws {
        let fields = parse("Offsite tomorrow for 1h for 3 days for 2 days")

        XCTAssertEqual(fields.title, "Offsite for 1h for 2 days")
        let timing = try XCTUnwrap(fields.eventTiming)
        assert(timing.start, day: 1, month: 10, hour: nil, minute: nil)
        assert(timing.end, day: 3, month: 10, hour: nil, minute: nil)
    }

    func testDurationSetsTheEndFromTheStartTime() throws {
        let cases: [(String, Int)] = [
            ("Call tomorrow 3pm for 45m", 45),
            ("Call tomorrow 3pm for 1.5h", 90),
            ("Call tomorrow 3pm for 1h30m", 90),
            ("Call tomorrow 3pm for an hour", 60),
            ("Call tomorrow 3pm for half an hour", 30),
            ("Call tomorrow 3pm for 2 hours", 120)
        ]

        for (input, minutes) in cases {
            let fields = parse(input)
            XCTAssertEqual(fields.title, "Call", input)
            let timing = try XCTUnwrap(fields.eventTiming, input)
            assert(timing.start, day: 1, month: 10, hour: 15, minute: 0)
            XCTAssertEqual(minutesBetween(timing.start, timing.end), minutes, input)
        }
    }

    func testTimedEventsDefaultToOneHour() throws {
        let timing = try XCTUnwrap(parse("Coffee with Maya tomorrow at 9am").eventTiming)

        assert(timing.start, day: 1, month: 10, hour: 9, minute: 0)
        assert(timing.end, day: 1, month: 10, hour: 10, minute: 0)
    }

    func testLengthsEndingInTheRepeatedHourKeepTheirEnd() throws {
        for (input, minutes) in [
            ("Shift 2026-11-01 12:30am for 2h", 120),
            ("Shift 2026-11-01 1:30am for 1h", 60),
            ("Shift 2026-11-01 1:45am for 30m", 30)
        ] {
            let timing = try XCTUnwrap(parse(input).eventTiming, input)
            XCTAssertEqual(minutesBetween(timing.start, timing.end), minutes, input)
        }
    }

    func testDurationBeforeTheTimeStillAttachesToTheDate() throws {
        let fields = parse("Call tomorrow for 30m at 3pm")

        XCTAssertEqual(fields.title, "Call")
        let timing = try XCTUnwrap(fields.eventTiming)
        assert(timing.start, day: 1, month: 10, hour: 15, minute: 0)
        XCTAssertEqual(minutesBetween(timing.start, timing.end), 30)
    }

    func testDayDurationMakesAMultiDayAllDayEvent() throws {
        let fields = parse("Offsite friday for 3 days")

        XCTAssertEqual(fields.title, "Offsite")
        let timing = try XCTUnwrap(fields.eventTiming)
        XCTAssertTrue(timing.isAllDay)
        assert(timing.start, day: 2, month: 10, hour: nil, minute: nil)
        assert(timing.end, day: 4, month: 10, hour: nil, minute: nil)
    }

    func testMinuteDurationWithoutAStartTimeStaysInTheTitle() throws {
        let fields = parse("Lunch tomorrow for 1h")

        XCTAssertEqual(fields.title, "Lunch for 1h")
        XCTAssertFalse(fields.usedTokens.contains { $0.kind == .duration })
        XCTAssertEqual(fields.eventTiming?.isAllDay, true)
    }

    func testDurationAfterARangeStaysInTheTitle() throws {
        let fields = parse("Review tomorrow 2-3pm for 2h")

        XCTAssertEqual(fields.title, "Review for 2h")
        let timing = try XCTUnwrap(fields.eventTiming)
        assert(timing.end, day: 1, month: 10, hour: 15, minute: 0)
    }

    func testRecurrenceCountIsNotReadAsADuration() {
        let fields = parse("Gym every day at 7am for 3 times")

        XCTAssertEqual(fields.title, "Gym")
        XCTAssertEqual(fields.recurrence?.end, .occurrenceCount(3))
        XCTAssertFalse(fields.usedTokens.contains { $0.kind == .duration })
    }

    func testRecurrenceCountSurvivesEventTimingBeforeTheEndClause() {
        for input in [
            "Gym every monday 2-3pm for 3 times",
            "Gym every monday at 2pm for 1h for 3 times",
            "Gym every monday for 1h at 2pm for 3 times"
        ] {
            let fields = parse(input)

            XCTAssertEqual(fields.title, "Gym", input)
            XCTAssertEqual(fields.recurrence?.end, .occurrenceCount(3), input)
            XCTAssertEqual(fields.eventTiming?.start.hour, 14, input)
            XCTAssertEqual(fields.eventTiming?.end.hour, 15, input)
        }
    }

    func testRecurrenceUntilDateSurvivesAnEventRange() throws {
        let fields = parse("Gym every monday 2-3pm until 2026-10-26")

        XCTAssertEqual(fields.title, "Gym")
        guard case let .date(end) = fields.recurrence?.end else {
            return XCTFail("Expected a recurrence end date")
        }
        assert(end, day: 26, month: 10, hour: nil, minute: nil)
    }

    // MARK: - All-day and other metadata

    func testEventsWithoutADateAreAllDayToday() throws {
        let timing = try XCTUnwrap(parse("Pay rent").eventTiming)

        XCTAssertTrue(timing.isAllDay)
        assert(timing.start, day: 30, month: 9, hour: nil, minute: nil)
        assert(timing.end, day: 30, month: 9, hour: nil, minute: nil)
    }

    func testRecurringRangeStartsOnTheFirstOccurrence() throws {
        let fields = parse("Team sync every monday 2-3pm")

        XCTAssertEqual(fields.title, "Team sync")
        XCTAssertEqual(fields.recurrence?.frequency, .weekly)
        let timing = try XCTUnwrap(fields.eventTiming)
        assert(timing.start, day: 5, month: 10, hour: 14, minute: 0)
        assert(timing.end, day: 5, month: 10, hour: 15, minute: 0)
    }

    func testRecurringRangesSkipPastOccurrences() throws {
        for input in [
            "Gym every wednesday 8-9am",
            "Gym every wednesday at 8-9am",
            "Gym every wednesday for 3 times 8-9am",
            "Gym 8-9am every wednesday",
            "Gym 8-9am #Work every wednesday at 7pm"
        ] {
            let fields = parse(input)
            XCTAssertEqual(fields.title, "Gym", input)
            let timing = try XCTUnwrap(fields.eventTiming)
            assert(timing.start, day: 7, month: 10, hour: 8, minute: 0)
            assert(timing.end, day: 7, month: 10, hour: 9, minute: 0)
            XCTAssertTrue(fields.usedTokens.contains { $0.kind == .timeRange }, input)
        }
    }

    func testRecurringRangeValidatesEndAgainstItsFirstFutureOccurrence() {
        let input = "Gym every wednesday 8-9am until 2026-09-30"
        let fields = parse(input)

        XCTAssertEqual(fields.title, input)
        XCTAssertNil(fields.recurrence)
        XCTAssertEqual(fields.eventTiming?.isAllDay, true)
    }

    func testSuppressingRecurringRangeRemovesItsStartTime() throws {
        let input = "Gym every wednesday 8-9am"
        let range = (input as NSString).range(of: "8-9am")
        let fields = QuickAddParser.parse(
            input, mode: .event, calendar: calendar, now: now,
            suppressedTokens: [.init(kind: .timeRange, range: range, text: "8-9am")]
        )

        XCTAssertEqual(fields.title, "Gym 8-9am")
        XCTAssertEqual(fields.recurrence?.frequency, .weekly)
        XCTAssertEqual(fields.eventTiming?.isAllDay, true)
        assert(try XCTUnwrap(fields.eventTiming).start, day: 30, month: 9, hour: nil, minute: nil)
    }

    func testAlertAppliesToARangeStart() {
        let fields = parse("Dentist tomorrow 2-3pm remind me 30m before")

        XCTAssertEqual(fields.title, "Dentist")
        XCTAssertEqual(fields.earlyReminder, ReminderEarlyReminder(amount: 30, unit: .minutes))
    }

    func testCalendarTokenAndPriorityInEventMode() {
        let fields = parse("Board meeting #Work P1 tomorrow 9am")

        XCTAssertEqual(fields.listName, "Work")
        XCTAssertEqual(fields.priority, 0)
        XCTAssertEqual(fields.title, "Board meeting P1")
    }

    // MARK: - Length editing

    func testPickingALengthKeepsTheRangeStart() throws {
        let updated = QuickAddTokenEditor.applyingEventLength(
            .duration(.minutes(30)),
            to: "Standup tomorrow 2-3pm",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(updated, "Standup tomorrow 2:00pm for 30m")
        let timing = try XCTUnwrap(parse(updated).eventTiming)
        assert(timing.start, day: 1, month: 10, hour: 14, minute: 0)
        XCTAssertEqual(minutesBetween(timing.start, timing.end), 30)
    }

    func testPickingALengthKeepsARangeRunningPastMidnight() throws {
        let updated = QuickAddTokenEditor.applyingEventLength(
            .duration(.minutes(90)),
            to: "Shift tomorrow 11pm-1am",
            calendar: calendar,
            now: now
        )
        let fields = parse(updated)

        XCTAssertEqual(fields.title, "Shift")
        let timing = try XCTUnwrap(fields.eventTiming)
        assert(timing.start, day: 1, month: 10, hour: 23, minute: 0)
        assert(timing.end, day: 2, month: 10, hour: 0, minute: 30)
    }

    func testPickingALengthKeepsARecurringRangeAndItsEnd() throws {
        for input in [
            "Gym every monday 2-3pm for 3 times",
            "Gym 2-3pm every monday for 3 times",
            "Gym 2-3pm"
        ] {
            let updated = QuickAddTokenEditor.applyingEventLength(
                .duration(.minutes(30)), to: input, calendar: calendar, now: now
            )
            let fields = parse(updated)
            let isRecurring = input.contains("every")

            XCTAssertEqual(fields.title, "Gym", updated)
            XCTAssertEqual(fields.recurrence, isRecurring ? ReminderRecurrence(
                frequency: .weekly, weekdays: [.monday], end: .occurrenceCount(3)
            ) : nil, updated)
            let timing = try XCTUnwrap(fields.eventTiming, updated)
            assert(timing.start, day: isRecurring ? 5 : 30, month: isRecurring ? 10 : 9, hour: 14, minute: 0)
            XCTAssertEqual(minutesBetween(timing.start, timing.end), 30, updated)
        }
    }

    func testPickingALengthReplacesTheOldOne() {
        let updated = QuickAddTokenEditor.applyingEventLength(
            .duration(.minutes(90)),
            to: "Call tomorrow 3pm for 45m",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(updated, "Call tomorrow 3:00pm for 1h30m")
    }

    func testPickingALengthKeepsItAcrossTheFallBackClockChange() throws {
        let updated = QuickAddTokenEditor.applyingEventLength(
            .duration(.minutes(120)),
            to: "Shift 2026-11-01 12:30am-2:30am",
            calendar: calendar,
            now: now
        )

        let timing = try XCTUnwrap(parse(updated).eventTiming)
        assert(timing.start, day: 1, month: 11, hour: 0, minute: 30)
        XCTAssertEqual(minutesBetween(timing.start, timing.end), 120)
    }

    func testPickingAllDayDropsTheTimeAndLength() throws {
        let updated = QuickAddTokenEditor.applyingEventLength(
            .allDay,
            to: "Call tomorrow 3pm for 45m",
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(updated, "Call 2026-10-01")
        let timing = try XCTUnwrap(parse(updated).eventTiming)
        XCTAssertTrue(timing.isAllDay)
    }

    func testPickingAllDayPreservesRecurrenceAndItsEnd() throws {
        for input in [
            "Gym every monday 2-3pm for 3 times #Work // Bring water",
            "Gym every monday at 2pm for 3 times for 1h #Work // Bring water",
            "Gym every monday #Work at 2pm for 3 times for 1h // Bring water"
        ] {
            let updated = QuickAddTokenEditor.applyingEventLength(
                .allDay, to: input, calendar: calendar, now: now
            )
            let fields = parse(updated)

            XCTAssertEqual(fields.title, "Gym", updated)
            XCTAssertEqual(fields.recurrence, ReminderRecurrence(
                frequency: .weekly, weekdays: [.monday], end: .occurrenceCount(3)
            ), updated)
            XCTAssertEqual(fields.eventTiming?.isAllDay, true)
            XCTAssertEqual(fields.listName, "Work")
            XCTAssertEqual(fields.inlineNotes, "Bring water")
        }
    }

    func testPickingAllDayPreservesUntilDateAndRemovesTimedAlert() throws {
        let updated = QuickAddTokenEditor.applyingEventLength(
            .allDay,
            to: "Gym every monday at 2pm until 2026-10-26 remind 30m early",
            calendar: calendar, now: now
        )
        let fields = parse(updated)

        XCTAssertEqual(updated, "Gym every monday until 2026-10-26")
        XCTAssertEqual(fields.title, "Gym")
        XCTAssertEqual(fields.eventTiming?.isAllDay, true)
        XCTAssertNil(fields.earlyReminder)
        guard case let .date(end) = fields.recurrence?.end else {
            return XCTFail("Expected a recurrence end date")
        }
        assert(end, day: 26, month: 10, hour: nil, minute: nil)
    }

    func testPickingADateKeepsTheRangeLengthAndLiteralDuration() throws {
        let selection = QuickAddDueDateSelection(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 16))),
            includesTime: true
        )

        let updated = QuickAddTokenEditor.applyingDueDate(
            selection,
            to: "Call tomorrow 2-3pm for 45m",
            calendar: calendar,
            now: now,
            mode: .event
        )

        XCTAssertEqual(updated, "Call 2026-10-06 4:00pm for 1h for 45m")
        XCTAssertEqual(parse(updated).title, "Call for 45m")
        let timing = try XCTUnwrap(parse(updated).eventTiming)
        assert(timing.start, day: 6, month: 10, hour: 16, minute: 0)
        XCTAssertEqual(minutesBetween(timing.start, timing.end), 60)
    }

    func testPickingADateWithoutATimeDropsOnlyLengthsThatNeedATime() throws {
        let selection = QuickAddDueDateSelection(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))),
            includesTime: false
        )
        let cases: [(input: String, title: String, lastDay: Int)] = [
            ("Call tomorrow 3pm for 45m", "Call", 6),
            ("Call for 45m tomorrow 3pm", "Call", 6),
            ("Call tomorrow for 45m", "Call for 45m", 6),
            ("Offsite tomorrow 9am #Work for 2 days", "Offsite", 7)
        ]

        for (input, title, lastDay) in cases {
            let updated = QuickAddTokenEditor.applyingDueDate(
                selection, to: input, calendar: calendar, now: now, mode: .event
            )
            let fields = parse(updated)

            XCTAssertEqual(fields.title, title, updated)
            let timing = try XCTUnwrap(fields.eventTiming, updated)
            XCTAssertTrue(timing.isAllDay, updated)
            assert(timing.start, day: 6, month: 10, hour: nil, minute: nil)
            assert(timing.end, day: lastDay, month: 10, hour: nil, minute: nil)
        }
    }

    func testPickingADatePreservesMultiHourAndOvernightRanges() throws {
        let selection = QuickAddDueDateSelection(
            date: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 16))),
            includesTime: true
        )

        for input in ["Review tomorrow 2-4pm", "Review tomorrow 11pm-1am"] {
            let updated = QuickAddTokenEditor.applyingDueDate(
                selection, to: input, calendar: calendar, now: now, mode: .event
            )
            let fields = parse(updated)

            XCTAssertEqual(fields.title, "Review")
            let timing = try XCTUnwrap(fields.eventTiming)
            assert(timing.start, day: 6, month: 10, hour: 16, minute: 0)
            assert(timing.end, day: 6, month: 10, hour: 18, minute: 0)
        }
    }

    // MARK: - Display

    func testEventEndingAtMidnightReadsAsTheSameEvening() throws {
        let current = Calendar.current
        let start = try XCTUnwrap(current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 23)))
        let end = try XCTUnwrap(current.date(byAdding: .hour, value: 1, to: start))
        let timing = CalendarEventTiming(
            start: current.dateComponents([.year, .month, .day, .hour, .minute], from: start),
            end: current.dateComponents([.year, .month, .day, .hour, .minute], from: end),
            isAllDay: false
        )

        XCTAssertFalse(timing.shortDisplayTitle.contains("Oct 7"), timing.shortDisplayTitle)
        XCTAssertEqual(timing.lengthDisplayTitle, "1 hr")
        XCTAssertEqual(timing.selectedLength, .duration(.minutes(60)))
    }

    func testLengthTitles() {
        XCTAssertEqual(CalendarEventTiming.lengthTitle(minutes: 45), "45 min")
        XCTAssertEqual(CalendarEventTiming.lengthTitle(minutes: 90), "1 hr 30 min")
        XCTAssertEqual(CalendarEventTiming.lengthTitle(minutes: 2 * 24 * 60), "2 days")
        XCTAssertEqual(QuickAddEventLength.duration(.minutes(90)).minutes, 90)
        XCTAssertNil(QuickAddEventLength.allDay.minutes)
    }

    // MARK: - Helpers

    private func parse(_ input: String) -> QuickAddFields {
        QuickAddParser.parse(input, mode: .event, calendar: calendar, now: now)
    }

    private func minutesBetween(_ start: DateComponents, _ end: DateComponents) -> Int? {
        guard let startDate = calendar.date(from: start),
              let endDate = calendar.date(from: end) else {
            return nil
        }

        return Int(endDate.timeIntervalSince(startDate) / 60)
    }

    private func assert(
        _ components: DateComponents,
        day: Int,
        month: Int,
        hour: Int?,
        minute: Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(components.month, month, file: file, line: line)
        XCTAssertEqual(components.day, day, file: file, line: line)
        XCTAssertEqual(components.hour, hour, file: file, line: line)
        XCTAssertEqual(components.minute, minute, file: file, line: line)
    }
}
