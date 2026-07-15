import SwiftUI

/// Last-known sync state for one instance, shown as the status line under it.
struct RemoteSyncStatus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        case syncing
        case synced(fileCount: Int, at: Date)
        case failed(String)
    }
    var state: State = .idle
}

/// Owns the user's configured remote instances (persisted to UserDefaults) and
/// orchestrates their SSH/rsync syncs off the main actor via
/// `RemoteLogSyncService`. Per-instance status is published for the Settings UI.
@MainActor
final class RemoteInstancesStore: ObservableObject {

    /// The configured instances, in the order the user added them.
    @Published private(set) var instances: [RemoteInstance] {
        didSet { persist() }
    }

    /// Per-instance last sync status keyed by instance id.
    @Published private(set) var status: [UUID: RemoteSyncStatus] = [:]

    /// Bumped after every sync completes so dependent views (History) can
    /// react and reload without a direct binding to `status`.
    @Published private(set) var syncGeneration: Int = 0

    private let service: RemoteLogSyncServiceProtocol
    private static let defaultsKey = "remoteInstances"
    /// Throttle floor for opportunistic (History-appear + auto-refresh) syncs.
    private var lastOpportunisticSync: Date = .distantPast
    private var autoSyncTask: Task<Void, Never>?

    /// The instances that participate in scans + syncs.
    var enabledInstances: [RemoteInstance] { instances.filter(\.enabled) }

    init(service: RemoteLogSyncServiceProtocol = RemoteLogSyncService()) {
        self.service = service
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([RemoteInstance].self, from: data) {
            self.instances = decoded
        } else {
            self.instances = []
        }
    }

    // MARK: - Mutations

    /// Adds an instance after validating host + user. Returns false (and adds
    /// nothing) when either is invalid.
    @discardableResult
    func addInstance(host: String, user: String, nickname: String?) -> Bool {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RemoteInstanceValidation.isValidHost(trimmedHost),
              RemoteInstanceValidation.isValidUser(trimmedUser) else {
            return false
        }
        let trimmedNick = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let instance = RemoteInstance(
            host: trimmedHost,
            user: trimmedUser,
            enabled: true,
            nickname: (trimmedNick?.isEmpty ?? true) ? nil : trimmedNick
        )
        instances.append(instance)
        return true
    }

    func removeInstance(_ id: UUID) {
        instances.removeAll { $0.id == id }
        status[id] = nil
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        guard let index = instances.firstIndex(where: { $0.id == id }),
              instances[index].enabled != enabled else { return }
        instances[index].enabled = enabled
    }

    func toggle(_ id: UUID) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        instances[index].enabled.toggle()
    }

    // MARK: - Sync

    func syncNow(_ id: UUID) {
        guard let instance = instances.first(where: { $0.id == id }) else { return }
        Task { await performSync(instance) }
    }

    func syncAll() {
        for instance in enabledInstances { syncNow(instance.id) }
    }

    /// Opportunistic, throttled sync of enabled instances whose cache is older
    /// than `interval` (or missing). Called on History appear and on the
    /// auto-refresh tick. Failures are tolerated: an unreachable/off instance
    /// just fails fast into its Settings status line without touching its
    /// cache, so History keeps showing whatever was last pulled.
    func syncStaleInstances(olderThan interval: TimeInterval = 300) {
        let now = Date()
        guard now.timeIntervalSince(lastOpportunisticSync) > 60 else { return }
        lastOpportunisticSync = now
        for instance in enabledInstances where cacheIsStale(instance, olderThan: interval, now: now) {
            syncNow(instance.id)
        }
    }

    /// Pulls enabled instances on the usage auto-refresh cadence so remote
    /// sessions stay current without a manual refresh. Reuses the throttled,
    /// failure-tolerant `syncStaleInstances`, so a down instance never blocks
    /// the usage refresh and never surfaces beyond its Settings status line.
    func startAutoSync(interval: TimeInterval) {
        autoSyncTask?.cancel()
        let interval = max(interval, 60)
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self else { return }
                self.syncStaleInstances(olderThan: interval)
            }
        }
    }

    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    private func cacheIsStale(_ instance: RemoteInstance, olderThan interval: TimeInterval, now: Date) -> Bool {
        let dir = RemoteLogCache.directory(forHost: instance.host)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dir.path),
              let mtime = attrs[.modificationDate] as? Date else { return true }
        return now.timeIntervalSince(mtime) > interval
    }

    private func performSync(_ instance: RemoteInstance) async {
        status[instance.id] = RemoteSyncStatus(state: .syncing)
        let outcome = await service.sync(instance)
        switch outcome {
        case .ok(let count, let date):
            status[instance.id] = RemoteSyncStatus(state: .synced(fileCount: count, at: date))
            // Only a successful pull changes the cache, so only then do
            // dependents (History/activity) need to reload. A failure leaves
            // the last-good logs untouched and shows only in Settings.
            syncGeneration &+= 1
        case .failed(let message):
            status[instance.id] = RemoteSyncStatus(state: .failed(message))
        }
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
