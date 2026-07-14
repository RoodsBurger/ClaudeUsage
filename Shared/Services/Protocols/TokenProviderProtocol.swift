import Foundation

protocol TokenProviderProtocol: Sendable {
    func currentToken() -> String?
    /// Whether a token source exists (config.json or credentials file), even if not yet decryptable
    func hasTokenSource() -> Bool
    /// Clear cached token - call after 401 so next read re-checks Keychain
    func invalidateToken()
    /// Re-reads the token from its sources (Keychain/files), bypassing the
    /// in-memory cache, and updates the cache. Returns true when the token
    /// changed since the last read - i.e. an account swap (`cswap`, `claude
    /// /login`) or token rotation that the file watcher cannot observe because
    /// the active token lives in the Keychain, not in a watched file.
    func refreshTokenIfChanged() -> Bool
    /// Proactively refreshes the app-owned OAuth token when it exists and is
    /// near expiry, awaiting the network exchange. Returns true when a usable
    /// OAuth access token is available afterwards. No-op returning false when
    /// no OAuth tokens exist (borrowed sources need no proactive refresh).
    /// Callers await this once per refresh tick, before reading the token.
    func refreshOAuthTokenIfNeeded() async -> Bool
    /// Forces one OAuth refresh after a 401, regardless of local expiry. On
    /// success saves + caches the new token so the caller's immediate retry
    /// reads it. Returns true when a refreshed token is available. No-op
    /// returning false when no OAuth tokens exist.
    func handleUnauthorizedOAuth() async -> Bool
    var isBootstrapped: Bool { get }
    func bootstrap() throws
    /// Signs out of the app-owned OAuth tokens and clears the cache, so the
    /// next `currentToken()` falls back to the borrowed source chain.
    func disconnectOAuth()
}
