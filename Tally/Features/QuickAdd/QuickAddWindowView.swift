import SwiftUI

struct QuickAddWindowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var reminderStore: ReminderStore
    @State private var quickAddText = ""
    @State private var notes = ""
    @State private var isShowingTokenHelp = false
    @State private var keepsOpenAfterAdd = false
    @State private var suppressedInferredTokens: [QuickAddSuppressedToken] = []
    @State private var quickAddSelectionRequest: NSRange?

    let onCancel: () -> Void
    let onSubmit: (String, String, Bool, [QuickAddSuppressedToken]) -> Void

    private var parsedPreview: QuickAddFields {
        QuickAddParser.parse(quickAddText, suppressedInferredTokens: suppressedInferredTokens)
    }

    private let supportedNLPHelp = """
    Supported tokens: today, tomorrow, tom, tod, tmr, today 3pm, today at 3:30pm, 6pm, fri at 7pm, jan 27, 27 jan, 27th, 1/27, in 45 minutes, in three days, in a couple of days, in half an hour, +5 days, 17 days from jul 9, 6 weeks before jul 21, in 3 days, next week, next month, this weekend, next weekend, later this week, later today, tonight, this afternoon, #List, @tag, // notes, P1, P2, P3, P4.
    """

    var body: some View {
        quickAddSurface
            .padding(TallyChrome.quickAddShadowPadding)
            .frame(width: TallyChrome.quickAddPanelSize.width, height: TallyChrome.quickAddPanelSize.height)
        .onChange(of: quickAddText) { _, newValue in
            suppressedInferredTokens = suppressedInferredTokens.filter { suppression in
                guard NSMaxRange(suppression.range) <= (newValue as NSString).length else {
                    return false
                }

                return (newValue as NSString).substring(with: suppression.range) == suppression.text
            }
        }
    }

    private var quickAddSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 11) {
                HighlightedQuickAddTextField(
                    text: $quickAddText,
                    selectedRangeRequest: $quickAddSelectionRequest,
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

                QuickAddPreview(
                    fields: parsedPreview,
                    fallbackListTitle: reminderStore.activeListTitle,
                    onApplyDueDateSelection: applyDueDateSelection,
                    onApplyListSelection: applyListSelection,
                    onApplyPrioritySelection: applyPrioritySelection,
                    onAddTagEntry: addTagEntry,
                    onEditTag: editTag,
                    onRemoveTag: removeTag
                )
                    .environmentObject(reminderStore)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .frame(height: 129, alignment: .top)

            Divider()
                .overlay(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08))

            HStack(spacing: 8) {
                Button {
                    isShowingTokenHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(.secondary.opacity(isShowingTokenHelp ? 0.12 : 0), in: Circle())
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
                    .tallySecondaryButtonStyle()
                    .keyboardShortcut(.cancelAction)

                Button(action: addReminder) {
                    HStack(spacing: 6) {
                        if reminderStore.isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.72)
                        }

                        Text(reminderStore.isSaving ? "Adding" : "Add task")
                    }
                }
                .tallyPrimaryButtonStyle()
                .disabled(parsedPreview.title.isEmpty || reminderStore.isSaving)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.026))
        }
        .frame(width: TallyChrome.quickAddWindowSize.width, height: TallyChrome.quickAddWindowSize.height)
        .tallyChromeSurface(
            cornerRadius: TallyChrome.panelCornerRadius,
            material: .regularMaterial,
            strokeOpacity: 0.16,
            shadowOpacity: 0.22,
            shadowRadius: 34,
            shadowY: 16
        )
    }

    private func addReminder() {
        let draft = quickAddText
        let noteDraft = notes
        let suppressedTokens = suppressedInferredTokens

        guard !QuickAddParser.parse(draft, suppressedInferredTokens: suppressedTokens).title.isEmpty else {
            return
        }

        quickAddText = ""
        notes = ""
        suppressedInferredTokens = []
        onSubmit(draft, noteDraft, keepsOpenAfterAdd, suppressedTokens)
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

    private func applyDueDateSelection(_ selection: QuickAddDueDateSelection?) {
        quickAddText = QuickAddTokenEditor.applyingDueDate(
            selection,
            to: quickAddText,
            suppressedInferredTokens: suppressedInferredTokens
        )
    }

    private func applyListSelection(_ listTitle: String) {
        quickAddText = QuickAddTokenEditor.applyingList(
            listTitle,
            to: quickAddText,
            suppressedInferredTokens: suppressedInferredTokens
        )
    }

    private func applyPrioritySelection(_ priority: Int) {
        quickAddText = QuickAddTokenEditor.applyingPriority(
            priority,
            to: quickAddText,
            suppressedInferredTokens: suppressedInferredTokens
        )
    }

    private func addTagEntry() {
        let edit = QuickAddTokenEditor.addingTagEntry(
            in: quickAddText,
            suppressedInferredTokens: suppressedInferredTokens
        )
        quickAddText = edit.text
        quickAddSelectionRequest = edit.selectedRange
    }

    private func editTag(at index: Int) {
        let edit = QuickAddTokenEditor.editingTag(
            at: index,
            in: quickAddText,
            suppressedInferredTokens: suppressedInferredTokens
        )
        quickAddText = edit.text
        quickAddSelectionRequest = edit.selectedRange
    }

    private func removeTag(at index: Int) {
        quickAddText = QuickAddTokenEditor.removingTag(
            at: index,
            from: quickAddText,
            suppressedInferredTokens: suppressedInferredTokens
        )
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

    let fields: QuickAddFields
    let fallbackListTitle: String
    let onApplyDueDateSelection: (QuickAddDueDateSelection?) -> Void
    let onApplyListSelection: (String) -> Void
    let onApplyPrioritySelection: (Int) -> Void
    let onAddTagEntry: () -> Void
    let onEditTag: (Int) -> Void
    let onRemoveTag: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                DatePickerChip(fields: fields, onApplySelection: onApplyDueDateSelection)

                ListPickerChip(
                    title: fields.listName ?? fallbackListTitle,
                    isPlaceholder: fields.listName == nil,
                    listTitles: reminderStore.reminderListTitles,
                    onSelect: onApplyListSelection
                )

                PriorityPickerChip(
                    priority: fields.priority,
                    onSelect: onApplyPrioritySelection
                )

                TagPickerChip(
                    tags: fields.tags,
                    onAdd: onAddTagEntry,
                    onEdit: onEditTag,
                    onRemove: onRemoveTag
                )
            }
            .frame(height: 30)
        }
        .frame(height: 30)
    }
}

