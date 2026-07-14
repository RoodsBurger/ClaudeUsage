import SwiftUI

/// Single-screen onboarding: logo, title, caption, the "Sign in with Claude"
/// connect flow (own OAuth login, or borrow Claude Code's session), and an
/// optional notifications opt-in. Replaces the old 2x2 card deck. The chrome
/// (solid dark window) is provided by `MainAppView.onboardingContent`; this
/// view fills it edge to edge.
struct OnboardingHeroView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var usageStore: UsageStore

    /// Local state for the "Use Claude Code's session" borrow flow - kept
    /// outside `OnboardingViewModel` since it drives `UsageStore.connectAutoDetect()`
    /// directly, mirroring `SettingsSectionView`'s own connectAutoDetect wrapper.
    @State private var isAutoDetecting = false
    @State private var autoDetectMessage: String?
    @State private var autoDetectSucceeded = false

    /// True once either connect path has produced a usable token: an
    /// app-owned OAuth login, or a successfully borrowed Claude Code session.
    private var isConnected: Bool {
        viewModel.isSignedInWithClaude || viewModel.oauthSignInStatus == .success || autoDetectSucceeded
    }

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            Spacer(minLength: 0)

            logo

            VStack(spacing: DS.Spacing.xs) {
                Text("RaiUsage")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(String(localized: "onboarding.hero.caption"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            connectArea
                .frame(maxWidth: 340)

            Spacer(minLength: 0)

            notificationsRow
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Pastel.base)
        .animation(DS.Motion.easeInOut, value: viewModel.oauthSignInStatus)
        .animation(DS.Motion.easeInOut, value: isConnected)
        .onAppear { viewModel.checkNotificationStatus() }
        .task { await viewModel.refreshConnectedAccountEmail() }
    }

    // MARK: - Logo

    private var logo: some View {
        ZStack {
            Circle()
                .fill(DS.Pastel.green.opacity(0.15))
                .frame(width: DS.IconDisc.hero, height: DS.IconDisc.hero)
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
        }
    }

    // MARK: - Connect area

    @ViewBuilder
    private var connectArea: some View {
        if isConnected {
            successBlock
        } else {
            switch viewModel.oauthSignInStatus {
            case .idle:
                idleBlock
            case .browserOpenedWaiting:
                waitingBlock
            case .manualCodePaste:
                manualPasteBlock
            case .success:
                successBlock
            case .failed(let error):
                failedBlock(error)
            }
        }
    }

    private var idleBlock: some View {
        VStack(spacing: DS.Spacing.sm) {
            Button {
                viewModel.signInWithClaude()
            } label: {
                Text(String(localized: "connect.signin.title"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(DS.Pastel.green)

            Button {
                runAutoDetect()
            } label: {
                if isAutoDetecting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(String(localized: "connect.secondary.title"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isAutoDetecting)

            Text(String(localized: "connect.secondary.subtitle"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if let message = autoDetectMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DS.Pastel.coral)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var waitingBlock: some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "connect.signin.waiting"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Button(String(localized: "connect.signin.manualpaste.link")) {
                    viewModel.switchToManualPaste()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(DS.Pastel.blue)

                Button(String(localized: "connect.signin.cancel")) {
                    viewModel.cancelSignIn()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var manualPasteBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(String(localized: "connect.signin.manualpaste.prompt"))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(String(localized: "connect.signin.manualpaste.placeholder"), text: $viewModel.manualPasteCode)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 16) {
                Button(String(localized: "connect.signin.manualpaste.submit")) {
                    viewModel.submitManualPasteCode()
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Pastel.green)
                .controlSize(.small)
                .disabled(viewModel.isSubmittingManualCode
                          || viewModel.manualPasteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(String(localized: "connect.signin.cancel")) {
                    viewModel.cancelSignIn()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func failedBlock(_ error: OAuthError) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Label {
                Text(OAuthErrorFormatter.message(for: error))
                    .font(.caption)
                    .multilineTextAlignment(.center)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(DS.Pastel.coral)

            HStack(spacing: 16) {
                Button(String(localized: "connect.signin.title")) {
                    viewModel.signInWithClaude()
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Pastel.green)
                .controlSize(.small)

                Button(String(localized: "connect.signin.manualpaste.link")) {
                    viewModel.switchToManualPaste()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(DS.Pastel.blue)
            }
        }
    }

    private var successBlock: some View {
        VStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DS.Pastel.green.opacity(0.15))
                    .frame(width: DS.IconDisc.standard, height: DS.IconDisc.standard)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Pastel.green)
            }

            Text(String(localized: "connect.signin.success"))
                .font(.callout)

            if let email = viewModel.connectedAccountEmail {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                settingsStore.hasCompletedOnboarding = true
            } label: {
                Text(String(localized: "onboarding.hero.done"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(DS.Pastel.green)
            .padding(.top, DS.Spacing.xs)
        }
    }

    // MARK: - Notifications (optional)

    @ViewBuilder
    private var notificationsRow: some View {
        switch viewModel.notificationStatus {
        case .unknown, .denied:
            EmptyView()
        case .notYetAsked:
            Button {
                viewModel.requestNotifications()
            } label: {
                Label(String(localized: "onboarding.hero.notifications"), systemImage: "bell")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .authorized:
            Label(String(localized: "onboarding.hero.notifications.enabled"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(DS.Pastel.green)
        }
    }

    // MARK: - Use Claude Code's session (borrowed token)

    /// Mirrors `SettingsSectionView.connectAutoDetect()`: guards on a token
    /// source existing first (a friendlier failure than the async round trip),
    /// then tests the borrowed token via `UsageStore.connectAutoDetect()`.
    private func runAutoDetect() {
        autoDetectMessage = nil
        guard settingsStore.credentialsTokenExists() else {
            autoDetectMessage = String(localized: "connect.noclaudecode")
            return
        }
        isAutoDetecting = true
        Task {
            let result = await usageStore.connectAutoDetect()
            isAutoDetecting = false
            if result.success {
                autoDetectSucceeded = true
            } else {
                autoDetectMessage = result.message
            }
        }
    }
}
