import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var reminderStore: ReminderStore
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController

    let onQuickAddShortcutChange: (GlobalShortcut) -> Bool
    let onTrayShortcutChange: (GlobalShortcut) -> Bool
    let onPermissionRequestComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSection("Menu Bar") {
                    settingRow("Badge") {
                        Picker("Badge", selection: $settingsStore.badgeStyle) {
                            ForEach(MenuBarBadgeStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    shortcutRow(
                        "Quick Add shortcut",
                        shortcut: settingsStore.quickAddShortcut,
                        defaultShortcut: .defaultQuickAddValue,
                        applyShortcut: onQuickAddShortcutChange
                    ) { shortcut in
                        settingsStore.quickAddShortcut = shortcut
                    }

                    shortcutRow(
                        "Tray shortcut",
                        shortcut: settingsStore.trayShortcut,
                        defaultShortcut: .defaultTrayValue,
                        applyShortcut: onTrayShortcutChange
                    ) { shortcut in
                        settingsStore.trayShortcut = shortcut
                    }
                }

                settingsSection("Permissions") {
                    settingRow("Reminders") {
                        HStack(spacing: 6) {
                            if reminderStore.isLoading || reminderStore.accessState == .requesting {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.72)
                            }

                            Text(reminderStore.accessState.displayTitle)
                                .foregroundStyle(reminderStore.accessState == .authorized ? .green : .secondary)
                        }
                    }

                    Button(reminderStore.accessState.permissionButtonTitle) {
                        Task {
                            await reminderStore.refreshAccessAfterUserRequest()
                            onPermissionRequestComplete()
                        }
                    }
                    .tallySecondaryButtonStyle()
                    .disabled(reminderStore.accessState == .requesting)

                    if let errorMessage = reminderStore.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                settingsSection("Startup") {
                    Toggle(
                        "Open at Login",
                        isOn: Binding(
                            get: { launchAtLoginController.isEnabled },
                            set: { launchAtLoginController.setEnabled($0) }
                        )
                    )

                    if let errorMessage = launchAtLoginController.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 460, idealWidth: 460, minHeight: 420, idealHeight: 420, alignment: .topLeading)
        .background(.regularMaterial)
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
                .frame(width: 112)

                Button {
                    guard shortcut != defaultShortcut,
                          applyShortcut(defaultShortcut)
                    else {
                        return
                    }

                    storeShortcut(defaultShortcut)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .background(resetButtonFill(isDisabled: shortcut == defaultShortcut), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055), lineWidth: 0.75)
                }
                .disabled(shortcut == defaultShortcut)
                .help("Reset shortcut")
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .tallyInsetGlassSurface()
        }
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            content()
        }
        .font(.system(size: 13))
        .frame(minHeight: 28)
    }

    private func resetButtonFill(isDisabled: Bool) -> Color {
        Color.primary.opacity(isDisabled ? 0.035 : 0.075)
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
