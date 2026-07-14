import Testing
import Foundation

// MARK: - Test Helpers

/// Records everything OAuthService's injected seams do, without touching any
/// real network, browser, or socket. `loopbackStarter` fires `onReady` (or
/// `onFailure`) synchronously so tests stay deterministic.
private final class SeamRecorder {
    private(set) var requests: [URLRequest] = []
    private var pendingResponses: [(Data?, URLResponse?, Error?) -> Void] = []
    var autoRespondWith: (Data?, URLResponse?, Error?)?

    private(set) var openedURLs: [URL] = []

    var shouldFailLoopbackImmediately = false
    var loopbackReadyPort: UInt16 = 51234
    private(set) var loopbackStopCallCount = 0

    func transport(_ request: URLRequest, _ completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        requests.append(request)
        if let auto = autoRespondWith {
            completion(auto.0, auto.1, auto.2)
        } else {
            pendingResponses.append(completion)
        }
    }

    /// Fires every request captured so far that hasn't been responded to yet.
    func respondToAll(data: Data?, response: URLResponse?, error: Error?) {
        let pending = pendingResponses
        pendingResponses = []
        for completion in pending { completion(data, response, error) }
    }

    func browserOpener(_ url: URL) {
        openedURLs.append(url)
    }

    func loopbackStarter(
        _ onReady: @escaping (UInt16) -> Void,
        _ onRequest: @escaping (String) -> Void,
        _ onFailure: @escaping () -> Void
    ) -> () -> Void {
        if shouldFailLoopbackImmediately {
            onFailure()
        } else {
            onReady(loopbackReadyPort)
        }
        return { [weak self] in self?.loopbackStopCallCount += 1 }
    }
}

private func validTokenResponseJSON(expiresIn: Int = 3600) -> Data {
    """
    {
        "access_token": "access-123",
        "refresh_token": "refresh-456",
        "expires_in": \(expiresIn),
        "token_type": "Bearer",
        "scope": "user:profile user:inference"
    }
    """.data(using: .utf8)!
}

private func httpResponse(_ statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: OAuthConstants.tokenURL)!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

// MARK: - OAuthService

@Suite("OAuthService")
@MainActor
struct OAuthServiceTests {

    // MARK: - Helpers

    private func makeSUT(
        tokens: [String] = ["verifier-value", "state-value"],
        now: Date = Date(timeIntervalSince1970: 1_700_000_000),
        recorder: SeamRecorder = SeamRecorder()
    ) -> (service: OAuthService, recorder: SeamRecorder) {
        var index = 0
        let service = OAuthService(
            transport: recorder.transport,
            browserOpener: recorder.browserOpener,
            loopbackStarter: recorder.loopbackStarter,
            randomToken: {
                defer { index += 1 }
                return tokens[index % tokens.count]
            },
            now: { now }
        )
        return (service, recorder)
    }

    // MARK: - beginLogin

    @Test("beginLogin opens the browser with a well-formed loopback authorize URL")
    func beginLoginOpensBrowser() throws {
        let (service, recorder) = makeSUT()

        service.beginLogin { _ in }

        #expect(recorder.openedURLs.count == 1)
        let url = try #require(recorder.openedURLs.first)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(params["state"] == "state-value")
        #expect(params["code_challenge"] == PKCE.challenge(for: "verifier-value"))
        #expect(params["client_id"] == OAuthConstants.clientID)
        #expect((params["redirect_uri"] ?? nil)?.hasPrefix("http://127.0.0.1:") == true)
    }

    @Test("loopback callback seam exchanges the code and delivers tokens via beginLogin's completion")
    func loopbackCallbackSeamSucceeds() throws {
        let (service, recorder) = makeSUT()
        recorder.autoRespondWith = (validTokenResponseJSON(), httpResponse(200), nil)

        var captured: Result<OAuthTokens, OAuthError>?
        service.beginLogin { captured = $0 }

        // Bypasses the real NWListener entirely: invokes the shared callback-handling
        // seam directly, as if the loopback socket had just received this GET.
        service.handleLoopbackCallback("/callback?code=auth-code-123&state=state-value")

        let result = try #require(captured)
        guard case .success(let tokens) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(tokens.accessToken == "access-123")
        #expect(tokens.refreshToken == "refresh-456")
    }

