import SwiftUI

struct DueDatePickerPopover: View {
    @State private var selectedDate: Date
    @State private var visibleMonth: Date
    @State private var includesTime: Bool
    @State private var hour: Int
    @State private var minute: Int
    @FocusState private var focusedDay: Date?

    let initialComponents: DateComponents?
    let onCancel: () -> Void
    let onClear: () -> Void
    let onDone: (QuickAddDueDateSelection) -> Void

    private let calendar = Calendar.current
    private let weekdayColumns = Array(repeating: GridItem(.fixed(29), spacing: 2), count: 7)

    init(
        initialComponents: DateComponents?,
        onCancel: @escaping () -> Void,
        onClear: @escaping () -> Void,
        onDone: @escaping (QuickAddDueDateSelection) -> Void
    ) {
        let calendar = Calendar.current
        let fallbackDate = Date()
        let initialDate = initialComponents.flatMap { calendar.date(from: $0) } ?? fallbackDate
        let defaultTime = Self.roundedDefaultTime(from: fallbackDate, calendar: calendar)
        let initialHour = initialComponents?.hour ?? defaultTime.hour
        let initialMinute = initialComponents?.minute ?? defaultTime.minute

        self.initialComponents = initialComponents
        self.onCancel = onCancel
        self.onClear = onClear
        self.onDone = onDone
        _selectedDate = State(initialValue: initialDate)
        _visibleMonth = State(initialValue: calendar.startOfMonth(for: initialDate))
        _includesTime = State(initialValue: initialComponents?.hour != nil || initialComponents?.minute != nil)
        _hour = State(initialValue: initialHour)
        _minute = State(initialValue: initialMinute)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            calendarHeader
            weekdayHeader
            calendarGrid
            Divider()
                .opacity(0.45)
            timeSection
            Divider()
                .opacity(0.45)
            footer
        }
        .padding(10)
        .frame(width: 240)
        .onAppear {
            DispatchQueue.main.async {
                focusedDay = calendar.startOfDay(for: selectedDate)
            }
        }
    }

    private var calendarHeader: some View {
        HStack(spacing: 8) {
            PickerIconButton(systemName: "chevron.left", accessibilityLabel: "Previous month") {
                moveMonth(by: -1)
            }

            Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())

            TodayHeaderButton(action: selectToday)

            PickerIconButton(systemName: "chevron.right", accessibilityLabel: "Next month") {
                moveMonth(by: 1)
            }
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: weekdayColumns, spacing: 2) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 29, height: 12)
            }
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: weekdayColumns, spacing: 2) {
            ForEach(calendarDays) { day in
                CalendarDayButton(
                    day: day,
                    isSelected: calendar.isDate(day.date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(day.date),
                    focusedDay: $focusedDay
                ) {
                    selectedDate = preservingTime(from: selectedDate, on: day.date)
                    focusedDay = calendar.startOfDay(for: day.date)
                    if !calendar.isDate(day.date, equalTo: visibleMonth, toGranularity: .month) {
                        visibleMonth = calendar.startOfMonth(for: day.date)
                    }
                }
            }
        }
    }

    private var timeSection: some View {
        HStack(spacing: 6) {
            Label("Time", systemImage: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Toggle("Include time", isOn: $includesTime)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)

            Spacer(minLength: 2)

            if includesTime {
                editableTimeControls
                    .transition(.opacity)
            } else {
                Text("No time")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.12), value: includesTime)
    }

    private var editableTimeControls: some View {
        HStack(spacing: 3) {
            TextField("Hour", value: hour12Binding, formatter: Self.hourFormatter)
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 31)
                .accessibilityLabel("Hour")

            timeSeparator

            TextField("Minute", value: minuteBinding, formatter: Self.minuteFormatter)
                .textFieldStyle(.roundedBorder)
                .controlSize(.mini)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 34)
                .accessibilityLabel("Minute")

            Picker("Meridiem", selection: meridiemBinding) {
                Text("AM").tag(Meridiem.am)
                Text("PM").tag(Meridiem.pm)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.mini)
            .frame(width: 48)
        }
    }

    private var timeSeparator: some View {
        Text(":")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Clear") {
                onClear()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(initialComponents == nil ? "Dismiss without a date" : "Clear due date")

            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button("Done") {
                onDone(QuickAddDueDateSelection(date: selectedDateWithTime, includesTime: includesTime))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
        .font(.system(size: 11, weight: .medium))
        .frame(height: 24)
    }

    private var selectedDateWithTime: Date {
        var components = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day], from: selectedDate)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? selectedDate
    }

    private var hour12Binding: Binding<Int> {
        Binding(
            get: {
                let value = hour % 12
                return value == 0 ? 12 : value
            },
            set: { newValue in
                let clamped = min(max(newValue, 1), 12)
                switch meridiem {
                case .am:
                    hour = clamped == 12 ? 0 : clamped
                case .pm:
                    hour = clamped == 12 ? 12 : clamped + 12
                }
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { minute },
            set: { newValue in
                minute = min(max(newValue, 0), 59)
            }
        )
    }

    private var meridiemBinding: Binding<Meridiem> {
        Binding(
            get: { meridiem },
            set: { newValue in
                if newValue == .am, hour >= 12 {
                    hour -= 12
                } else if newValue == .pm, hour < 12 {
                    hour += 12
                }
            }
        )
    }

    private var meridiem: Meridiem {
        hour < 12 ? .am : .pm
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var calendarDays: [CalendarDay] {
        let monthStart = calendar.startOfMonth(for: visibleMonth)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }

            return CalendarDay(
                date: date,
                dayNumber: calendar.component(.day, from: date),
                isInVisibleMonth: calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month)
            )
        }
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: visibleMonth) else {
            return
        }

        visibleMonth = calendar.startOfMonth(for: month)
    }

    private func selectToday() {
        let today = Date()
        selectedDate = preservingTime(from: selectedDate, on: today)
        visibleMonth = calendar.startOfMonth(for: today)
    }

    private func preservingTime(from source: Date, on date: Date) -> Date {
        var components = calendar.dateComponents([.calendar, .timeZone, .year, .month, .day], from: date)
        components.hour = calendar.component(.hour, from: source)
        components.minute = calendar.component(.minute, from: source)
        return calendar.date(from: components) ?? date
    }

    private static func roundedDefaultTime(
        from date: Date,
        calendar: Calendar
    ) -> (hour: Int, minute: Int) {
        let minute = calendar.component(.minute, from: date)
        let remainder = minute % 15
        let minutesToAdd = remainder == 0 ? 0 : 15 - remainder
        let roundedDate = calendar.date(byAdding: .minute, value: minutesToAdd, to: date) ?? date

        return (
            calendar.component(.hour, from: roundedDate),
            calendar.component(.minute, from: roundedDate)
        )
    }

    private static let hourFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 12
        formatter.minimumIntegerDigits = 1
        formatter.maximumIntegerDigits = 2
        return formatter
    }()

    private static let minuteFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = 59
        formatter.minimumIntegerDigits = 2
        formatter.maximumIntegerDigits = 2
        return formatter
    }()
}

