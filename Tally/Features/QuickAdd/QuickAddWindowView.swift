import SwiftUI

enum QuickAddFocusTarget: Hashable {
    case dueDate
    case eventLength
    case list
    case priority
    case tag
    case help
    case keepOpen
    case cancel
    case submit
}

struct QuickAddWindowView: View {
    private static let titleBaseHeight: CGFloat = 28
    private static let notesBaseHeight: CGFloat = 24

    @EnvironmentObject private var reminderStore: ReminderStore
    @EnvironmentObject private var calendarEventStore: CalendarEventStore
    @ObservedObject var draft: QuickAddDraft
    @FocusState private var focusedControl: QuickAddFocusTarget?
    @State private var activePopover: QuickAddPopoverKind?
    @State private var titleEditorHeight = titleBaseHeight
    @State private var notesEditorHeight = notesBaseHeight

    let onCancel: () -> Void
    let onSubmit: (QuickAddSubmission) -> Void
    let onCalendarAccessAction: () -> Void
    let onPreferredHeightChange: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 0) {
            composer

            Divider()
                .opacity(0.58)

            footer
        }
        .frame(
            width: TallyChrome.quickAddPanelSize.width,
            height: preferredPanelHeight
        )
        .background(TallyPanelBackdrop())
        .clipShape(panelShape)
        .overlay {
            panelShape
                .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .onExitCommand(perform: handleExitCommand)
        .onAppear {
            onPreferredHeightChange(preferredPanelHeight)
        }
        .onChange(of: preferredPanelHeight) { _, height in
            onPreferredHeightChange(height)
        }
    }

    private var preferredPanelHeight: CGFloat {
        TallyChrome.quickAddPanelSize.height
            + titleEditorHeight - Self.titleBaseHeight
            + notesEditorHeight - Self.notesBaseHeight
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: TallyChrome.panelCornerRadius, style: .continuous)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            QuickAddModePicker(mode: draft.mode, onSelect: selectMode)
                .padding(.bottom, 10)

            HighlightedQuickAddTextField(
                text: $draft.text,
                selectedRangeRequest: $draft.selectedRangeRequest,
                measuredHeight: $titleEditorHeight,
                tokens: draft.fields.usedTokens,
                placeholder: draft.mode == .event ? "New Event" : "New Reminder",
                onSubmit: submit,
                onEscape: handleEscape,
                onForwardTab: draft.focusNotes,
                onBackwardTab: {
                    focusedControl = draft.canSubmit ? .submit : .cancel
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: titleEditorHeight)

            QuickAddNotesField(
                text: $draft.notes,
                measuredHeight: $notesEditorHeight,
                focusRequestID: draft.notesFocusRequestID,
                onSubmit: submit,
                onForwardTab: {
                    focusedControl = .dueDate
                },
                onBackwardTab: draft.focusTitleAtEnd
            )
            .frame(maxWidth: .infinity)
            .frame(height: notesEditorHeight)
            .padding(.top, 7)

            if needsCalendarAccess {
                QuickAddCalendarAccessBanner(
                    accessState: calendarEventStore.accessState,
                    onAction: onCalendarAccessAction
                )
                .padding(.top, 11)
            } else {
                QuickAddMetadataBar(
                    mode: draft.mode,
                    fields: draft.fields,
                    fallbackList: fallbackList,
                    lists: draft.mode == .event
                        ? calendarEventStore.calendars
                        : reminderStore.reminderLists,
                    reminderDayCounts: draft.mode == .event ? [:] : reminderDayCounts,
                    activePopover: $activePopover,
                    focusedControl: $focusedControl,
                    onFocusTitle: draft.focusTitleAtEnd,
                    onApplyDueDate: draft.applyDueDate,
                    onApplyEventLength: draft.applyEventLength,
                    onSelectList: draft.selectList,
                    onUseDefaultList: draft.useDefaultList,
                    onApplyPriority: draft.applyPriority,
                    onAddTag: draft.addTagEntry,
                    onEditTag: draft.editTag,
                    onRemoveTag: draft.removeTag
                )
                .padding(.top, 11)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var feedbackLine: some View {
        if let errorMessage = draft.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Could not add \(draft.mode == .event ? "event" : "reminder"): \(errorMessage)")
                .font(.system(size: 11.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        } else if let confirmationMessage = draft.confirmationMessage {
            Label(confirmationMessage, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if hasFeedback {
                feedbackLine
                    .frame(maxWidth: 300, alignment: .leading)
            } else {
                helpButton
                keepOpenButton
            }

            Spacer(minLength: 12)

            Button(action: onCancel) {
                Text("Cancel")
            }
            .buttonStyle(QuickAddFooterButtonStyle(kind: .secondary))
            .quickAddFocus(
                $focusedControl,
                equals: .cancel,
                shape: Capsule()
            )
            .quickAddKeyboardActivation(onCancel)

            Button(action: submit) {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.mini)
                    }

                    Text(submitTitle)
                }
            }
            .buttonStyle(QuickAddFooterButtonStyle(kind: .primary))
            .quickAddFocus(
                $focusedControl,
                equals: .submit,
                shape: Capsule(),
                isEnabled: canSubmit
            )
            .quickAddKeyboardActivation(submit)
            .disabled(!canSubmit)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .frame(height: TallyChrome.quickAddFooterHeight)
    }

    private var helpButton: some View {
        Button {
            togglePopover(.help)
        } label: {
            Label("Help", systemImage: "questionmark")
        }
        .buttonStyle(QuickAddFooterButtonStyle(
            kind: .utility(isActive: activePopover == .help)
        ))
        .quickAddFocus(
            $focusedControl,
            equals: .help,
            shape: Capsule()
        )
        .quickAddKeyboardActivation {
            togglePopover(.help)
        }
        .popover(isPresented: presentationBinding(for: .help), arrowEdge: .bottom) {
            QuickAddHelpPopover(mode: draft.mode)
                .onExitCommand {
                    activePopover = nil
                }
        }
        .accessibilityLabel("Quick Add help")
        .restoreQuickAddFocus(when: activePopover == .help, to: .help, using: $focusedControl)
    }

    private var keepOpenButton: some View {
        Button {
            draft.keepsOpenAfterAdd.toggle()
        } label: {
            Label(
                "Keep open",
                systemImage: draft.keepsOpenAfterAdd ? "pin.fill" : "pin"
            )
        }
        .buttonStyle(QuickAddFooterButtonStyle(
            kind: .utility(isActive: draft.keepsOpenAfterAdd)
        ))
        .quickAddFocus(
            $focusedControl,
            equals: .keepOpen,
            shape: Capsule()
        )
        .quickAddKeyboardActivation {
            draft.keepsOpenAfterAdd.toggle()
        }
        .accessibilityValue(draft.keepsOpenAfterAdd ? "On" : "Off")
        .help("Keep Quick Add open after a successful save")
    }

    private var hasFeedback: Bool {
        draft.errorMessage != nil || draft.confirmationMessage != nil
    }

    private var isSaving: Bool {
        draft.mode == .event ? calendarEventStore.isSaving : reminderStore.isSaving
    }

    private var needsCalendarAccess: Bool {
        draft.mode == .event && calendarEventStore.accessState != .authorized
    }

    private var canSubmit: Bool {
        draft.canSubmit && !isSaving && !needsCalendarAccess
    }

    private var submitTitle: String {
        if isSaving {
            return "Adding…"
        }

        return draft.mode == .event ? "Add Event" : "Add Reminder"
    }

    private var fallbackList: CalendarDestinationInfo {
        if draft.mode == .event {
            return CalendarDestinationInfo(id: "fallback", title: calendarEventStore.defaultCalendarTitle)
        }

        if let preferredList = reminderStore.preferredList(
            for: draft.defaultListIdentifier
        ) {
            return preferredList
        }

        if draft.defaultListIdentifier != nil {
            return CalendarDestinationInfo(id: "unavailable", title: "Unavailable list")
        }

        return CalendarDestinationInfo(id: "fallback", title: reminderStore.activeListTitle)
    }

    private var reminderDayCounts: [Date: Int] {
        let calendar = Calendar.current
        return reminderStore.reminders.reduce(into: [:]) { counts, reminder in
            guard let components = reminder.dueDate,
                  let date = calendar.date(from: components) else {
                return
            }

            counts[calendar.startOfDay(for: date), default: 0] += 1
        }
    }

    private func submit() {
        guard canSubmit, let submission = draft.makeSubmission() else {
            return
        }

        onSubmit(submission)
    }

    private func selectMode(_ mode: QuickAddMode) {
        guard draft.mode != mode else {
            return
        }

        activePopover = nil
        draft.mode = mode

        if mode == .event, calendarEventStore.accessState == .notDetermined {
            onCalendarAccessAction()
        }
    }

    private func handleEscape(selectedRange: NSRange) -> Bool {
        if draft.keepTokenAsText(at: selectedRange) {
            return true
        }

        onCancel()
        return true
    }

    private func handleExitCommand() {
        if activePopover != nil {
            activePopover = nil
        } else {
            onCancel()
        }
    }

    private func togglePopover(_ kind: QuickAddPopoverKind) {
        activePopover = activePopover == kind ? nil : kind
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

/// Switches between creating a reminder and an event. ⌘1 and ⌘2 always pick
/// the same mode, so the shortcut never depends on the current state.
private struct QuickAddModePicker: View {
    let mode: QuickAddMode
    let onSelect: (QuickAddMode) -> Void

    var body: some View {
        HStack(spacing: 2) {
            segment(.reminder, title: "Reminder", systemName: "checklist", key: "1")
            segment(.event, title: "Event", systemName: "calendar", key: "2")
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Type")
    }

    private func segment(
        _ value: QuickAddMode,
        title: String,
        systemName: String,
        key: KeyEquivalent
    ) -> some View {
        let isSelected = mode == value

        return Button {
            onSelect(value)
        } label: {
            Label(title, systemImage: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear,
                    in: Capsule()
                )
                .shadow(color: .black.opacity(isSelected ? 0.12 : 0), radius: 1, y: 0.5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .keyboardShortcut(key, modifiers: .command)
        .help("\(title) (⌘\(key.character))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Shown in Event mode until Tally has full Calendar access.
private struct QuickAddCalendarAccessBanner: View {
    let accessState: EventKitAccessState
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TallyPalette.date)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let actionTitle {
                Button(actionTitle, action: onAction)
                    .controlSize(.small)
            }
        }
        .frame(height: 30)
    }

    private var message: String {
        switch accessState {
        case .notDetermined:
            return "Tally needs Calendar access to add events."
        case .requesting:
            return "Waiting for Calendar access…"
        case .denied:
            return "Tally needs full Calendar access to add events."
        case .authorized:
            return ""
        }
    }

    private var actionTitle: String? {
        switch accessState.availableAction {
        case .request:
            return "Allow Access…"
        case .openSystemSettings:
            return "Open System Settings…"
        case .none:
            return nil
        }
    }
}

private struct QuickAddFooterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    enum Kind {
        case primary
        case secondary
        case utility(isActive: Bool)
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .frame(height: 32)
            .background(
                backgroundColor(isPressed: configuration.isPressed),
                in: Capsule()
            )
            .overlay {
                if showsBorder {
                    Capsule()
                        .strokeBorder(borderColor, lineWidth: 0.5)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.46)
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .primary:
            return 12
        case .secondary:
            return 11
        case .utility:
            return 10
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return Color(nsColor: .alternateSelectedControlTextColor)
        case .secondary:
            return .primary
        case let .utility(isActive):
            return isActive ? TallyPalette.accent : .secondary
        }
    }

    private var showsBorder: Bool {
        switch kind {
        case .primary:
            return false
        case .secondary, .utility:
            return true
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return .clear
        case .secondary:
            return Color.primary.opacity(0.08)
        case let .utility(isActive):
            return isActive
                ? TallyPalette.accent.opacity(0.16)
                : Color.primary.opacity(0.06)
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return TallyPalette.accent.opacity(isPressed ? 0.82 : 1)
        case .secondary:
            return Color.primary.opacity(isPressed ? 0.13 : 0.08)
        case let .utility(isActive):
            if isActive {
                return TallyPalette.accent.opacity(isPressed ? 0.17 : 0.11)
            }

            return Color.primary.opacity(isPressed ? 0.10 : 0.04)
        }
    }
}
