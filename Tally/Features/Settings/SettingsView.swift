import AppKit
import SwiftUI

private enum SettingsFocusTarget: Hashable {
    case back
    case defaultList
    case afterAdding
    case launchAtLogin
    case quickAddShortcut
    case quickAddReset
    case menuShortcut
    case menuReset
}

struct SettingsView: View {
    static let contentWidth: CGFloat = 420
    private static let headerHeight: CGFloat = 50
    private static let panelCornerRadius: CGFloat = 14
    private static let contentHorizontalPadding: CGFloat = 18
    fileprivate static let shortcutRecorderWidth: CGFloat = 112

    @ObservedObject var model: SettingsViewModel
    @FocusState private var focusedControl: SettingsFocusTarget?
    @State private var quickAddShortcutActivationRequestID = 0
    @State private var menuShortcutActivationRequestID = 0
    private let onReturnToMenu: () -> Void
    private let onContentHeightChange: (CGFloat) -> Void

    init(
        model: SettingsViewModel,
        onReturnToMenu: @escaping () -> Void = {},
        onContentHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.model = model
        self.onReturnToMenu = onReturnToMenu
        self.onContentHeightChange = onContentHeightChange
    }

    var body: some View {
        ZStack {
            TallyPanelBackdrop()

            VStack(spacing: 0) {
                panelHeader

                Divider()
                    .opacity(0.48)

                ScrollView(.vertical) {
                    settingsContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, 14)
                        .padding(.bottom, 16)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: SettingsContentHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        }
                }
                .contentMargins(
                    .horizontal,
                    Self.contentHorizontalPadding,
                    for: .scrollContent
                )
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .onPreferenceChange(SettingsContentHeightPreferenceKey.self) { height in
                    guard height > 0 else {
                        return
                    }
                    onContentHeightChange(ceil(height + Self.headerHeight + 1))
                }
            }
        }
        .frame(width: Self.contentWidth)
        .clipShape(panelShape)
        .overlay {
            panelShape
                .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .controlSize(.small)
        .onKeyPress(keys: [.tab]) { keyPress in
            moveFocus(forward: !keyPress.modifiers.contains(.shift))
            return .handled
        }
        .task {
            focusedControl = .back
        }
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            Button(action: onReturnToMenu) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .settingsFocus(
                $focusedControl,
                equals: .back,
                shape: Circle()
            )
            .onKeyPress(keys: [.space, .return]) { _ in
                onReturnToMenu()
                return .handled
            }
            .help("Back to reminders")
            .accessibilityLabel("Back to reminders")

            Text("Settings")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: Self.headerHeight)
        .frame(maxWidth: .infinity)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            quickAddSettings
            appSettings
        }
    }

    private var quickAddSettings: some View {
        SettingsSection(
            title: "Quick Add",
            subtitle: "Choose where new reminders go and whether Quick Add stays open."
        ) {
            SettingsRow(
                title: "Default list",
                detail: nil
            ) {
                DefaultReminderListMenu(
                    model: model,
                    focusedControl: $focusedControl
                )
            }

            SettingsRowDivider()

            SettingsRow(title: "After adding", detail: nil) {
                SettingsValueMenu(
                    title: "After adding",
                    selection: $model.quickAddBehavior,
                    options: QuickAddBehavior.allCases,
                    label: \.title,
                    width: 150,
                    focusedControl: $focusedControl,
                    focusTarget: .afterAdding
                )
            }
        }
    }

    private var appSettings: some View {
        SettingsSection(
            title: "App",
            subtitle: "Access, startup, and keyboard shortcuts."
        ) {
            SettingsRow(title: "Reminders access", detail: nil) {
                accessAccessory
            }

            SettingsRowDivider()

            SettingsRow(
                title: "Open at login",
                detail: model.launchAtLoginError,
                detailIsError: model.launchAtLoginError != nil
            ) {
                Toggle("Open at login", isOn: $model.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .settingsFocus(
                        $focusedControl,
                        equals: .launchAtLogin,
                        shape: Capsule()
                    )
                    .onKeyPress(keys: [.space, .return]) { _ in
                        model.launchAtLogin.toggle()
                        return .handled
                    }
            }

            SettingsRowDivider()

            shortcutRow(
                title: "Quick Add shortcut",
                kind: .quickAdd,
                shortcut: model.quickAddShortcut,
                defaultShortcut: .defaultQuickAddValue,
                error: model.quickAddShortcutError
            )

            SettingsRowDivider()

            shortcutRow(
                title: "Menu shortcut",
                kind: .menuBar,
                shortcut: model.trayShortcut,
                defaultShortcut: .defaultTrayValue,
                error: model.trayShortcutError
            )
        }
    }

    private var accessAccessory: some View {
        HStack(spacing: 9) {
            if model.isRequestingAccess {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Label {
                    Text(model.accessStatusTitle)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: model.accessStatusSymbol)
                        .foregroundStyle(Color(nsColor: model.accessStatusColor))
                }
                .font(.callout)
                .labelStyle(.titleAndIcon)
            }

            if let actionTitle = model.accessActionTitle,
               !model.isRequestingAccess {
                Button(actionTitle) {
                    model.performAccessAction()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func shortcutRow(
        title: String,
        kind: SettingsShortcutKind,
        shortcut: GlobalShortcut,
        defaultShortcut: GlobalShortcut,
        error: String?
    ) -> some View {
        SettingsRow(title: title, detail: nil) {
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 8) {
                    ShortcutRecorderView(
                        shortcut: shortcut,
                        activationRequestID: shortcutActivationRequestID(for: kind),
                        onFocus: {
                            focusedControl = focusTarget(for: kind)
                        },
                        onMoveFocus: moveFocus,
                        onRecord: { event in
                            model.recordShortcut(kind, from: event)
                        }
                    )
                    .frame(width: Self.shortcutRecorderWidth, height: 24)
                    .settingsFocus(
                        $focusedControl,
                        equals: focusTarget(for: kind),
                        shape: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .onKeyPress(keys: [.space, .return]) { _ in
                        requestShortcutRecording(kind)
                        return .handled
                    }

                    Button("Reset") {
                        model.resetShortcut(kind)
                    }
                    .buttonStyle(.borderless)
                    .disabled(shortcut == defaultShortcut)
                    .settingsFocus(
                        $focusedControl,
                        equals: resetFocusTarget(for: kind),
                        shape: RoundedRectangle(cornerRadius: 5, style: .continuous),
                        isEnabled: shortcut != defaultShortcut
                    )
                    .onKeyPress(keys: [.space, .return]) { _ in
                        guard shortcut != defaultShortcut else {
                            return .ignored
                        }

                        model.resetShortcut(kind)
                        return .handled
                    }
                }

                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 170, alignment: .trailing)
                }
            }
        }
    }

    private var focusTargets: [SettingsFocusTarget] {
        var targets: [SettingsFocusTarget] = [
            .back,
            .defaultList,
            .afterAdding,
            .launchAtLogin,
            .quickAddShortcut
        ]
        if model.quickAddShortcut != .defaultQuickAddValue {
            targets.append(.quickAddReset)
        }
        targets.append(.menuShortcut)
        if model.trayShortcut != .defaultTrayValue {
            targets.append(.menuReset)
        }
        return targets
    }

    private func moveFocus(forward: Bool) {
        guard !focusTargets.isEmpty else {
            return
        }

        let currentIndex = focusedControl.flatMap(focusTargets.firstIndex(of:)) ?? 0
        let offset = forward ? 1 : -1
        let nextIndex = (currentIndex + offset + focusTargets.count) % focusTargets.count
        focusedControl = focusTargets[nextIndex]
    }

    private func focusTarget(for kind: SettingsShortcutKind) -> SettingsFocusTarget {
        kind == .quickAdd ? .quickAddShortcut : .menuShortcut
    }

    private func resetFocusTarget(for kind: SettingsShortcutKind) -> SettingsFocusTarget {
        kind == .quickAdd ? .quickAddReset : .menuReset
    }

    private func shortcutActivationRequestID(for kind: SettingsShortcutKind) -> Int {
        kind == .quickAdd
            ? quickAddShortcutActivationRequestID
            : menuShortcutActivationRequestID
    }

    private func requestShortcutRecording(_ kind: SettingsShortcutKind) {
        switch kind {
        case .quickAdd:
            quickAddShortcutActivationRequestID += 1
        case .menuBar:
            menuShortcutActivationRequestID += 1
        }
    }
}

