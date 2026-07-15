import SwiftUI

struct SettingsSectionView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var updateStore: UpdateStore
    @EnvironmentObject private var remoteInstancesStore: RemoteInstancesStore

    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var importSuccess = false

    // Add-instance form fields for the Remote sessions section.
    @State private var newRemoteNickname = ""
    @State private var newRemoteHost = ""
    @State private var newRemoteUser = ""
    @State private var remoteAddError: String?
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
                remoteSessionsSection
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

            // Estimated cost is an enterprise-only surface: the row only exists
            // on the enterprise plan, so personal plans stay pixel-identical.
            if usageStore.planType == .enterprise {
                toggleRow(
                    String(localized: "settings.general.showCost"),
                    hint: String(localized: "settings.general.showCost.hint"),
                    isOn: $settingsStore.display.showCostEstimate
                )
            }

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

    // MARK: - Remote sessions (SSH)

    /// Manage the remote instances whose Claude Code session logs are pulled
    /// over SSH so History / activity / cost include them. Available on all
    /// plans. Keys only, no passwords - see `RemoteLogSyncService`.
    private var remoteSessionsSection: some View {
        Section {
            ForEach(remoteInstancesStore.instances) { instance in
                RemoteInstanceRow(
                    instance: instance,
                    status: remoteInstancesStore.status[instance.id],
                    onToggle: { remoteInstancesStore.setEnabled(instance.id, $0) },
                    onSync: { remoteInstancesStore.syncNow(instance.id) },
                    onRemove: { remoteInstancesStore.removeInstance(instance.id) }
                )
            }

            addRemoteInstanceRow

            // Explicitly-styled helper instead of a Section `footer:` - the
            // default footer rendering varies across macOS versions and looked
            // inconsistent; this keeps one appearance everywhere.
            Text(String(localized: "settings.remote.footer"))
                .settingsHelperCaption()
        } header: {
            Text(String(localized: "settings.remote.title"))
        }
    }

    private var canAddRemoteInstance: Bool {
        !newRemoteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !newRemoteUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// New-instance form. `prompt:` renders the gray in-field placeholder (a
    /// macOS Form otherwise pulls a plain placeholder out as a leading label);
    /// `.labelsHidden()` drops the redundant label. The user/host pair sits on
    /// one line with a literal `@` between, equal width, mirroring the actual
    /// `ssh user@host` call. Nickname is its own optional row; Add is trailing.
    private var addRemoteInstanceRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                String(localized: "settings.remote.nickname.label"),
                text: $newRemoteNickname,
                prompt: Text(String(localized: "settings.remote.nickname.placeholder"))
            )
            .textFieldStyle(.roundedBorder)
            .labelsHidden()

            HStack(spacing: 8) {
                TextField(
                    String(localized: "settings.remote.user.label"),
                    text: $newRemoteUser,
                    prompt: Text(String(localized: "settings.remote.user.placeholder"))
                )
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Text(verbatim: "@")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)

                TextField(
                    String(localized: "settings.remote.host.label"),
                    text: $newRemoteHost,
                    prompt: Text(String(localized: "settings.remote.host.placeholder"))
                )
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                if let remoteAddError {
                    Label(remoteAddError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(DS.Pastel.coral)
                        .transition(.opacity)
                } else {
                    Text(String(localized: "settings.remote.hint"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(String(localized: "settings.remote.add")) {
                    addRemoteInstance()
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Pastel.green)
                .controlSize(.small)
                .disabled(!canAddRemoteInstance)
            }
        }
        .padding(.vertical, 2)
    }

    private func addRemoteInstance() {
        let nickname = newRemoteNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = remoteInstancesStore.addInstance(
            host: newRemoteHost,
            user: newRemoteUser,
            nickname: nickname.isEmpty ? nil : nickname
        )
        if ok {
            newRemoteNickname = ""
            newRemoteHost = ""
            newRemoteUser = ""
            remoteAddError = nil
        } else {
            remoteAddError = String(localized: "settings.remote.invalid")
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

            Text(String(localized: "settings.proxy.footer"))
                .settingsHelperCaption()
        } header: {
            Text(String(localized: "settings.tab.proxy"))
        }
    }

    // MARK: - Refresh interval

    private var refreshSection: some View {
        Section {
            Picker(selection: $settingsStore.refreshInterval) {
                ForEach(intervalOptions([180, 300, 600, 900], current: settingsStore.refreshInterval), id: \.self) {
                    Text(formatInterval($0)).tag($0)
                }
            } label: {
                Text(String(localized: "settings.refresh.interval"))
            }
            .pickerStyle(.menu)

            if settingsStore.refreshInterval < 300 {
                Label {
                    Text(String(localized: "settings.refresh.warning"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(DS.Pastel.amber)
                .settingsHelperCaption()
            }
        } header: {
            Text(String(localized: "settings.refresh.title"))
        }
    }

    // MARK: - Service status (outage monitoring)

    private var serviceStatusSection: some View {
        Section {
            Toggle(String(localized: "settings.status.master"), isOn: $settingsStore.outageMonitoringEnabled)
                .tint(DS.Pastel.green)
            if settingsStore.outageMonitoringEnabled {
                Picker(selection: $settingsStore.statusPollInterval) {
                    ForEach(intervalOptions([60, 120, 300, 600, 900, 1800], current: settingsStore.statusPollInterval), id: \.self) {
                        Text(formatInterval($0)).tag($0)
                    }
                } label: {
                    Text(String(localized: "settings.status.interval.label"))
                }
                .pickerStyle(.menu)
                Toggle(String(localized: "settings.status.badge"), isOn: $settingsStore.statusShowMenuBarBadge)
                    .tint(DS.Pastel.green)
            }
        } header: {
            Text(String(localized: "sidebar.serviceStatus"))
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
                    Label(String(localized: "settings.updates.check"), systemImage: "arrow.clockwise")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .tint(DS.Pastel.blue)
                .controlSize(.small)
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
                url: URL(string: "https://github.com/RoodsBurger/RaiUsage")!
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

    /// Preset interval choices for a menu Picker, keeping any previously-saved
    /// off-grid value selectable so the picker never shows a blank selection.
    private func intervalOptions(_ presets: [Int], current: Int) -> [Int] {
        (presets.contains(current) ? presets : presets + [current]).sorted()
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

// MARK: - Remote instance row

/// One configured remote instance: enable toggle + nickname/target, a "Sync
/// now" action, remove, and the last-status line. The enable toggle mirrors
/// the model into local `@State` and syncs back via `.onChange` - the SwiftUI
/// rules forbid `Binding(get:set:)` / bindings to store-derived values.
private struct RemoteInstanceRow: View {
    let instance: RemoteInstance
    let status: RemoteSyncStatus?
    let onToggle: (Bool) -> Void
    let onSync: () -> Void
    let onRemove: () -> Void

    @State private var enabled: Bool

    init(
        instance: RemoteInstance,
        status: RemoteSyncStatus?,
        onToggle: @escaping (Bool) -> Void,
        onSync: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.instance = instance
        self.status = status
        self.onToggle = onToggle
        self.onSync = onSync
        self.onRemove = onRemove
        _enabled = State(initialValue: instance.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .tint(DS.Pastel.green)

                VStack(alignment: .leading, spacing: 1) {
                    Text(instance.displayLabel)
                        .font(.callout)
                    // Show the SSH target as a subline whenever a nickname is
                    // the primary label, so the host stays visible.
                    if instance.nickname?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Text(instance.sshTarget)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    onSync()
                } label: {
                    Label(String(localized: "settings.remote.syncNow"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(isSyncing || !enabled)

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(String(localized: "settings.remote.remove"))
            }

            statusLine
        }
        .padding(.vertical, 2)
        .onChange(of: enabled) { _, newValue in
            if newValue != instance.enabled { onToggle(newValue) }
        }
        .onChange(of: instance.enabled) { _, newValue in
            if newValue != enabled { enabled = newValue }
        }
    }

    private var isSyncing: Bool {
        if case .syncing = status?.state { return true }
        return false
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status?.state {
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(String(localized: "settings.remote.status.syncing"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .synced(let count, let at):
            Text(String(format: String(localized: "settings.remote.status.synced"),
                        count, at.formatted(.relative(presentation: .named))))
                .font(.caption2)
                .foregroundStyle(DS.Pastel.green)
        case .failed(let message):
            Label {
                Text(message)
                    .font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(DS.Pastel.coral)
        case .idle, .none:
            EmptyView()
        }
    }
}
