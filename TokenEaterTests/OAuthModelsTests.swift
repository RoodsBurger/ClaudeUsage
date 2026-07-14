import Testing
import Foundation

@Suite("OAuthTokens")
struct OAuthTokensTests {
    @Test("needsRefresh returns false for fresh token")
    func needsRefreshFresh() {
        let now = Date()
        let expiresAt = now.addingTimeInterval(600) // 10 minutes away
        let tokens = OAuthTokens(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: expiresAt
        )
        #expect(tokens.needsRefresh(now: now) == false)
    }

    @Test("needsRefresh returns true within margin (300s default)")
    func needsRefreshWithinMargin() {
        let now = Date()
        let expiresAt = now.addingTimeInterval(100) // 100s away, within 300s margin
        let tokens = OAuthTokens(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: expiresAt
        )
        #expect(tokens.needsRefresh(now: now) == true)
    }

    @Test("needsRefresh returns true when past expiry")
    func needsRefreshPastExpiry() {
        let now = Date()
        let expiresAt = now.addingTimeInterval(-100) // 100s ago
        let tokens = OAuthTokens(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: expiresAt
        )
        #expect(tokens.needsRefresh(now: now) == true)
    }

    @Test("needsRefresh respects custom margin")
    func needsRefreshCustomMargin() {
        let now = Date()
        let expiresAt = now.addingTimeInterval(150) // 150s away
        let tokens = OAuthTokens(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: expiresAt
        )
        // With default 300s margin: should refresh
        #expect(tokens.needsRefresh(now: now, margin: 300) == true)
        // With 100s margin: should not refresh
        #expect(tokens.needsRefresh(now: now, margin: 100) == false)
    }

    @Test("OAuthTokens is Codable")
    func oauthTokensCodable() throws {
        let now = Date()
        let tokens = OAuthTokens(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: now
        )
        let encoded = try JSONEncoder().encode(tokens)
        let decoded = try JSONDecoder().decode(OAuthTokens.self, from: encoded)
        #expect(decoded == tokens)
    }

    @Test("OAuthTokens decodes epoch-SECONDS JSON format")
    func oauthTokensEpochSecondsFormat() throws {
        let json = """
        {"accessToken":"a","refreshToken":"r","expiresAt":1783980000}
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let tokens = try decoder.decode(OAuthTokens.self, from: json)

        #expect(tokens.accessToken == "a")
        #expect(tokens.refreshToken == "r")
        #expect(abs(tokens.expiresAt.timeIntervalSince1970 - 1783980000) < 0.1)
    }
}

@Suite("TokenResponse")
struct TokenResponseTests {
    @Test("TokenResponse decodes standard OAuth token endpoint response")
    func decodeTokenResponse() throws {
        let json = """
        {
            "access_token": "test-access-token",
            "refresh_token": "test-refresh-token",
            "expires_in": 3600,
            "token_type": "Bearer",
            "scope": "user:profile user:inference"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TokenResponse.self, from: json)
        let now = Date()
        let tokens = response.tokens(now: now)

        #expect(tokens.accessToken == "test-access-token")
        #expect(tokens.refreshToken == "test-refresh-token")
        // Check that expiresAt is approximately now + 3600
        let expectedExpiry = now.addingTimeInterval(3600)
        #expect(abs(tokens.expiresAt.timeIntervalSince(expectedExpiry)) < 1.0)
    }

