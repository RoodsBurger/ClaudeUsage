import Testing
import Foundation
import UserNotifications

private let settingsKeys = [
    "showMenuBar", "launchInBackground", "pinnedMetrics",
    "hasCompletedOnboarding", "launchAtLoginEnabled", "refreshInterval",
    "proxyEnabled", "proxyHost", "proxyPort",
    "outageMonitoringEnabled", "statusPollInterval", "statusShowMenuBarBadge",
    "notifVendorDegraded", "notifVendorRestored"
]

private func cleanDefaults() {
    for key in settingsKeys {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

@Suite("SettingsStore", .serialized)
@MainActor
struct SettingsStoreTests {

    // MARK: - Helpers

    private func makeStore(
        tokenProvider: MockTokenProvider = MockTokenProvider()
    ) -> (SettingsStore, MockNotificationService, MockTokenProvider) {
        cleanDefaults()
        let notif = MockNotificationService()
        let store = SettingsStore(notificationService: notif, tokenProvider: tokenProvider)
        return (store, notif, tokenProvider)
    }

    // MARK: - Proxy Config

    @Test("proxyConfig reflects current values")
    func proxyConfigReflectsValues() {
        let (store, _, _) = makeStore()
        store.proxyEnabled = true
        store.proxyHost = "10.0.0.1"
        store.proxyPort = 8080

        let config = store.proxyConfig
        #expect(config.enabled == true)
        #expect(config.host == "10.0.0.1")
        #expect(config.port == 8080)
    }

    @Test("proxyConfig returns defaults on fresh store")
    func proxyConfigDefaults() {
        let (store, _, _) = makeStore()

        let config = store.proxyConfig
        #expect(config.enabled == false)
        #expect(config.host == "127.0.0.1")
        #expect(config.port == 1080)
    }

    // MARK: - Toggle Metric

    @Test("toggleMetric adds a metric not in the set")
    func toggleMetricAdds() {
        let (store, _, _) = makeStore()
        #expect(!store.pinnedMetrics.contains(.sonnet))

        store.toggleMetric(.sonnet)
        #expect(store.pinnedMetrics.contains(.sonnet))
    }

    @Test("toggleMetric removes metric when count > 1")
    func toggleMetricRemoves() {
        let (store, _, _) = makeStore()
        #expect(store.pinnedMetrics.count == 2)
        #expect(store.pinnedMetrics.contains(.fiveHour))

        store.toggleMetric(.fiveHour)
        #expect(!store.pinnedMetrics.contains(.fiveHour))
    }

    @Test("toggleMetric does not remove last metric")
    func toggleMetricKeepsLast() {
        let (store, _, _) = makeStore()
        store.pinnedMetrics = [.sonnet]
        #expect(store.pinnedMetrics.count == 1)

        store.toggleMetric(.sonnet)
        #expect(store.pinnedMetrics.contains(.sonnet))
        #expect(store.pinnedMetrics.count == 1)
    }

    @Test("toggleMetric works with .weeklyPacing")
    func toggleMetricWeeklyPacing() {
        let (store, _, _) = makeStore()
        #expect(!store.pinnedMetrics.contains(.weeklyPacing))

        store.toggleMetric(.weeklyPacing)
        #expect(store.pinnedMetrics.contains(.weeklyPacing))

        store.toggleMetric(.weeklyPacing)
        // Still has other metrics, so weeklyPacing should be removed
        #expect(!store.pinnedMetrics.contains(.weeklyPacing))
    }

    // MARK: - Credentials delegation

    @Test("credentialsTokenExists delegates to token provider")
    func credentialsTokenExistsDelegates() {
        let tp = MockTokenProvider()
        tp.token = "some-token"
        let (store, _, _) = makeStore(tokenProvider: tp)

        #expect(store.credentialsTokenExists() == true)
    }

    @Test("credentialsTokenExists returns false when no token")
    func credentialsTokenExistsFalseWhenNoToken() {
        let (store, _, _) = makeStore()

        #expect(store.credentialsTokenExists() == false)
    }

    // MARK: - Notification delegation

    @Test("requestNotificationPermission delegates to service")
    func requestNotificationPermissionDelegates() {
        let (store, notif, _) = makeStore()

        store.requestNotificationPermission()

        #expect(notif.permissionRequested == true)
    }

    @Test("sendTestNotification delegates to service")
    func sendTestNotificationDelegates() {
        let (store, notif, _) = makeStore()

        store.sendTestNotification()

        #expect(notif.testSent == true)
    }

    @Test("refreshNotificationStatus updates status from service")
    func refreshNotificationStatusUpdates() async {
        let (store, notif, _) = makeStore()
        notif.stubbedAuthStatus = .authorized

        await store.refreshNotificationStatus()

        #expect(store.notificationStatus == .authorized)
    }

    // MARK: - Persistence

    @Test("hasCompletedOnboarding persists to UserDefaults")
    func hasCompletedOnboardingPersists() {
        let (store, _, _) = makeStore()

        store.hasCompletedOnboarding = true
        #expect(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") == true)
    }

    @Test("pinnedMetrics persists to UserDefaults")
    func pinnedMetricsPersists() {
        let (store, _, _) = makeStore()

        store.pinnedMetrics = [.sonnet, .weeklyPacing]

        let saved = UserDefaults.standard.stringArray(forKey: "pinnedMetrics") ?? []
        #expect(saved.contains("sonnet"))
        #expect(saved.contains("weeklyPacing"))
    }

    // MARK: - Launch in background (#198)

    @Test("launchInBackground defaults to false")
    func launchInBackgroundDefaults() {
        let (store, _, _) = makeStore()
        #expect(store.launchInBackground == false)
    }

    @Test("launchInBackground persists to UserDefaults")
    func launchInBackgroundPersists() {
        let (store, _, _) = makeStore()
        store.launchInBackground = true
        #expect(UserDefaults.standard.object(forKey: "launchInBackground") as? Bool == true)
    }

    @Test("launchInBackground reads back on a fresh store instance")
    func launchInBackgroundReadsBack() {
        let (store, _, _) = makeStore()
        store.launchInBackground = true
        // A new store built against the same UserDefaults picks the value up
        // (makeStore would wipe it, so construct directly here).
        let fresh = SettingsStore(notificationService: MockNotificationService(), tokenProvider: MockTokenProvider())
        #expect(fresh.launchInBackground == true)
    }

    // MARK: - Service status settings

    @Test("service status settings default on, poll interval 300")
    func serviceStatusDefaults() {
        let (store, _, _) = makeStore()
        #expect(store.outageMonitoringEnabled == true)
        #expect(store.statusPollInterval == 300)
        #expect(store.statusShowMenuBarBadge == true)
        #expect(store.notifVendorDegraded == true)
        #expect(store.notifVendorRestored == true)
    }

    @Test("statusPollInterval persists across store instances")
    func statusPollIntervalPersists() {
        let (store, notif, tp) = makeStore()
        store.statusPollInterval = 900
        let reloaded = SettingsStore(notificationService: notif, tokenProvider: tp)
        #expect(reloaded.statusPollInterval == 900)
    }

}