private struct TagPickerChip: View {
    @State private var isShowingPicker = false

    let tags: [String]
    let onAdd: () -> Void
    let onEdit: (Int) -> Void
    let onRemove: (Int) -> Void

    private var title: String {
        switch tags.count {
        case 0:
            return "Tag"
        case 1:
            return tags[0]
        default:
            return "\(tags.count) tags"
        }
    }

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            QuickAddChip(
                systemName: "tag.fill",
                title: title,
                tint: .orange,
                isPlaceholder: tags.isEmpty,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            QuickAddTagPickerPopover(
                tags: tags,
                onAdd: {
                    onAdd()
                    isShowingPicker = false
                },
                onEdit: { index in
                    onEdit(index)
                    isShowingPicker = false
                },
                onRemove: onRemove
            )
        }
        .accessibilityLabel("Tags")
    }
}

private struct QuickAddTagPickerPopover: View {
    let tags: [String]
    let onAdd: () -> Void
    let onEdit: (Int) -> Void
    let onRemove: (Int) -> Void

    var body: some View {
        QuickAddPickerPanel(width: 230) {
            if tags.isEmpty {
                Text("No tags")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
            } else {
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    QuickAddTagPickerRow(
                        tag: tag,
                        onEdit: { onEdit(index) },
                        onRemove: { onRemove(index) }
                    )
                }
            }

            Divider()
                .padding(.vertical, 3)

            Button(action: onAdd) {
                QuickAddPickerRow(
                    systemName: "plus",
                    title: "Add tag",
                    tint: .orange,
                    isSelected: false
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct QuickAddTagPickerRow: View {
    @State private var isHovering = false

    let tag: String
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.orange)
                .frame(width: 15)

            Text(tag)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Spacer(minLength: 10)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Edit tag")

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove tag")
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        Color.primary.opacity(isHovering ? 0.07 : 0)
    }
}

private struct DatePickerChip: View {
    @State private var isShowingPicker = false

    let fields: QuickAddFields
    let onApplySelection: (QuickAddDueDateSelection?) -> Void

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            QuickAddChip(
                systemName: "calendar",
                title: fields.dueDate?.shortDisplayTitle ?? "Date",
                tint: .green,
                isPlaceholder: fields.dueDate == nil
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            DueDatePickerPopover(
                initialComponents: fields.dueDate,
                onCancel: {
                    isShowingPicker = false
                },
                onClear: {
                    onApplySelection(nil)
                    isShowingPicker = false
                },
                onDone: { selection in
                    onApplySelection(selection)
                    isShowingPicker = false
                }
            )
        }
    }
}

private struct ListPickerChip: View {
    @State private var isShowingPicker = false

    let title: String
    let isPlaceholder: Bool
    let listTitles: [String]
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            QuickAddChip(
                systemName: "tray",
                title: title,
                tint: .purple,
                isPlaceholder: isPlaceholder,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            QuickAddListPickerPopover(
                listTitles: listTitles,
                onSelect: { listTitle in
                    onSelect(listTitle)
                    isShowingPicker = false
                }
            )
        }
        .accessibilityLabel("Reminder list")
    }
}

