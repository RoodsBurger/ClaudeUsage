import Foundation

final class CredentialsFileReader: CredentialsFileReaderProtocol, @unchecked Sendable {

    private let filePath: String

    init() {
        guard let pw = getpwuid(getuid()) else {
            filePath = ""
            return
        }
        let home = String(cString: pw.pointee.pw_dir)
        filePath = home + "/.claude/.credentials.json"
    }

    init(filePath: String) {
        self.filePath = filePath
    }

    func readToken() -> String? {
        readCredential()?.accessToken
    }

    /// Same parse as `readToken`, but also surfaces `refreshToken`
    /// (absent/empty -> nil) and `expiresAt` (Claude Code stores this as
    /// milliseconds since epoch, unlike this app's own seconds-based
    /// `OAuthTokens`).
    func readCredential() -> BorrowedCredential? {
        guard let data = FileManager.default.contents(atPath: filePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else {
            return nil
        }
        let refreshToken = (oauth["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return BorrowedCredential(accessToken: token, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    func tokenExists() -> Bool {
        FileManager.default.fileExists(atPath: filePath)
    }
}
