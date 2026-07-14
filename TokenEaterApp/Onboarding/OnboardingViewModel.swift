import SwiftUI
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.raiusage.app", category: "Onboarding")

enum ClaudeCodeStatus {
    case checking
    case detected
    case notFound
}

enum ConnectionStatus {
    case idle
    case connecting
    case success(UsageResponse)
    case rateLimited
    case failed(String)
}

enum NotificationStatus {
    case unknown
    case authorized
    case denied
    case notYetAsked
}

/// State machine for the "Sign in with Claude" own-OAuth-login flow, as
/// distinct from `ConnectionStatus` (the borrowed Claude Code token flow).
enum OAuthSignInStatus: Equatable {
    case idle
    /// The browser was opened and the loopback listener is waiting for the
    /// authorization callback.
    case browserOpenedWaiting
    /// The user is pasting the "code#state" string from the fallback page
    /// (chosen manually, or shown as an option while waiting).
    case manualCodePaste
    case success
    case failed(OAuthError)
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var claudeCodeStatus: ClaudeCodeStatus = .checking
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var notificationStatus: NotificationStatus = .unknown
    /// Drives the "Sign in with Claude" own-login UI, separate from
    /// `connectionStatus` (the borrowed-token flow via `connect()`).
    @Published var oauthSignInStatus: OAuthSignInStatus = .idle
    /// Bound to the manual "code#state" paste field shown in `.manualCodePaste`.
    @Published var manualPasteCode: String = ""
    /// True while a manual-paste exchange is in flight, so the UI can disable
    /// the submit button and prevent a double-submit / duplicate exchange.
    @Published var isSubmittingManualCode: Bool = false
    /// Account email for the connected-state display, fetched from the
    /// profile endpoint once a durable OAuth login exists.
    @Published var connectedAccountEmail: String?

    /// Total number of cards the user can interact with. Used by the hero
    /// progress indicator. Hard-coded at 3 (Claude Code, Notifications,
    /// Connect).
    let totalSteps: Int = 3

    private let tokenProvider: TokenProviderProtocol
    private let repository: UsageRepositoryProtocol
    private let notificationService: NotificationServiceProtocol
    private let oauthService: OAuthServiceProtocol

    init(
        tokenProvider: TokenProviderProtocol = TokenProvider(),
        repository: UsageRepositoryProtocol = UsageRepository(),
        notificationService: NotificationServiceProtocol = NotificationService(),
        oauthService: OAuthServiceProtocol = OAuthService()
    ) {
        self.tokenProvider = tokenProvider
        self.repository = repository
        self.notificationService = notificationService
        self.oauthService = oauthService
    }

    /// Whether the app currently owns a durable "Sign in with Claude" login,
    /// as opposed to only a borrowed Claude Code/Desktop token.
    var isSignedInWithClaude: Bool { tokenProvider.hasOwnOAuthLogin() }

    /// Whether the user might see a Keychain dialog (first connection attempt)
    var needsBootstrap: Bool { tokenProvider.currentToken() == nil }

    /// Gating rule for the Finish button. Both required cards must succeed:
    /// Claude Code detected AND Connect connected (rateLimited counts as
    /// connected because the token works - server is just throttling).
    var canFinish: Bool {
        guard claudeCodeStatus == .detected else { return false }
        switch connectionStatus {
        case .success, .rateLimited:
            return true
        default:
            return false
        }
    }

    /// Hero progress count - how many of the 3 cards are in their "ready"
    /// state. Both gates must be green; the optional toggle counts as ready
    /// when authorized (Notifications).
    var readyCount: Int {
        var count = 0
        if claudeCodeStatus == .detected { count += 1 }
        if notificationStatus == .authorized { count += 1 }
        switch connectionStatus {
        case .success, .rateLimited:
            count += 1
        default:
            break
        }
        return count
    }