private struct PriorityPickerChip: View {
    @State private var isShowingPicker = false

    let priority: Int
    let onSelect: (Int) -> Void

    private var isPlaceholder: Bool {
        priority == 0
    }

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            QuickAddChip(
                systemName: "flag.fill",
                title: isPlaceholder ? "Priority" : priority.quickAddTitle,
                tint: .red,
                isPlaceholder: isPlaceholder,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            QuickAddPriorityPickerPopover(
                selectedPriority: priority,
                onSelect: { selectedPriority in
                    onSelect(selectedPriority)
                    isShowingPicker = false
                }
            )
        }
        .accessibilityLabel("Priority")
    }
}

private struct QuickAddListPickerPopover: View {
    let listTitles: [String]
    let onSelect: (String) -> Void

    var body: some View {
        QuickAddPickerPanel {
            if listTitles.isEmpty {
                Text("No writable lists")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
            } else {
                ForEach(listTitles, id: \.self) { listTitle in
                    Button {
                        onSelect(listTitle)
                    } label: {
                        QuickAddPickerRow(
                            systemName: "tray",
                            title: listTitle,
                            tint: .purple,
                            isSelected: false
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct QuickAddPriorityPickerPopover: View {
    let selectedPriority: Int
    let onSelect: (Int) -> Void

    private let options = [
        QuickAddPriorityOption(title: "P1", token: "P1", value: 1),
        QuickAddPriorityOption(title: "P2", token: "P2", value: 5),
        QuickAddPriorityOption(title: "P3", token: "P3", value: 9),
        QuickAddPriorityOption(title: "None", token: "P4", value: 0)
    ]

    var body: some View {
        QuickAddPickerPanel {
            ForEach(options) { option in
                Button {
                    onSelect(option.value)
                } label: {
                    QuickAddPickerRow(
                        systemName: option.value == 0 ? "flag" : "flag.fill",
                        title: option.title,
                        tint: .red,
                        isSelected: option.value == selectedPriority
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct QuickAddPriorityOption: Identifiable {
    let title: String
    let token: String
    let value: Int

    var id: String {
        token
    }
}

private struct QuickAddPickerPanel<Content: View>: View {
    let width: CGFloat
    let content: Content

    init(width: CGFloat = 190, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .padding(6)
        }
        .frame(width: width)
        .frame(maxHeight: 220)
    }
}

private struct QuickAddPickerRow: View {
    @State private var isHovering = false

    let systemName: String
    let title: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 15)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 10)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .foregroundStyle(isSelected ? tint : Color.primary)
        .padding(.horizontal, 9)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { isHovering = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            return tint.opacity(isHovering ? 0.18 : 0.12)
        }

        return Color.primary.opacity(isHovering ? 0.07 : 0)
    }
}

private struct QuickAddChip: View {
    let systemName: String
    let title: String
    let tint: Color
    var isPlaceholder = false
    var showsChevron = false
    var isInteractive = true

    var body: some View {
        QuickAddChipContent(
            systemName: systemName,
            title: title,
            tint: tint,
            isPlaceholder: isPlaceholder,
            showsChevron: showsChevron
        )
        .quickAddChipSurface(tint: tint, isPlaceholder: isPlaceholder, isInteractive: isInteractive)
    }
}

private struct QuickAddChipContent: View {
    let systemName: String
    let title: String
    let tint: Color
    let isPlaceholder: Bool
    var showsChevron = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(title)
                .lineLimit(1)

            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.leading, -1)
                    .opacity(0.82)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 9)
        .frame(height: 28)
        .foregroundStyle(foregroundStyle)
    }

    private var foregroundStyle: Color {
        isPlaceholder ? .secondary : tint
    }
}

private struct QuickAddChipSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false

    let tint: Color
    let isPlaceholder: Bool
    let isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: TallyChrome.controlCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: TallyChrome.controlCornerRadius, style: .continuous)
                    .stroke(strokeStyle, lineWidth: 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: TallyChrome.controlCornerRadius, style: .continuous))
            .onHover { isHovering = $0 && isInteractive }
    }

    private var backgroundStyle: Color {
        if isPlaceholder {
            return .secondary.opacity(isHovering ? 0.16 : 0.10)
        }

        return tint.opacity(isHovering ? 0.20 : 0.14)
    }

    private var strokeStyle: Color {
        let opacity = isPlaceholder ? 0.07 : 0.10

        if colorScheme == .dark {
            return .white.opacity(opacity)
        }

        return .black.opacity(opacity)
    }
}

private extension View {
    func quickAddChipSurface(
        tint: Color,
        isPlaceholder: Bool,
        isInteractive: Bool = true
    ) -> some View {
        modifier(QuickAddChipSurface(
            tint: tint,
            isPlaceholder: isPlaceholder,
            isInteractive: isInteractive
        ))
    }
}
