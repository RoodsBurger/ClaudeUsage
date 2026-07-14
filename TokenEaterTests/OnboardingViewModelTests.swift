import Testing
import Foundation

private let settingsKeys = ["hasCompletedOnboarding"]

private func cleanDefaults() {
    for key in settingsKeys {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@Suite("OnboardingViewModel", .serialized)
@MainActor
struct OnboardingViewModelTests {

    private func makeViewModel(
        tokenProvider: TokenProviderProtocol = MockTokenProvider(),
        repository: UsageRepositoryProtocol = MockUsageRepository(),
        notificationService: NotificationServiceProtocol = MockNotificationService(),
        oauthService: OAuthServiceProtocol = MockOAuthService()
    ) -> OnboardingViewModel {
        cleanDefaults()
        return OnboardingViewModel(
            tokenProvider: tokenProvider,
            repository: repository,
            notificationService: notificationService,
            oauthService: oauthService
        )
    }

    // MARK: - Sign in with Claude

    @Test("signInWithClaude sets browserOpenedWaiting synchronously before the browser callback resolves")
    func signInWithClaudeSetsWaitingState() {
        let oauthService = MockOAuthService()
        oauthService.deferLoginCompletion = true
        let vm = makeViewModel(oauthService: oauthService)

        vm.signInWithClaude()

        #expect(vm.oauthSignInStatus == .browserOpenedWaiting)
        #expect(oauthService.beginLoginCallCount == 1)
    }

    @Test("signInWithClaude success persists tokens and moves to success")
    func signInWithClaudeSuccessConnects() {
        let oauthService = MockOAuthService()
        let tokens = OAuthTokens(accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture)
        oauthService.stubbedLoginResult = .success(tokens)
        let tokenProvider = MockTokenProvider()
        let vm = makeViewModel(tokenProvider: tokenProvider, oauthService: oauthService)

        vm.signInWithClaude()

        #expect(vm.oauthSignInStatus == .success)
        #expect(tokenProvider.completeOAuthLoginCallCount == 1)
        #expect(tokenProvider.lastCompletedOAuthLogin == tokens)
    }

    @Test("signInWithClaude failure surfaces the typed OAuthError")
    func signInWithClaudeFailureSetsErrorState() {
        let oauthService = MockOAuthService()
        oauthService.stubbedLoginResult = .failure(.exchangeFailed(500))
        let vm = makeViewModel(oauthService: oauthService)

        vm.signInWithClaude()

        #expect(vm.oauthSignInStatus == .failed(.exchangeFailed(500)))
    }

    @Test("signInWithClaude surfaces a persistence failure as a dedicated persistenceFailed error")
    func signInWithClaudePersistenceFailureSetsErrorState() {
        let oauthService = MockOAuthService()
        let tokens = OAuthTokens(accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture)
        oauthService.stubbedLoginResult = .success(tokens)
        let tokenProvider = MockTokenProvider()
        struct SaveError: Error {}
        tokenProvider.completeOAuthLoginError = SaveError()
        let vm = makeViewModel(tokenProvider: tokenProvider, oauthService: oauthService)

        vm.signInWithClaude()

        #expect(vm.oauthSignInStatus == .failed(.persistenceFailed))
    }

    @Test("switchToManualPaste moves to the manual code paste state")
    func switchToManualPasteTransitions() {
        let oauthService = MockOAuthService()
        oauthService.deferLoginCompletion = true
        let vm = makeViewModel(oauthService: oauthService)
        vm.signInWithClaude()

        vm.switchToManualPaste()

        #expect(vm.oauthSignInStatus == .manualCodePaste)
    }

    @Test("submitManualPasteCode success completes the login with the pasted code")
    func submitManualPasteCodeSuccess() {
        let oauthService = MockOAuthService()
        let tokens = OAuthTokens(accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture)
        oauthService.stubbedManualLoginResult = .success(tokens)
        let tokenProvider = MockTokenProvider()
        let vm = makeViewModel(tokenProvider: tokenProvider, oauthService: oauthService)
        vm.manualPasteCode = "abc123#state456"

        vm.submitManualPasteCode()

        #expect(oauthService.lastManualPaste == "abc123#state456")
        #expect(vm.oauthSignInStatus == .success)
        #expect(tokenProvider.completeOAuthLoginCallCount == 1)
    }

    @Test("submitManualPasteCode failure surfaces the typed OAuthError")
    func submitManualPasteCodeFailure() {
        let oauthService = MockOAuthService()
        oauthService.stubbedManualLoginResult = .failure(.malformedCallback)
        let vm = makeViewModel(oauthService: oauthService)
        vm.manualPasteCode = "garbage"

        vm.submitManualPasteCode()

        #expect(vm.oauthSignInStatus == .failed(.malformedCallback))
    }

    @Test("submitManualPasteCode ignores a second call while one exchange is in flight")
    func submitManualPasteCodeGuardsAgainstDoubleSubmit() {
        let oauthService = MockOAuthService()
        oauthService.deferLoginCompletion = true
        let vm = makeViewModel(oauthService: oauthService)
        vm.manualPasteCode = "code#state"

        vm.submitManualPasteCode()
        #expect(vm.isSubmittingManualCode == true)

        // Second tap while the first is unresolved must not start another exchange.
        vm.submitManualPasteCode()
        #expect(oauthService.completeManualLoginCallCount == 1)

        // Resolving clears the in-flight flag so a later retry is allowed.
        oauthService.resolvePendingLogin(.failure(.malformedCallback))
        #expect(vm.isSubmittingManualCode == false)
    }

    @Test("cancelSignIn cancels the in-flight login and resets to idle")
    func cancelSignInResetsToIdle() {
        let oauthService = MockOAuthService()
        oauthService.deferLoginCompletion = true
        let vm = makeViewModel(oauthService: oauthService)
        vm.signInWithClaude()
        vm.manualPasteCode = "leftover"

        vm.cancelSignIn()

        #expect(oauthService.cancelLoginCallCount == 1)
        #expect(vm.oauthSignInStatus == .idle)
        #expect(vm.manualPasteCode == "")
    }

    @Test("signOut disconnects OAuth and resets the sign-in state")
    func signOutDisconnectsAndResets() {
        let oauthService = MockOAuthService()
        let tokens = OAuthTokens(accessToken: "access", refreshToken: "refresh", expiresAt: .distantFuture)
        oauthService.stubbedLoginResult = .success(tokens)
        let tokenProvider = MockTokenProvider()
        let vm = makeViewModel(tokenProvider: tokenProvider, oauthService: oauthService)
        vm.signInWithClaude()
        vm.connectedAccountEmail = "user@example.com"

        vm.signOut()

        #expect(tokenProvider.disconnectOAuthCallCount == 1)
        #expect(vm.oauthSignInStatus == .idle)
        #expect(vm.connectedAccountEmail == nil)
    }

    @Test("isSignedInWithClaude mirrors tokenProvider.hasOwnOAuthLogin")
    func isSignedInWithClaudeMirrorsTokenProvider() {
        let tokenProvider = MockTokenProvider()
        let vm = makeViewModel(tokenProvider: tokenProvider)
        #expect(vm.isSignedInWithClaude == false)

        tokenProvider._hasOwnOAuthLogin = true
        #expect(vm.isSignedInWithClaude == true)
    }

    @Test("refreshConnectedAccountEmail populates the email when signed in with Claude")
    func refreshConnectedAccountEmailPopulatesWhenSignedIn() async {
        let tokenProvider = MockTokenProvider()
        tokenProvider._hasOwnOAuthLogin = true
        tokenProvider.token = "own-access-token"
        let repository = MockUsageRepository()
        repository.stubbedProfile = .fixture(email: "owner@example.com")
        let vm = makeViewModel(tokenProvider: tokenProvider, repository: repository)

        let email = await vm.refreshConnectedAccountEmail()

        #expect(email == "owner@example.com")
        #expect(vm.connectedAccountEmail == "owner@example.com")
        #expect(repository.fetchProfileCallCount == 1)
    }

    @Test("refreshConnectedAccountEmail is a no-op when there is no own OAuth login")
    func refreshConnectedAccountEmailNoOpWhenBorrowedOnly() async {
        let tokenProvider = MockTokenProvider()
        tokenProvider._hasOwnOAuthLogin = false
        tokenProvider.token = "borrowed-token"
        let repository = MockUsageRepository()
        let vm = makeViewModel(tokenProvider: tokenProvider, repository: repository)

        let email = await vm.refreshConnectedAccountEmail()

        #expect(email == nil)
        #expect(vm.connectedAccountEmail == nil)
        #expect(repository.fetchProfileCallCount == 0)
    }

}
