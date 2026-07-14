import Foundation

final class MockOAuthService: OAuthServiceProtocol, @unchecked Sendable {
    var beginLoginCallCount = 0
    var completeManualLoginCallCount = 0
    var cancelLoginCallCount = 0
    var refreshCallCount = 0

    var lastManualPaste: String?
    var lastRefreshTokens: OAuthTokens?

    var stubbedLoginResult: Result<OAuthTokens, OAuthError> = .failure(.cancelled)
    var stubbedManualLoginResult: Result<OAuthTokens, OAuthError> = .failure(.cancelled)
    var stubbedRefreshResult: Result<OAuthTokens, OAuthError> = .failure(.cancelled)

    func beginLogin(completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
        beginLoginCallCount += 1
        completion(stubbedLoginResult)
    }

    func completeManualLogin(pasted: String, completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
        completeManualLoginCallCount += 1
        lastManualPaste = pasted
        completion(stubbedManualLoginResult)
    }

    func cancelLogin() {
        cancelLoginCallCount += 1
    }

    func refresh(_ tokens: OAuthTokens, completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
        refreshCallCount += 1
        lastRefreshTokens = tokens
        completion(stubbedRefreshResult)
    }
}
