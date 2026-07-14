import Foundation

// MARK: - OAuth Constants

enum OAuthConstants {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = "https://claude.ai/oauth/authorize"
    static let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    static let manualRedirectURI = "https://console.anthropic.com/oauth/code/callback"
    static let scopes = "user:profile user:inference"
}

// MARK: - OAuthTokens

struct OAuthTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    /// True when within `margin` of expiry (default 300s) — refresh trigger.
    func needsRefresh(now: Date = .init(), margin: TimeInterval = 300) -> Bool {
        let refreshThreshold = expiresAt.addingTimeInterval(-margin)
        return now >= refreshThreshold
    }
}

// MARK: - TokenResponse

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }

    /// Converts the response to OAuthTokens with the given reference time.
    func tokens(now: Date) -> OAuthTokens {
        let expiresAt = now.addingTimeInterval(TimeInterval(expiresIn))
        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }
}

// MARK: - OAuthError

enum OAuthError: Error, Equatable {
    case stateMismatch
    case malformedCallback
    case exchangeFailed(Int)
    case refreshFailed(Int)
    case cancelled
    case listenerFailed
}
