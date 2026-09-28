import SwiftUI

enum QuickAddPopoverKind: Hashable {
    case dueDate
    case eventLength
    case list
    case priority
    case tags
    case help
}

struct QuickAddMetadataBar: View {
    let mode: QuickAddMode
    let fields: QuickAddFields
    let fallbackList: CalendarDestinationInfo
    let lists: [CalendarDestinationInfo]
    let reminderDayCounts: [Date: Int]
    @Binding var activePopover: QuickAddPopoverKind?
    let focusedControl: FocusState<QuickAddFocusTarget?>.Binding
    let onFocusTitle: () -> Void
    let onApplyDueDate: (QuickAddDueDateSelection?) -> Void
    let onApplyEventLength: (QuickAddEventLength) -> Void
    let onSelectList: (CalendarDestinationInfo) -> Void
    let onUseDefaultList: () -> Void
    let onApplyPriority: (Int) -> Void
    let onAddTag: () -> Void
    let onEditTag: (Int) -> Void
    let onRemoveTag: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                QuickAddDateButton(
                    isPresented: presentationBinding(for: .dueDate),
                    dueDate: fields.dueDate,
                    title: dateTitle,
                    isActive: fields.dueDate != nil,
                    reminderDayCounts: reminderDayCounts,
                    focusedControl: focusedControl,
                    onFocusTitle: onFocusTitle,
                    onApply: onApplyDueDate
                )

                if mode == .event, let timing = fields.eventTiming {
                    QuickAddEventLengthButton(
                        isPresented: presentationBinding(for: .eventLength),
                        timing: timing,
                        isActive: fields.usedTokens.contains {
                            $0.kind == .duration || $0.kind == .timeRange
                        },
                        focusedControl: focusedControl,
                        onFocusTitle: onFocusTitle,
                        onSelect: onApplyEventLength
                    )
                }

                QuickAddListButton(
                    isPresented: presentationBinding(for: .list),
                    destination: mode == .event ? .calendar : .reminderList,
                    selectedName: fields.listName,
                    fallbackList: fallbackList,
                    lists: lists,
                    focusedControl: focusedControl,
                    onFocusTitle: onFocusTitle,
                    onSelect: onSelectList,
                    onUseDefault: onUseDefaultList
                )

                if mode == .reminder {
                    QuickAddPriorityButton(
                        isPresented: presentationBinding(for: .priority),
                        priority: fields.priority,
                        focusedControl: focusedControl,
                        onFocusTitle: onFocusTitle,
                        onSelect: onApplyPriority
                    )
                }

                QuickAddTagButton(
                    isPresented: presentationBinding(for: .tags),
                    tags: fields.tags,
                    focusedControl: focusedControl,
                    onAdd: onAddTag,
                    onEdit: onEditTag,
                    onRemove: onRemoveTag
                )

            }
            .frame(height: 30)
        }
        .frame(height: 30)
    }

    private var dateTitle: String {
        if mode == .event, let timing = fields.eventTiming {
            return timing.shortDisplayTitle
        }

        return fields.dueDate?.shortDisplayTitle ?? "Date"
    }

    private func presentationBinding(for kind: QuickAddPopoverKind) -> Binding<Bool> {
        Binding(
            get: { activePopover == kind },
            set: { isPresented in
                activePopover = isPresented ? kind : nil
            }
        )
    }
}

