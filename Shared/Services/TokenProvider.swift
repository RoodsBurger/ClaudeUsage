import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.tokeneater.app", category: "TokenProvider")

final class TokenProvider: TokenProviderProtocol, @unchecked Sendable {
    private let securityCLIReader: SecurityCLIReaderProtocol
    private let credentialsFileReader: CredentialsFileReaderProtocol
    private let configReader: ClaudeConfigReaderProtocol
    private let decryptionService: ElectronDecryptionServiceProtocol
    private let keychainReader: KeychainTokenReader
    private let oauthService: OAuthServiceProtocol
    private let oauthTokenStore: OAuthTokenStoreProtocol

    /// In-memory token cache - avoids hitting the Keychain on every refresh.
    /// Cleared on 401 (token expired) via `invalidateToken()` and on
    /// `disconnectOAuth()`.
    private var cachedToken: String?

    /// Closure type for reading from the Keychain. `silent` = use kSecUseAuthenticationUISkip.
    typealias KeychainTokenReader = (_ silent: Bool) -> String?

    init(
        securityCLIReader: SecurityCLIReaderProtocol = SecurityCLIReader(),
        credentialsFileReader: CredentialsFileReaderProtocol = CredentialsFileReader(),
        configReader: ClaudeConfigReaderProtocol = ClaudeConfigReader(),
        decryptionService: ElectronDecryptionServiceProtocol = ElectronDecryptionService(),
        keychainReader: KeychainTokenReader? = nil,
        oauthService: OAuthServiceProtocol = OAuthService(),
        oauthTokenStore: OAuthTokenStoreProtocol = OAuthTokenStore(),
        oauthImportFileURL: URL? = nil
    ) {
        self.securityCLIReader = securityCLIReader
        self.credentialsFileReader = credentialsFileReader
        self.configReader = configReader
        self.decryptionService = decryptionService
        self.keychainReader = keychainReader ?? Self.defaultKeychainReader
        self.oauthService = oauthService
        self.oauthTokenStore = oauthTokenStore
        Self.importPendingOAuthTokensIfNeeded(
            fileURL: oauthImportFileURL ?? Self.defaultOAuthImportFileURL(),
            store: oauthTokenStore
        )
    }

    var isBootstrapped: Bool { true }

    func hasTokenSource() -> Bool {
        if oauthTokenStore.load() != nil { return true }
        if cachedToken != nil { return true }
        if securityCLIReader.readToken() != nil { return true }
        if credentialsFileReader.readToken() != nil { return true }
        if configReader.readEncryptedToken() != nil { return true }
        if keychainReader(true) != nil { return true }
        return false
    }

    /// Returns the current token. This is synchronous and never touches the
    /// network: OAuth tokens (source 0, this app's own authorization) take
    /// priority whenever they exist and the stored access token is returned
    /// as-is, even if near expiry - the proactive/reactive refresh runs on the
    /// async paths (`refreshOAuthTokenIfNeeded`, `handleUnauthorizedOAuth`),
    /// not here. Only when no OAuth tokens exist at all does this fall back to
    /// the borrowed source chain, using the in-memory cache so the Keychain is
    /// only read when the cache is empty (app start, or after
    /// `invalidateToken()`).
    ///
    /// Borrowed source priority (v5.0+):
    /// 1. `/usr/bin/security` shell-out (primary - works for all modern Claude Code macOS users,
    ///    no popups across app updates because `security` has a stable Apple signing identity)
    /// 2. `.credentials.json` (legacy Claude Code fallback - still present on Linux/Windows and
    ///    on very old macOS Claude Code installs)
    /// 3. Claude Desktop `config.json` decryption (for users without Claude Code CLI at all)
    /// 4. Direct `SecItemCopyMatching` (last resort - the Claude Code Keychain ACL doesn't
    ///    whitelist us directly, but kept for defence-in-depth)
    func currentToken() -> String? {
        if let token = cachedToken { return token }

        if let tokens = oauthTokenStore.load() {
            cachedToken = tokens.accessToken
            return tokens.accessToken
        }

        let token = readFromSources()
        cachedToken = token
        return token
    }

    /// Proactively refreshes the OAuth token when it's near expiry. Callers
    /// await this once per refresh tick before reading the token so a
    /// near-expiry token is renewed ahead of the fetch. No-op returning false
    /// for borrowed sources (they self-heal on 401 via `invalidateToken`).
    func refreshOAuthTokenIfNeeded() async -> Bool {
        guard let tokens = oauthTokenStore.load() else { return false }
        guard tokens.needsRefresh() else {
            cachedToken = tokens.accessToken
            return true
        }
        return await performOAuthRefresh(tokens)
    }

    /// Forces one OAuth refresh after a 401, regardless of local expiry: the
    /// server rejected a token whose local `expiresAt` may still be in the
    /// future. No-op returning false for borrowed sources - the 401 caller
    /// then falls back to `invalidateToken` + a borrowed re-read.
    func handleUnauthorizedOAuth() async -> Bool {
        guard let tokens = oauthTokenStore.load() else { return false }
        return await performOAuthRefresh(tokens)
    }

