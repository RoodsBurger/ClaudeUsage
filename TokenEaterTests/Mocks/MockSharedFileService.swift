import Foundation

final class MockSharedFileService: SharedFileServiceProtocol, @unchecked Sendable {
    var fileURL: URL { URL(fileURLWithPath: "/tmp/mock-shared.json") }

    var _cachedUsage: CachedUsage?
    var _lastSyncDate: Date?
    var updateAfterSyncCallCount = 0

    var isConfigured: Bool { _cachedUsage != nil }

    var cachedUsage: CachedUsage? { _cachedUsage }
    var lastSyncDate: Date? { _lastSyncDate }

    func updateAfterSync(usage: CachedUsage, syncDate: Date) {
        updateAfterSyncCallCount += 1
        _cachedUsage = usage
        _lastSyncDate = syncDate
    }

    func invalidateCache() {}

    func clear() {
        _cachedUsage = nil
        _lastSyncDate = nil
    }
}
