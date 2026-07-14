import Foundation

final class MockCredentialsFileReader: CredentialsFileReaderProtocol, @unchecked Sendable {
    var storedToken: String?
    var fileExists: Bool = false

    /// Explicit stub for `readCredential()`. When nil, it's derived from
    /// `storedToken` (accessToken only, no refresh token, no expiry) so
    /// existing tests that only set `storedToken` keep compiling and
    /// behaving the same.
    var credential: BorrowedCredential?

    func readToken() -> String? { storedToken }

    func readCredential() -> BorrowedCredential? {
        if let credential { return credential }
        guard let storedToken else { return nil }
        return BorrowedCredential(accessToken: storedToken, refreshToken: nil, expiresAt: nil)
    }

    func tokenExists() -> Bool { fileExists }
}
