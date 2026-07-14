import Testing
import Foundation
import Combine

@Suite("UpdateStore")
@MainActor
struct UpdateStoreTests {

    private static let suiteName = "UpdateStoreTests"

    private func makeStore(
        checker: MockUpdateChecker = MockUpdateChecker(),
        installer: MockUpdateInstaller = MockUpdateInstaller()
    ) -> (UpdateStore, MockUpdateChecker, MockUpdateInstaller, UserDefaults) {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        let store = UpdateStore(
            checker: checker,
            installer: installer,
            defaults: defaults,
            currentVersion: "5.8.0"
        )
        return (store, checker, installer, defaults)
    }

    private var sampleInfo: UpdateInfo {
        UpdateInfo(
            version: "9.9.9",
            releaseURL: URL(string: "https://github.com/RoodsBurger/RaiUsage/releases/tag/v9.9.9")!,
            dmgURL: URL(string: "https://github.com/RoodsBurger/RaiUsage/releases/download/v9.9.9/RaiUsage-v9.9.9.dmg")!
        )
    }

    // MARK: - Check

    @Test("check lands in upToDate when the checker returns nil")
    func checkUpToDate() async {
        let (store, checker, _, _) = makeStore()
        checker.stubbedInfo = nil
        await store.checkNow()
        #expect(store.state == .upToDate)
        #expect(checker.checkCallCount == 1)
    }

    @Test("check lands in available with the checker's info")
    func checkAvailable() async {
        let (store, checker, _, _) = makeStore()
        checker.stubbedInfo = sampleInfo
        await store.checkNow()
        #expect(store.state == .available(sampleInfo))
    }

    @Test("a checker failure lands in failed with a readable message")
    func checkFailure() async {
        let (store, checker, _, _) = makeStore()
        checker.stubbedError = UpdateCheckerError.badResponse
        await store.checkNow()
        guard case .failed(let message) = store.state else {
            Issue.record("expected .failed, got \(store.state)")
            return
        }
        #expect(!message.isEmpty)
    }

    @Test("every check records the last-check timestamp")
    func checkRecordsTimestamp() async {
        let (store, _, _, defaults) = makeStore()
        #expect(defaults.double(forKey: UpdateStore.lastCheckKey) == 0)
        await store.checkNow()
        #expect(defaults.double(forKey: UpdateStore.lastCheckKey) > 0)
    }

    // MARK: - Auto-check throttle

    @Test("auto-check runs when no check was ever recorded")
    func autoCheckRunsWhenNeverChecked() async {
        let (store, checker, _, _) = makeStore()
        let ran = await store.autoCheckIfDue()
        #expect(ran)
        #expect(checker.checkCallCount == 1)
    }

    @Test("auto-check is skipped inside the 24h window")
    func autoCheckThrottled() async {
        let (store, checker, _, defaults) = makeStore()
        defaults.set(Date().timeIntervalSince1970, forKey: UpdateStore.lastCheckKey)
        let ran = await store.autoCheckIfDue()
        #expect(!ran)
        #expect(checker.checkCallCount == 0)
    }

    @Test("auto-check runs again once 24h have elapsed")
    func autoCheckDueAfterInterval() async {
        let (store, checker, _, defaults) = makeStore()
        let stale = Date().addingTimeInterval(-UpdateStore.autoCheckInterval - 60)
        defaults.set(stale.timeIntervalSince1970, forKey: UpdateStore.lastCheckKey)
        let ran = await store.autoCheckIfDue()
        #expect(ran)
        #expect(checker.checkCallCount == 1)
    }

    @Test("a manual check bypasses the 24h throttle")
    func manualCheckBypassesThrottle() async {
        let (store, checker, _, defaults) = makeStore()
        defaults.set(Date().timeIntervalSince1970, forKey: UpdateStore.lastCheckKey)
        await store.checkNow()
        #expect(checker.checkCallCount == 1)
    }

    // MARK: - Install pipeline

    @Test("install is a no-op unless an update is available")
    func installRequiresAvailable() async {
        let (store, _, installer, _) = makeStore()
        await store.installAvailableUpdate()
        #expect(store.state == .idle)
        #expect(installer.downloadedURLs.isEmpty)
        #expect(installer.relaunchCallCount == 0)
    }

    @Test("happy path walks downloading -> installing -> relaunch")
    func installHappyPath() async {
        let (store, checker, installer, _) = makeStore()
        checker.stubbedInfo = sampleInfo
        await store.checkNow()

        var seen: [UpdateState] = []
        let cancellable = store.$state.sink { seen.append($0) }
        await store.installAvailableUpdate()
        cancellable.cancel()

        #expect(seen.contains(.downloading(nil)))
        #expect(seen.contains(.installing))
        #expect(installer.downloadedURLs == [sampleInfo.dmgURL])
        #expect(installer.installedDMGs == [URL(fileURLWithPath: "/tmp/mock-update.dmg")])
        #expect(installer.relaunchCallCount == 1)
    }

    @Test("download progress updates the downloading fraction")
    func downloadProgressPublishes() async {
        let (store, checker, installer, _) = makeStore()
        checker.stubbedInfo = sampleInfo
        installer.progressEvents = [0.25, 0.5]
        await store.checkNow()

        var seen: [UpdateState] = []
        let cancellable = store.$state.sink { seen.append($0) }
        await store.installAvailableUpdate()
        cancellable.cancel()

        #expect(seen.contains(.downloading(0.25)))
        #expect(seen.contains(.downloading(0.5)))
        #expect(installer.relaunchCallCount == 1)
    }

    @Test("a download failure lands in failed without installing or relaunching")
    func downloadFailure() async {
        let (store, checker, installer, _) = makeStore()
        checker.stubbedInfo = sampleInfo
        installer.stubbedDownloadError = UpdateInstallerError.downloadFailed("HTTP 500")
        await store.checkNow()
        await store.installAvailableUpdate()

        guard case .failed = store.state else {
            Issue.record("expected .failed, got \(store.state)")
            return
        }
        #expect(installer.installedDMGs.isEmpty)
        #expect(installer.relaunchCallCount == 0)
    }

    @Test("an install failure lands in failed without relaunching")
    func installFailure() async {
        let (store, checker, installer, _) = makeStore()
        checker.stubbedInfo = sampleInfo
        installer.stubbedInstallError = UpdateInstallerError.appNotFoundInDMG
        await store.checkNow()
        await store.installAvailableUpdate()

        guard case .failed = store.state else {
            Issue.record("expected .failed, got \(store.state)")
            return
        }
        #expect(installer.relaunchCallCount == 0)
    }

    @Test("a check never stomps an install in flight")
    func checkDuringInstallIsIgnored() async {
        let (store, checker, installer, _) = makeStore()
        checker.stubbedInfo = sampleInfo
        await store.checkNow()

        installer.holdDownload = true
        let installTask = Task { await store.installAvailableUpdate() }
        // Spin (bounded) until the pipeline reaches the downloading phase.
        for _ in 0..<10_000 where store.state != .downloading(nil) { await Task.yield() }
        #expect(store.state == .downloading(nil))

        await store.checkNow()
        #expect(store.state == .downloading(nil))
        #expect(checker.checkCallCount == 1)

        installer.holdDownload = false
        await installTask.value
        #expect(installer.relaunchCallCount == 1)
    }
}
