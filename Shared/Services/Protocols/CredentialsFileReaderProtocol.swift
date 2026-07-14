import Foundation

protocol CredentialsFileReaderProtocol: Sendable {
    func readToken() -> String?
    /// Same source as `readToken()`, but surfaces the full credential
    /// (refresh token, expiry) so callers can skip an expired one instead of
    /// serving it, or self-refresh it as a last resort.
    func readCredential() -> BorrowedCredential?
    func tokenExists() -> Bool
}
