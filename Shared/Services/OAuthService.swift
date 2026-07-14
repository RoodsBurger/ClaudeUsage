import Foundation
import Network
import AppKit

/// Performs the authorization-code + PKCE login flow and serialized refresh
/// exchanges against `OAuthConstants.tokenURL`. All I/O is injected so the
/// service never opens a real browser, hits the real network, or binds a
/// real socket unless the real default seams are used (production only).
final class OAuthService: OAuthServiceProtocol {
    // MARK: - Injected Seams

    /// URLSession-shaped transport; tests capture the request and stub the response.
    typealias Transport = (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void
    /// Opens a URL in the user's default browser.
    typealias BrowserOpener = (URL) -> Void
    /// Starts the loopback listener. Calls `onReady(port)` once bound, `onRequest(raw)`
    /// for each received GET (path + query), `onFailure()` if binding fails. Returns a
    /// stop closure the caller invokes to tear the listener down.
    typealias LoopbackStarter = (
        _ onReady: @escaping (UInt16) -> Void,
        _ onRequest: @escaping (String) -> Void,
        _ onFailure: @escaping () -> Void
    ) -> () -> Void

    private let transport: Transport
    private let browserOpener: BrowserOpener
    private let loopbackStarter: LoopbackStarter
    private let randomToken: () -> String
    private let now: () -> Date

    // MARK: - Pending Login Session

    /// State for one in-flight login attempt, shared by the loopback and manual paths.
    private final class PendingLogin {
        let state: String
        let codeVerifier: String
        let completion: (Result<OAuthTokens, OAuthError>) -> Void
        var redirectURI: String?
        var stopListener: (() -> Void)?
        var isFinished = false

        init(state: String, codeVerifier: String, completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
            self.state = state
            self.codeVerifier = codeVerifier
            self.completion = completion
        }
    }

    /// Guarded by `stateQueue`.
    private var pendingLogin: PendingLogin?

    // MARK: - Refresh Coalescing

    /// Completions waiting on the single in-flight refresh exchange, if any.
    /// Guarded by `stateQueue`.
    private var pendingRefreshCompletions: [(Result<OAuthTokens, OAuthError>) -> Void] = []

    /// Serializes every access to the mutable login/refresh state. The production
    /// transport delivers URLSession completions on a background queue while
    /// `refresh`/`cancelLogin` are driven from the main queue, so all reads and
    /// mutations of `pendingLogin`, `pendingRefreshCompletions`, and a session's
    /// `isFinished`/`redirectURI`/`stopListener` fields run here. Injected seams
    /// (transport, browser, listener) and user completions are always invoked
    /// outside this queue to avoid reentrant deadlocks.
    private let stateQueue = DispatchQueue(label: "com.raiusage.oauth.state")

    // MARK: - Init

    init(
        transport: @escaping Transport = OAuthService.urlSessionTransport,
        browserOpener: @escaping BrowserOpener = { NSWorkspace.shared.open($0) },
        loopbackStarter: @escaping LoopbackStarter = OAuthService.startRealLoopbackListener,
        randomToken: @escaping () -> String = PKCE.generateVerifier,
        now: @escaping () -> Date = Date.init
    ) {
        self.transport = transport
        self.browserOpener = browserOpener
        self.loopbackStarter = loopbackStarter
        self.randomToken = randomToken
        self.now = now
    }

    private static let urlSessionTransport: Transport = { request, completion in
        URLSession.shared.dataTask(with: request) { data, response, error in
            completion(data, response, error)
        }.resume()
    }

    /// Real loopback listener backed by Network.framework. Never invoked by tests.
    private static let startRealLoopbackListener: LoopbackStarter = { onReady, onRequest, onFailure in
        let listener: NWListener
        do {
            // Bind to loopback only so no other host on the network can reach the
            // callback listener; the ephemeral port is chosen by the stack.
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        } catch {
            onFailure()
            return {}
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let port = listener.port?.rawValue {
                    onReady(port)
                } else {
                    onFailure()
                }
            case .failed, .cancelled:
                onFailure()
            default:
                break
            }
        }

        listener.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .userInitiated))
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                guard let data, let requestText = String(data: data, encoding: .utf8) else {
                    connection.cancel()
                    return
                }
                let requestLine = requestText.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? requestText
                let tokens = requestLine.split(separator: " ", maxSplits: 2)
                let path = tokens.count > 1 ? String(tokens[1]) : ""

                let html = "<html><body>You can close this window.</body></html>"
                let responseText = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                connection.send(content: responseText.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })

                onRequest(path)
            }
        }

        listener.start(queue: .global(qos: .userInitiated))
        return { listener.cancel() }
    }

    // MARK: - beginLogin

    func beginLogin(completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
        cancelLogin()

        let verifier = randomToken()
        let challenge = PKCE.challenge(for: verifier)
        let state = randomToken()

        let session = PendingLogin(state: state, codeVerifier: verifier, completion: completion)
        stateQueue.sync { pendingLogin = session }

        let stop = loopbackStarter(
            { [weak self] port in self?.handleLoopbackReady(port: port, challenge: challenge, session: session) },
            { [weak self] raw in self?.handleLoopbackCallback(raw) },
            { [weak self] in self?.handleLoopbackFailure(session: session) }
        )

        // If the listener failed or was cancelled inline (before this returns), the
        // session is already finished; tear down the just-created listener instead.
        let alreadyFinished: Bool = stateQueue.sync {
            if session.isFinished { return true }
            session.stopListener = stop
            return false
        }
        if alreadyFinished { stop() }
    }

    private func handleLoopbackReady(port: UInt16, challenge: String, session: PendingLogin) {
        let redirectURI: String? = stateQueue.sync {
            guard pendingLogin === session, !session.isFinished else { return nil }
            let uri = "http://127.0.0.1:\(port)/callback"
            session.redirectURI = uri
            return uri
        }
        guard let redirectURI else { return }
        let url = OAuthURLBuilder.authorizeURL(redirectURI: redirectURI, challenge: challenge, state: session.state)
        browserOpener(url)
    }

    private func handleLoopbackFailure(session: PendingLogin) {
        finishLogin(session: session, result: .failure(.listenerFailed), via: session.completion)
    }

    /// Callback-handling seam: processes a raw loopback GET request (path + query),
    /// exactly as the real listener's connection handler does. Tests call this directly
    /// to simulate a received callback without binding a real socket.
    func handleLoopbackCallback(_ raw: String) {
        let session: PendingLogin? = stateQueue.sync {
            guard let session = pendingLogin, !session.isFinished else { return nil }
            return session
        }
        guard let session else { return }
        let redirectURI = stateQueue.sync { session.redirectURI } ?? OAuthConstants.manualRedirectURI
        processCallback(raw, expectedState: session.state, codeVerifier: session.codeVerifier, redirectURI: redirectURI) { [weak self] result in
            guard let self else { return }
            self.finishLogin(session: session, result: result, via: session.completion)
        }
    }

    // MARK: - completeManualLogin

    func completeManualLogin(pasted: String, completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
        let session: PendingLogin? = stateQueue.sync {
            guard let session = pendingLogin, !session.isFinished else { return nil }
            return session
        }
        guard let session else {
            deliver(.failure(.stateMismatch), via: completion)
            return
        }
        processCallback(pasted, expectedState: session.state, codeVerifier: session.codeVerifier, redirectURI: OAuthConstants.manualRedirectURI) { [weak self] result in
            guard let self else { return }
            self.finishLogin(session: session, result: result, via: completion)
        }
    }

    // MARK: - cancelLogin

    func cancelLogin() {
        var captured: (stop: (() -> Void)?, completion: (Result<OAuthTokens, OAuthError>) -> Void)?
        stateQueue.sync {
            guard let session = pendingLogin else { return }
            pendingLogin = nil
            session.isFinished = true
            captured = (session.stopListener, session.completion)
        }
        guard let captured else { return }
        captured.stop?()
        deliver(.failure(.cancelled), via: captured.completion)
    }

    // MARK: - Shared Login Completion

    /// Atomically claims completion of `session`. Only the first caller (cancel or a
    /// resolved exchange) wins; later callers see `isFinished` and do nothing, so a
    /// completion is never dropped or delivered twice.
    private func finishLogin(session: PendingLogin, result: Result<OAuthTokens, OAuthError>, via completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
        var stop: (() -> Void)?
        let shouldDeliver: Bool = stateQueue.sync {
            guard !session.isFinished else { return false }
            session.isFinished = true
            stop = session.stopListener
            if pendingLogin === session { pendingLogin = nil }
            return true
        }
        guard shouldDeliver else { return }
        stop?()
        deliver(result, via: completion)
    }

    private func processCallback(_ raw: String, expectedState: String, codeVerifier: String, redirectURI: String, completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
        let parsed: (code: String, state: String)
        do {
            parsed = try OAuthURLBuilder.parseCallback(raw)
        } catch {
            completion(.failure(.malformedCallback))
            return
        }
        guard parsed.state == expectedState else {
            completion(.failure(.stateMismatch))
            return
        }
        exchangeAuthorizationCode(code: parsed.code, state: parsed.state, verifier: codeVerifier, redirectURI: redirectURI, completion: completion)
    }

    // MARK: - Token Exchange

    private func exchangeAuthorizationCode(code: String, state: String, verifier: String, redirectURI: String, completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": OAuthConstants.clientID,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ]
        let request = makeTokenRequest(body: body)
        transport(request) { [weak self] data, response, error in
            guard let self else { return }
            let result = self.decodeTokenResponse(data: data, response: response, error: error, failureCase: OAuthError.exchangeFailed)
            completion(result)
        }
    }

    // MARK: - refresh

    func refresh(_ tokens: OAuthTokens, completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
        let shouldStart: Bool = stateQueue.sync {
            pendingRefreshCompletions.append(completion)
            return pendingRefreshCompletions.count == 1
        }
        if shouldStart { performRefresh(tokens) }
    }

    private func performRefresh(_ tokens: OAuthTokens) {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": OAuthConstants.clientID,
        ]
        let request = makeTokenRequest(body: body)
        transport(request) { [weak self] data, response, error in
            guard let self else { return }
            let result = self.decodeTokenResponse(data: data, response: response, error: error, failureCase: OAuthError.refreshFailed)
            self.finishRefresh(with: result)
        }
    }

    private func finishRefresh(with result: Result<OAuthTokens, OAuthError>) {
        let completions: [(Result<OAuthTokens, OAuthError>) -> Void] = stateQueue.sync {
            let snapshot = pendingRefreshCompletions
            pendingRefreshCompletions = []
            return snapshot
        }
        for completion in completions {
            deliver(result, via: completion)
        }
    }

    // MARK: - Shared Request / Response Handling

    private func makeTokenRequest(body: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: OAuthConstants.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Decodes a token endpoint response. `failureCase` distinguishes exchange vs refresh
    /// failures. A transport-level failure (no HTTP response) reports status -1.
    private func decodeTokenResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        failureCase: (Int) -> OAuthError
    ) -> Result<OAuthTokens, OAuthError> {
        guard error == nil, let http = response as? HTTPURLResponse else {
            return .failure(failureCase(-1))
        }
        guard http.statusCode == 200, let data else {
            return .failure(failureCase(http.statusCode))
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            return .failure(failureCase(http.statusCode))
        }
        return .success(decoded.tokens(now: now()))
    }

    private func deliver(_ result: Result<OAuthTokens, OAuthError>, via completion: @escaping (Result<OAuthTokens, OAuthError>) -> Void) {
        if Thread.isMainThread {
            completion(result)
        } else {
            DispatchQueue.main.async { completion(result) }
        }
    }
}
