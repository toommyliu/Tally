import XCTest
@testable import Tally

final class QuickAddEarlyReminderTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        value.locale = Locale(identifier: "en_US")
        return value
    }
    private var now: Date { date(2026, 9, 30, 10, 0) }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    private func parse(_ text: String, mode: QuickAddMode = .reminder) -> QuickAddFields {
        QuickAddParser.parse(text, mode: mode, calendar: calendar, now: now)
    }
    private func assertClaim(_ fields: QuickAddFields, input: String, span: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let expected = (input as NSString).range(of: span)
        XCTAssertEqual(fields.earlyReminder?.range, expected, file: file, line: line)
        XCTAssertEqual(fields.usedTokens.filter { $0.kind == .earlyReminder }.map(\.range), [expected], file: file, line: line)
        for token in fields.usedTokens where token.kind != .earlyReminder {
            XCTAssertEqual(NSIntersectionRange(token.range, expected).length, 0, file: file, line: line)
        }
    }
    private func assertInstant(_ fields: QuickAddFields, _ expected: Date,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard case let .instant(actual, _) = fields.earlyReminder?.firePoint else {
            return XCTFail("Expected a timed fire point", file: file, line: line)
        }
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    func testTimedOffsetsAnywhereAndWordAmounts() {
        for (span, amount, unit, hour, minute) in [
            ("!30m", 30, ScheduleUnit.minutes, 14, 30), ("!30 min before", 30, .minutes, 14, 30),
            ("!2 hours", 2, .hours, 13, 0), ("!an hour", 1, .hours, 14, 0),
            ("!half an hour", 30, .minutes, 14, 30), ("!ninety-nine minutes", 99, .minutes, 13, 21),
            ("!ninety nine minutes", 99, .minutes, 13, 21), ("!00099m", 99, .minutes, 13, 21),
            ("!30m,", 30, .minutes, 14, 30)
        ] {
            for input in ["Call tomorrow 3pm \(span)", "Call \(span) tomorrow 3pm", "Call tomorrow \(span) 3pm"] {
                let fields = parse(input)
                XCTAssertEqual(fields.title, "Call", input)
                XCTAssertEqual(fields.dueDate?.day, 1, input)
                XCTAssertEqual(fields.dueDate?.hour, 15, input)
                XCTAssertEqual(fields.earlyReminder?.reminderValue?.amount.value, amount, input)
                XCTAssertEqual(fields.earlyReminder?.reminderValue?.unit, unit, input)
                assertInstant(fields, date(2026, 10, 1, hour, minute))
                assertClaim(fields, input: input, span: span)
            }
        }
    }

    func testEveryUnitAliasInCompactAndSpacedForms() {
        let rows: [(ScheduleUnit, [String])] = [
            (.minutes, ["m", "min", "mins", "minute", "minutes"]),
            (.hours, ["h", "hr", "hrs", "hour", "hours"]), (.days, ["d", "day", "days"]),
            (.weeks, ["w", "wk", "wks", "week", "weeks"]), (.months, ["mo", "mos", "month", "months"])
        ]
        for (unit, aliases) in rows {
            for alias in aliases {
                for span in ["!2\(alias)", "!2 \(alias.uppercased())"] {
                    let input = "Call tomorrow 3pm \(span)"
                    let fields = parse(input)
                    XCTAssertEqual(fields.title, "Call", input)
                    XCTAssertEqual(fields.earlyReminder?.reminderValue?.unit, unit, input)
                    XCTAssertEqual(fields.earlyReminder?.reminderValue?.amount.value, 2, input)
                    assertClaim(fields, input: input, span: span)
                }
            }
        }
    }

    func testDateOnlyOffsetsHaveNoInventedTime() {
        for (span, month, day) in [("!a day", 9, 30), ("!two weeks", 9, 17), ("!3mo", 7, 1)] {
            let input = "Call \(span) tomorrow"
            let fields = parse(input)
            XCTAssertEqual(fields.title, "Call")
            XCTAssertEqual(fields.dueDate?.day, 1)
            XCTAssertNil(fields.dueDate?.hour)
            guard case let .day(fire) = fields.earlyReminder?.firePoint else { return XCTFail("Expected a day") }
            XCTAssertEqual(fire.year, 2026)
            XCTAssertEqual(fire.month, month)
            XCTAssertEqual(fire.day, day)
            XCTAssertNil(fire.hour)
            assertClaim(fields, input: input, span: span)
        }
    }

    func testWarningPrecedenceAndConsumedRanges() {
        for (input, span, title, warning) in [
            ("Call !30m", "!30m", "Call", "Add a date"),
            ("Call tomorrow !30m", "!30m", "Call", "Add a time"),
            ("Call !half a day tomorrow", "!half a day", "Call", "Add a time"),
            ("Call tomorrow 3pm !100m before", "!100m before", "Call", "Up to 99"),
            ("Call !999999999999999999999999999999mo tomorrow", "!999999999999999999999999999999mo", "Call", "Up to 99"),
            ("Call !0m tomorrow 3pm", "!0m", "Call", "Use 1 or more"),
            ("Call !100h", "!100h", "Call", "Up to 99"),
            ("Call in !2h", "!2h", "Call in", "Add a date")
        ] {
            let fields = parse(input)
            XCTAssertEqual(fields.title, title, input)
            XCTAssertEqual(fields.earlyReminder?.warning, warning, input)
            XCTAssertNil(fields.earlyReminder?.reminderValue, input)
            XCTAssertNil(fields.earlyReminder?.eventValue, input)
            assertClaim(fields, input: input, span: span)
        }
        XCTAssertNil(parse("Call in !2h").dueDate)
    }

    func testDuplicatePhrasesStayWholeAndLiteral() {
        for (first, warning) in [("!30m", nil), ("!100m", "Up to 99")] {
            let input = "Call \(first) !2 hours before tomorrow 3pm"
            let fields = parse(input)
            XCTAssertEqual(fields.title, "Call !2 hours before")
            XCTAssertEqual(fields.dueDate?.hour, 15)
            XCTAssertEqual(fields.earlyReminder?.warning, warning)
            assertClaim(fields, input: input, span: first)
        }
    }

    func testUnrecognizedBangsRemainTitleAndDoNotSetOtherMetadata() {
        for span in ["!3pm", "!important", "!p1", "!tomorrow", "!!", "!", "!1.5h", "!1h30m", "!+2h", "!-2h", "!!30m", "!30"] {
            let fields = parse("Call \(span)")
            XCTAssertEqual(fields.title, "Call \(span)")
            XCTAssertNil(fields.dueDate)
            XCTAssertNil(fields.earlyReminder)
            XCTAssertEqual(fields.priority, 0)
        }
        XCTAssertEqual(parse("Wow! Ship it !!").title, "Wow! Ship it !!")
        XCTAssertEqual(parse("Call Monday!").dueDate?.day, 5)
        XCTAssertNil(parse("Call !few hours").earlyReminder)
    }

    func testNotesAndInvalidRecurrenceCannotTakeTheClaim() {
        let notes = parse("Call !30m // tomorrow 3pm !1d")
        XCTAssertEqual(notes.title, "Call")
        XCTAssertNil(notes.dueDate)
        XCTAssertEqual(notes.inlineNotes, "tomorrow 3pm !1d")
        XCTAssertEqual(notes.earlyReminder?.warning, "Add a date")
        let input = "Review every 2147483648 days !30m at 9am"
        let invalid = parse(input)
        XCTAssertEqual(invalid.title, "Review every 2147483648 days at 9am")
        XCTAssertNil(invalid.dueDate)
        XCTAssertNil(invalid.recurrence)
        XCTAssertEqual(invalid.earlyReminder?.warning, "Add a date")
        assertClaim(invalid, input: input, span: "!30m")
    }

    func testRecurrenceCanAttachTimeAcrossTheClaimAndURL() {
        let input = "Review every Monday !30m at 9am https://example.com until Oct 30"
        let fields = parse(input)
        XCTAssertEqual(fields.title, "Review")
        XCTAssertEqual(fields.recurrence?.frequency, .weekly)
        XCTAssertEqual(fields.dueDate?.day, 5)
        XCTAssertEqual(fields.dueDate?.hour, 9)
        XCTAssertEqual(fields.url, URL(string: "https://example.com"))
        assertInstant(fields, date(2026, 10, 5, 8, 30))
        assertClaim(fields, input: input, span: "!30m")
    }

    func testOldGrammarAndBareBeforeHaveNoEarlyReminder() {
        for (input, title) in [("Call 30m before", "Call before"), ("Call remind 30m early", "Call remind early")] {
            let fields = parse(input)
            XCTAssertEqual(fields.title, title)
            XCTAssertEqual(fields.dueDate?.hour, 10)
            XCTAssertEqual(fields.dueDate?.minute, 30)
            XCTAssertNil(fields.earlyReminder)
        }
        let fields = parse("Call !2 days before friday")
        XCTAssertEqual(fields.title, "Call")
        XCTAssertEqual(fields.dueDate?.day, 2)
        XCTAssertEqual(fields.earlyReminder?.reminderValue?.unit, .days)
    }

    func testMonthEndAndDSTUseCalendarMathForReminders() {
        assertInstant(parse("Renew 2026-03-31 10am !1mo"), date(2026, 2, 28, 10, 0))
        assertInstant(parse("Renew 2026-11-01 3pm !1d"), date(2026, 10, 31, 15, 0))
        XCTAssertFalse(parse("Renew 2026-03-31 10am !1mo").earlyReminder!.isWarning)
    }

    func testEventsUseElapsedAlertsAndKeepDefaultAllDayToday() {
        let input = "Dentist tomorrow 2-3pm !30m"
        let timed = parse(input, mode: .event)
        XCTAssertEqual(timed.title, "Dentist")
        XCTAssertEqual(timed.eventTiming?.start.hour, 14)
        XCTAssertEqual(timed.eventTiming?.end.hour, 15)
        XCTAssertEqual(timed.earlyReminder?.eventValue?.secondsBeforeStart, 1800)
        assertInstant(timed, date(2026, 10, 1, 13, 30))
        assertClaim(timed, input: input, span: "!30m")
        let barrier = parse("Dentist tomorrow 2pm for !30m", mode: .event)
        XCTAssertEqual(barrier.title, "Dentist for")
        XCTAssertEqual(barrier.eventTiming?.end.hour, 15)
        XCTAssertEqual(barrier.earlyReminder?.eventValue?.secondsBeforeStart, 1800)
        let undated = parse("Standup !30m", mode: .event)
        XCTAssertEqual(undated.title, "Standup")
        XCTAssertEqual(undated.eventTiming?.isAllDay, true)
        XCTAssertEqual(undated.eventTiming?.start.day, 30)
        XCTAssertEqual(undated.earlyReminder?.warning, "Add a time")
        assertInstant(parse("Review 2026-11-01 3pm !1d", mode: .event), date(2026, 10, 31, 16, 0))
    }

    func testUnsupportedEventAlertsWarnWithoutDroppingTheSchedule() {
        for (input, warning, allDay) in [
            ("Offsite tomorrow !1d", "Add a time", true),
            ("Review tomorrow 3pm !1mo", "Use days or weeks", false),
            ("Review tomorrow !1mo", "Add a time", true),
            ("Review every month at 3pm !1mo", "Use days or weeks", false)
        ] {
            let fields = parse(input, mode: .event)
            XCTAssertEqual(fields.earlyReminder?.warning, warning, input)
            XCTAssertEqual(fields.eventTiming?.isAllDay, allDay, input)
            XCTAssertNil(fields.earlyReminder?.eventValue, input)
        }
        let weekly = parse("Review every Monday at 3pm !1w", mode: .event)
        XCTAssertEqual(weekly.recurrence?.frequency, .weekly)
        XCTAssertEqual(weekly.earlyReminder?.eventValue?.secondsBeforeStart, 604800)
    }
    @MainActor
    func testDraftProjectionsSaveWarningsWithoutAlerts() throws {
        let defaults = UserDefaults(suiteName: "QuickAddEarlyReminderTests.\(UUID().uuidString)")!
        let draft = QuickAddDraft(settingsStore: AppSettingsStore(userDefaults: defaults), calendar: calendar, now: { self.now })
        for input in ["Call !30m", "Call tomorrow !30m", "Call tomorrow 3pm !100m", "Call tomorrow !0m"] {
            draft.text = input
            XCTAssertTrue(draft.canSubmit, input)
            let request = try XCTUnwrap(draft.makeReminderRequest())
            XCTAssertEqual(request.title, "Call", input)
            XCTAssertNil(request.earlyReminder, input)
        }
        draft.text = "Call tomorrow 3pm !3mo"
        XCTAssertEqual(draft.makeReminderRequest()?.earlyReminder?.unit, .months)
        XCTAssertEqual(draft.makeReminderRequest()?.earlyReminder?.amount.value, 3)
        draft.mode = .event
        for input in ["Call tomorrow !1d", "Call tomorrow 3pm !1mo", "Call !30m"] {
            draft.text = input
            XCTAssertTrue(draft.canSubmit, input)
            let request = try XCTUnwrap(draft.makeEventRequest())
            XCTAssertEqual(request.title, "Call", input)
            XCTAssertNil(request.alert, input)
        }
        draft.text = "Call tomorrow 3pm !30m"
        XCTAssertEqual(draft.makeEventRequest()?.alert?.secondsBeforeStart, 1800)
    }

    func testEscSuppressionIsOpaqueToEarlierPhrases() {
        let input = "📞 Call in !2 hours tomorrow 3pm !1d"
        let range = (input as NSString).range(of: "!2 hours")
        let fields = QuickAddParser.parse(input, calendar: calendar, now: now,
            suppressedTokens: [QuickAddSuppressedToken(kind: .earlyReminder, range: range, text: "!2 hours")])
        XCTAssertEqual(fields.title, "📞 Call in !2 hours")
        XCTAssertEqual(fields.dueDate?.hour, 15)
        XCTAssertEqual(fields.earlyReminder?.reminderValue?.unit, .days)
        assertClaim(fields, input: input, span: "!1d")
        let partial = "Call !two weeks tomorrow 3pm"
        let suppressed = (partial as NSString).range(of: "weeks")
        let blocked = QuickAddParser.parse(partial, calendar: calendar, now: now,
            suppressedTokens: [QuickAddSuppressedToken(kind: .date, range: suppressed, text: "weeks")])
        XCTAssertNil(blocked.earlyReminder)
        XCTAssertEqual(blocked.title, "Call !two weeks")
    }

    func testPresetTextEditsReplaceOnlyTheClaimAndAreIdempotent() {
        let offset = ReminderEarlyReminder(amount: EarlyReminderAmount(validating: 15)!, unit: .minutes)
        func edit(_ input: String, _ value: ReminderEarlyReminder?) -> String {
            QuickAddTokenEditor.applyingEarlyReminder(value, to: input, calendar: calendar, now: now).text
        }
        let replaced = edit("Call !100m tomorrow 3pm // note", offset)
        XCTAssertEqual(replaced, "Call !15m tomorrow 3pm // note")
        XCTAssertEqual(edit(replaced, offset), replaced)
        XCTAssertEqual(edit(replaced, nil), "Call tomorrow 3pm // note")
        XCTAssertEqual(edit("Call tomorrow // note", offset), "Call tomorrow !15m // note")
        let duplicates = edit("Call !30m !2h tomorrow 3pm", offset)
        XCTAssertEqual(duplicates, "Call !15m !2h tomorrow 3pm")
        let removed = edit(duplicates, nil)
        XCTAssertEqual(removed, "Call !2h tomorrow 3pm")
        XCTAssertEqual(parse(removed).earlyReminder?.reminderValue?.amount.value, 2)
    }

    @MainActor
    func testDraftDateEditsPreserveTheTokenAndResolveItAgain() throws {
        let defaults = UserDefaults(suiteName: "QuickAddEarlyReminderTests.\(UUID().uuidString)")!
        let draft = QuickAddDraft(settingsStore: AppSettingsStore(userDefaults: defaults), calendar: calendar, now: { self.now })
        draft.text = "Call tomorrow 3pm !30m"
        draft.applyDueDate(nil)
        XCTAssertEqual(draft.text, "Call !30m")
        XCTAssertEqual(draft.fields.earlyReminder?.warning, "Add a date")
        draft.applyDueDate(QuickAddDueDateSelection(date: date(2026, 10, 1, 15, 0), includesTime: false))
        XCTAssertEqual(draft.fields.earlyReminder?.warning, "Add a time")
        draft.applyDueDate(QuickAddDueDateSelection(date: date(2026, 10, 1, 15, 0), includesTime: true))
        XCTAssertEqual(draft.makeReminderRequest()?.earlyReminder?.amount.value, 30)
        draft.mode = .event
        draft.applyEventLength(.allDay)
        XCTAssertTrue(draft.text.contains("!30m"))
        XCTAssertEqual(draft.fields.earlyReminder?.warning, "Add a time")
        XCTAssertNil(try XCTUnwrap(draft.makeEventRequest()).alert)
    }

    @MainActor
    func testDraftPresetEditsPreserveEscRangesAfterEmojiInsertion() throws {
        let defaults = UserDefaults(suiteName: "QuickAddEarlyReminderTests.\(UUID().uuidString)")!
        let draft = QuickAddDraft(settingsStore: AppSettingsStore(userDefaults: defaults), calendar: calendar, now: { self.now })
        draft.text = "Call !30 min before tomorrow 3pm"
        let token = try XCTUnwrap(draft.fields.earlyReminder?.token)
        XCTAssertTrue(draft.keepTokenAsText(at: token.range))
        draft.text = "📞 " + draft.text
        draft.applyEarlyReminder(ReminderEarlyReminder(amount: EarlyReminderAmount(validating: 1)!, unit: .days))
        XCTAssertEqual(draft.fields.title, "📞 Call !30 min before")
        XCTAssertEqual(draft.fields.earlyReminder?.reminderValue?.unit, .days)
        draft.applyDueDate(QuickAddDueDateSelection(date: date(2026, 10, 2, 15, 0), includesTime: true))
        XCTAssertEqual(draft.fields.title, "📞 Call !30 min before")
        XCTAssertEqual(draft.suppressedTokens.count, 1)
    }

    func testPresentationsShowFireTimeOrDayAndExactWarnings() {
        func presentation(_ text: String, mode: QuickAddMode = .reminder) -> EarlyReminderPresentation {
            EarlyReminderPresentation(parse(text, mode: mode).earlyReminder, calendar: calendar, locale: Locale(identifier: "en_US"))
        }
        XCTAssertEqual(presentation("Call tomorrow 3pm !30m").chipTitle, "30 min before · 2:30 PM")
        XCTAssertEqual(presentation("Call tomorrow 3pm !30m").previewTitle, "Thu, Oct 1 at 2:30 PM")
        let day = presentation("Call 2026-10-02 !1d")
        XCTAssertEqual(day.chipTitle, "1 day before · Thu")
        XCTAssertEqual(day.previewTitle, "Thu, Oct 1")
        XCTAssertFalse(day.accessibilityValue.contains("AM"))
        XCTAssertFalse(day.accessibilityValue.contains("PM"))
        XCTAssertTrue(day.accessibilityValue.contains("October 1, 2026"))
        let dst = presentation("Call 2026-11-01 3pm !1d", mode: .event)
        XCTAssertEqual(dst.chipTitle, "1 day before · 4:00 PM")
        XCTAssertTrue(dst.accessibilityValue.contains("October 31, 2026"))
        XCTAssertEqual(presentation("Call !100m").chipTitle, "Up to 99")
        XCTAssertEqual(presentation("Call !0m").chipTitle, "Use 1 or more")
    }

    func testPresetCatalogMatchesRemindersWordingAndOrder() {
        XCTAssertEqual(EarlyReminderCatalog.presets(for: .dateOnly).map(\.title), [
            "1 day before", "2 days before", "1 week before", "2 weeks before", "1 month before", "3 months before", "6 months before"
        ])
        XCTAssertEqual(EarlyReminderCatalog.presets(for: .timed).map(\.title), [
            "5 minutes before", "15 minutes before", "30 minutes before", "1 hour before", "2 hours before",
            "1 day before", "2 days before", "1 week before", "1 month before"
        ])
    }

    @MainActor
    func testCustomAmountsShareSyntaxValidationWithoutClamping() {
        let defaults = UserDefaults(suiteName: "QuickAddEarlyReminderTests.\(UUID().uuidString)")!
        let draft = QuickAddDraft(settingsStore: AppSettingsStore(userDefaults: defaults), calendar: calendar, now: { self.now })
        draft.text = "Call"
        let input = EarlyReminderCustomInput(amountText: "0002", unit: .hours)
        XCTAssertEqual(input.unitMenuTitle(.hours), "hours before")
        XCTAssertEqual(EarlyReminderCustomInput(amountText: "1", unit: .days).unitMenuTitle(.days), "day before")
        draft.applyEarlyReminder(input.offset)
        XCTAssertEqual(draft.text, "Call !2h")
        XCTAssertEqual(draft.fields.earlyReminder?.warning, "Add a date")
        for (text, warning) in [("0", "Use 1 or more"), ("100", "Up to 99"), ("99999999999999999999999999", "Up to 99"), ("1.5", "Use a whole number")] {
            let invalid = EarlyReminderCustomInput(amountText: text, unit: .days)
            XCTAssertNil(invalid.offset)
            XCTAssertEqual(invalid.numericWarning, warning)
        }
    }

    func testSharedDurationGrammarsKeepTheirOwnLimits() {
        for (text, amount) in [("in half an hour", 30), ("+2 hours", 120)] {
            let fields = parse("Call \(text)")
            XCTAssertEqual(fields.title, "Call")
            XCTAssertEqual(calendar.date(from: fields.dueDate!)!.timeIntervalSince(now), Double(amount * 60))
        }
        XCTAssertEqual(parse("Call in a few days").dueDate?.day, 3)
        XCTAssertEqual(parse("Call 2 days before friday").dueDate?.day, 30)
        for (text, minutes, days) in [("1.5h", 90, 0), ("1h30m", 90, 0), ("120m", 120, 0), ("2 weeks", 0, 14)] {
            let fields = parse("Call tomorrow 3pm for \(text)", mode: .event)
            XCTAssertEqual(fields.title, "Call")
            if days == 0 { XCTAssertEqual(fields.eventTiming?.durationMinutes, minutes) }
            else { XCTAssertEqual(fields.eventDuration?.amount, days) }
        }
    }

}

