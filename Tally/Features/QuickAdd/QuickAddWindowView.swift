import SwiftUI

struct QuickAddWindowView: View {
    @EnvironmentObject private var reminderStore: ReminderStore
    @State private var quickAddText = ""
    @State private var notes = ""
    @State private var isShowingTokenHelp = false
    @State private var keepsOpenAfterAdd = false
    @State private var suppressedInferredTokens: [QuickAddSuppressedToken] = []

    let onCancel: () -> Void
    let onSubmit: (String, String, Bool) -> Void

    private var parsedPreview: QuickAddFields {
        QuickAddParser.parse(quickAddText, suppressedInferredTokens: suppressedInferredTokens)
    }

    private let supportedNLPHelp = """
    Supported tokens: today, tomorrow, tom, tod, tmr, today 3pm, today at 3:30pm, 6pm, fri at 7pm, jan 27, 27 jan, 27th, 1/27, in 45 minutes, in three days, in a couple of days, in half an hour, +5 days, 17 days from jul 9, 6 weeks before jul 21, in 3 days, next week, next month, this weekend, next weekend, later this week, later today, tonight, this afternoon, #List, @tag, // notes, P1, P2, P3, P4.
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HighlightedQuickAddTextField(
                    text: $quickAddText,
                    tokens: parsedPreview.usedTokens,
                    placeholder: "New reminder",
                    onSubmit: addReminder,
                    onEscape: handleEscape
                )
                .frame(height: 25)

                TextField("Notes", text: $notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1...3)

                QuickAddPreview(fields: parsedPreview, fallbackListTitle: reminderStore.activeListTitle)
                    .environmentObject(reminderStore)
                    .onInsertToken(insertToken)
                    .onSelectDate(setDueDate)
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .frame(height: 118, alignment: .top)

            Divider()

            HStack(spacing: 8) {
                Button {
                    isShowingTokenHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .onHover { isHovering in
                    isShowingTokenHelp = isHovering
                }
                .popover(isPresented: $isShowingTokenHelp, arrowEdge: .bottom) {
                    TokenHelpView(helpText: supportedNLPHelp)
                }
                .accessibilityLabel("Supported quick add tokens")

                Spacer()

                Toggle("Keep open", isOn: $keepsOpenAfterAdd)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Add task", action: addReminder)
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedPreview.title.isEmpty || reminderStore.isSaving)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 14)
            .frame(height: 57)
            .background(.regularMaterial)
        }
        .frame(width: 520, height: 176)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .onChange(of: quickAddText) { _, newValue in
            suppressedInferredTokens = suppressedInferredTokens.filter { suppression in
                guard NSMaxRange(suppression.range) <= (newValue as NSString).length else {
                    return false
                }

                return (newValue as NSString).substring(with: suppression.range) == suppression.text
            }
        }
    }

    private func addReminder() {
        let draft = quickAddText
        let noteDraft = notes

        guard !QuickAddParser.parse(draft).title.isEmpty else {
            return
        }

        quickAddText = ""
        notes = ""
        suppressedInferredTokens = []
        onSubmit(draft, noteDraft, keepsOpenAfterAdd)
    }

    private func handleEscape(selectedRange: NSRange) -> Bool {
        if dismissInferredToken(at: selectedRange) {
            return true
        }

        onCancel()
        return true
    }

    private func dismissInferredToken(at selectedRange: NSRange) -> Bool {
        let token = parsedPreview.usedTokens.first { token in
            guard token.source == .inferred,
                  token.kind == .date || token.kind == .time else {
                return false
            }

            if selectedRange.length > 0 {
                return NSIntersectionRange(token.range, selectedRange).length > 0
            }

            return NSLocationInRange(selectedRange.location, token.range) ||
                selectedRange.location == NSMaxRange(token.range)
        }

        guard let token,
              NSMaxRange(token.range) <= (quickAddText as NSString).length else {
            return false
        }

        suppressedInferredTokens.append(QuickAddSuppressedToken(
            kind: token.kind,
            range: token.range,
            text: (quickAddText as NSString).substring(with: token.range)
        ))
        return true
    }

    private func insertToken(_ token: String) {
        let separator = quickAddText.isEmpty || quickAddText.hasSuffix(" ") ? "" : " "
        quickAddText += separator + token
    }

    private func setDueDate(_ date: Date) {
        let token = Self.dateToken(for: date)
        let fields = QuickAddParser.parse(quickAddText)

        if let existingDateToken = fields.usedTokens.first(where: { $0.kind == .date }),
           let range = Range(existingDateToken.range, in: quickAddText) {
            quickAddText.replaceSubrange(range, with: token)
        } else {
            insertToken(token)
        }
    }

    private static func dateToken(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 1

        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private struct TokenHelpView: View {
    let helpText: String
    
    var body: some View {
        Text(helpText)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(width: 280, alignment: .leading)
    }
}

private struct QuickAddPreview: View {
    @EnvironmentObject private var reminderStore: ReminderStore
    @Environment(\.insertQuickAddToken) private var insertToken
    @Environment(\.selectQuickAddDate) private var selectDate

    let fields: QuickAddFields
    let fallbackListTitle: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                DatePickerChip(fields: fields, onSelectDate: selectDate)

                Menu {
                    ForEach(reminderStore.reminderListTitles, id: \.self) { listTitle in
                        Button(listTitle) { insertToken("#\(QuickAddListTokenCodec.encode(listTitle))") }
                    }
                } label: {
                    Chip(
                        systemName: "tray",
                        title: fields.listName ?? fallbackListTitle,
                        tint: .purple,
                        isPlaceholder: fields.listName == nil
                    )
                }
                .menuStyle(.borderlessButton)

                Menu {
                    Button("P1") { insertToken("P1") }
                    Button("P2") { insertToken("P2") }
                    Button("P3") { insertToken("P3") }
                    Button("None") { insertToken("P4") }
                } label: {
                    Chip(
                        systemName: "flag.fill",
                        title: fields.priority > 0 ? fields.priority.quickAddTitle : "Priority",
                        tint: .red,
                        isPlaceholder: fields.priority == 0
                    )
                }
                .menuStyle(.borderlessButton)

                if fields.tags.isEmpty {
                    Button {
                        insertToken("@")
                    } label: {
                        Chip(systemName: "tag.fill", title: "Tag", tint: .orange, isPlaceholder: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(fields.tags, id: \.self) { tag in
                        Chip(systemName: "tag.fill", title: tag, tint: .orange)
                    }
                }
            }
            .frame(height: 27)
        }
        .frame(height: 27)
    }
}

private struct DatePickerChip: View {
    @State private var isShowingPicker = false

    let fields: QuickAddFields
    let onSelectDate: (Date) -> Void

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            Chip(
                systemName: "calendar",
                title: fields.dueDate?.shortDisplayTitle ?? "Date",
                tint: .green,
                isPlaceholder: fields.dueDate == nil
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            DatePicker(
                "Due date",
                selection: Binding(
                    get: { selectedDate },
                    set: { date in
                        onSelectDate(date)
                        isShowingPicker = false
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(12)
        }
    }

    private var selectedDate: Date {
        guard let dueDate = fields.dueDate,
              let date = Calendar.current.date(from: dueDate)
        else {
            return Date()
        }

        return date
    }
}

private struct Chip: View {
    let systemName: String
    let title: String
    let tint: Color
    var isPlaceholder = false

    var body: some View {
        Label(title, systemImage: systemName)
            .font(.system(size: 12, weight: .medium))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(foregroundStyle)
    }

    private var backgroundStyle: Color {
        isPlaceholder ? .secondary.opacity(0.10) : tint.opacity(0.14)
    }

    private var foregroundStyle: Color {
        isPlaceholder ? .secondary : tint
    }
}

private struct InsertQuickAddTokenKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}

private struct SelectQuickAddDateKey: EnvironmentKey {
    static let defaultValue: (Date) -> Void = { _ in }
}

private extension EnvironmentValues {
    var insertQuickAddToken: (String) -> Void {
        get { self[InsertQuickAddTokenKey.self] }
        set { self[InsertQuickAddTokenKey.self] = newValue }
    }

    var selectQuickAddDate: (Date) -> Void {
        get { self[SelectQuickAddDateKey.self] }
        set { self[SelectQuickAddDateKey.self] = newValue }
    }
}

private extension View {
    func onInsertToken(_ action: @escaping (String) -> Void) -> some View {
        environment(\.insertQuickAddToken, action)
    }

    func onSelectDate(_ action: @escaping (Date) -> Void) -> some View {
        environment(\.selectQuickAddDate, action)
    }
}
