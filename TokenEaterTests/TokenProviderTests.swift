import Testing
import Foundation

@Suite("TokenProvider")
struct TokenProviderTests {

    // MARK: - Helpers

    /// keychainReader that always returns nil (no Keychain in tests)
    private static let noKeychain: TokenProvider.KeychainTokenReader = { _ in nil }

    /// A per-call, guaranteed-nonexistent import file path. Every `TokenProvider`
    /// construction in this suite must pass an explicit import URL (never the
    /// real default) so tests never touch the real filesystem or Keychain.
    private static var noImportFileURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenProviderTests-\(UUID().uuidString)")
            .appendingPathComponent("oauth-import.json")
    }

    private func makeSUT(
        securityCLIToken: String? = nil,
        credentialsToken: String? = nil,
        keychainToken: String? = nil,
        encryptedToken: String? = nil,
        hasEncryptionKey: Bool = false,
        decryptedData: Data? = nil,
        oauthTokens: OAuthTokens? = nil,
        oauthRefreshResult: Result<OAuthTokens, OAuthError> = .failure(.cancelled)
    ) -> (TokenProvider, MockSecurityCLIReader, MockCredentialsFileReader, MockClaudeConfigReader, MockElectronDecryptionService, MockOAuthTokenStore, MockOAuthService) {
        let securityCLI = MockSecurityCLIReader()
        securityCLI.token = securityCLIToken

        let credentials = MockCredentialsFileReader()
        credentials.storedToken = credentialsToken

        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = encryptedToken

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = hasEncryptionKey
        decryption.decryptedData = decryptedData

        let keychainReader: TokenProvider.KeychainTokenReader = { _ in keychainToken }

        let oauthStore = MockOAuthTokenStore()
        if let oauthTokens {
            try? oauthStore.save(oauthTokens)
        }

        let oauthService = MockOAuthService()
        oauthService.stubbedRefreshResult = oauthRefreshResult

        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: keychainReader,
            oauthService: oauthService,
            oauthTokenStore: oauthStore,
            oauthImportFileURL: Self.noImportFileURL
        )

        return (provider, securityCLI, credentials, configReader, decryption, oauthStore, oauthService)
    }

    // MARK: - Tests

    @Test("security CLI is the primary source")
    func securityCLIFirst() {
        let (provider, securityCLI, _, _, decryption, _, _) = makeSUT(
            securityCLIToken: "security-token",
            credentialsToken: "creds-token",
            keychainToken: "keychain-token",
            encryptedToken: "some-encrypted",
            hasEncryptionKey: true
        )

        let token = provider.currentToken()

        #expect(token == "security-token")
        #expect(securityCLI.readCallCount == 1)
        #expect(decryption.decryptCallCount == 0)
    }

    @Test("falls back to credentials file when security CLI returns nil")
    func fallbackToCredentialsFile() {
        let (provider, _, _, _, decryption, _, _) = makeSUT(
            securityCLIToken: nil,
            credentialsToken: "creds-token",
            keychainToken: "keychain-token"
        )

        let token = provider.currentToken()

        #expect(token == "creds-token")
        #expect(decryption.decryptCallCount == 0)
    }

    @Test("falls back to keychain when security CLI and credentials file miss")
    func fallbackToKeychain() {
        let (provider, _, _, _, decryption, _, _) = makeSUT(
            securityCLIToken: nil,
            credentialsToken: nil,
            keychainToken: "keychain-token"
        )

        let token = provider.currentToken()

        #expect(token == "keychain-token")
        #expect(decryption.decryptCallCount == 0)
    }

    @Test("falls back to config.json decryption when earlier sources miss")
    func fallbackToConfigDecryption() {
        let oauthJSON: [String: Any] = [
            "claudeAiOauth": ["accessToken": "decrypted-token"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

        let (provider, _, _, _, decryption, _, _) = makeSUT(
            securityCLIToken: nil,
            credentialsToken: nil,
            keychainToken: nil,
            encryptedToken: "encrypted-blob",
            hasEncryptionKey: true,
            decryptedData: jsonData
        )

        let token = provider.currentToken()

        #expect(token == "decrypted-token")
        #expect(decryption.decryptCallCount == 1)
    }

    @Test("extracts token from UUID-based config.json format")
    func extractsUUIDFormat() {
        let uuidJSON: [String: Any] = [
            "uuid:uuid:https://api.anthropic.com": ["token": "sk-ant-test-only-no-real-secret"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: uuidJSON)

        let (provider, _, _, _, _, _, _) = makeSUT(
            securityCLIToken: nil,
            credentialsToken: nil,
            keychainToken: nil,
            encryptedToken: "encrypted-blob",
            hasEncryptionKey: true,
            decryptedData: jsonData
        )

        #expect(provider.currentToken() == "sk-ant-test-only-no-real-secret")
    }

    @Test("returns nil when no source available")
    func returnsNilWhenNoSource() {
        let (provider, _, _, _, _, _, _) = makeSUT()

        #expect(provider.currentToken() == nil)
    }

    @Test("isBootstrapped is always true")
    func isBootstrappedAlwaysTrue() {
        let (provider, _, _, _, _, _, _) = makeSUT(hasEncryptionKey: false)
        #expect(provider.isBootstrapped == true)
    }

    @Test("hasTokenSource returns true when security CLI has token")
    func hasTokenSourceViaSecurityCLI() {
        let (provider, _, _, _, _, _, _) = makeSUT(securityCLIToken: "some-token")
        #expect(provider.hasTokenSource() == true)
    }

    @Test("hasTokenSource returns true when keychain has token")
    func hasTokenSourceViaKeychain() {
        let (provider, _, _, _, _, _, _) = makeSUT(keychainToken: "some-token")
        #expect(provider.hasTokenSource() == true)
    }

    @Test("hasTokenSource returns false when nothing available")
    func hasTokenSourceReturnsFalse() {
        let (provider, _, _, _, _, _, _) = makeSUT()
        #expect(provider.hasTokenSource() == false)
    }

    @Test("config.json decryption is tried before direct Keychain")
    func configJsonBeforeKeychain() {
        let oauthJSON: [String: Any] = [
            "claudeAiOauth": ["accessToken": "config-token"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

        var keychainWasCalled = false
        let securityCLI = MockSecurityCLIReader()
        let credentials = MockCredentialsFileReader()
        credentials.storedToken = nil

        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = "encrypted-blob"

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = true
        decryption.decryptedData = jsonData

        let keychainReader: TokenProvider.KeychainTokenReader = { _ in
            keychainWasCalled = true
            return "keychain-token"
        }

        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: keychainReader,
            oauthService: MockOAuthService(),
            oauthTokenStore: MockOAuthTokenStore(),
            oauthImportFileURL: Self.noImportFileURL
        )

        let token = provider.currentToken()

        #expect(token == "config-token")
        #expect(keychainWasCalled == false)
    }

    @Test("silent re-bootstrap recovers when decryption key is stale")
    func silentRebootstrapRecovery() {
        let oauthJSON: [String: Any] = [
            "claudeAiOauth": ["accessToken": "recovered-token"]
        ]
        let jsonData = try! JSONSerialization.data(withJSONObject: oauthJSON)

        let securityCLI = MockSecurityCLIReader()
        let credentials = MockCredentialsFileReader()
        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = "encrypted-blob"

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = false // key not loaded initially
        decryption.silentRebootstrapResult = true // but silent re-bootstrap works
        decryption.decryptedData = jsonData

        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: { _ in nil },
            oauthService: MockOAuthService(),
            oauthTokenStore: MockOAuthTokenStore(),
            oauthImportFileURL: Self.noImportFileURL
        )

        let token = provider.currentToken()

        #expect(token == "recovered-token")
        #expect(decryption.silentRebootstrapCallCount == 1)
        #expect(decryption.decryptCallCount == 1)
    }

    @Test("falls back to Keychain when config.json unavailable and re-bootstrap fails")
    func fallbackToKeychainWhenConfigUnavailable() {
        let securityCLI = MockSecurityCLIReader()
        let credentials = MockCredentialsFileReader()
        let configReader = MockClaudeConfigReader()
        configReader.encryptedToken = nil // no config.json

        let decryption = MockElectronDecryptionService()
        decryption._hasEncryptionKey = false

        let provider = TokenProvider(
            securityCLIReader: securityCLI,
            credentialsFileReader: credentials,
            configReader: configReader,
            decryptionService: decryption,
            keychainReader: { _ in "keychain-fallback" },
            oauthService: MockOAuthService(),
            oauthTokenStore: MockOAuthTokenStore(),
            oauthImportFileURL: Self.noImportFileURL
        )

        let token = provider.currentToken()

        #expect(token == "keychain-fallback")
    }

    // MARK: - refreshTokenIfChanged (account swap detection)

    @Test("refreshTokenIfChanged detects a rotated Keychain token and updates the cache")
    func refreshTokenIfChangedDetectsRotation() {
        let (provider, securityCLI, _, _, _, _, _) = makeSUT(securityCLIToken: "tok-A")

        // Prime the cache with account A's token.
        #expect(provider.currentToken() == "tok-A")

        // cswap rotates the Keychain item to account B's token.
        securityCLI.token = "tok-B"

        #expect(provider.refreshTokenIfChanged() == true)
        #expect(provider.currentToken() == "tok-B")
    }

    @Test("refreshTokenIfChanged returns false when the token is unchanged")
    func refreshTokenIfChangedNoChange() {
        let (provider, _, _, _, _, _, _) = makeSUT(securityCLIToken: "tok-A")

        #expect(provider.currentToken() == "tok-A")
        #expect(provider.refreshTokenIfChanged() == false)
        #expect(provider.currentToken() == "tok-A")
    }

    @Test("refreshTokenIfChanged keeps the cached token when all sources momentarily miss")
    func refreshTokenIfChangedKeepsCacheOnTransientMiss() {
        let (provider, securityCLI, _, _, _, _, _) = makeSUT(securityCLIToken: "tok-A")

        #expect(provider.currentToken() == "tok-A")

        // A transient read failure (no source available) must not drop a
        // working token.
        securityCLI.token = nil
        #expect(provider.refreshTokenIfChanged() == false)
        #expect(provider.currentToken() == "tok-A")
    }

    @Test("refreshTokenIfChanged treats first population as not-a-rotation")
    func refreshTokenIfChangedFirstReadIsNotRotation() {
        let (provider, _, _, _, _, _, _) = makeSUT(securityCLIToken: "tok-A")

        // No prior currentToken() call, so the cache is empty: the first read
        // establishes a baseline rather than signalling a swap.
        #expect(provider.refreshTokenIfChanged() == false)
    }

    // MARK: - OAuth source 0

    @Test("OAuth tokens take priority over the borrowed source chain")
    func oauthSourceWinsOverBorrowedSources() {
        let freshTokens = OAuthTokens(accessToken: "oauth-access", refreshToken: "oauth-refresh", expiresAt: Date().addingTimeInterval(3600))
        let (provider, securityCLI, _, _, _, _, oauthService) = makeSUT(
            securityCLIToken: "security-cli-token",
            oauthTokens: freshTokens
        )

        #expect(provider.currentToken() == "oauth-access")
        #expect(securityCLI.readCallCount == 0)
        #expect(oauthService.refreshCallCount == 0)
    }

    @Test("hasTokenSource returns true when OAuth tokens are present")
    func hasTokenSourceViaOAuth() {
        let tokens = OAuthTokens(accessToken: "oauth-access", refreshToken: "oauth-refresh", expiresAt: Date().addingTimeInterval(3600))
        let (provider, _, _, _, _, _, _) = makeSUT(oauthTokens: tokens)

        #expect(provider.hasTokenSource() == true)
    }

    @Test("currentToken returns the stored OAuth access token near expiry without touching the network")
    func currentTokenNearExpiryIsNonBlocking() {
        let staleTokens = OAuthTokens(accessToken: "stale-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(60))
        let (provider, securityCLI, _, _, _, _, oauthService) = makeSUT(
            securityCLIToken: "should-not-be-used",
            oauthTokens: staleTokens,
            oauthRefreshResult: .success(OAuthTokens(accessToken: "fresh-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(3600)))
        )

        // currentToken() is synchronous and must never refresh: it serves the
        // stored access token as-is. The async path renews it.
        #expect(provider.currentToken() == "stale-access")
        #expect(oauthService.refreshCallCount == 0)
        #expect(securityCLI.readCallCount == 0)
    }

    @Test("refreshOAuthTokenIfNeeded renews a near-expiry token exactly once and saves it")
    func refreshOAuthTokenIfNeededRenewsNearExpiry() async {
        let staleTokens = OAuthTokens(accessToken: "stale-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(60))
        let refreshedTokens = OAuthTokens(accessToken: "fresh-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(3600))
        let (provider, _, _, _, _, oauthStore, oauthService) = makeSUT(
            oauthTokens: staleTokens,
            oauthRefreshResult: .success(refreshedTokens)
        )

        let usable = await provider.refreshOAuthTokenIfNeeded()

        #expect(usable == true)
        #expect(oauthService.refreshCallCount == 1)
        #expect(oauthStore.load() == refreshedTokens)
        #expect(provider.currentToken() == "fresh-access")
    }

    @Test("refreshOAuthTokenIfNeeded is a no-op for a fresh token")
    func refreshOAuthTokenIfNeededSkipsFreshToken() async {
        let freshTokens = OAuthTokens(accessToken: "fresh-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(3600))
        let (provider, _, _, _, _, _, oauthService) = makeSUT(oauthTokens: freshTokens)

        let usable = await provider.refreshOAuthTokenIfNeeded()

        #expect(usable == true)
        #expect(oauthService.refreshCallCount == 0)
    }

    @Test("refreshOAuthTokenIfNeeded is a no-op returning false with no OAuth tokens")
    func refreshOAuthTokenIfNeededNoOpWithoutTokens() async {
        let (provider, securityCLI, _, _, _, _, oauthService) = makeSUT(securityCLIToken: "borrowed")

        let usable = await provider.refreshOAuthTokenIfNeeded()

        #expect(usable == false)
        #expect(oauthService.refreshCallCount == 0)
        #expect(securityCLI.readCallCount == 0) // borrowed sources aren't touched here
    }

    @Test("refreshOAuthTokenIfNeeded failure keeps the stored token untouched")
    func refreshOAuthTokenIfNeededFailureKeepsToken() async {
        let staleTokens = OAuthTokens(accessToken: "stale-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(60))
        let (provider, _, _, _, _, oauthStore, oauthService) = makeSUT(
            oauthTokens: staleTokens,
            oauthRefreshResult: .failure(.refreshFailed(500))
        )

        let usable = await provider.refreshOAuthTokenIfNeeded()

        #expect(usable == false)
        #expect(oauthService.refreshCallCount == 1)
        #expect(oauthStore.load() == staleTokens) // failed refresh persisted nothing
        #expect(provider.currentToken() == "stale-access")
    }

    @Test("refreshOAuthTokenIfNeeded awaits a delayed, non-inline completion")
    func refreshOAuthTokenIfNeededAwaitsDelayedCompletion() async {
        let staleTokens = OAuthTokens(accessToken: "stale-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(60))
        let refreshedTokens = OAuthTokens(accessToken: "fresh-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(3600))
        let (provider, _, _, _, _, oauthStore, oauthService) = makeSUT(
            oauthTokens: staleTokens,
            oauthRefreshResult: .success(refreshedTokens)
        )
        // Deliver the completion off a background queue AFTER refresh() returns,
        // so a success dropped by the old timeout bridge would fail this test.
        oauthService.deliverRefreshAsynchronously = true

        let usable = await provider.refreshOAuthTokenIfNeeded()

        #expect(usable == true)
        #expect(oauthStore.load() == refreshedTokens)
        #expect(provider.currentToken() == "fresh-access")
    }

    @Test("handleUnauthorizedOAuth forces a refresh regardless of expiry and saves it")
    func handleUnauthorizedOAuthForcesRefresh() async {
        // Token is NOT near expiry, yet a 401 means the server rejected it.
        let liveButRejected = OAuthTokens(accessToken: "old-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(3600))
        let newTokens = OAuthTokens(accessToken: "new-access", refreshToken: "new-refresh", expiresAt: Date().addingTimeInterval(3600))
        let (provider, _, _, _, _, oauthStore, oauthService) = makeSUT(
            oauthTokens: liveButRejected,
            oauthRefreshResult: .success(newTokens)
        )

        let refreshed = await provider.handleUnauthorizedOAuth()

        #expect(refreshed == true)
        #expect(oauthService.refreshCallCount == 1)
        #expect(oauthStore.load() == newTokens)
        #expect(provider.currentToken() == "new-access")
    }

    @Test("handleUnauthorizedOAuth failure leaves the stored tokens untouched")
    func handleUnauthorizedOAuthFailureKeepsTokens() async {
        let oldTokens = OAuthTokens(accessToken: "old-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(3600))
        let (provider, _, _, _, _, oauthStore, oauthService) = makeSUT(
            oauthTokens: oldTokens,
            oauthRefreshResult: .failure(.refreshFailed(401))
        )

        let refreshed = await provider.handleUnauthorizedOAuth()

        #expect(refreshed == false)
        #expect(oauthService.refreshCallCount == 1)
        #expect(oauthStore.load() == oldTokens) // nothing persisted on failure
    }

    @Test("handleUnauthorizedOAuth is a no-op returning false with no OAuth tokens")
    func handleUnauthorizedOAuthNoOpWithoutTokens() async {
        let (provider, _, _, _, _, _, oauthService) = makeSUT(securityCLIToken: "borrowed")

        let refreshed = await provider.handleUnauthorizedOAuth()

        #expect(refreshed == false)
        #expect(oauthService.refreshCallCount == 0)
    }

    @Test("refreshTokenIfChanged is a no-op and reads no borrowed source while OAuth tokens exist")
    func refreshTokenIfChangedIsNoOpWithOAuthTokens() {
        let tokens = OAuthTokens(accessToken: "oauth-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(3600))
        let (provider, securityCLI, _, _, _, _, _) = makeSUT(
            securityCLIToken: "work-account-token", // a DIFFERENT account's borrowed token
            credentialsToken: "work-creds-token",
            oauthTokens: tokens
        )

        // Prime the OAuth token into the cache the way an auto-refresh tick does.
        #expect(provider.currentToken() == "oauth-access")

        // The tick must NOT reconcile against - or even read - the borrowed
        // chain (securityCLI is the first source in that chain), so the
        // personal OAuth token can never be clobbered by the work account's.
        #expect(provider.refreshTokenIfChanged() == false)
        #expect(securityCLI.readCallCount == 0)
        #expect(provider.currentToken() == "oauth-access")
    }

    @Test("invalidateToken only clears the cache and never calls oauthService.refresh")
    func invalidateTokenDoesNotRefresh() {
        let tokens = OAuthTokens(accessToken: "oauth-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(3600))
        let (provider, _, _, _, _, oauthStore, oauthService) = makeSUT(
            oauthTokens: tokens,
            oauthRefreshResult: .success(OAuthTokens(accessToken: "should-not-appear", refreshToken: "x", expiresAt: Date().addingTimeInterval(3600)))
        )

        provider.invalidateToken()

        #expect(oauthService.refreshCallCount == 0) // no network on a bare invalidate
        #expect(oauthStore.load() == tokens) // store untouched
        #expect(provider.currentToken() == "oauth-access")
    }

    @Test("disconnectOAuth clears the store and cache, falling back to the borrowed source chain")
    func disconnectOAuthFallsBackToBorrowedChain() {
        let tokens = OAuthTokens(accessToken: "oauth-access", refreshToken: "refresh-token", expiresAt: Date().addingTimeInterval(3600))
        let (provider, _, _, _, _, oauthStore, _) = makeSUT(
            securityCLIToken: "security-cli-token",
            oauthTokens: tokens
        )

        #expect(provider.currentToken() == "oauth-access")

        provider.disconnectOAuth()

        #expect(oauthStore.load() == nil)
        #expect(provider.currentToken() == "security-cli-token")
    }

    // MARK: - One-time OAuth import

    @Test("one-time import reads a pre-minted token file, saves it, and deletes the file")
    func oneTimeImportSavesAndDeletesFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let importURL = tempDir.appendingPathComponent("oauth-import.json")
        // Rounded to whole seconds - the epoch-seconds JSON codec drops
        // sub-second precision, so comparing against an unrounded Date below
        // would fail on the fractional part alone.
        let expiresAt = Date(timeIntervalSince1970: Date().addingTimeInterval(3600).timeIntervalSince1970.rounded())
        let tokens = OAuthTokens(accessToken: "imported-access", refreshToken: "imported-refresh", expiresAt: expiresAt)
        try OAuthTokenStore.encode(tokens).write(to: importURL)

        let oauthStore = MockOAuthTokenStore()
        _ = TokenProvider(
            securityCLIReader: MockSecurityCLIReader(),
            credentialsFileReader: MockCredentialsFileReader(),
            configReader: MockClaudeConfigReader(),
            decryptionService: MockElectronDecryptionService(),
            keychainReader: { _ in nil },
            oauthService: MockOAuthService(),
            oauthTokenStore: oauthStore,
            oauthImportFileURL: importURL
        )

        #expect(oauthStore.load() == tokens)
        #expect(FileManager.default.fileExists(atPath: importURL.path) == false)
    }

    @Test("missing import file is a no-op")
    func missingImportFileIsNoOp() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let importURL = tempDir.appendingPathComponent("oauth-import.json") // never created

        let oauthStore = MockOAuthTokenStore()
        _ = TokenProvider(
            securityCLIReader: MockSecurityCLIReader(),
            credentialsFileReader: MockCredentialsFileReader(),
            configReader: MockClaudeConfigReader(),
            decryptionService: MockElectronDecryptionService(),
            keychainReader: { _ in nil },
            oauthService: MockOAuthService(),
            oauthTokenStore: oauthStore,
            oauthImportFileURL: importURL
        )

        #expect(oauthStore.load() == nil)
    }

    @Test("import errors leave the file untouched")
    func malformedImportFileIsLeftInPlace() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let importURL = tempDir.appendingPathComponent("oauth-import.json")
        try Data("not valid json".utf8).write(to: importURL)

        let oauthStore = MockOAuthTokenStore()
        _ = TokenProvider(
            securityCLIReader: MockSecurityCLIReader(),
            credentialsFileReader: MockCredentialsFileReader(),
            configReader: MockClaudeConfigReader(),
            decryptionService: MockElectronDecryptionService(),
            keychainReader: { _ in nil },
            oauthService: MockOAuthService(),
            oauthTokenStore: oauthStore,
            oauthImportFileURL: importURL
        )

        #expect(oauthStore.load() == nil)
        #expect(FileManager.default.fileExists(atPath: importURL.path) == true)
    }
}
