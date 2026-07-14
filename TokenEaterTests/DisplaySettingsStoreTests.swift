import Testing
import Foundation
import Combine

@Suite("DisplaySettingsStore", .serialized)
@MainActor
struct DisplaySettingsStoreTests {

    private let displayKeys = [
        "showMenuBar", "launchInBackground", "pinnedMetrics", "resetDisplayFormat",
        "smartColorEnabled", "smartColorProfile",
        "sessionPacingDisplayMode", "weeklyPacingDisplayMode",
        "menuBarConfig", "popoverConfig",
        "warningThreshold", "criticalThreshold",
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
        #expect(store.sessionPacingDisplayMode == .dotDelta)
        #expect(store.weeklyPacingDisplayMode == .dotDelta)
        #expect(store.warningThreshold == 60)
        #expect(store.criticalThreshold == 85)
        #expect(store.thresholds == UsageThresholds(warningPercent: 60, criticalPercent: 85))
        #expect(store.menuBarConfig == MenuBarConfig())
        #expect(store.popoverConfig == PopoverConfig())
    }

    @Test("changing popoverConfig persists to UserDefaults as JSON")
    func popoverConfigPersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.popoverConfig.showSpend = false
        store.popoverConfig.hiddenMetrics = [.design]

        let data = UserDefaults.standard.data(forKey: "popoverConfig")
        #expect(data != nil)
        let decoded = data.flatMap { try? JSONDecoder().decode(PopoverConfig.self, from: $0) }
        #expect(decoded?.showSpend == false)
        #expect(decoded?.hiddenMetrics == [.design])
    }

    @Test("popoverConfig round-trips across store instances")
    func popoverConfigRoundTrips() {
        clean(); defer { clean() }
        let first = DisplaySettingsStore()
        first.popoverConfig = PopoverConfig(
            metricOrder: [.sevenDay, .fiveHour, .sonnet, .opus, .cowork, .fable, .design],
            hiddenMetrics: [.opus, .cowork],
            showPacing: false,
            showSpend: false,
            showTimestamp: false
        )

        let second = DisplaySettingsStore()
        #expect(second.popoverConfig == first.popoverConfig)
    }

    @Test("corrupted popoverConfig data falls back to defaults")
    func popoverConfigDecodeFailureFallsBackToDefaults() {
        clean(); defer { clean() }
        UserDefaults.standard.set(Data("not json".utf8), forKey: "popoverConfig")
        let store = DisplaySettingsStore()
        #expect(store.popoverConfig == PopoverConfig())
    }

    @Test("changing menuBarConfig persists to UserDefaults as JSON")
    func menuBarConfigPersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.menuBarConfig.colorMode = .monochrome
        store.menuBarConfig.rotateSeconds = 9

        let data = UserDefaults.standard.data(forKey: "menuBarConfig")
        #expect(data != nil)
        let decoded = data.flatMap { try? JSONDecoder().decode(MenuBarConfig.self, from: $0) }
        #expect(decoded?.colorMode == .monochrome)
        #expect(decoded?.rotateSeconds == 9)
    }

    @Test("menuBarConfig round-trips across store instances")
    func menuBarConfigRoundTrips() {
        clean(); defer { clean() }
        let first = DisplaySettingsStore()
        first.menuBarConfig = MenuBarConfig(
            pinned: [.init(id: .sonnet, prefix: .symbol, value: .percentRemaining, showCountdown: true)],
            displayMode: .highestRisk,
            rotateSeconds: 20,
            colorMode: .monochrome,
            showIcon: false,
            separator: "|",
            fixedWidth: true
        )

        let second = DisplaySettingsStore()
        #expect(second.menuBarConfig == first.menuBarConfig)
    }

    @Test("corrupted menuBarConfig data falls back to defaults")
    func menuBarConfigDecodeFailureFallsBackToDefaults() {
        clean(); defer { clean() }
        UserDefaults.standard.set(Data("not json".utf8), forKey: "menuBarConfig")
        let store = DisplaySettingsStore()
        #expect(store.menuBarConfig == MenuBarConfig())
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

    @Test("child change relays objectWillChange to SettingsStore parent")
    func relaysToParent() {
        clean(); defer { clean() }
        let parent = SettingsStore(
            notificationService: MockNotificationService(),
            tokenProvider: MockTokenProvider()
        )
        var fired = false
        let c = parent.objectWillChange.sink { fired = true }
        parent.display.menuBarConfig.colorMode = .monochrome
        #expect(fired == true)
        _ = c
    }
}
