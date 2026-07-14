import Foundation
import Security

enum OAuthTokenStoreError: Error, Equatable, CustomStringConvertible {
    case encodeFailed
    case keychainWriteFailed(OSStatus)

    var description: String {
        switch self {
        case .encodeFailed: return "Failed to encode OAuth tokens"
        case .keychainWriteFailed(let status): return "Keychain write failed (status \(status))"
        }
    }
}

final class OAuthTokenStore: OAuthTokenStoreProtocol {
    // MARK: - Constants

    private static let service = "com.raiusage.oauth"
    private static let account = "claude"
    private static let accessibleAttribute = kSecAttrAccessibleAfterFirstUnlock

    // MARK: - Protocol Methods

    func load() -> OAuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecUseAuthenticationUISkip as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return Self.decode(data)
    }

    func save(_ tokens: OAuthTokens) throws {
        guard let encodedData = try? Self.encode(tokens) else {
            throw OAuthTokenStoreError.encodeFailed
        }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: encodedData,
            kSecAttrAccessible as String: Self.accessibleAttribute,
            kSecUseAuthenticationUISkip as String: true
        ]

        // Try to update existing item first.
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist; create it.
            let createStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard createStatus == errSecSuccess else {
                throw OAuthTokenStoreError.keychainWriteFailed(createStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw OAuthTokenStoreError.keychainWriteFailed(updateStatus)
        }
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]

        _ = SecItemDelete(query as CFDictionary)
    }

    // MARK: - Internal Codec

    /// Encodes OAuthTokens to JSON Data using epoch-seconds date strategy.
    static func encode(_ tokens: OAuthTokens) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(tokens)
    }

    /// Decodes OAuthTokens from JSON Data using epoch-seconds date strategy.
    /// Returns nil if decoding fails.
    static func decode(_ data: Data) -> OAuthTokens? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(OAuthTokens.self, from: data)
    }
}