    @Test("listener failure delivers .listenerFailed via beginLogin's completion")
    func listenerFailureDeliversError() throws {
        let recorder = SeamRecorder()
        recorder.shouldFailLoopbackImmediately = true
        let (service, _) = makeSUT(recorder: recorder)

        var captured: Result<OAuthTokens, OAuthError>?
        service.beginLogin { captured = $0 }

        let result = try #require(captured)
        #expect(result == .failure(.listenerFailed))
    }

    @Test("cancelLogin delivers .cancelled, stops the listener, and ignores late callbacks")
    func cancelLoginStopsListener() throws {
        let (service, recorder) = makeSUT()
        var captured: Result<OAuthTokens, OAuthError>?
        service.beginLogin { captured = $0 }

        service.cancelLogin()

        let result = try #require(captured)
        #expect(result == .failure(.cancelled))
        #expect(recorder.loopbackStopCallCount == 1)

        // A callback arriving after cancellation must be a no-op.
        captured = nil
        service.handleLoopbackCallback("/callback?code=too-late&state=state-value")
        #expect(captured == nil)
    }

    // MARK: - Manual paste path (exchange request/response correctness, state mismatch)

    @Test("manual login sends a correctly-shaped exchange request")
    func manualLoginRequestShape() throws {
        let (service, recorder) = makeSUT()
        recorder.autoRespondWith = (validTokenResponseJSON(), httpResponse(200), nil)

        service.beginLogin { _ in }
        service.completeManualLogin(pasted: "auth-code-123#state-value") { _ in }

        let request = try #require(recorder.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url == URL(string: OAuthConstants.tokenURL))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let bodyData = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: String])
        #expect(body["grant_type"] == "authorization_code")
        #expect(body["code"] == "auth-code-123")
        #expect(body["state"] == "state-value")
        #expect(body["client_id"] == OAuthConstants.clientID)
        #expect(body["redirect_uri"] == OAuthConstants.manualRedirectURI)
        #expect(body["code_verifier"] == "verifier-value")
    }

    @Test("manual login success decodes TokenResponse into OAuthTokens")
    func manualLoginSuccessDecodesTokens() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (service, recorder) = makeSUT(now: now)
        recorder.autoRespondWith = (validTokenResponseJSON(expiresIn: 3600), httpResponse(200), nil)

        service.beginLogin { _ in }
        var captured: Result<OAuthTokens, OAuthError>?
        service.completeManualLogin(pasted: "auth-code-123#state-value") { captured = $0 }

