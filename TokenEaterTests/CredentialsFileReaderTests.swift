import Testing
import Foundation

/// Exercises `CredentialsFileReader` against a controlled temp file (never
/// the real `~/.claude/.credentials.json`) via the test-only `init(filePath:)`.
@Suite("CredentialsFileReader")
struct CredentialsFileReaderTests {

    private func writeFixture(_ json: String) -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("CredentialsFileReaderTests-\(UUID().uuidString).json")
        try? Data(json.utf8).write(to: path)
        return path.path
    }

    @Test("readCredential extracts accessToken, refreshToken, and expiresAt (ms epoch converted to seconds)")
    func readsFullCredential() {
        let path = writeFixture("""
        {"claudeAiOauth":{"accessToken":"file-access","refreshToken":"file-refresh","expiresAt":1735689600000}}
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let reader = CredentialsFileReader(filePath: path)
        let credential = reader.readCredential()

        #expect(credential?.accessToken == "file-access")
        #expect(credential?.refreshToken == "file-refresh")
        #expect(credential?.expiresAt == Date(timeIntervalSince1970: 1735689600))
    }

    @Test("readCredential normalizes an empty refreshToken to nil")
    func emptyRefreshTokenIsNil() {
        let path = writeFixture("""
        {"claudeAiOauth":{"accessToken":"file-access","refreshToken":""}}
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let reader = CredentialsFileReader(filePath: path)
        #expect(reader.readCredential()?.refreshToken == nil)
    }

    @Test("readCredential surfaces nil expiresAt when the field is absent")
    func missingExpiresAtIsNil() {
        let path = writeFixture("""
        {"claudeAiOauth":{"accessToken":"file-access"}}
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let reader = CredentialsFileReader(filePath: path)
        #expect(reader.readCredential()?.expiresAt == nil)
    }

    @Test("readCredential returns nil for an empty accessToken")
    func emptyAccessTokenReturnsNil() {
        let path = writeFixture("""
        {"claudeAiOauth":{"accessToken":""}}
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let reader = CredentialsFileReader(filePath: path)
        #expect(reader.readCredential() == nil)
    }

    @Test("readCredential returns nil when the file doesn't exist")
    func missingFileReturnsNil() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("CredentialsFileReaderTests-nonexistent-\(UUID().uuidString).json")
            .path

        let reader = CredentialsFileReader(filePath: path)
        #expect(reader.readCredential() == nil)
    }

    @Test("readToken stays in sync with readCredential's accessToken")
    func readTokenMatchesCredential() {
        let path = writeFixture("""
        {"claudeAiOauth":{"accessToken":"file-access","refreshToken":"file-refresh"}}
        """)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let reader = CredentialsFileReader(filePath: path)
        #expect(reader.readToken() == "file-access")
        #expect(reader.readToken() == reader.readCredential()?.accessToken)
    }
}