extension QuickAddEarlyReminderTests {
    func testEveryFollowedByABangSymbolKeepsTheRemainingScheduleLiteral() {
        for word in ["!$", "!+", "!-", "!#", "!)", "!😀", "!2", "!!x", "!important", "!é"] {
            for suffix in ["tomorrow at 5pm", "every Monday at 9am"] {
                for mode in [QuickAddMode.reminder, .event] {
                    let input = "Call every \(word) \(suffix)"
                    let fields = parse(input, mode: mode)
                    XCTAssertEqual(fields.title, input, input)
                    XCTAssertNil(fields.dueDate, input)
                    XCTAssertNil(fields.recurrence, input)
                    if mode == .event { XCTAssertEqual(fields.eventTiming?.isAllDay, true, input) }
                }
            }
        }
    }

    func testEveryFollowedByABangPunctuationWordAllowsTheFollowingSchedule() {
        for word in ["!", "!!", "!.", "!,", "...!", "!?!"] {
            for mode in [QuickAddMode.reminder, .event] {
                let fields = parse("Call every \(word) tomorrow at 5pm", mode: mode)
                XCTAssertEqual(fields.title, "Call every \(word)")
                if mode == .reminder {
                    XCTAssertEqual(fields.dueDate?.day, 1)
                    XCTAssertEqual(fields.dueDate?.hour, 17)
                } else {
                    XCTAssertEqual(fields.eventTiming?.start.day, 1)
                    XCTAssertEqual(fields.eventTiming?.start.hour, 17)
                }
            }
        }
    }

