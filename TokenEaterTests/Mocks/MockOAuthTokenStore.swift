import Foundation

final class MockOAuthTokenStore: OAuthTokenStoreProtocol, @unchecked Sendable {
    private var storedTokens: OAuthTokens?

    func load() -> OAuthTokens? {
        storedTokens
    }

    func save(_ tokens: OAuthTokens) throws {
        storedTokens = tokens
    }

    func clear() {
        storedTokens = nil
    }
}