private struct CalendarDay: Identifiable {
    var date: Date
    var dayNumber: Int
    var isInVisibleMonth: Bool

    var id: Date { date }
}

private struct CalendarDayButton: View {
    @State private var isHovering = false

    let day: CalendarDay
    let isSelected: Bool
    let isToday: Bool
    let focusedDay: FocusState<Date?>.Binding
    let action: () -> Void

    private var isFocused: Bool {
        focusedDay.wrappedValue.map { Calendar.current.isDate($0, inSameDayAs: day.date) } ?? false
    }

    var body: some View {
        Button(action: action) {
            Text("\(day.dayNumber)")
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(foregroundStyle)
                .frame(width: 22, height: 22)
                .background(backgroundStyle, in: Circle())
                .overlay {
                    ZStack {
                        Circle()
                            .stroke(todayStrokeStyle, lineWidth: isToday && !isSelected ? 1 : 0)

                        Circle()
                            .stroke(focusStrokeStyle, lineWidth: isFocused ? 1.5 : 0)
                    }
                }
                .frame(width: 29, height: 22)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused(focusedDay, equals: Calendar.current.startOfDay(for: day.date))
        .focusEffectDisabled()
        .onKeyPress(keys: [.space, .return]) { _ in
            action()
            return .handled
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
    }

    private var foregroundStyle: Color {
        if isSelected {
            return .white
        }

        if day.isInVisibleMonth {
            return .primary
        }

        return .secondary.opacity(0.58)
    }

    private var backgroundStyle: Color {
        if isSelected {
            return .accentColor
        }

        if isHovering {
            return .secondary.opacity(0.14)
        }

        return .clear
    }

    private var todayStrokeStyle: Color {
        .accentColor.opacity(day.isInVisibleMonth ? 0.7 : 0.35)
    }

    private var focusStrokeStyle: Color {
        isSelected ? .white.opacity(0.92) : .accentColor.opacity(0.88)
    }
}

private struct PickerIconButton: View {
    @State private var isHovering = false

    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .background(iconBackgroundStyle, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .contentShape(Circle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconBackgroundStyle: Color {
        isHovering ? Color.secondary.opacity(0.12) : Color.clear
    }
}

private struct TodayHeaderButton: View {
    @State private var isHovering = false

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Today")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(backgroundStyle, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
        .help("Jump to today")
        .accessibilityLabel("Jump to today")
    }

    private var backgroundStyle: Color {
        Color.accentColor.opacity(isHovering ? 0.16 : 0.10)
    }
}

private enum Meridiem {
    case am
    case pm
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.calendar, .timeZone, .year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
