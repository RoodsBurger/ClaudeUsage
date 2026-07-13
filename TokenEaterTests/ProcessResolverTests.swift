import Testing
import Foundation

@Suite("ProcessResolver")
struct ProcessResolverTests {

    // MARK: - Claude Code version detection

    @Test("detects Claude Code version from local install")
    func detectsClaudeCodeVersion() {
        let version = ProcessResolver.detectClaudeCodeVersion()
        // On dev machines Claude Code should be installed; in CI it might not be
        if let version {
            #expect(version.contains("."))
            #expect(version.first?.isNumber == true)
        }
    }
}
