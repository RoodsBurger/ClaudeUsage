import Testing
import Foundation
import Combine

@Suite("DisplaySettingsStore", .serialized)
@MainActor
struct DisplaySettingsStoreTests {

    private let displayKeys = [
        "showMenuBar", "launchInBackground", "pinnedMetrics", "resetDisplayFormat",
        "smartColorEnabled", "smartResetColor", "smartColorProfile",
        "menuBarStyle", "pacingShape", "sessionPacingDisplayMode", "weeklyPacingDisplayMode",
        "pacingDisplayMode", "resetTextColorHex", "sessionPeriodColorHex",
        "displaySonnet", "displayDesign", "showSessionReset",
        "warningThreshold", "criticalThreshold", "menuBarMonochrome",
    ]
    private func clean() { displayKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    @Test("defaults on a fresh install")
    func defaults() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        #expect(store.showMenuBar == true)
        #expect(store.launchInBackground == false)
        #expect(store.pinnedMetrics == [.fiveHour, .sevenDay])
        #expect(store.resetDisplayFormat == .relative)
        #expect(store.smartColorEnabled == true)
        #expect(store.smartColorProfile == .default)
        #expect(store.menuBarStyle == .classic)
        #expect(store.pacingShape == .circle)
        #expect(store.sessionPacingDisplayMode == .dotDelta)
        #expect(store.weeklyPacingDisplayMode == .dotDelta)
        #expect(store.resetTextColorHex == "")
        #expect(store.sessionPeriodColorHex == "")
        #expect(store.displaySonnet == false)
        #expect(store.displayDesign == false)
        #expect(store.warningThreshold == 60)
        #expect(store.criticalThreshold == 85)
        #expect(store.menuBarMonochrome == false)
        #expect(store.thresholds == UsageThresholds(warningPercent: 60, criticalPercent: 85))
    }

    @Test("changing menuBarStyle persists to UserDefaults")
    func menuBarStylePersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.menuBarStyle = .badge
        #expect(UserDefaults.standard.string(forKey: "menuBarStyle") == MenuBarStyle.badge.rawValue)
    }

    @Test("changing pinnedMetrics persists the raw value array")
    func pinnedMetricsPersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.pinnedMetrics = [.fiveHour, .sevenDay, .sessionPacing]
        let saved = Set(UserDefaults.standard.stringArray(forKey: "pinnedMetrics") ?? [])
        #expect(saved == ["fiveHour", "sevenDay", "sessionPacing"])
    }

    @Test("smartColorEnabled persists to UserDefaults")
    func smartColorEnabledPersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.smartColorEnabled = false
        #expect(UserDefaults.standard.object(forKey: "smartColorEnabled") as? Bool == false)
    }

    @Test("smartColorProfile persists to UserDefaults")
    func smartColorProfilePersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.smartColorProfile = .vigilant
        #expect(UserDefaults.standard.string(forKey: "smartColorProfile") == SmartColorProfile.vigilant.rawValue)
    }

    // MARK: - Thresholds

    @Test("changing warningThreshold persists to UserDefaults")
    func warningThresholdPersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.warningThreshold = 70
        #expect(UserDefaults.standard.integer(forKey: "warningThreshold") == 70)
    }

    @Test("changing criticalThreshold persists to UserDefaults")
    func criticalThresholdPersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.criticalThreshold = 90
        #expect(UserDefaults.standard.integer(forKey: "criticalThreshold") == 90)
    }

    @Test("thresholds round-trips warning/critical through UserDefaults across store instances")
    func thresholdsRoundTrip() {
        clean(); defer { clean() }
        let first = DisplaySettingsStore()
        first.warningThreshold = 65
        first.criticalThreshold = 92

        let second = DisplaySettingsStore()
        #expect(second.warningThreshold == 65)
        #expect(second.criticalThreshold == 92)
        #expect(second.thresholds == UsageThresholds(warningPercent: 65, criticalPercent: 92))
    }

    // MARK: - menuBarMonochrome

    @Test("menuBarMonochrome persists to UserDefaults")
    func menuBarMonochromePersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()

        store.menuBarMonochrome = true
        #expect(UserDefaults.standard.bool(forKey: "menuBarMonochrome") == true)

        store.menuBarMonochrome = false
        #expect(UserDefaults.standard.bool(forKey: "menuBarMonochrome") == false)
    }

    @Test("child change relays objectWillChange to SettingsStore parent")
    func relaysToParent() {
        clean(); defer { clean() }
        let parent = SettingsStore(
            notificationService: MockNotificationService(),
            tokenProvider: MockTokenProvider(),
            sharedFileService: MockSharedFileService()
        )
        var fired = false
        let c = parent.objectWillChange.sink { fired = true }
        parent.display.menuBarStyle = .badge
        #expect(fired == true)
        _ = c
    }
}
