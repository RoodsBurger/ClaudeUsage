import SwiftUI

/// Settings sub-section dedicated to notifications. Hosts the authorization
/// status row + test button at the top, then a section per category (usage
/// thresholds / pacing / reset reminders / extra credits / health) with one
/// toggle per event.
struct NotificationsSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    /// Read-only, for the enterprise-aware "Organization usage" group title.
    @EnvironmentObject private var usageStore: UsageStore

    @State private var notifTestCooldown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader(
                String(localized: "sidebar.notifications"),
                subtitle: String(localized: "sidebar.notifications.subtitle")
            ) {
                ClickChip(
                    label: String(localized: "settings.notifications.master"),
                    icon: settingsStore.notificationsEnabled ? "checkmark" : "bell.slash",
                    isActive: settingsStore.notificationsEnabled,
                    accent: DS.Pastel.green,
                    style: .compact
                ) {
                    settingsStore.notificationsEnabled.toggle()
                }
            }

            Form {
                authorizationSection
                usageSection
                pacingSection
                resetRemindersSection
                extraCreditsSection
                healthSection

                Section {
                    ResetSectionButton(
                        confirmTitle: String(localized: "settings.notifications.reset.confirm"),
                        onReset: resetToDefaults
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await settingsStore.refreshNotificationStatus() }
    }

    private func resetToDefaults() {
        settingsStore.notificationsEnabled = true
        settingsStore.notifTrackFiveHour = true
        settingsStore.notifTrackWeekly = true
        settingsStore.notifTrackSonnet = false
        settingsStore.notifTrackDesign = true
        settingsStore.notifSendRecovery = true
        settingsStore.notifPacingHot = true
        settingsStore.notifPacingWarning = false
        settingsStore.notifResetReminderSession = false
        settingsStore.notifResetReminderWeekly = false
        settingsStore.notifResetReminderSessionOffset = 15
        settingsStore.notifResetReminderWeeklyOffset = 60
        settingsStore.notifExtraCredits = true
        settingsStore.notifTokenExpired = false
        settingsStore.notifVendorDegraded = true
        settingsStore.notifVendorRestored = true
    }

    // MARK: - Authorization

    private var authorizationSection: some View {
        Section {
            HStack {
                statusLabel
                Spacer()
                if settingsStore.notificationStatus == .denied {
                    Button(String(localized: "settings.notifications.open")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings")!)
                    }
                    .buttonStyle(.borderless)
                } else if settingsStore.notificationStatus != .authorized {
                    Button(String(localized: "settings.notifications.enable")) {
                        settingsStore.requestNotificationPermission()
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            await settingsStore.refreshNotificationStatus()
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Button(String(localized: "settings.notifications.test")) {
                    if settingsStore.notificationStatus != .authorized {
                        settingsStore.requestNotificationPermission()
                    }
                    settingsStore.sendTestNotification()
                    notifTestCooldown = true
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        notifTestCooldown = false
                        await settingsStore.refreshNotificationStatus()
                    }
                }
                .buttonStyle(.borderless)
                .disabled(notifTestCooldown)
            }
        } header: {
            Text(String(localized: "settings.notifications.status"))
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch settingsStore.notificationStatus {
        case .authorized:
            Label(String(localized: "settings.notifications.on"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(DS.Pastel.green)
        case .denied:
            Label(String(localized: "settings.notifications.off"), systemImage: "xmark.circle.fill")
                .foregroundStyle(DS.Pastel.coral)
        default:
            Label(String(localized: "settings.notifications.unknown"), systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Usage thresholds

    private var usageSection: some View {
        Section {
            Toggle(String(localized: "settings.notifications.track.fivehour"), isOn: $settingsStore.notification.trackFiveHour)
                .tint(DS.Pastel.green)
            Toggle(String(localized: "settings.notifications.track.weekly"), isOn: $settingsStore.notification.trackWeekly)
                .tint(DS.Pastel.green)
            Toggle(String(localized: "settings.notifications.track.sonnet"), isOn: $settingsStore.notification.trackSonnet)
                .tint(DS.Pastel.green)
            Toggle(String(localized: "settings.notifications.track.design"), isOn: $settingsStore.notification.trackDesign)
                .tint(DS.Pastel.green)
            Toggle(String(localized: "settings.notifications.track.fable"), isOn: $settingsStore.notification.trackFable)
                .tint(DS.Pastel.green)
            Toggle(String(localized: "settings.notifications.recovery"), isOn: $settingsStore.notification.sendRecovery)
                .tint(DS.Pastel.green)
        } header: {
            Text(String(localized: "settings.notifications.group.usage"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.notifications.group.usage.hint"))
                Text(String(localized: "settings.notifications.recovery.hint"))
            }
        }
    }

    // MARK: - Pacing

    private var pacingSection: some View {
        Section {
            Toggle(String(localized: "settings.notifications.pacing.hot"), isOn: $settingsStore.notification.pacingHot)
                .tint(DS.Pastel.green)
            Toggle(String(localized: "settings.notifications.pacing.warning"), isOn: $settingsStore.notification.pacingWarning)
                .tint(DS.Pastel.green)
        } header: {
            Text(String(localized: "settings.notifications.group.pacing"))
        } footer: {
            Text(String(localized: "settings.notifications.group.pacing.hint"))
        }
    }

    // MARK: - Reset reminders

    private var resetRemindersSection: some View {
        Section {
            Toggle(String(localized: "settings.notifications.reset.session"), isOn: $settingsStore.notification.resetReminderSession)
                .tint(DS.Pastel.green)
            reminderOffsetPicker(
                selection: $settingsStore.notification.resetReminderSessionOffset,
                options: [5, 10, 15, 30, 60],
                enabled: settingsStore.notifResetReminderSession
            )
            Toggle(String(localized: "settings.notifications.reset.weekly"), isOn: $settingsStore.notification.resetReminderWeekly)
                .tint(DS.Pastel.green)
            reminderOffsetPicker(
                selection: $settingsStore.notification.resetReminderWeeklyOffset,
                options: [30, 60, 120, 180, 360],
                enabled: settingsStore.notifResetReminderWeekly
            )
        } header: {
            Text(String(localized: "settings.notifications.group.reset"))
        } footer: {
            Text(String(localized: "settings.notifications.group.reset.hint"))
        }
    }

    private func reminderOffsetPicker(selection: Binding<Int>, options: [Int], enabled: Bool) -> some View {
        Picker(String(localized: "settings.notifications.reset.offset.label"), selection: selection) {
            ForEach(options, id: \.self) { minutes in
                Text(formatOffsetMinutes(minutes)).tag(minutes)
            }
        }
        .disabled(!enabled)
    }

    private func formatOffsetMinutes(_ minutes: Int) -> String {
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return String(format: String(localized: "settings.notifications.reset.offset.hours"), hours)
        }
        return String(format: String(localized: "settings.notifications.reset.offset.minutes"), minutes)
    }

    // MARK: - Extra credits

    private var extraCreditsSection: some View {
        Section {
            Toggle(String(localized: "settings.notifications.extra"), isOn: $settingsStore.notification.extraCredits)
                .tint(DS.Pastel.green)
        } header: {
            // Enterprise renames the pool to "Organization usage".
            Text(usageStore.planType == .enterprise
                 ? String(localized: "metric.orgUsage")
                 : String(localized: "settings.notifications.group.extra"))
        } footer: {
            Text(String(localized: "settings.notifications.group.extra.hint"))
        }
    }

    // MARK: - Health

    private var healthSection: some View {
        Section {
            Toggle(String(localized: "settings.notifications.token"), isOn: $settingsStore.notification.tokenExpired)
                .tint(DS.Pastel.green)
            Toggle(String(localized: "settings.notifications.status.degraded"), isOn: $settingsStore.notification.vendorDegraded)
                .tint(DS.Pastel.green)
            Toggle(String(localized: "settings.notifications.status.restored"), isOn: $settingsStore.notification.vendorRestored)
                .tint(DS.Pastel.green)
        } header: {
            Text(String(localized: "settings.notifications.group.health"))
        } footer: {
            Text(String(localized: "settings.notifications.group.health.hint"))
        }
    }
}
