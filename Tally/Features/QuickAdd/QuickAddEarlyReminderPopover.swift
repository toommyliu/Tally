import AppKit
import SwiftUI

struct QuickAddEarlyReminderButton: View {
    let parsed: QuickAddEarlyReminder?
    let target: EarlyReminderTarget
    let context: QuickAddParseContext
    @Binding var isPresented: Bool
    let focusedControl: FocusState<QuickAddFocusTarget?>.Binding
    let onFocusTitle: () -> Void
    let onApply: (ReminderEarlyReminder?) -> Void
    private enum FocusReturn { case idle, chip, title }
    @State private var focusReturn = FocusReturn.idle
    @Environment(\.locale) private var locale

    var body: some View {
        let presentation = EarlyReminderPresentation(parsed, calendar: context.calendar, locale: locale)
        Button(action: togglePopover) {
            QuickAddMetadataChip(
                systemName: presentation.showsWarning ? "exclamationmark.triangle.fill" : parsed == nil ? "bell" : "bell.fill",
                title: parsed == nil && target.isEvent ? "Alert" : presentation.chipTitle,
                tint: presentation.showsWarning ? .orange : TallyPalette.date,
                isActive: parsed != nil,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .quickAddFocus(focusedControl, equals: .earlyReminder, shape: RoundedRectangle(cornerRadius: 7))
        .quickAddKeyboardActivation(togglePopover)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            QuickAddEarlyReminderPopover(parsed: parsed, target: target, context: context, onDismiss: { isPresented = false }) { offset in
                focusReturn = .title
                onApply(offset)
                isPresented = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            guard !isPresented else { return }
            let destination = focusReturn
            focusReturn = .idle
            switch destination {
            case .idle: break
            case .chip: focusedControl.wrappedValue = .earlyReminder
            case .title:
                focusedControl.wrappedValue = nil
                onFocusTitle()
            }
        }
        .accessibilityLabel(target.isEvent ? "Alert" : "Early reminder")
        .accessibilityValue(presentation.accessibilityValue)
        .help(presentation.detail ?? (target.isEvent ? "Set an event alert" : "Set an early reminder"))
    }

    private func togglePopover() {
        if !isPresented { focusReturn = .chip }
        isPresented.toggle()
    }

}

struct QuickAddEarlyReminderPopover: View {
    let parsed: QuickAddEarlyReminder?
    let target: EarlyReminderTarget
    let context: QuickAddParseContext
    let onDismiss: () -> Void
    let onApply: (ReminderEarlyReminder?) -> Void
    @State private var custom: EarlyReminderCustomInput?
    @FocusState private var focusedOption: Int?

    private var presets: [EarlyReminderPreset] {
        EarlyReminderCatalog.presets(for: target.hasTime ? .timed : .dateOnly)
    }
    private func available(_ offset: ReminderEarlyReminder) -> Bool {
        !target.isEvent || !target.preview(offset, context: context).isWarning
    }
    private var enabledOptions: [Int] {
        [0] + presets.indices.filter { available(presets[$0].id) }.map { $0 + 1 } + [presets.count + 1]
    }

    var body: some View {
        Group {
            if let custom {
                QuickAddEarlyReminderCustomEditor(input: custom, target: target, context: context,
                                                   onCancel: dismissLevel, onApply: onApply)
                    .padding(6)
                    .frame(width: 250)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(Color(nsColor: .windowBackgroundColor))
            } else {
                QuickAddPopoverPanel(width: 300) {
                    option(0, title: "None", selected: parsed == nil) { onApply(nil) }
                    ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                        option(index + 1, title: preset.title, subtitle: preset.syntax,
                               selected: parsed?.selectedOffset == preset.id, enabled: available(preset.id)) {
                            onApply(preset.id)
                        }
                    }
                    Divider().padding(.vertical, 4)
                    option(presets.count + 1, title: "Custom…") { beginCustom() }
                    if target.isEvent {
                        Text(target.hasTime ? "Use days or weeks for event alerts. A day is 24 hours; a week is 168 hours."
                             : "Add a time to set an alert.")
                            .font(.caption).foregroundStyle(.secondary).padding(8)
                    }
                }
                .frame(height: 270)
                .task { focusedOption = 0 }
            }
        }
        .onKeyPress(keys: [.tab]) { press in
            guard custom == nil else { return .ignored }
            let options = enabledOptions
            let index = options.firstIndex(of: focusedOption ?? 0) ?? 0
            focusedOption = options[(index + (press.modifiers.contains(.shift) ? options.count - 1 : 1)) % options.count]
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            guard custom == nil, let focus = focusedOption else { return .ignored }
            if focus == 0 { onApply(nil) }
            else if focus == presets.count + 1 { beginCustom() }
            else if presets.indices.contains(focus - 1), available(presets[focus - 1].id) { onApply(presets[focus - 1].id) }
            return .handled
        }
        .onExitCommand(perform: dismissLevel)
    }

    private func option(_ index: Int, title: String, subtitle: String? = nil,
                        selected: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            QuickAddPopoverRow(systemName: "bell", title: title, subtitle: subtitle, tint: TallyPalette.date, isSelected: selected)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .quickAddPopoverFocus($focusedOption, equals: index, isEnabled: enabled)
    }

    private func dismissLevel() {
        if custom != nil {
            custom = nil
            focusedOption = presets.count + 1
        } else {
            onDismiss()
        }
    }

    private func beginCustom() {
        let selected = parsed?.selectedOffset
        custom = EarlyReminderCustomInput(amountText: String(selected?.amount.value ?? 1), unit: selected?.unit ?? .days)
    }

}

private struct QuickAddEarlyReminderCustomEditor: View {
    @State var input: EarlyReminderCustomInput
    let target: EarlyReminderTarget
    let context: QuickAddParseContext
    let onCancel: () -> Void
    let onApply: (ReminderEarlyReminder?) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        let resolved = input.offset.map { target.preview($0, context: context) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                QuickAddEarlyReminderAmountField(text: $input.amountText, onSubmit: apply, onCancel: onCancel)
                    .frame(width: 44)
                Picker("Unit", selection: $input.unit) {
                    ForEach(ScheduleUnit.allCases, id: \.self) { unit in
                        Text(input.unitMenuTitle(unit)).tag(unit)
                    }
                }
                .labelsHidden()
            }
            Group {
                if let warning = input.numericWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if let resolved {
                    let presentation = EarlyReminderPresentation(resolved, calendar: context.calendar, locale: locale)
                    Text(presentation.previewTitle)
                        .foregroundStyle(resolved.isWarning ? .orange : .secondary)
                        .help(presentation.accessibilityValue)
                }
            }
            .font(.caption)
            .lineLimit(1)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.offset == nil || (target.isEvent && (resolved?.isWarning ?? true)))
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
    }

    private func apply() {
        guard let offset = input.offset, !target.isEvent || !target.preview(offset, context: context).isWarning else { return }
        onApply(offset)
    }

}

private struct QuickAddEarlyReminderAmountField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = InitiallyFocusedTextField()
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.usesSingleLineMode = true
        field.setAccessibilityLabel("Amount")
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickAddEarlyReminderAmountField
        init(parent: QuickAddEarlyReminderAmountField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            if command == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if command == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

private final class InitiallyFocusedTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.initialFirstResponder = self
        window.makeFirstResponder(self)
        selectText(nil)
    }
}