    /// Runs one OAuth refresh exchange, awaiting the completion-based
    /// `oauthService.refresh` via a checked continuation - no run-loop pump,
    /// no semaphore. The new tokens are saved to the store inside the
    /// completion so a slow-but-successful refresh can never be dropped by a
    /// timeout. On success the in-memory cache is updated so the next
    /// `currentToken()` returns the fresh access token. A failure leaves the
    /// stored tokens untouched (the access token keeps being served until a
    /// hard 401).
    private func performOAuthRefresh(_ tokens: OAuthTokens) async -> Bool {
        let refreshed: OAuthTokens? = await withCheckedContinuation { continuation in
            oauthService.refresh(tokens) { result in
                if case .success(let newTokens) = result {
                    try? self.oauthTokenStore.save(newTokens)
                    continuation.resume(returning: newTokens)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        guard let refreshed else {
            logger.info("OAuth refresh failed - keeping existing access token")
            return false
        }
        cachedToken = refreshed.accessToken
        logger.info("OAuth token refreshed")
        return true
    }

    /// Reads the token from all sources in priority order, bypassing the
    /// in-memory cache. Returns the freshest token currently on the system.
    private func readFromSources() -> String? {
        if let token = securityCLIReader.readToken() {
            logger.info("Token read via /usr/bin/security")
            return token
        }

        if let token = credentialsFileReader.readToken() {
            return token
        }

        if let token = tokenFromConfigJSON() {
            return token
        }

        if let token = keychainReader(true) {
            logger.info("Token read from Keychain (silent)")
            return token
        }

        return nil
    }

    /// Re-reads the token from its sources and updates the cache when it
    /// changed. The file watcher only sees `config.json` / `.credentials.json`,
    /// but on modern macOS the active token lives in the Keychain - so a
    /// `cswap`/`claude login` account swap rotates the Keychain item with no
    /// filesystem event and the cache would otherwise keep serving the previous
    /// account's token until a 401. Polling here (on the auto-refresh tick)
    /// closes that gap. Returns true only on an actual change between two
    /// non-nil tokens; first population and transient read failures return false
    /// so a working token is never dropped.
    ///
    /// OAuth tokens are authoritative: while they exist this never reconciles
    /// against the borrowed chain (nor reads it), so a borrowed token from a
    /// *different* account can never silently replace the app's own OAuth token
    /// on a tick.
    func refreshTokenIfChanged() -> Bool {
        if oauthTokenStore.load() != nil { return false }
        guard let fresh = readFromSources() else { return false }
        let previous = cachedToken
        cachedToken = fresh
        guard let previous else { return false }
        if previous != fresh {
            logger.info("Token changed on Keychain/disk - cache refreshed for new account")
            return true
        }
        return false
    }

    /// Try to decrypt config.json. If key is missing, attempt silent re-bootstrap.
    private func tokenFromConfigJSON() -> String? {
        guard let encrypted = configReader.readEncryptedToken() else { return nil }

        if decryptionService.hasEncryptionKey,
           let token = decryptFromConfigJSON(encrypted) {
            return token
        }

        if decryptionService.trySilentRebootstrap(),
           let token = decryptFromConfigJSON(encrypted) {
            logger.info("Token recovered via silent re-bootstrap of decryption key")
            return token
        }

        return nil
    }

    /// Call this after a 401 - clears the in-memory cache so the next
    /// `currentToken()` re-reads its source (a rotated borrowed token, or the
    /// stored OAuth token, possibly just renewed by `handleUnauthorizedOAuth`).
    /// Synchronous and network-free: the OAuth refresh-on-401 is a separate
    /// async step the caller awaits, so non-401 callers (`handleTokenChange`,
    /// "Retry now") that only invalidate never rotate the refresh token.
    func invalidateToken() {
        cachedToken = nil
        logger.info("Token cache invalidated - next read will check its source")
    }

    /// Signs out of the app-owned OAuth tokens. The next `currentToken()`
    /// falls back to the borrowed source chain.
    func disconnectOAuth() {
        oauthTokenStore.clear()
        cachedToken = nil
        logger.info("OAuth disconnected - falling back to borrowed token sources")
    }

    // MARK: - One-Time OAuth Import

    /// Imports a pre-minted OAuth token file dropped at `fileURL` (same JSON
    /// shape `OAuthTokenStore` persists) into `store`, then deletes the file
    /// so the import runs exactly once. Leaves the file untouched on any
    /// read/decode/save failure. Never logs token material.
    private static func importPendingOAuthTokensIfNeeded(fileURL: URL, store: OAuthTokenStoreProtocol) {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let tokens = OAuthTokenStore.decode(data) else { return }
        do {
            try store.save(tokens)
        } catch {
            return
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// `~/Library/Application Support/com.tokeneater.shared/oauth-import.json`,
    /// resolved via the real home directory (`getpwuid`) rather than
    /// `FileManager.homeDirectoryForCurrentUser`, which returns the sandbox
    /// container path inside the widget - see `SharedFileService`.
    private static func defaultOAuthImportFileURL() -> URL {
        let home: String
        if let pw = getpwuid(getuid()) {
            home = String(cString: pw.pointee.pw_dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.tokeneater.shared")
            .appendingPathComponent("oauth-import.json")
    }

    func bootstrap() throws {
        if let token = keychainReader(false) {
            cachedToken = token
            logger.info("Bootstrap succeeded via interactive Keychain read")
        }

        do {
            try decryptionService.bootstrapEncryptionKey()
        } catch {
            logger.info("Decryption key bootstrap skipped: \(error)")
        }
    }

    // MARK: - Keychain (static, no instance state)

    private static func defaultKeychainReader(silent: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if silent {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }

        return token
    }

    // MARK: - Config.json Decryption (fallback)

    private func decryptFromConfigJSON(_ encrypted: String) -> String? {
        do {
            let data = try decryptionService.decrypt(encrypted)
            return Self.extractToken(from: data)
        } catch {
            return nil
        }
    }

    private static func extractToken(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty {
            return token
        }
        for (_, value) in json {
            if let entry = value as? [String: Any],
               let token = entry["token"] as? String,
               token.hasPrefix("sk-ant-") {
                return token
            }
        }
        return nil
    }
}
