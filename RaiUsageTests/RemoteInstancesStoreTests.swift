import Testing
import Foundation

@MainActor
@Suite("RemoteInstancesStore", .serialized)
struct RemoteInstancesStoreTests {

    private static let key = "remoteInstances"

    private func makeStore(mock: MockRemoteLogSyncService = MockRemoteLogSyncService()) -> RemoteInstancesStore {
        UserDefaults.standard.removeObject(forKey: Self.key)
        return RemoteInstancesStore(service: mock)
    }

    @Test("addInstance accepts a valid host/user and persists it")
    func addValid() {
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        let store = makeStore()
        #expect(store.addInstance(host: "10.63.7.150", user: "ubuntu", nickname: "prod"))
        #expect(store.instances.count == 1)
        #expect(store.instances.first?.host == "10.63.7.150")
        #expect(store.instances.first?.nickname == "prod")

        // A fresh store reads the persisted value back.
        let reloaded = RemoteInstancesStore(service: MockRemoteLogSyncService())
        #expect(reloaded.instances.count == 1)
        #expect(reloaded.instances.first?.host == "10.63.7.150")
    }

    @Test("addInstance rejects an invalid host and adds nothing")
    func addInvalid() {
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        let store = makeStore()
        #expect(!store.addInstance(host: "bad host;rm", user: "ubuntu", nickname: nil))
        #expect(store.instances.isEmpty)
    }

    @Test("a blank nickname is stored as nil")
    func blankNicknameNormalized() {
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        let store = makeStore()
        #expect(store.addInstance(host: "h", user: "ubuntu", nickname: "   "))
        #expect(store.instances.first?.nickname == nil)
    }

    @Test("toggle and setEnabled flip the enabled flag; enabledInstances filters")
    func togglingEnabled() {
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        let store = makeStore()
        store.addInstance(host: "a", user: "ubuntu", nickname: nil)
        store.addInstance(host: "b", user: "ubuntu", nickname: nil)
        let idA = store.instances[0].id
        let idB = store.instances[1].id

        store.setEnabled(idB, false)
        #expect(store.enabledInstances.map(\.id) == [idA])

        store.toggle(idB)
        #expect(store.enabledInstances.count == 2)
    }

    @Test("removeInstance drops it and clears its status")
    func removing() {
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        let store = makeStore()
        store.addInstance(host: "a", user: "ubuntu", nickname: nil)
        let id = store.instances[0].id
        store.removeInstance(id)
        #expect(store.instances.isEmpty)
        #expect(store.status[id] == nil)
    }

    @Test("syncNow drives the service and records success status")
    func syncNowSucceeds() async {
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        let mock = MockRemoteLogSyncService(outcome: .ok(fileCount: 42, date: Date()))
        let store = makeStore(mock: mock)
        store.addInstance(host: "10.0.0.9", user: "ubuntu", nickname: nil)
        let id = store.instances[0].id

        store.syncNow(id)
        // Let the detached sync Task run to completion.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(mock.syncedInstances.map(\.host) == ["10.0.0.9"])
        if case .synced(let count, _) = store.status[id]?.state {
            #expect(count == 42)
        } else {
            Issue.record("expected .synced status, got \(String(describing: store.status[id]?.state))")
        }
        #expect(store.syncGeneration >= 1)
    }

    @Test("syncNow records a failure message from the service")
    func syncNowFails() async {
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        let mock = MockRemoteLogSyncService(outcome: .failed("Connection timed out"))
        let store = makeStore(mock: mock)
        store.addInstance(host: "10.0.0.9", user: "ubuntu", nickname: nil)
        let id = store.instances[0].id

        store.syncNow(id)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(store.status[id]?.state == .failed("Connection timed out"))
    }

    @Test("a failed sync stays graceful: no syncGeneration bump, so no reload")
    func failureDoesNotBumpGeneration() async {
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        let mock = MockRemoteLogSyncService(outcome: .failed("Connection timed out"))
        let store = makeStore(mock: mock)
        store.addInstance(host: "10.0.0.9", user: "ubuntu", nickname: nil)
        let before = store.syncGeneration

        store.syncNow(store.instances[0].id)
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(store.syncGeneration == before)
    }
}
