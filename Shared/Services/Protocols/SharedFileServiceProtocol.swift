import Foundation

protocol SharedFileServiceProtocol: Sendable {
    var fileURL: URL { get }
    var isConfigured: Bool { get }
    var cachedUsage: CachedUsage? { get }
    var lastSyncDate: Date? { get }

    func invalidateCache()
    func updateAfterSync(usage: CachedUsage, syncDate: Date)
    func clear()
}
