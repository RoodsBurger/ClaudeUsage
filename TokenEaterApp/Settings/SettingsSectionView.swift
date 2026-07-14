import SwiftUI

struct SettingsSectionView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var updateStore: UpdateStore

    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var importSuccess = false
    /// Owns the "Sign in with Claude" own-OAuth-login flow for this card.
    /// A child view's `@StateObject` (not the App struct), so it is allowed
    /// to persist across this view's re-renders per the SwiftUI rules.
    @StateObject private var connectFlow = OnboardingViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader(
                String(localized: "sidebar.settings"),
                subtitle: String(localized: "sidebar.settings.subtitle")
            )

            Form {
                connectionSection
                generalSection
                proxySection
                refreshSection
                serviceStatusSection
                updatesSection
                aboutSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            Task { await settingsStore.refreshNotificationStatus() }
            Task { await connectFlow.refreshConnectedAccountEmail() }
        }
        .onChange(of: connectFlow.oauthSignInStatus) { _, newStatus in
            guard case .success = newStatus else { return }
            usageStore.proxyConfig = settingsStore.proxyConfig
            usageStore.handleTokenChange()
            usageStore.reloadConfig(thresholds: settingsStore.thresholds)
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section {
            HStack(spacing: 8) {
                Circle()
                    .fill(usageStore.hasConfig && !usageStore.isDisconnected ? RiskZone.ok.color : RiskZone.critical.color)
                    .frame(width: 8, height: 8)
                Text(usageStore.hasConfig && !usageStore.isDisconnected
                     ? String(localized: "settings.connected")
                     : String(localized: "settings.disconnected"))
                Spacer()
                if isImporting {
                    ProgressView().controlSize(.small)
                }
                Button(String(localized: "settings.redetect")) {
                    connectAutoDetect()
                }
                .buttonStyle(.borderless)
            }
            if let message = importMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(importSuccess ? DS.Pastel.green : DS.Pastel.amber)
            }
            if usageStore.errorState == .rateLimited {
                VStack(alignment: .leading, spacing: 3) {
                    Label {
                        Text("error.banner.apiunavailable.settings")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "icloud.slash")
                    }
                    .foregroundStyle(DS.Pastel.amber)
                    if let last = usageStore.lastUpdate {
                        Text(String(format: String(localized: "error.banner.lastupdate"),
                                    last.formatted(.relative(presentation: .named))))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            signInWithClaudeBlock
                .padding(.vertical, 2)
        } header: {
            Text(String(localized: "settings.tab.connection"))
        }
    }

    // MARK: - General (launch at login + replay onboarding)

    private var generalSection: some View {
        Section {
            toggleRow(
                String(localized: "settings.launchAtLogin"),
                hint: String(localized: "settings.launchAtLogin.hint"),
                isOn: $settingsStore.launchAtLoginEnabled
            )
            toggleRow(
                String(localized: "settings.launchInBackground"),
                hint: String(localized: "settings.launchInBackground.hint"),
                isOn: $settingsStore.display.launchInBackground
            )

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.general.replayOnboarding"))
                    Text(String(localized: "settings.general.replayOnboarding.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    settingsStore.hasCompletedOnboarding = false
                } label: {
                    Label(String(localized: "settings.general.replayOnboarding.action"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 2)
        } header: {
            Text(String(localized: "settings.general.title"))
        }
    }

    // MARK: - Proxy

    private var proxySection: some View {
        Section {
            Toggle(String(localized: "settings.proxy.toggle"), isOn: $settingsStore.proxyEnabled)
                .tint(DS.Pastel.green)
            if settingsStore.proxyEnabled {
                LabeledContent(String(localized: "settings.proxy.host")) {
                    TextField("127.0.0.1", text: $settingsStore.proxyHost)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 140)
                }
                LabeledContent(String(localized: "settings.proxy.port")) {
                    TextField("1080", value: $settingsStore.proxyPort, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                Text(String(localized: "settings.proxy.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(String(localized: "settings.tab.proxy"))
        } footer: {
            Text(String(localized: "settings.proxy.footer"))
        }
    }

    // MARK: - Refresh interval

    private var refreshSection: some View {
        Section {
            Stepper(value: $settingsStore.refreshInterval, in: 180...900, step: 60) {
                LabeledContent(
                    String(localized: "settings.refresh.interval"),
                    value: formatInterval(settingsStore.refreshInterval)
                )
            }
        } header: {
            Text(String(localized: "settings.refresh.title"))
        } footer: {
            if settingsStore.refreshInterval < 300 {
                Label {
                    Text(String(localized: "settings.refresh.warning"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(DS.Pastel.amber)
            }
        }
    }

    // MARK: - Service status (outage monitoring)

    private var serviceStatusSection: some View {
        Section {
            Toggle(String(localized: "settings.status.master"), isOn: $settingsStore.outageMonitoringEnabled)
                .tint(DS.Pastel.green)
            if settingsStore.outageMonitoringEnabled {
                Stepper(value: $settingsStore.statusPollInterval, in: 60...1800, step: 60) {
                    LabeledContent(
                        String(localized: "settings.status.interval.label"),
                        value: formatInterval(settingsStore.statusPollInterval)
                    )
                }
                Toggle(String(localized: "settings.status.badge"), isOn: $settingsStore.statusShowMenuBarBadge)
                    .tint(DS.Pastel.green)
            }
        } header: {
            Text(String(localized: "sidebar.serviceStatus"))
        } footer: {
            Text(String(localized: "sidebar.serviceStatus.subtitle"))
        }
    }

    // MARK: - Updates

    /// In-app updater: current version + manual check row, then one
    /// state-dependent feedback row (up to date / available with install +
    /// release notes / download progress / installing / error).
    private var updatesSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.updates.current"))
                    Text("v\(updateStore.currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if updateStore.state == .checking {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await updateStore.checkNow() }
                } label: {
                    Label(String(localized: "settings.updates.check"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(updateCheckDisabled)
            }
            .padding(.vertical, 2)

            updateStatusRow
        } header: {
            Text(String(localized: "settings.updates.title"))
        }
    }

    private var updateCheckDisabled: Bool {
        switch updateStore.state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        switch updateStore.state {
        case .idle, .checking:
            EmptyView()

        case .upToDate:
            Label(String(localized: "settings.updates.uptodate"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(DS.Pastel.green)

        case .available(let info):
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: String(localized: "settings.updates.available"), info.version))
                    .font(.callout)
                HStack(spacing: 14) {
                    Button {
                        Task { await updateStore.installAvailableUpdate() }
                    } label: {
                        Label(String(localized: "settings.updates.install"), systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Pastel.green)
                    .controlSize(.small)

                    Link(String(localized: "settings.updates.notes"), destination: info.releaseURL)
                        .font(.caption)
                        .foregroundStyle(DS.Pastel.blue)
                }
            }
            .padding(.vertical, 2)

        case .downloading(let fraction):
            HStack(spacing: 10) {
                if let fraction {
                    ProgressView(value: fraction)
                        .controlSize(.small)
                        .frame(width: 120)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(String(localized: "settings.updates.downloading"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .installing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(String(localized: "settings.updates.installing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .failed(let message):
            Label {
                Text(String(format: String(localized: "settings.updates.failed"), message))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(DS.Pastel.coral)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            aboutRow(
                icon: "chevron.left.forwardslash.chevron.right",
                title: String(localized: "settings.about.repository"),
                subtitle: String(localized: "settings.about.repository.hint"),
                url: URL(string: "https://github.com/RoodsBurger/ClaudeUsage")!
            )
        } header: {
            Text(String(localized: "settings.about.title"))
        }
    }

    private func aboutRow(icon: String, title: String, subtitle: String, url: URL) -> some View {
        Link(destination: url) {
            LabeledContent {
                Image(systemName: "arrow.up.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } label: {
                Label(title, systemImage: icon)
            }
        }
        .help(subtitle)
    }

    // MARK: - Row helpers

    /// A `Toggle` with a `.caption` hint line underneath, for General's two
    /// launch-behavior rows where each toggle needs its own explanation
    /// (a single `Section` footer can only describe one thing).
    private func toggleRow(_ title: String, hint: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: isOn)
                .tint(DS.Pastel.green)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private func formatInterval(_ seconds: Int) -> String {
        let minutes = seconds / 60
        return "\(minutes) min"
    }

    private func connectAutoDetect() {
        isImporting = true
        importMessage = nil
        guard settingsStore.credentialsTokenExists() else {
            isImporting = false
            importMessage = String(localized: "connect.noclaudecode")
            importSuccess = false
            return
        }
        Task {
            let result = await usageStore.connectAutoDetect()
            isImporting = false
            if result.success {
                importMessage = String(localized: "connect.oauth.success")
                importSuccess = true
                usageStore.proxyConfig = settingsStore.proxyConfig
                usageStore.reloadConfig(thresholds: settingsStore.thresholds)
            } else {
                importMessage = result.message
                importSuccess = false
            }
        }
    }

    private func signOutOfClaude() {
        connectFlow.signOut()
        usageStore.handleTokenChange()
        usageStore.reloadConfig(thresholds: settingsStore.thresholds)
    }

    // MARK: - Sign in with Claude

    /// Durable own-login management, below the existing borrowed-token status
    /// row: connected state (account email + Sign out) when the app owns an
    /// OAuth login, otherwise the primary "Sign in with Claude" CTA plus the
    /// labeled secondary "Use Claude Code's session" borrow path and the
    /// browser-waiting / manual-paste / error states.
    @ViewBuilder
    private var signInWithClaudeBlock: some View {
        if connectFlow.isSignedInWithClaude {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(DS.Pastel.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "connect.signin.success"))
                        .font(.callout)
                    if let email = connectFlow.connectedAccountEmail {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    signOutOfClaude()
                } label: {
                    Text(String(localized: "connect.signin.signout"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                switch connectFlow.oauthSignInStatus {
                case .idle:
                    HStack(spacing: 10) {
                        Button {
                            connectFlow.signInWithClaude()
                        } label: {
                            Label(String(localized: "connect.signin.title"), systemImage: "person.badge.key.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DS.Pastel.green)
                        .controlSize(.small)

                        Button(String(localized: "connect.secondary.title")) {
                            connectAutoDetect()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Text(String(localized: "connect.secondary.subtitle"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                case .browserOpenedWaiting:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "connect.signin.waiting"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 14) {
                        Button(String(localized: "connect.signin.manualpaste.link")) {
                            connectFlow.switchToManualPaste()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(DS.Pastel.blue)

                        Button(String(localized: "connect.signin.cancel")) {
                            connectFlow.cancelSignIn()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }

                case .manualCodePaste:
                    Text(String(localized: "connect.signin.manualpaste.prompt"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "connect.signin.manualpaste.placeholder"), text: $connectFlow.manualPasteCode)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 14) {
                        Button(String(localized: "connect.signin.manualpaste.submit")) {
                            connectFlow.submitManualPasteCode()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DS.Pastel.green)
                        .controlSize(.small)
                        .disabled(connectFlow.isSubmittingManualCode
                                  || connectFlow.manualPasteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(String(localized: "connect.signin.cancel")) {
                            connectFlow.cancelSignIn()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }

                case .success:
                    Label(String(localized: "connect.signin.success"), systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(DS.Pastel.green)

                case .failed(let error):
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text(OAuthErrorFormatter.message(for: error))
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(DS.Pastel.coral)
                        HStack(spacing: 14) {
                            Button(String(localized: "connect.signin.title")) {
                                connectFlow.signInWithClaude()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DS.Pastel.green)
                            .controlSize(.small)

                            Button(String(localized: "connect.signin.manualpaste.link")) {
                                connectFlow.switchToManualPaste()
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(DS.Pastel.blue)
                        }
                    }
                }
            }
        }
    }
}