    func testUnsupportedRecurrenceKeepsAnUnrecognizedBangAndItsTailLiteral() {
        let input = "Call every !important tomorrow"
        let fields = parse(input)
        XCTAssertEqual(fields.title, input)
        XCTAssertNil(fields.dueDate)
        XCTAssertNil(fields.recurrence)
        XCTAssertNil(fields.earlyReminder)
        XCTAssertTrue(fields.usedTokens.isEmpty)
    }
}

extension QuickAddEarlyReminderTests {
    @MainActor
    func testPickingAnEarlyReminderPreservesAKeptNoteWithTrailingWhitespace() throws {
        let defaults = UserDefaults(suiteName: "QuickAddEarlyReminderTests.\(UUID().uuidString)")!
        let draft = QuickAddDraft(settingsStore: AppSettingsStore(userDefaults: defaults),
            calendar: calendar, now: { self.now })
        draft.text = "Buy milk tomorrow 3pm // note text "
        let token = try XCTUnwrap(draft.fields.usedTokens.first { $0.kind == .note })
        XCTAssertTrue(draft.keepTokenAsText(at: token.range))
        let offset = ReminderEarlyReminder(amount: EarlyReminderAmount(validating: 1)!, unit: .hours)
        draft.applyEarlyReminder(offset)
        XCTAssertEqual(draft.text, "Buy milk tomorrow 3pm // note text !1h")
        XCTAssertEqual(draft.suppressedTokens.map(\.text), ["// note text"])
        XCTAssertEqual(draft.fields.title, "Buy milk // note text")
        XCTAssertNil(draft.fields.inlineNotes)
        XCTAssertEqual(draft.makeReminderRequest()?.earlyReminder, offset)
    }