    func checkClaudeCode() {
        claudeCodeStatus = .checking
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            // Check if a token source EXISTS (config.json or credentials file)
            // This doesn't require the decryption key - bootstrap happens in connect()
            let hasSource = self.tokenProvider.hasTokenSource()
            self.claudeCodeStatus = hasSource ? .detected : .notFound
        }
    }

    func checkNotificationStatus() {
        Task {
            let status = await notificationService.checkAuthorizationStatus()
            switch status {
            case .authorized, .provisional, .ephemeral:
                notificationStatus = .authorized
            case .denied:
                notificationStatus = .denied
            case .notDetermined:
                notificationStatus = .notYetAsked
            @unknown default:
                notificationStatus = .unknown
            }
        }
    }

    func requestNotifications() {
        notificationService.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkNotificationStatus()
        }
    }

    func sendTestNotification() {
        notificationService.sendTest()
    }

    func connect() {
        connectionStatus = .connecting

        // Bootstrap encryption key if needed (triggers one-time Keychain modal)
        if !tokenProvider.isBootstrapped {
            logger.info("Bootstrap needed - reading Claude Safe Storage from Keychain")
            do {
                try tokenProvider.bootstrap()
                logger.info("Bootstrap succeeded, isBootstrapped=\(self.tokenProvider.isBootstrapped)")
            } catch {
                logger.error("Bootstrap failed: \(error)")
                connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }

        let token = tokenProvider.currentToken()
        logger.info("currentToken result: \(token != nil ? "got token (\(token!.prefix(10))...)" : "nil")")
        guard let token else {
            logger.error("No token after bootstrap - hasTokenSource=\(self.tokenProvider.hasTokenSource()), isBootstrapped=\(self.tokenProvider.isBootstrapped)")
            connectionStatus = .failed(String(localized: "onboarding.connection.failed.notoken"))
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        Task {
            do {
                let usage = try await repository.testConnection(token: token, proxyConfig: nil)
                connectionStatus = .success(usage)
            } catch let error as APIError {
                if case .rateLimited = error {
                    connectionStatus = .rateLimited
                } else {
                    connectionStatus = .failed(error.localizedDescription)
                }
            } catch {
                connectionStatus = .failed(error.localizedDescription)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func completeOnboarding() {
    }

    // MARK: - Sign in with Claude (own OAuth login)

    /// Starts the durable own-login flow: opens the browser and waits on the
    /// loopback callback. `OAuthService`'s completion is documented to land
    /// on the main queue, so it is safe to update published state directly
    /// from it on this `@MainActor` type.
    func signInWithClaude() {
        manualPasteCode = ""
        isSubmittingManualCode = false
        oauthSignInStatus = .browserOpenedWaiting
        oauthService.beginLogin { [weak self] result in
            self?.handleOAuthResult(result)
        }
    }

    /// Switches the UI to the manual "code#state" paste field - offered
    /// alongside the waiting state since a rejected loopback redirect never
    /// surfaces as a distinct error (the browser tab simply never calls back).
    func switchToManualPaste() {
        oauthSignInStatus = .manualCodePaste
    }

    func submitManualPasteCode() {
        guard !isSubmittingManualCode else { return }
        isSubmittingManualCode = true
        oauthService.completeManualLogin(pasted: manualPasteCode) { [weak self] result in
            self?.handleOAuthResult(result)
        }
    }

    /// Cancels an in-flight `signInWithClaude()`/`submitManualPasteCode()` attempt.
    func cancelSignIn() {
        oauthService.cancelLogin()
        oauthSignInStatus = .idle
        manualPasteCode = ""
        isSubmittingManualCode = false
    }

    /// Signs out of the app-owned OAuth login. The app falls back to a
    /// borrowed Claude Code/Desktop token on the next read, if one exists.
    func signOut() {
        tokenProvider.disconnectOAuth()
        oauthSignInStatus = .idle
        manualPasteCode = ""
        isSubmittingManualCode = false
        connectedAccountEmail = nil
    }

    /// Fetches the connected account's email for the connected-state display.
    /// No-op when there is no durable OAuth login, or the profile fetch fails
    /// (non-critical - the connected state still shows without an email).
    @discardableResult
    func refreshConnectedAccountEmail() async -> String? {
        guard isSignedInWithClaude, let token = tokenProvider.currentToken() else { return nil }
        guard let profile = try? await repository.fetchProfile(token: token, proxyConfig: nil) else { return nil }
        connectedAccountEmail = profile.account.email
        return profile.account.email
    }

    private func handleOAuthResult(_ result: Result<OAuthTokens, OAuthError>) {
        isSubmittingManualCode = false
        switch result {
        case .success(let tokens):
            do {
                try tokenProvider.completeOAuthLogin(tokens)
                oauthSignInStatus = .success
                manualPasteCode = ""
                Task { await self.refreshConnectedAccountEmail() }
            } catch {
                oauthSignInStatus = .failed(.persistenceFailed)
            }
        case .failure(let error):
            oauthSignInStatus = .failed(error)
        }
    }
}