private struct DefaultReminderListMenu: View {
    @ObservedObject var model: SettingsViewModel
    let focusedControl: FocusState<SettingsFocusTarget?>.Binding

    @State private var activationRequestID = 0

    var body: some View {
        SettingsNativePopUpButton(
            title: "Default reminder list",
            selection: Binding(
                get: { model.defaultListIdentifier },
                set: model.chooseDefaultList
            ),
            choices: [
                SettingsPopUpChoice(value: String?.none, label: "System default")
            ] + model.reminderLists.map {
                SettingsPopUpChoice(value: Optional($0.id), label: $0.title)
            },
            activationRequestID: activationRequestID,
            onFocus: {
                focusedControl.wrappedValue = .defaultList
            }
        )
        .frame(width: 150, height: 24)
        .settingsFocus(
            focusedControl,
            equals: .defaultList,
            shape: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .onKeyPress(keys: [.space, .return]) { _ in
            activationRequestID += 1
            return .handled
        }
    }
}

private struct SettingsContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                content
            }
            .overlay(alignment: .top) {
                Divider()
            }
        }
        .settingsSectionSurface()
    }
}

private struct SettingsSectionSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.065), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

private extension View {
    func settingsSectionSurface() -> some View {
        modifier(SettingsSectionSurface())
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let detail: String?
    var detailIsError = false
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(2)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(detailIsError ? Color.red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            accessory
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, detail == nil ? 7 : 9)
        .frame(maxWidth: .infinity, minHeight: 42)
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .opacity(0.62)
    }
}