        let result = try #require(captured)
        guard case .success(let tokens) = result else {
            Issue.record("Expected success, got \(result)")
            return
        }
        #expect(tokens.accessToken == "access-123")
        #expect(tokens.refreshToken == "refresh-456")
        #expect(tokens.expiresAt == now.addingTimeInterval(3600))
    }

    @Test("non-200 manual exchange response yields .exchangeFailed with status code")
    func manualLoginNon200() throws {
        let (service, recorder) = makeSUT()
        recorder.autoRespondWith = (Data(), httpResponse(401), nil)

        service.beginLogin { _ in }
        var captured: Result<OAuthTokens, OAuthError>?
        service.completeManualLogin(pasted: "auth-code-123#state-value") { captured = $0 }

        let result = try #require(captured)
        #expect(result == .failure(.exchangeFailed(401)))
    }

    @Test("pasted state mismatch yields .stateMismatch without attempting an exchange")
    func manualLoginStateMismatch() throws {
        let (service, recorder) = makeSUT()
        service.beginLogin { _ in }

        var captured: Result<OAuthTokens, OAuthError>?
        service.completeManualLogin(pasted: "auth-code-123#wrong-state") { captured = $0 }

        let result = try #require(captured)
        #expect(result == .failure(.stateMismatch))
        #expect(recorder.requests.isEmpty)
    }

    @Test("completeManualLogin without a pending login yields .stateMismatch")
    func manualLoginWithoutPendingSession() throws {
        let (service, _) = makeSUT()

        var captured: Result<OAuthTokens, OAuthError>?
        service.completeManualLogin(pasted: "code#state") { captured = $0 }

        let result = try #require(captured)
        #expect(result == .failure(.stateMismatch))
    }

    @Test("malformed pasted string yields .malformedCallback")
    func manualLoginMalformed() throws {
        let (service, _) = makeSUT()
        service.beginLogin { _ in }

        var captured: Result<OAuthTokens, OAuthError>?
        service.completeManualLogin(pasted: "not-a-valid-paste") { captured = $0 }

        let result = try #require(captured)
        #expect(result == .failure(.malformedCallback))
    }

    // MARK: - refresh

    @Test("non-200 refresh response yields .refreshFailed with status code")
    func refreshNon200() throws {
        let (service, recorder) = makeSUT()
        recorder.autoRespondWith = (Data(), httpResponse(400), nil)
        let tokens = OAuthTokens(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: .distantFuture)

        var captured: Result<OAuthTokens, OAuthError>?
        service.refresh(tokens) { captured = $0 }

        let result = try #require(captured)
        #expect(result == .failure(.refreshFailed(400)))
    }

    @Test("concurrent refresh calls coalesce into a single transport hit and both complete")
    func refreshCoalesces() throws {
        let (service, recorder) = makeSUT()
        let tokens = OAuthTokens(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: .distantFuture)

        var captured1: Result<OAuthTokens, OAuthError>?
        var captured2: Result<OAuthTokens, OAuthError>?
        service.refresh(tokens) { captured1 = $0 }
        service.refresh(tokens) { captured2 = $0 }

        // Only one network exchange should have been made so far.
        #expect(recorder.requests.count == 1)
        #expect(captured1 == nil)
        #expect(captured2 == nil)

        recorder.respondToAll(data: validTokenResponseJSON(), response: httpResponse(200), error: nil)

        let result1 = try #require(captured1)
        let result2 = try #require(captured2)
        guard case .success(let t1) = result1, case .success(let t2) = result2 else {
            Issue.record("Expected both completions to succeed")
            return
        }
        #expect(t1 == t2)
        #expect(t1.accessToken == "access-123")
        #expect(recorder.requests.count == 1)
    }
}

// MARK: - MockOAuthService

@Suite("MockOAuthService")
struct MockOAuthServiceTests {
    @Test("beginLogin increments call count and returns the stubbed result")
    func beginLoginStub() {
        let mock = MockOAuthService()
        let tokens = OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: .distantFuture)
        mock.stubbedLoginResult = .success(tokens)

        var captured: Result<OAuthTokens, OAuthError>?
        mock.beginLogin { captured = $0 }

        #expect(mock.beginLoginCallCount == 1)
        #expect(captured == .success(tokens))
    }

    @Test("completeManualLogin records the pasted string and call count")
    func completeManualLoginRecordsPaste() {
        let mock = MockOAuthService()

        mock.completeManualLogin(pasted: "code#state") { _ in }

        #expect(mock.completeManualLoginCallCount == 1)
        #expect(mock.lastManualPaste == "code#state")
    }

    @Test("cancelLogin increments call count")
    func cancelLoginCounts() {
        let mock = MockOAuthService()

        mock.cancelLogin()

        #expect(mock.cancelLoginCallCount == 1)
    }

    @Test("refresh records the tokens passed in and returns the stubbed result")
    func refreshStub() {
        let mock = MockOAuthService()
        let oldTokens = OAuthTokens(accessToken: "old", refreshToken: "oldr", expiresAt: .distantPast)
        let newTokens = OAuthTokens(accessToken: "new", refreshToken: "newr", expiresAt: .distantFuture)
        mock.stubbedRefreshResult = .success(newTokens)

        var captured: Result<OAuthTokens, OAuthError>?
        mock.refresh(oldTokens) { captured = $0 }

        #expect(mock.refreshCallCount == 1)
        #expect(mock.lastRefreshTokens == oldTokens)
        #expect(captured == .success(newTokens))
    }
}
