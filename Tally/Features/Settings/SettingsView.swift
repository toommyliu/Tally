import AppKit
import SwiftUI

enum SettingsLayout {
    static let windowSize = CGSize(width: 492, height: 430)
}

struct SettingsView: View {
    @EnvironmentObject private var reminderStore: ReminderStore
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController

    let onQuickAddShortcutChange: (GlobalShortcut) -> Bool
    let onTrayShortcutChange: (GlobalShortcut) -> Bool
    let onPermissionRequestComplete: () -> Void

    var body: some View {
        ScrollView {
            settingsContent {
                settingsSection("Menu Bar", systemImage: "menubar.rectangle") {
                    settingRow("Count display") {
                        Picker("Count display", selection: $settingsStore.badgeStyle) {
                            ForEach(MenuBarBadgeStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 192)
                    }

                    settingsDivider

                    shortcutRow(
                        "Quick Add shortcut",
                        shortcut: settingsStore.quickAddShortcut,
                        defaultShortcut: .defaultQuickAddValue,
                        applyShortcut: onQuickAddShortcutChange
                    ) { shortcut in
                        settingsStore.quickAddShortcut = shortcut
                    }

                    settingsDivider

                    shortcutRow(
                        "Tray shortcut",
                        shortcut: settingsStore.trayShortcut,
                        defaultShortcut: .defaultTrayValue,
                        applyShortcut: onTrayShortcutChange
                    ) { shortcut in
                        settingsStore.trayShortcut = shortcut
                    }
                }

                settingsSection("Permissions", systemImage: "checkmark.shield") {
                    settingRow("Reminders") {
                        HStack(spacing: 7) {
                            if reminderStore.isLoading || reminderStore.accessState == .requesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.72)
                            }

                            Label {
                                Text(reminderStore.accessState.displayTitle)
                            } icon: {
                                Image(systemName: reminderStore.accessState.statusSymbolName)
                                    .foregroundStyle(reminderStore.accessState.statusColor)
                            }
                            .labelStyle(.titleAndIcon)
                        }
                    }

                    settingsDivider

                    settingRow("Access") {
                        Button(reminderStore.accessState.permissionButtonTitle) {
                            Task {
                                await reminderStore.refreshAccessAfterUserRequest()
                                onPermissionRequestComplete()
                            }
                        }
                        .tallySecondaryButtonStyle()
                        .controlSize(.small)
                        .disabled(reminderStore.accessState == .requesting)
                    }

                    if let errorMessage = reminderStore.errorMessage {
                        settingsDivider
                        errorRow(errorMessage)
                    }
                }

                settingsSection("Startup", systemImage: "power") {
                    settingRow("Open at Login") {
                        Toggle(
                            "Open at Login",
                            isOn: Binding(
                                get: { launchAtLoginController.isEnabled },
                                set: { launchAtLoginController.setEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    if let errorMessage = launchAtLoginController.errorMessage {
                        settingsDivider
                        errorRow(errorMessage)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(
            minWidth: SettingsLayout.windowSize.width,
            idealWidth: SettingsLayout.windowSize.width,
            minHeight: SettingsLayout.windowSize.height,
            idealHeight: SettingsLayout.windowSize.height,
            alignment: .top
        )
        .background(.regularMaterial)
        .background(SettingsWindowConfigurator(contentSize: SettingsLayout.windowSize))
    }

    private func shortcutRow(
        _ title: String,
        shortcut: GlobalShortcut,
        defaultShortcut: GlobalShortcut,
        applyShortcut: @escaping (GlobalShortcut) -> Bool,
        storeShortcut: @escaping (GlobalShortcut) -> Void
    ) -> some View {
        settingRow(title) {
            HStack(spacing: 8) {
                ShortcutRecorderView(shortcut: shortcut) { event in
                    guard let shortcut = GlobalShortcut.candidate(from: event),
                          applyShortcut(shortcut)
                    else {
                        return
                    }

                    storeShortcut(shortcut)
                }
                .frame(width: 118)

                Button {
                    guard shortcut != defaultShortcut,
                          applyShortcut(defaultShortcut)
                    else {
                        return
                    }

                    storeShortcut(defaultShortcut)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(shortcut == defaultShortcut)
                .help("Reset shortcut")
            }
        }
    }

    @ViewBuilder
    private func settingsContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            .font(.system(size: 12, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .tallyInsetGlassSurface(cornerRadius: 14)
        }
    }

    private var settingsDivider: some View {
        Divider()
            .padding(.leading, 14)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)

            Text(message)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 20)
            content()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
    }
}

private struct SettingsWindowConfigurator: NSViewRepresentable {
    let contentSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWhenAttached(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard !context.coordinator.didConfigure else {
            return
        }

        configureWhenAttached(view, coordinator: context.coordinator)
    }

    private func configureWhenAttached(_ view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard !coordinator.didConfigure,
                  let window = view.window
            else {
                return
            }

            window.styleMask.remove(.resizable)
            window.setContentSize(contentSize)
            window.contentMinSize = contentSize
            window.contentMaxSize = contentSize
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            coordinator.didConfigure = true
        }
    }

    final class Coordinator {
        var didConfigure = false
    }
}

private extension ReminderStore.AccessState {
    var displayTitle: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .notDetermined:
            return "Not Requested"
        case .requesting:
            return "Requesting"
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        }
    }

    var statusSymbolName: String {
        switch self {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .requesting:
            return "clock.fill"
        case .unknown, .notDetermined:
            return "circle"
        }
    }

    var statusColor: Color {
        switch self {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .requesting:
            return .secondary
        case .unknown, .notDetermined:
            return .secondary
        }
    }

    var permissionButtonTitle: String {
        switch self {
        case .authorized:
            return "Refresh Permission"
        case .requesting:
            return "Requesting Access"
        case .unknown, .notDetermined, .denied:
            return "Grant Reminders Access"
        }
    }
}
