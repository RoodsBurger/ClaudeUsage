import Foundation

final class SharedFileService: SharedFileServiceProtocol, @unchecked Sendable {
    private static let directoryName = "com.raiusage.shared"
    private static let fileName = "shared.json"

    private var realHomeDirectory: String {
        guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
        return String(cString: pw.pointee.pw_dir)
    }

    /// Root directory for the app's own usage cache. Uses the home-relative
    /// `~/Library/Application Support/com.raiusage.shared/` path directly: the
    /// app is desandboxed (post v5.0 Apple Dev migration) and declares no
    /// `application-groups` entitlement, so it writes this path freely without
    /// a Group Container. `realHomeDirectory` (via `getpwuid`) resolves the
    /// real home rather than any sandbox container.
    private var rootDirectoryURL: URL {
        URL(fileURLWithPath: realHomeDirectory)
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(Self.directoryName)
    }

    private var sharedFileURL: URL {
        rootDirectoryURL.appendingPathComponent(Self.fileName)
    }

    // MARK: - SharedData (same JSON format as SharedContainer for backward compat)

    private struct SharedData: Codable {
        var cachedUsage: CachedUsage?
        var lastSyncDate: Date?
    }

    /// In-memory cache - avoids redundant disk reads within the same process.
    /// Each process (app, widget) has its own SharedFileService instance, so no cross-process staleness.
    private var cachedData: SharedData?

    private func load() -> SharedData {
        if let cached = cachedData { return cached }

        var result = SharedData()
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: sharedFileURL, options: [], error: &error) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            if let decoded = try? JSONDecoder().decode(SharedData.self, from: data) {
                result = decoded
            }
        }
        cachedData = result
        return result
    }

    /// Reads the latest on-disk state, bypassing the in-memory cache. The app
    /// holds one `SharedFileService` per store (UsageStore / SettingsStore),
    /// each with its own `cachedData`. Writing off a stale per-instance cache
    /// would clobber whatever another instance wrote since the last read, so
    /// the update path reads fresh immediately before writing.
    private func loadFresh() -> SharedData {
        cachedData = nil
        return load()
    }

    private func save(_ shared: SharedData) {
        let dir = sharedFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(writingItemAt: sharedFileURL, options: .forReplacing, error: &error) { url in
            try? JSONEncoder().encode(shared).write(to: url, options: .atomic)
        }
        cachedData = shared
    }

    // MARK: - SharedFileServiceProtocol

    var fileURL: URL { sharedFileURL }

    func invalidateCache() {
        cachedData = nil
    }

    var isConfigured: Bool { cachedUsage != nil }

    var cachedUsage: CachedUsage? {
        load().cachedUsage
    }

    var lastSyncDate: Date? {
        load().lastSyncDate
    }

    func updateAfterSync(usage: CachedUsage, syncDate: Date) {
        var data = loadFresh()
        data.cachedUsage = usage
        data.lastSyncDate = syncDate
        save(data)
    }

    func clear() {
        let empty = SharedData()
        save(empty)
    }
}