    @MainActor
    func testPickingAPresetPreservesAnEarlyReminderKeptAsTextAcrossWhitespaceNormalization() throws {
        let defaults = UserDefaults(suiteName: "QuickAddEarlyReminderTests.\(UUID().uuidString)")!
        let draft = QuickAddDraft(settingsStore: AppSettingsStore(userDefaults: defaults),
            calendar: calendar, now: { self.now })
        draft.text = "Call !30   min before tomorrow 3pm"
        let token = try XCTUnwrap(draft.fields.earlyReminder?.token)
        XCTAssertTrue(draft.keepTokenAsText(at: token.range))
        let offset = ReminderEarlyReminder(amount: EarlyReminderAmount(validating: 1)!, unit: .days)
        let edited = QuickAddTokenEditor.applyingEarlyReminder(offset, to: draft.text,
            calendar: calendar, now: now, suppressedTokens: draft.suppressedTokens).text
        draft.applyEarlyReminder(offset)
        XCTAssertEqual(draft.text, edited)
        XCTAssertEqual(draft.suppressedTokens.map(\.text), ["!30 min before"])
        XCTAssertEqual(draft.fields.title, "Call !30 min before")
        XCTAssertEqual(draft.makeReminderRequest()?.earlyReminder, offset)
        draft.applyEarlyReminder(offset)
        XCTAssertEqual(draft.text, edited)
        XCTAssertEqual(draft.fields.title, "Call !30 min before")
        XCTAssertEqual(draft.makeReminderRequest()?.earlyReminder, offset)
    }
}
