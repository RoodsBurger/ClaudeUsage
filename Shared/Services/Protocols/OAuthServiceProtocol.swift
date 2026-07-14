import Foundation

protocol OAuthServiceProtocol: AnyObject {
    /// Starts login: opens browser (NSWorkspace.open), listens on loopback.
    /// Completion on main queue. Cancellable.
    func beginLogin(completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void)
    /// Manual path: user pasted "code#state" from the fallback page.
    func completeManualLogin(pasted: String, completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void)
    func cancelLogin()
    /// Exchanges refresh token; serialized (one in-flight refresh at a time).
    func refresh(_ tokens: OAuthTokens, completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void)
}
