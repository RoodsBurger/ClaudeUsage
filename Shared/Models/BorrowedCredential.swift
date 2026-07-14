import Foundation

/// A credential read from a source the app doesn't own (Claude Code CLI's
/// Keychain item or `.credentials.json`, Claude Desktop's `config.json`).
/// `expiresAt` is nil when the source doesn't carry expiry information at
/// all - not to be confused with an expired credential.
struct BorrowedCredential: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    /// True only when `expiresAt` is known and at or before `now`. A source
    /// with no expiry information is never considered expired here.
    func isExpired(now: Date = .init()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }

    /// True when `expiresAt` is known and within `margin` (default 300s) of
    /// `now`, mirroring `OAuthTokens.needsRefresh`. A source with no expiry
    /// information never needs refresh here.
    func needsRefresh(now: Date = .init(), margin: TimeInterval = 300) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt.addingTimeInterval(-margin)
    }
}
