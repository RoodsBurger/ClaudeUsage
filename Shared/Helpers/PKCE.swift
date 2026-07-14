import Foundation
import CryptoKit

// MARK: - PKCE

enum PKCE {
    /// Generates a random 32-byte PKCE verifier and encodes it as base64url (no padding).
    /// Result is always 43 characters.
    static func generateVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return base64urlEncode(bytes)
    }

    /// Computes the SHA256 hash of the verifier and encodes it as base64url (no padding).
    static func challenge(for verifier: String) -> String {
        let data = verifier.data(using: .utf8)!
        let digest = SHA256.hash(data: data)
        let bytes = [UInt8](digest)
        return base64urlEncode(bytes)
    }

    // MARK: - Private Helpers

    /// Encodes bytes as base64url without padding (RFC 4648 §5).
    private static func base64urlEncode(_ bytes: [UInt8]) -> String {
        let base64 = Data(bytes).base64EncodedString()
        // Convert standard base64 to base64url: + → -, / → _, remove padding
        let base64url = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        return base64url
    }
}

// MARK: - OAuthURLBuilder

enum OAuthURLBuilder {
    /// Builds the authorization URL with all required OAuth parameters.
    static func authorizeURL(redirectURI: String, challenge: String, state: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "claude.ai"
        components.path = "/oauth/authorize"

        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: OAuthConstants.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: OAuthConstants.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        return components.url!
    }

    /// Parses the OAuth callback, handling both query-string form (?code=...&state=...)
    /// and hash-pasted form (code#state).
    static func parseCallback(_ raw: String) throws -> (code: String, state: String) {
        // Strip URL prefix if present
        var input = raw
        if let range = input.range(of: "?") {
            input = String(input[range.lowerBound...])
        }

        // Try hash form first (pasted code#state)
        if input.contains("#") {
            let parts = input.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let code = String(parts[0]).trimmingCharacters(in: CharacterSet(charactersIn: "?&"))
                let state = String(parts[1])
                if !code.isEmpty && !state.isEmpty {
                    return (code: code, state: state)
                }
            }
        }

        // Try query-string form
        let params = parseQueryString(input)
        guard let code = params["code"], let state = params["state"] else {
            throw OAuthError.malformedCallback
        }
        guard !code.isEmpty && !state.isEmpty else {
            throw OAuthError.malformedCallback
        }

        return (code: code, state: state)
    }

    // MARK: - Private Helpers

    /// Parses a query string into a dictionary.
    private static func parseQueryString(_ query: String) -> [String: String] {
        var result = [String: String]()
        // Strip leading ? if present
        let cleanQuery = query.hasPrefix("?") ? String(query.dropFirst()) : query
        let pairs = cleanQuery.split(separator: "&")
        for pair in pairs {
            let components = pair.split(separator: "=", maxSplits: 1)
            if components.count == 2 {
                let key = String(components[0])
                let value = String(components[1])
                result[key] = value.removingPercentEncoding ?? value
            }
        }
        return result
    }
}