private struct QuickAddDateButton: View {
    @State private var didCompleteSelection = false
    @Binding var isPresented: Bool
    let dueDate: DateComponents?
    let title: String
    let isActive: Bool
    let reminderDayCounts: [Date: Int]
    let focusedControl: FocusState<QuickAddFocusTarget?>.Binding
    let onFocusTitle: () -> Void
    let onApply: (QuickAddDueDateSelection?) -> Void

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            QuickAddMetadataChip(
                systemName: "calendar",
                title: title,
                tint: TallyPalette.date,
                isActive: isActive,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .quickAddFocus(
            focusedControl,
            equals: .dueDate,
            shape: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .quickAddKeyboardActivation {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            DueDatePickerPopover(
                initialComponents: dueDate,
                reminderDayCounts: reminderDayCounts,
                onCancel: { isPresented = false },
                onDone: { selection in
                    didCompleteSelection = true
                    onApply(selection)
                    isPresented = false
                }
            )
            .onExitCommand {
                isPresented = false
            }
        }
        .restoreQuickAddMetadataFocus(
            when: isPresented,
            didCompleteSelection: $didCompleteSelection,
            to: .dueDate,
            using: focusedControl,
            onSelection: onFocusTitle
        )
        .accessibilityLabel("Date")
        .accessibilityValue(title)
    }
}

private struct QuickAddEventLengthButton: View {
    @State private var didCompleteSelection = false
    @Binding var isPresented: Bool
    let timing: CalendarEventTiming
    let isActive: Bool
    let focusedControl: FocusState<QuickAddFocusTarget?>.Binding
    let onFocusTitle: () -> Void
    let onSelect: (QuickAddEventLength) -> Void

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            QuickAddMetadataChip(
                systemName: timing.isAllDay ? "sun.max" : "clock",
                durationMinutes: timing.isAllDay ? nil : timing.durationMinutes,
                title: timing.lengthDisplayTitle,
                tint: TallyPalette.date,
                isActive: isActive,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .quickAddFocus(
            focusedControl,
            equals: .eventLength,
            shape: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .quickAddKeyboardActivation {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            QuickAddEventLengthPopover(timing: timing) { length in
                didCompleteSelection = true
                onSelect(length)
                isPresented = false
            }
            .onExitCommand {
                isPresented = false
            }
        }
        .restoreQuickAddMetadataFocus(
            when: isPresented,
            didCompleteSelection: $didCompleteSelection,
            to: .eventLength,
            using: focusedControl,
            onSelection: onFocusTitle
        )
        .accessibilityLabel("Event length")
        .accessibilityValue(timing.lengthDisplayTitle)
    }
}

/// Where a list chip saves to, which changes its icon and wording.
enum QuickAddDestinationKind {
    case reminderList
    case calendar

    var systemName: String {
        switch self {
        case .reminderList:
            return "tray"
        case .calendar:
            return "calendar.badge.clock"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .reminderList:
            return "Reminder list"
        case .calendar:
            return "Calendar"
        }
    }

    var emptyMessage: String {
        switch self {
        case .reminderList:
            return "No writable lists"
        case .calendar:
            return "No writable calendars"
        }
    }
}

private struct QuickAddListButton: View {
    @State private var didCompleteSelection = false
    @Binding var isPresented: Bool
    let destination: QuickAddDestinationKind
    let selectedName: String?
    let fallbackList: CalendarDestinationInfo
    let lists: [CalendarDestinationInfo]
    let focusedControl: FocusState<QuickAddFocusTarget?>.Binding
    let onFocusTitle: () -> Void
    let onSelect: (CalendarDestinationInfo) -> Void
    let onUseDefault: () -> Void

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            QuickAddMetadataChip(
                systemName: destination.systemName,
                title: selectedName ?? fallbackList.title,
                tint: TallyPalette.list,
                isActive: selectedName != nil,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .quickAddFocus(
            focusedControl,
            equals: .list,
            shape: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .quickAddKeyboardActivation {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            QuickAddListPopover(
                destination: destination,
                selectedName: selectedName,
                fallbackList: fallbackList,
                lists: lists,
                onUseDefault: {
                    didCompleteSelection = true
                    onUseDefault()
                    isPresented = false
                },
                onSelect: { list in
                    didCompleteSelection = true
                    onSelect(list)
                    isPresented = false
                }
            )
            .onExitCommand {
                isPresented = false
            }
        }
        .restoreQuickAddMetadataFocus(
            when: isPresented,
            didCompleteSelection: $didCompleteSelection,
            to: .list,
            using: focusedControl,
            onSelection: onFocusTitle
        )
        .accessibilityLabel(destination.accessibilityLabel)
        .accessibilityValue(selectedName ?? fallbackList.title)
    }
}

private struct QuickAddPriorityButton: View {
    @State private var didCompleteSelection = false
    @Binding var isPresented: Bool
    let priority: Int
    let focusedControl: FocusState<QuickAddFocusTarget?>.Binding
    let onFocusTitle: () -> Void
    let onSelect: (Int) -> Void

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            QuickAddMetadataChip(
                systemName: priority == 0 ? "flag" : "flag.fill",
                title: priority == 0 ? "Priority" : priority.reminderPriorityTitle,
                tint: priority.priorityColor,
                isActive: priority != 0,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .quickAddFocus(
            focusedControl,
            equals: .priority,
            shape: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .quickAddKeyboardActivation {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            QuickAddPriorityPopover(selectedPriority: priority) { value in
                didCompleteSelection = true
                onSelect(value)
                isPresented = false
            }
            .onExitCommand {
                isPresented = false
            }
        }
        .restoreQuickAddMetadataFocus(
            when: isPresented,
            didCompleteSelection: $didCompleteSelection,
            to: .priority,
            using: focusedControl,
            onSelection: onFocusTitle
        )
        .accessibilityLabel("Priority")
        .accessibilityValue(priority.reminderPriorityTitle)
    }
}

private struct QuickAddTagButton: View {
    @State private var didCompleteSelection = false
    @Binding var isPresented: Bool
    let tags: [String]
    let focusedControl: FocusState<QuickAddFocusTarget?>.Binding
    let onAdd: () -> Void
    let onEdit: (Int) -> Void
    let onRemove: (Int) -> Void

