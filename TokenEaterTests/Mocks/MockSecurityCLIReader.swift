import Foundation

final class MockSecurityCLIReader: SecurityCLIReaderProtocol, @unchecked Sendable {
    var token: String?
    var readCallCount = 0

    /// Explicit stub for `readCredential()`. When nil, it's derived from
    /// `token` (accessToken only, no refresh token, no expiry) so existing
    /// tests that only set `token` keep compiling and behaving the same.
    var credential: BorrowedCredential?
    var readCredentialCallCount = 0

    func readToken() -> String? {
        readCallCount += 1
        return token
    }

    func readCredential() -> BorrowedCredential? {
        readCredentialCallCount += 1
        if let credential { return credential }
        guard let token else { return nil }
        return BorrowedCredential(accessToken: token, refreshToken: nil, expiresAt: nil)
    }
}
