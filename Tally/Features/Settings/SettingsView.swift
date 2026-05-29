import SwiftUI

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var reminderStore: ReminderStore
    @EnvironmentObject private var settingsStore: AppSettingsStore
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController

    let onQuickAddShortcutChange: (GlobalShortcut) -> Bool
    let onTrayShortcutChange: (GlobalShortcut) -> Bool

    var body: some View {
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
                    Text(reminderStore.accessState.displayTitle)
                        .foregroundStyle(reminderStore.accessState == .authorized ? .green : .secondary)
                }

                Button(reminderStore.accessState == .authorized ? "Refresh Permission" : "Grant Reminders Access") {
                    Task {
                        await reminderStore.requestAccessIfNeeded()
                        await reminderStore.reload()
                    }
                }
                .tallySecondaryButtonStyle()
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

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 460, height: 374, alignment: .topLeading)
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
        case .requesting:
            return "Requesting"
        case .authorized:
            return "Granted"
        case .denied:
            return "Denied"
        }
    }
}