    private var title: String {
        switch tags.count {
        case 0: return "Tags"
        case 1: return tags[0]
        default: return "\(tags.count) tags"
        }
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            QuickAddMetadataChip(
                systemName: tags.isEmpty ? "tag" : "tag.fill",
                title: title,
                tint: TallyPalette.tag,
                isActive: !tags.isEmpty,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .quickAddFocus(
            focusedControl,
            equals: .tag,
            shape: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .quickAddKeyboardActivation {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            QuickAddTagPopover(
                tags: tags,
                onAdd: {
                    didCompleteSelection = true
                    onAdd()
                    isPresented = false
                },
                onEdit: { index in
                    didCompleteSelection = true
                    onEdit(index)
                    isPresented = false
                },
                onRemove: onRemove
            )
            .onExitCommand {
                isPresented = false
            }
        }
        .restoreQuickAddMetadataFocus(
            when: isPresented,
            didCompleteSelection: $didCompleteSelection,
            to: .tag,
            using: focusedControl,
            onSelection: {}
        )
        .accessibilityLabel("Tags")
        .accessibilityValue(tags.isEmpty ? "None" : tags.joined(separator: ", "))
    }
}

private struct QuickAddMetadataChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemName: String
    /// Draws a dial filled to this length instead of the symbol.
    var durationMinutes: Int? = nil
    let title: String
    let tint: Color
    let isActive: Bool
    var showsChevron = false

    var body: some View {
        HStack(spacing: 6) {
            QuickAddRowIcon(systemName: systemName, durationMinutes: durationMinutes)
                .font(.system(size: 11.5, weight: .semibold))

            Text(title)
                .lineLimit(1)

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isActive ? tint : .secondary)
        .padding(.horizontal, 9)
        .frame(height: 29)
        .background(
            isActive ? tint.opacity(colorScheme == .dark ? 0.17 : 0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    isActive ? tint.opacity(0.18) : Color.primary.opacity(0.12),
                    lineWidth: 0.5
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct QuickAddListPopover: View {
    @FocusState private var focusedItem: FocusTarget?

    let destination: QuickAddDestinationKind
    let selectedName: String?
    let fallbackList: CalendarDestinationInfo
    let lists: [CalendarDestinationInfo]
    let onUseDefault: () -> Void
    let onSelect: (CalendarDestinationInfo) -> Void

    private enum FocusTarget: Hashable {
        case useDefault
        case list(String)
    }

    var body: some View {
        QuickAddPopoverPanel(width: 238) {
            Button(action: onUseDefault) {
                QuickAddPopoverRow(
                    systemName: "wand.and.stars",
                    title: "Default · \(fallbackList.title)",
                    tint: TallyPalette.list,
                    isSelected: selectedName == nil
                )
            }
            .buttonStyle(.plain)
            .quickAddPopoverFocus($focusedItem, equals: .useDefault)

            Divider().padding(.vertical, 3)

            if lists.isEmpty {
                Text(destination.emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(9)
            } else {
                ForEach(lists) { list in
                    Button {
                        onSelect(list)
                    } label: {
                        QuickAddPopoverRow(
                            systemName: destination.systemName,
                            title: list.title,
                            subtitle: list.sourceTitle,
                            tint: TallyPalette.list,
                            isSelected: selectedName?.localizedCaseInsensitiveCompare(list.title) == .orderedSame
                        )
                    }
                    .buttonStyle(.plain)
                    .quickAddPopoverFocus($focusedItem, equals: .list(list.id))
                }
            }
        }
        .onKeyPress(keys: [.tab]) { keyPress in
            moveFocus(forward: !keyPress.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            switch focusedItem {
            case .useDefault:
                onUseDefault()
            case let .list(id):
                guard let list = lists.first(where: { $0.id == id }) else {
                    return .ignored
                }
                onSelect(list)
            case nil:
                return .ignored
            }

            return .handled
        }
        .task {
            focusedItem = initialFocusTarget
        }
    }

    private var focusTargets: [FocusTarget] {
        [.useDefault] + lists.map { .list($0.id) }
    }

    private var initialFocusTarget: FocusTarget {
        guard let selectedName,
              let selectedList = lists.first(where: {
                  $0.title.localizedCaseInsensitiveCompare(selectedName) == .orderedSame
              })
        else {
            return .useDefault
        }

        return .list(selectedList.id)
    }

    private func moveFocus(forward: Bool) {
        focusedItem = nextQuickAddPopoverFocus(
            current: focusedItem,
            initial: initialFocusTarget,
            targets: focusTargets,
            forward: forward
        )
    }
}

private struct QuickAddEventLengthPopover: View {
    @FocusState private var focusedOption: QuickAddEventLength?

    let timing: CalendarEventTiming
    let onSelect: (QuickAddEventLength) -> Void

    private static let durations: [QuickAddEventDuration] = [
        .minutes(15), .minutes(30), .minutes(45), .minutes(60), .minutes(90), .minutes(120)
    ]

    private var options: [QuickAddEventLength] {
        Self.durations.map(QuickAddEventLength.duration) + [.allDay]
    }

    /// Lengths in minutes need a start time, so all-day events only offer all-day.
    private var availableOptions: [QuickAddEventLength] {
        timing.isAllDay ? [.allDay] : options
    }

    var body: some View {
        QuickAddPopoverPanel(width: 210) {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    QuickAddPopoverRow(
                        systemName: option == .allDay ? "sun.max" : "clock",
                        durationMinutes: option.minutes,
                        title: option.displayTitle,
                        tint: TallyPalette.date,
                        isSelected: option == timing.selectedLength
                    )
                }
                .buttonStyle(.plain)
                .disabled(!availableOptions.contains(option))
                .opacity(availableOptions.contains(option) ? 1 : 0.4)
                .quickAddPopoverFocus($focusedOption, equals: option)
            }

            if timing.isAllDay {
                Text("Add a time to set a length.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
        }
        .onKeyPress(keys: [.tab]) { keyPress in
            focusedOption = nextQuickAddPopoverFocus(
                current: focusedOption,
                initial: initialFocus,
                targets: availableOptions,
                forward: !keyPress.modifiers.contains(.shift)
            )
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            guard let focusedOption, availableOptions.contains(focusedOption) else {
                return .ignored
            }

            onSelect(focusedOption)
            return .handled
        }
        .task {
            focusedOption = initialFocus
        }
    }

    private var initialFocus: QuickAddEventLength {
        timing.selectedLength.flatMap { availableOptions.contains($0) ? $0 : nil }
            ?? availableOptions[0]
    }
}

private struct QuickAddPriorityPopover: View {
    @FocusState private var focusedPriority: Int?

    let selectedPriority: Int
    let onSelect: (Int) -> Void

    private let priorities = [
        (value: 1, title: "High", syntax: "P1", color: Color.red),
        (value: 5, title: "Medium", syntax: "P2", color: Color.orange),
        (value: 9, title: "Low", syntax: "P3", color: Color.blue),
        (value: 0, title: "None", syntax: "P4", color: Color.secondary)
    ]

    var body: some View {
        QuickAddPopoverPanel(width: 210) {
            ForEach(priorities, id: \.value) { option in
                Button {
                    onSelect(option.value)
                } label: {
                    QuickAddPopoverRow(
                        systemName: option.value == 0 ? "flag" : "flag.fill",
                        title: option.title,
                        subtitle: option.syntax,
                        tint: option.color,
                        isSelected: selectedPriority == option.value
                    )
                }
                .buttonStyle(.plain)
                .quickAddPopoverFocus($focusedPriority, equals: option.value)
            }
        }
        .onKeyPress(keys: [.tab]) { keyPress in
            moveFocus(forward: !keyPress.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            guard let focusedPriority,
                  priorities.contains(where: { $0.value == focusedPriority })
            else {
                return .ignored
            }

            onSelect(focusedPriority)
            return .handled
        }
        .task {
            focusedPriority = selectedPriority
        }
    }

    private func moveFocus(forward: Bool) {
        guard !priorities.isEmpty else {
            return
        }

        let currentIndex = priorities.firstIndex { $0.value == focusedPriority }
            ?? priorities.firstIndex { $0.value == selectedPriority }
            ?? 0
        let offset = forward ? 1 : -1
        let nextIndex = (currentIndex + offset + priorities.count) % priorities.count
        focusedPriority = priorities[nextIndex].value
    }
}

private struct QuickAddTagPopover: View {
    @FocusState private var focusedItem: FocusTarget?

    let tags: [String]
    let onAdd: () -> Void
    let onEdit: (Int) -> Void
    let onRemove: (Int) -> Void

    private enum FocusTarget: Hashable {
        case tag(Int)
        case remove(Int)
        case add
    }

    var body: some View {
        QuickAddPopoverPanel(width: 250) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                HStack(spacing: 6) {
                    Button {
                        onEdit(index)
                    } label: {
                        QuickAddPopoverRow(
                            systemName: "tag.fill",
                            title: tag,
                            tint: TallyPalette.tag,
                            isSelected: false
                        )
                    }
                    .buttonStyle(.plain)
                    .quickAddPopoverFocus($focusedItem, equals: .tag(index))

                    Button {
                        onRemove(index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .quickAddPopoverFocus(
                        $focusedItem,
                        equals: .remove(index),
                        shape: Circle()
                    )
                    .foregroundStyle(.secondary)
                    .help("Remove @\(tag)")
                }
            }

            if !tags.isEmpty {
                Divider().padding(.vertical, 3)
            }

            Button(action: onAdd) {
                QuickAddPopoverRow(
                    systemName: "plus",
                    title: "Add tag",
                    tint: TallyPalette.tag,
                    isSelected: false
                )
            }
            .buttonStyle(.plain)
            .quickAddPopoverFocus($focusedItem, equals: .add)
        }
        .onKeyPress(keys: [.tab]) { keyPress in
            moveFocus(forward: !keyPress.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            switch focusedItem {
            case let .tag(index):
                guard tags.indices.contains(index) else {
                    return .ignored
                }
                onEdit(index)
            case let .remove(index):
                guard tags.indices.contains(index) else {
                    return .ignored
                }
                onRemove(index)
            case .add:
                onAdd()
            case nil:
                return .ignored
            }

            return .handled
        }
        .task {
            focusedItem = initialFocusTarget
        }
        .onChange(of: tags) { _, _ in
            guard !focusTargets.contains(where: { $0 == focusedItem }) else {
                return
            }

            focusedItem = initialFocusTarget
        }
    }

    private var focusTargets: [FocusTarget] {
        tags.indices.flatMap { [.tag($0), .remove($0)] } + [.add]
    }

    private var initialFocusTarget: FocusTarget {
        tags.isEmpty ? .add : .tag(0)
    }

    private func moveFocus(forward: Bool) {
        focusedItem = nextQuickAddPopoverFocus(
            current: focusedItem,
            initial: initialFocusTarget,
            targets: focusTargets,
            forward: forward
        )
    }
}

private struct QuickAddPopoverPanel<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .padding(6)
        }
        .frame(width: width)
        .frame(maxHeight: 270)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct QuickAddPopoverRow: View {
    @State private var isHovering = false

    let systemName: String
    /// Draws a dial filled to this length instead of the symbol.
    var durationMinutes: Int? = nil
    let title: String
    var subtitle: String? = nil
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            QuickAddRowIcon(systemName: systemName, durationMinutes: durationMinutes)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 9)
        .frame(minHeight: subtitle == nil ? 31 : 38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(isHovering ? 0.07 : isSelected ? 0.04 : 0),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovering = $0 }
    }
}

/// An SF Symbol, or a duration dial when a length is given.
private struct QuickAddRowIcon: View {
    let systemName: String
    let durationMinutes: Int?

    var body: some View {
        if let durationMinutes {
            QuickAddDurationDial(minutes: durationMinutes)
        } else {
            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
        }
    }
}

/// A clock face swept like a clock hand: the first hour fills the dial, and a
/// second hour fills the outer ring, so 15 min is a quarter and 1 hr 30 min is
/// a full dial with half a ring.
struct QuickAddDurationDial: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 12

    let minutes: Int

    private var firstHour: Double {
        min(max(Double(minutes), 0), 60) / 60
    }

    private var secondHour: Double {
        min(max(Double(minutes) - 60, 0), 60) / 60
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 1.1)
                .opacity(secondHour > 0 ? 0.35 : 1)

            if secondHour > 0 {
                Circle()
                    .trim(from: 0, to: secondHour)
                    .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            QuickAddDialSweep(fraction: firstHour)
                .padding(2.4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A pie slice starting at 12 o'clock and sweeping clockwise.
private struct QuickAddDialSweep: Shape {
    let fraction: Double

    func path(in rect: CGRect) -> Path {
        guard fraction > 0 else {
            return Path()
        }

        guard fraction < 1 else {
            return Path(ellipseIn: rect)
        }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

struct QuickAddHelpPopover: View {
    let mode: QuickAddMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quick Add")
                .font(.system(size: 13.5, weight: .semibold))
                .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 7) {
                helpRow(
                    icon: "calendar",
                    tint: TallyPalette.date,
                    title: "Date & Time",
                    examples: "today 5 PM · next Friday"
                )
                if mode == .event {
                    helpRow(
                        icon: "clock",
                        tint: TallyPalette.date,
                        title: "Time",
                        examples: "2-3pm · 2pm to 4pm · for 45m"
                    )
                }
                helpRow(
                    icon: mode == .event ? "calendar.badge.clock" : "tray",
                    tint: TallyPalette.list,
                    title: mode == .event ? "Calendar" : "List",
                    examples: "#Work"
                )
                helpRow(
                    icon: "tag",
                    tint: TallyPalette.tag,
                    title: "Tags",
                    examples: "@follow-up"
                )
                if mode == .reminder {
                    helpRow(
                        icon: "flag",
                        tint: TallyPalette.priority,
                        title: "Priority",
                        examples: "P1 High · P2 Medium · P3 Low"
                    )
                }
                helpRow(
                    icon: "text.alignleft",
                    tint: .secondary,
                    title: "Notes",
                    examples: "// details"
                )
                helpRow(
                    icon: "repeat",
                    tint: TallyPalette.date,
                    title: "Repeat",
                    examples: "every Monday · every 2 weeks"
                )
            }

            Divider()
                .padding(.vertical, 10)

            HStack(spacing: 16) {
                keyboardHint(key: "Return", description: "Add")
                keyboardHint(key: "⌘1 ⌘2", description: "Reminder / Event")
                keyboardHint(key: "Esc", description: "Keep text / close")
            }
        }
        .padding(14)
        .frame(width: 400, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func helpRow(
        icon: String,
        tint: Color,
        title: String,
        examples: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 16, height: 16)

            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 70, alignment: .leading)

            Text(examples)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private func keyboardHint(key: String, description: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 9.5, weight: .medium))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.primary.opacity(0.13), lineWidth: 0.5)
                }

            Text(description)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    func quickAddPopoverFocus<Value: Hashable>(
        _ focusedValue: FocusState<Value?>.Binding,
        equals value: Value,
        isEnabled: Bool = true
    ) -> some View {
        quickAddPopoverFocus(
            focusedValue,
            equals: value,
            shape: RoundedRectangle(cornerRadius: 7, style: .continuous),
            isEnabled: isEnabled
        )
    }

    func quickAddPopoverFocus<Value: Hashable, S: InsettableShape>(
        _ focusedValue: FocusState<Value?>.Binding,
        equals value: Value,
        shape _: S,
        isEnabled: Bool = true
    ) -> some View {
        quickAddPopoverFocusState(
            focusedValue,
            equals: value,
            isEnabled: isEnabled
        )
    }

    func quickAddPopoverFocusState<Value: Hashable>(
        _ focusedValue: FocusState<Value?>.Binding,
        equals value: Value,
        isEnabled: Bool = true
    ) -> some View {
        focusable(isEnabled)
            .focused(focusedValue, equals: value)
            .focusEffectDisabled()
    }

    func restoreQuickAddMetadataFocus(
        when isPresented: Bool,
        didCompleteSelection: Binding<Bool>,
        to fallbackTarget: QuickAddFocusTarget,
        using focusedControl: FocusState<QuickAddFocusTarget?>.Binding,
        onSelection: @escaping () -> Void
    ) -> some View {
        onChange(of: isPresented) { _, isPresented in
            guard !isPresented else {
                return
            }

            if didCompleteSelection.wrappedValue {
                didCompleteSelection.wrappedValue = false
                focusedControl.wrappedValue = nil
                DispatchQueue.main.async(execute: onSelection)
            } else {
                focusedControl.wrappedValue = fallbackTarget
            }
        }
    }

    func restoreQuickAddFocus(
        when isPresented: Bool,
        to target: QuickAddFocusTarget,
        using focusedControl: FocusState<QuickAddFocusTarget?>.Binding
    ) -> some View {
        onChange(of: isPresented) { _, isPresented in
            if !isPresented {
                focusedControl.wrappedValue = target
            }
        }
    }

    func quickAddKeyboardActivation(_ action: @escaping () -> Void) -> some View {
        onKeyPress(keys: [.space, .return]) { _ in
            action()
            return .handled
        }
    }

    func quickAddFocus<S: InsettableShape>(
        _ focusedControl: FocusState<QuickAddFocusTarget?>.Binding,
        equals target: QuickAddFocusTarget,
        shape _: S,
        isEnabled: Bool = true
    ) -> some View {
        focusable(isEnabled)
            .focused(focusedControl, equals: target)
            .focusEffectDisabled()
    }
}

func nextQuickAddPopoverFocus<Value: Hashable>(
    current: Value?,
    initial: Value,
    targets: [Value],
    forward: Bool
) -> Value {
    guard !targets.isEmpty else {
        return initial
    }

    let currentIndex = current.flatMap(targets.firstIndex(of:))
        ?? targets.firstIndex(of: initial)
        ?? 0
    let offset = forward ? 1 : -1
    let nextIndex = (currentIndex + offset + targets.count) % targets.count
    return targets[nextIndex]
}
