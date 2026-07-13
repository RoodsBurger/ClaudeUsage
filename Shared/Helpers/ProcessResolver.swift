import Foundation

enum ProcessResolver {
    /// Detect the installed Claude Code version by scanning known installation directories.
    /// Returns the highest semantic version found, or nil if Claude Code is not installed.
    static func detectClaudeCodeVersion() -> String? {
        let fm = FileManager.default
        guard let pw = getpwuid(getuid()) else { return nil }
        let home = String(cString: pw.pointee.pw_dir)

        var candidates: [String] = []

        // npm / native installer: ~/.local/share/claude/versions/<version>/
        let npmDir = home + "/.local/share/claude/versions"
        if let entries = try? fm.contentsOfDirectory(atPath: npmDir) {
            candidates.append(contentsOf: entries)
        }

        // Claude Desktop embedded CLI: ~/Library/Application Support/Claude/claude-code/<version>/
        let desktopDir = home + "/Library/Application Support/Claude/claude-code"
        if let entries = try? fm.contentsOfDirectory(atPath: desktopDir) {
            candidates.append(contentsOf: entries)
        }

        // Homebrew Cask: stable + @latest channel, arm64 + x86_64
        for caskDir in [
            "/opt/homebrew/Caskroom/claude-code",
            "/usr/local/Caskroom/claude-code",
            "/opt/homebrew/Caskroom/claude-code@latest",
            "/usr/local/Caskroom/claude-code@latest",
        ] {
            if let entries = try? fm.contentsOfDirectory(atPath: caskDir) {
                candidates.append(contentsOf: entries)
            }
        }

        // Pick the highest semver-like version
        return candidates
            .filter { $0.first?.isNumber == true }
            .sorted { lhs, rhs in
                lhs.compare(rhs, options: .numeric) == .orderedAscending
            }
            .last
    }
}