private struct SettingsValueMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    let width: CGFloat
    let focusedControl: FocusState<SettingsFocusTarget?>.Binding
    let focusTarget: SettingsFocusTarget

    @State private var activationRequestID = 0

    var body: some View {
        SettingsNativePopUpButton(
            title: title,
            selection: $selection,
            choices: options.map {
                SettingsPopUpChoice(value: $0, label: label($0))
            },
            activationRequestID: activationRequestID,
            onFocus: {
                focusedControl.wrappedValue = focusTarget
            }
        )
        .frame(width: width, height: 24)
        .settingsFocus(
            focusedControl,
            equals: focusTarget,
            shape: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .onKeyPress(keys: [.space, .return]) { _ in
            activationRequestID += 1
            return .handled
        }
    }
}

private struct SettingsPopUpChoice<Value: Hashable> {
    let value: Value
    let label: String
}

private struct SettingsNativePopUpButton<Value: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Value
    let choices: [SettingsPopUpChoice<Value>]
    let activationRequestID: Int
    let onFocus: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> SettingsPopUpButton {
        let button = SettingsPopUpButton()
        button.cell = NSPopUpButtonCell(
            textCell: "",
            pullsDown: false
        )
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12)
        button.alignment = .right
        button.isBordered = false
        button.focusRingType = .none
        button.autoenablesItems = false
        button.onFocus = onFocus
        button.onShowMenu = { [weak button, weak coordinator = context.coordinator] in
            guard let button, let coordinator else {
                return
            }
            coordinator.showMenu(for: button)
        }
        return button
    }

    func updateNSView(_ button: SettingsPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.onFocus = onFocus
        button.onShowMenu = { [weak button, weak coordinator = context.coordinator] in
            guard let button, let coordinator else {
                return
            }
            coordinator.showMenu(for: button)
        }
        button.setAccessibilityLabel(title)

        let values = choices.map(\.value)
        let labels = choices.map(\.label)
        if context.coordinator.values != values
            || context.coordinator.labels != labels {
            button.removeAllItems()
            button.addItems(withTitles: labels)
            context.coordinator.values = values
            context.coordinator.labels = labels
        }

        let selectedIndex = values.firstIndex(of: selection)
        if let selectedIndex {
            button.selectItem(at: selectedIndex)
        }
        for (index, item) in button.itemArray.enumerated() {
            item.target = context.coordinator
            item.action = #selector(Coordinator.selectionChanged(_:))
            item.tag = index
            item.state = index == selectedIndex ? .on : .off
        }
        button.setAccessibilityValue(selectedLabel(from: choices, selection: selection))

        if context.coordinator.lastActivationRequestID != activationRequestID {
            context.coordinator.lastActivationRequestID = activationRequestID
            DispatchQueue.main.async { [weak button] in
                button?.performClick(nil)
            }
        }
    }

    private func selectedLabel(
        from choices: [SettingsPopUpChoice<Value>],
        selection: Value
    ) -> String {
        choices.first { $0.value == selection }?.label ?? "Unavailable"
    }

    final class Coordinator: NSObject {
        var parent: SettingsNativePopUpButton
        var values: [Value] = []
        var labels: [String] = []
        var lastActivationRequestID = 0

        init(parent: SettingsNativePopUpButton) {
            self.parent = parent
        }

        func showMenu(for button: SettingsPopUpButton) {
            guard let menu = button.menu else {
                return
            }

            menu.minimumWidth = button.bounds.width
            let location = NSPoint(
                x: button.bounds.maxX - max(button.bounds.width, menu.size.width),
                y: button.isFlipped ? button.bounds.maxY : button.bounds.minY
            )
            menu.popUp(positioning: nil, at: location, in: button)
            parent.onFocus()
        }

        @objc func selectionChanged(_ sender: NSMenuItem) {
            guard values.indices.contains(sender.tag) else {
                return
            }

            parent.selection = values[sender.tag]
            parent.onFocus()
        }
    }
}

private final class SettingsPopUpButton: NSPopUpButton {
    var onFocus: (() -> Void)?
    var onShowMenu: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocus?()
        }
        return didBecomeFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onFocus?()
        onShowMenu?()
    }

    override func performClick(_ sender: Any?) {
        onFocus?()
        onShowMenu?()
    }

    override func accessibilityPerformPress() -> Bool {
        onFocus?()
        onShowMenu?()
        return true
    }

}

private extension View {
    func settingsFocus<Value: Hashable, S: InsettableShape>(
        _ focusedValue: FocusState<Value?>.Binding,
        equals value: Value,
        shape _: S,
        isEnabled: Bool = true
    ) -> some View {
        focusable(isEnabled)
            .focused(focusedValue, equals: value)
            .focusEffectDisabled()
    }

}