    @Test("TokenResponse.tokens uses provided now parameter")
    func tokensUsesNowParameter() throws {
        let json = """
        {
            "access_token": "test-access-token",
            "refresh_token": "test-refresh-token",
            "expires_in": 3600,
            "token_type": "Bearer",
            "scope": "user:profile user:inference"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(TokenResponse.self, from: json)
        let customNow = Date(timeIntervalSince1970: 1000000)
        let tokens = response.tokens(now: customNow)

        let expectedExpiry = customNow.addingTimeInterval(3600)
        #expect(abs(tokens.expiresAt.timeIntervalSince(expectedExpiry)) < 1.0)
    }
}

@Suite("OAuthError")
struct OAuthErrorTests {
    @Test("OAuthError is Equatable")
    func oauthErrorEquatable() {
        let error1 = OAuthError.stateMismatch
        let error2 = OAuthError.stateMismatch
        #expect(error1 == error2)

        let error3 = OAuthError.exchangeFailed(401)
        let error4 = OAuthError.exchangeFailed(401)
        #expect(error3 == error4)

        let error5 = OAuthError.exchangeFailed(401)
        let error6 = OAuthError.exchangeFailed(500)
        #expect(error5 != error6)
    }
}

@Suite("OAuthURLBuilder")
struct OAuthURLBuilderTests {
    @Test("authorizeURL builds correct URL with all required parameters")
    func authorizeURLStructure() {
        let redirectURI = "http://localhost:8080/callback"
        let challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        let state = "test-state-value"

        let url = OAuthURLBuilder.authorizeURL(redirectURI: redirectURI, challenge: challenge, state: state)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Issue.record("Failed to parse URL components")
            return
        }

        #expect(url.scheme == "https")
        #expect(url.host == "claude.ai")
        #expect(url.path == "/oauth/authorize")

        let queryParams = components.queryItems ?? []
        let paramDict = Dictionary(uniqueKeysWithValues: queryParams.map { ($0.name, $0.value) })

        #expect(paramDict["code"] == "true")
        #expect(paramDict["client_id"] == "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        #expect(paramDict["response_type"] == "code")
        #expect(paramDict["redirect_uri"] == redirectURI)
        #expect(paramDict["scope"] == "user:profile user:inference")
        #expect(paramDict["code_challenge"] == challenge)
        #expect(paramDict["code_challenge_method"] == "S256")
        #expect(paramDict["state"] == state)
    }

    @Test("authorizeURL percent-encodes spaces in scope")
    func authorizeURLScopeEncoding() {
        let url = OAuthURLBuilder.authorizeURL(
            redirectURI: "http://localhost:8080/callback",
            challenge: "test-challenge",
            state: "test-state"
        )

        let urlString = url.absoluteString
        // The scope "user:profile user:inference" should have space percent-encoded as %20
        #expect(urlString.contains("user:profile%20user:inference"))
    }

    @Test("parseCallback handles query string form")
    func parseCallbackQueryForm() throws {
        let raw = "code=auth-code-123&state=state-value-456"
        let (code, state) = try OAuthURLBuilder.parseCallback(raw)
        #expect(code == "auth-code-123")
        #expect(state == "state-value-456")
    }

    @Test("parseCallback handles hash form (paste)")
    func parseCallbackHashForm() throws {
        let raw = "auth-code-123#state-value-456"
        let (code, state) = try OAuthURLBuilder.parseCallback(raw)
        #expect(code == "auth-code-123")
        #expect(state == "state-value-456")
    }

    @Test("parseCallback rejects missing code")
    func parseCallbackMissingCode() throws {
        let raw = "state=state-value"
        do {
            _ = try OAuthURLBuilder.parseCallback(raw)
            Issue.record("Should have thrown malformedCallback")
        } catch OAuthError.malformedCallback {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("parseCallback rejects missing state")
    func parseCallbackMissingState() throws {
        let raw = "code=code-value"
        do {
            _ = try OAuthURLBuilder.parseCallback(raw)
            Issue.record("Should have thrown malformedCallback")
        } catch OAuthError.malformedCallback {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("parseCallback rejects completely invalid input")
    func parseCallbackInvalid() throws {
        let raw = "garbage"
        do {
            _ = try OAuthURLBuilder.parseCallback(raw)
            Issue.record("Should have thrown malformedCallback")
        } catch OAuthError.malformedCallback {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("parseCallback handles query string with full URL")
    func parseCallbackFullURL() throws {
        let raw = "http://localhost:8080/callback?code=auth-code-123&state=state-value-456"
        let (code, state) = try OAuthURLBuilder.parseCallback(raw)
        #expect(code == "auth-code-123")
        #expect(state == "state-value-456")
    }
}
