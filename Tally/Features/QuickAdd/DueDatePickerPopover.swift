import AppKit
import SwiftUI

struct DueDatePickerPopover: View {
    @FocusState private var focusedItem: FocusTarget?
    @State private var selectedDate: Date
    @State private var visibleMonth: Date
    @State private var includesTime: Bool
    @State private var isEditingTime = false
    @State private var isTimeHovering = false
    @State private var isChoosingMonthYear = false
    @State private var isMonthTitleHovering = false

    let initialComponents: DateComponents?
    let reminderDayCounts: [Date: Int]
    let onCancel: () -> Void
    let onDone: (QuickAddDueDateSelection) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    private enum FocusTarget: Hashable {
        case shortcut(String)
        case month
        case today
        case previousMonth
        case nextMonth
        case day(Date)
        case time
    }

    init(
        initialComponents: DateComponents?,
        reminderDayCounts: [Date: Int],
        onCancel: @escaping () -> Void,
        onDone: @escaping (QuickAddDueDateSelection) -> Void
    ) {
        let calendar = Calendar.current
        let defaultDate = Self.roundedDefaultDate(calendar: calendar)
        let selection = Self.selectionDate(
            from: initialComponents,
            defaultDate: defaultDate,
            calendar: calendar
        )

        self.initialComponents = initialComponents
        self.reminderDayCounts = reminderDayCounts
        self.onCancel = onCancel
        self.onDone = onDone
        _selectedDate = State(initialValue: selection)
        _visibleMonth = State(initialValue: calendar.startOfMonth(for: selection))
        _includesTime = State(
            initialValue: initialComponents?.hour != nil || initialComponents?.minute != nil
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            shortcutSection

            Divider()

            calendarSection

            Divider()

            timeButton
        }
        .frame(width: 244)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand {
            if isChoosingMonthYear {
                isChoosingMonthYear = false
                focusedItem = .month
            } else if isEditingTime {
                isEditingTime = false
                focusedItem = .time
            } else {
                onCancel()
            }
        }
        .onKeyPress(keys: [.tab]) { keyPress in
            guard !isChoosingMonthYear, !isEditingTime else {
                return .ignored
            }

            moveFocus(forward: !keyPress.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            guard !isChoosingMonthYear, !isEditingTime else {
                return .ignored
            }

            switch focusedItem {
            case let .shortcut(id):
                guard let shortcut = shortcuts.first(where: { $0.id == id }) else {
                    return .ignored
                }
                apply(shortcut.date)
            case .month:
                isChoosingMonthYear = true
            case .today:
                guard !isShowingCurrentMonth else {
                    return .ignored
                }
                visibleMonth = calendar.startOfMonth(for: Date())
            case .previousMonth:
                moveMonth(by: -1)
            case .nextMonth:
                moveMonth(by: 1)
            case let .day(date):
                apply(date)
            case .time:
                isEditingTime = true
            case nil:
                return .ignored
            }

            return .handled
        }
        .task {
            focusedItem = initialFocusTarget
        }
        .onChange(of: visibleMonth) { _, _ in
            guard !focusTargets.contains(where: { $0 == focusedItem }) else {
                return
            }

            focusedItem = .month
        }
        .onChange(of: isChoosingMonthYear) { _, isPresented in
            if !isPresented {
                focusedItem = .month
            }
        }
        .onChange(of: isEditingTime) { _, isPresented in
            if !isPresented {
                focusedItem = .time
            }
        }
    }

    private var shortcutSection: some View {
        VStack(spacing: 1) {
            ForEach(shortcuts) { shortcut in
                DateShortcutButton(shortcut: shortcut) {
                    apply(shortcut.date)
                }
                .quickAddPopoverFocus(
                    $focusedItem,
                    equals: .shortcut(shortcut.id),
                    shape: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
            }

        }
        .padding(6)
    }

    private var calendarSection: some View {
        VStack(spacing: 5) {
            monthHeader
            weekdayHeader
            calendarGrid
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 9)
    }

    private var monthHeader: some View {
        HStack(spacing: 3) {
            Button {
                isChoosingMonthYear = true
            } label: {
                ViewThatFits(in: .horizontal) {
                    Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                        .fixedSize(horizontal: true, vertical: false)

                    Text(visibleMonth.formatted(.dateTime.month(.abbreviated).year()))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .frame(width: 122, height: 21)
                .background(
                    Color.primary.opacity(isMonthTitleHovering ? 0.055 : 0),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .quickAddPopoverFocus(
                $focusedItem,
                equals: .month,
                shape: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .onHover { isMonthTitleHovering = $0 }
            .popover(isPresented: $isChoosingMonthYear, arrowEdge: .bottom) {
                MonthYearPickerPopover(
                    initialMonth: visibleMonth,
                    onSelect: { month in
                        visibleMonth = calendar.startOfMonth(for: month)
                        isChoosingMonthYear = false
                    }
                )
            }
            .accessibilityLabel("Choose month and year")
            .accessibilityValue(
                visibleMonth.formatted(.dateTime.month(.wide).year())
            )

            Spacer(minLength: 4)

            MonthHeaderTodayButton(isEnabled: !isShowingCurrentMonth) {
                visibleMonth = calendar.startOfMonth(for: Date())
            }
            .quickAddPopoverFocus(
                $focusedItem,
                equals: .today,
                shape: RoundedRectangle(cornerRadius: 4, style: .continuous),
                isEnabled: !isShowingCurrentMonth
            )

            MonthNavigationButton(
                systemName: "chevron.left",
                accessibilityLabel: "Previous month"
            ) {
                moveMonth(by: -1)
            }
            .quickAddPopoverFocus(
                $focusedItem,
                equals: .previousMonth,
                shape: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )

            MonthNavigationButton(
                systemName: "chevron.right",
                accessibilityLabel: "Next month"
            ) {
                moveMonth(by: 1)
            }
            .quickAddPopoverFocus(
                $focusedItem,
                equals: .nextMonth,
                shape: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
        }
        .frame(height: 23)
    }

    private var isShowingCurrentMonth: Bool {
        calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 13)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(calendarDays) { day in
                if day.isInVisibleMonth {
                    CalendarDateButton(
                        day: day,
                        isSelected: calendar.isDate(day.date, inSameDayAs: selectedDate),
                        isToday: calendar.isDateInToday(day.date),
                        isKeyboardFocused: focusedItem == .day(
                            calendar.startOfDay(for: day.date)
                        ),
                        reminderCount: reminderDayCounts[
                            calendar.startOfDay(for: day.date),
                            default: 0
                        ]
                    ) {
                        apply(day.date)
                    }
                    .quickAddPopoverFocusState(
                        $focusedItem,
                        equals: .day(calendar.startOfDay(for: day.date))
                    )
                } else {
                    Color.clear
                        .frame(height: 27)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var timeButton: some View {
        Button {
            isEditingTime = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(TallyPalette.date)

                Text("Time")
                    .font(.system(size: 12))

                Spacer(minLength: 8)

                if includesTime {
                    Text(selectedDate.formatted(.dateTime.hour().minute()))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(DatePickerRowButtonStyle(isHovering: isTimeHovering))
        .quickAddPopoverFocus(
            $focusedItem,
            equals: .time,
            shape: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .onHover { isTimeHovering = $0 }
        .popover(isPresented: $isEditingTime, arrowEdge: .trailing) {
            TimeEditorPopover(
                initialDate: selectedDate,
                hasExistingTime: includesTime,
                onCancel: { isEditingTime = false },
                onRemove: {
                    includesTime = false
                    isEditingTime = false
                    onDone(
                        QuickAddDueDateSelection(
                            date: selectedDate,
                            includesTime: false
                        )
                    )
                },
                onSave: { date in
                    selectedDate = date
                    includesTime = true
                    isEditingTime = false
                    onDone(
                        QuickAddDueDateSelection(
                            date: date,
                            includesTime: true
                        )
                    )
                }
            )
        }
        .accessibilityLabel("Time")
        .accessibilityValue(
            includesTime
                ? selectedDate.formatted(.dateTime.hour().minute())
                : "None"
        )
    }

    private var shortcuts: [DateShortcut] {
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let weekend = upcoming(weekday: 7, from: today, includingToday: true)
        let nextWeek = upcoming(weekday: 2, from: today, includingToday: false)

        return [
            DateShortcut(
                title: "Today",
                trailingTitle: shortWeekday(for: today),
                systemName: "calendar",
                tint: Color(nsColor: .systemGreen),
                date: today
            ),
            DateShortcut(
                title: "Tomorrow",
                trailingTitle: shortWeekday(for: tomorrow),
                systemName: "sun.max",
                tint: Color(nsColor: .systemOrange),
                date: tomorrow
            ),
            DateShortcut(
                title: "This Weekend",
                trailingTitle: shortWeekday(for: weekend),
                systemName: "sofa",
                tint: TallyPalette.date,
                date: weekend
            ),
            DateShortcut(
                title: "Next Week",
                trailingTitle: nextWeek.formatted(
                    .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                ),
                systemName: "arrow.right.square",
                tint: Color(nsColor: .systemPurple),
                date: nextWeek
            ),
        ]
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var calendarDays: [CalendarDate] {
        let monthStart = calendar.startOfMonth(for: visibleMonth)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31
        let occupiedCells = leadingDays + daysInMonth
        let cellCount = ((occupiedCells + 6) / 7) * 7
        let gridStart = calendar.date(
            byAdding: .day,
            value: -leadingDays,
            to: monthStart
        ) ?? monthStart

        return (0..<cellCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }

            return CalendarDate(
                date: date,
                dayNumber: calendar.component(.day, from: date),
                isInVisibleMonth: calendar.isDate(
                    date,
                    equalTo: visibleMonth,
                    toGranularity: .month
                )
            )
        }
    }

    private var focusTargets: [FocusTarget] {
        var targets = shortcuts.map { FocusTarget.shortcut($0.id) }
        targets.append(.month)
        if !isShowingCurrentMonth {
            targets.append(.today)
        }
        targets.append(contentsOf: [.previousMonth, .nextMonth])
        targets.append(contentsOf: calendarDays.compactMap { day in
            guard day.isInVisibleMonth else {
                return nil
            }

            return .day(calendar.startOfDay(for: day.date))
        })
        targets.append(.time)
        return targets
    }

    private var initialFocusTarget: FocusTarget {
        guard initialComponents != nil else {
            return .shortcut("Today")
        }

        let selectedDay = calendar.startOfDay(for: selectedDate)
        let selectedTarget = FocusTarget.day(selectedDay)
        return focusTargets.contains(selectedTarget) ? selectedTarget : .month
    }

    private func moveFocus(forward: Bool) {
        focusedItem = nextQuickAddPopoverFocus(
            current: focusedItem,
            initial: initialFocusTarget,
            targets: focusTargets,
            forward: forward
        )
    }

    private func apply(_ date: Date) {
        let selection = datePreservingTime(on: date)
        selectedDate = selection
        onDone(
            QuickAddDueDateSelection(
                date: selection,
                includesTime: includesTime
            )
        )
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(
            byAdding: .month,
            value: value,
            to: visibleMonth
        ) else {
            return
        }

        visibleMonth = calendar.startOfMonth(for: month)
    }

    private func upcoming(
        weekday: Int,
        from date: Date,
        includingToday: Bool
    ) -> Date {
        if includingToday, calendar.component(.weekday, from: date) == weekday {
            return date
        }

        return calendar.nextDate(
            after: date,
            matching: DateComponents(weekday: weekday),
            matchingPolicy: .nextTime
        ) ?? date
    }

    private func shortWeekday(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func datePreservingTime(on date: Date) -> Date {
        var components = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day],
            from: date
        )
        components.hour = calendar.component(.hour, from: selectedDate)
        components.minute = calendar.component(.minute, from: selectedDate)
        return calendar.date(from: components) ?? date
    }

    private static func selectionDate(
        from components: DateComponents?,
        defaultDate: Date,
        calendar: Calendar
    ) -> Date {
        guard var components else {
            return defaultDate
        }

        if components.hour == nil {
            components.hour = calendar.component(.hour, from: defaultDate)
        }
        if components.minute == nil {
            components.minute = calendar.component(.minute, from: defaultDate)
        }

        return calendar.date(from: components) ?? defaultDate
    }

    private static func roundedDefaultDate(calendar: Calendar) -> Date {
        let now = Date()
        let minute = calendar.component(.minute, from: now)
        let minutesToAdd = (15 - minute % 15) % 15
        return calendar.date(byAdding: .minute, value: minutesToAdd, to: now) ?? now
    }
}

private struct DateShortcut: Identifiable {
    let title: String
    let trailingTitle: String?
    let systemName: String
    let tint: Color
    let date: Date

    var id: String { title }
}

private struct DateShortcutButton: View {
    @State private var isHovering = false

    let shortcut: DateShortcut
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: shortcut.systemName)
                    .font(.system(size: 11.5, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(shortcut.tint)
                    .frame(width: 18)

                Text(shortcut.title)
                    .font(.system(size: 12))

                Spacer(minLength: 8)

                if let trailingTitle = shortcut.trailingTitle {
                    Text(trailingTitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(DatePickerRowButtonStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
        .accessibilityLabel(shortcut.title)
        .accessibilityValue(shortcut.trailingTitle ?? "")
    }
}

private struct DatePickerRowButtonStyle: ButtonStyle {
    var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.primary.opacity(
                    configuration.isPressed ? 0.08 : (isHovering ? 0.045 : 0)
                ),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
    }
}

private struct CalendarDate: Identifiable {
    let date: Date
    let dayNumber: Int
    let isInVisibleMonth: Bool

    var id: Date { date }
}

private struct CalendarDateButton: View {
    @State private var isHovering = false

    let day: CalendarDate
    let isSelected: Bool
    let isToday: Bool
    let isKeyboardFocused: Bool
    let reminderCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(day.dayNumber)")
                    .font(
                        .system(
                            size: 10.5,
                            weight: isSelected ? .semibold : .regular
                        )
                        .monospacedDigit()
                    )
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: 21, height: 21)
                    .background(backgroundColor, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(
                                TallyPalette.date.opacity(isToday && !isSelected ? 0.85 : 0),
                                lineWidth: 1
                            )
                    }

                HStack(spacing: 1.5) {
                    ForEach(0..<min(reminderCount, 3), id: \.self) { _ in
                        Circle()
                            .foregroundStyle(TallyPalette.date)
                            .frame(width: 2.5, height: 2.5)
                    }
                }
                .frame(width: 12, height: 5)
                .opacity(reminderCount > 0 ? 1 : 0)
                .clipped()
            }
            .frame(height: 27)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(
            day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        )
        .accessibilityValue(reminderCount == 0 ? "" : "\(reminderCount) reminders")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isSelected {
            return TallyPalette.date
        }
        if isKeyboardFocused {
            return Color.primary.opacity(0.055)
        }
        return isHovering ? Color.primary.opacity(0.08) : .clear
    }
}

private struct MonthHeaderTodayButton: View {
    @State private var isHovering = false

    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Today")
                .fixedSize()
        }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(TallyPalette.date.opacity(isEnabled ? 1 : 0.38))
            .padding(.horizontal, 4)
            .frame(height: 20)
            .background(
                Color.primary.opacity(isHovering && isEnabled ? 0.055 : 0),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .contentShape(Rectangle())
            .disabled(!isEnabled)
            .onHover { isHovering = $0 }
            .help("Return to the current month")
            .accessibilityLabel("Return to current month")
    }
}

private struct MonthYearPickerPopover: View {
    @FocusState private var focusedItem: FocusTarget?
    @State private var year: Int

    let initialMonth: Date
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    private enum FocusTarget: Hashable {
        case year
        case month(Int)
    }

    init(
        initialMonth: Date,
        onSelect: @escaping (Date) -> Void
    ) {
        self.initialMonth = initialMonth
        self.onSelect = onSelect
        _year = State(initialValue: Calendar.current.component(.year, from: initialMonth))
    }

    var body: some View {
        VStack(spacing: 8) {
            yearHeader

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(calendar.shortStandaloneMonthSymbols.enumerated()), id: \.offset) {
                    monthIndex,
                    monthName in
                    MonthChoiceButton(
                        title: monthName,
                        isSelected: isSelected(month: monthIndex + 1)
                    ) {
                        select(month: monthIndex + 1)
                    }
                    .quickAddPopoverFocus(
                        $focusedItem,
                        equals: .month(monthIndex + 1),
                        shape: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                }
            }
        }
        .padding(10)
        .frame(width: 216)
        .background(Color(nsColor: .windowBackgroundColor))
        .onKeyPress(keys: [.tab]) { keyPress in
            moveFocus(forward: !keyPress.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            guard case let .month(month) = focusedItem else {
                return .ignored
            }

            select(month: month)
            return .handled
        }
        .task {
            focusedItem = .month(calendar.component(.month, from: initialMonth))
        }
    }

    private var yearHeader: some View {
        HStack {
            Spacer()

            TextField(
                "Year",
                value: $year,
                format: .number.grouping(.never)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 58, height: 22)
            .background(
                Color.primary.opacity(focusedItem == .year ? 0.055 : 0),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.08),
                        lineWidth: 0.5
                    )
            }
            .focused($focusedItem, equals: .year)
            .focusEffectDisabled()
            .onKeyPress(keys: [.tab]) { keyPress in
                moveFocus(forward: !keyPress.modifiers.contains(.shift))
                return .handled
            }
            .onSubmit {
                year = min(max(year, 1), 9999)
            }
            .accessibilityLabel("Year")
            .accessibilityValue(String(year))

            Spacer()
        }
        .frame(height: 22)
    }

    private var focusTargets: [FocusTarget] {
        [.year] + (1...12).map(FocusTarget.month)
    }

    private func moveFocus(forward: Bool) {
        focusedItem = nextQuickAddPopoverFocus(
            current: focusedItem,
            initial: .month(calendar.component(.month, from: initialMonth)),
            targets: focusTargets,
            forward: forward
        )
    }

    private func isSelected(month: Int) -> Bool {
        calendar.component(.year, from: initialMonth) == year
            && calendar.component(.month, from: initialMonth) == month
    }

    private func select(month: Int) {
        var components = calendar.dateComponents(
            [.calendar, .timeZone],
            from: initialMonth
        )
        components.year = year
        components.month = month
        components.day = 1

        guard let date = calendar.date(from: components) else {
            return
        }

        onSelect(date)
    }
}

private struct MonthChoiceButton: View {
    @State private var isHovering = false

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? TallyPalette.date : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .background(
                    backgroundColor,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isSelected {
            return TallyPalette.date.opacity(0.14)
        }
        return Color.primary.opacity(isHovering ? 0.055 : 0)
    }
}

private struct MonthNavigationButton: View {
    @State private var isHovering = false

    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8.5, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(
                    Color.primary.opacity(isHovering ? 0.06 : 0),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct TimeEditorPopover: View {
    @FocusState private var focusedItem: FocusTarget?
    @State private var draftDate: Date

    let hasExistingTime: Bool
    let onCancel: () -> Void
    let onRemove: () -> Void
    let onSave: (Date) -> Void

    private enum FocusTarget: Hashable {
        case time
        case preset(Int)
        case remove
        case cancel
        case save
    }

    private let calendar = Calendar.current
    private let presetColumns = Array(
        repeating: GridItem(.flexible(), spacing: 6),
        count: 2
    )
    private let presets = [
        TimePreset(title: "Morning", hour: 9),
        TimePreset(title: "Noon", hour: 12),
        TimePreset(title: "Afternoon", hour: 15),
        TimePreset(title: "Evening", hour: 18),
    ]

    init(
        initialDate: Date,
        hasExistingTime: Bool,
        onCancel: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onSave: @escaping (Date) -> Void
    ) {
        _draftDate = State(initialValue: initialDate)
        self.hasExistingTime = hasExistingTime
        self.onCancel = onCancel
        self.onRemove = onRemove
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("Time")
                        .font(.system(size: 12.5, weight: .semibold))

                    Spacer(minLength: 12)

                    TimeStepperField(date: $draftDate)
                    .fixedSize()
                    .focused($focusedItem, equals: .time)
                    .focusEffectDisabled()
                    .accessibilityLabel("Time")
                }

                LazyVGrid(columns: presetColumns, spacing: 6) {
                    ForEach(presets) { preset in
                        TimePresetButton(
                            title: preset.title,
                            time: displayTime(date(forHour: preset.hour)),
                            isSelected: isSelected(preset)
                        ) {
                            apply(preset)
                        }
                        .quickAddPopoverFocus(
                            $focusedItem,
                            equals: .preset(preset.hour),
                            shape: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                    }
                }
            }
            .padding(12)

            Divider()

            HStack(spacing: 8) {
                if hasExistingTime {
                    Button("Remove Time", action: onRemove)
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                        .quickAddPopoverFocus(
                            $focusedItem,
                            equals: .remove,
                            shape: Capsule()
                        )
                }

                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 6))
                    .controlSize(.small)
                    .quickAddPopoverFocus(
                        $focusedItem,
                        equals: .cancel,
                        shape: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 6))
                    .controlSize(.small)
                    .tint(TallyPalette.date)
                    .keyboardShortcut(.defaultAction)
                    .quickAddPopoverFocus(
                        $focusedItem,
                        equals: .save,
                        shape: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
        }
        .frame(width: 268)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: onCancel)
        .onKeyPress(keys: [.tab]) { keyPress in
            moveFocus(forward: !keyPress.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            switch focusedItem {
            case let .preset(hour):
                guard let preset = presets.first(where: { $0.hour == hour }) else {
                    return .ignored
                }
                apply(preset)
            case .remove:
                onRemove()
            case .cancel:
                onCancel()
            case .save:
                save()
            case .time, nil:
                return .ignored
            }

            return .handled
        }
        .task {
            focusedItem = .time
        }
    }

    private var focusTargets: [FocusTarget] {
        var targets: [FocusTarget] = [.time]
        targets.append(contentsOf: presets.map { .preset($0.hour) })
        if hasExistingTime {
            targets.append(.remove)
        }
        targets.append(contentsOf: [.cancel, .save])
        return targets
    }

    private func moveFocus(forward: Bool) {
        focusedItem = nextQuickAddPopoverFocus(
            current: focusedItem,
            initial: .time,
            targets: focusTargets,
            forward: forward
        )
    }

    private func apply(_ preset: TimePreset) {
        draftDate = date(forHour: preset.hour)
    }

    private func date(forHour hour: Int) -> Date {
        var components = calendar.dateComponents(
            [.calendar, .timeZone, .year, .month, .day],
            from: draftDate
        )
        components.hour = hour
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? draftDate
    }

    private func isSelected(_ preset: TimePreset) -> Bool {
        calendar.component(.hour, from: draftDate) == preset.hour
            && calendar.component(.minute, from: draftDate) == 0
    }

    private func save() {
        onSave(draftDate)
    }

    private func displayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct TimePreset: Identifiable {
    let title: String
    let hour: Int

    var id: Int { hour }
}

private struct TimeStepperField: NSViewRepresentable {
    @Binding var date: Date

    func makeCoordinator() -> Coordinator {
        Coordinator(date: $date)
    }

    func makeNSView(context: Context) -> PickerContainer {
        let container = PickerContainer()
        let picker = container.picker
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.datePickerMode = .single
        picker.controlSize = .regular
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.dateValue = date
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        picker.setAccessibilityLabel("Time")
        container.updateColors()
        return container
    }

    func updateNSView(_ container: PickerContainer, context: Context) {
        let picker = container.picker
        context.coordinator.date = $date
        picker.locale = .current
        picker.calendar = .current
        picker.timeZone = .current

        if picker.dateValue != date {
            picker.dateValue = date
        }

        container.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: PickerContainer,
        context: Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class PickerContainer: NSView {
        static let leadingInset: CGFloat = 6

        let picker = NSDatePicker()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.borderWidth = 0.5
            layer?.masksToBounds = true
            addSubview(picker)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            let pickerSize = picker.intrinsicContentSize
            return NSSize(
                width: pickerSize.width + Self.leadingInset,
                height: pickerSize.height
            )
        }

        override func layout() {
            super.layout()
            picker.frame = NSRect(
                x: Self.leadingInset,
                y: 0,
                width: max(0, bounds.width - Self.leadingInset),
                height: bounds.height
            )
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateColors()
        }

        func updateColors() {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor
                .withAlphaComponent(0.7)
                .cgColor
        }
    }

    final class Coordinator: NSObject {
        var date: Binding<Date>

        init(date: Binding<Date>) {
            self.date = date
        }

        @objc
        func dateChanged(_ sender: NSDatePicker) {
            date.wrappedValue = sender.dateValue
        }
    }
}

private struct TimePresetButton: View {
    @State private var isHovering = false

    let title: String
    let time: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? TallyPalette.date : Color.primary)

                Text(time)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 37)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(time)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isSelected {
            return TallyPalette.date.opacity(0.14)
        }
        return Color.primary.opacity(isHovering ? 0.055 : 0.035)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents(
            [.calendar, .timeZone, .year, .month],
            from: date
        )
        return self.date(from: components) ?? date
    }
}
