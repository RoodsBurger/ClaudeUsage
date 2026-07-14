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
        "warningThreshold", "criticalThreshold", "showCostEstimate",
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
        #expect(store.showCostEstimate == false)
    }

    @Test("showCostEstimate persists to UserDefaults")
    func showCostEstimatePersists() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        #expect(store.showCostEstimate == false)
        store.showCostEstimate = true
        #expect(UserDefaults.standard.bool(forKey: "showCostEstimate") == true)
        // A fresh store re-reads the persisted value.
        #expect(DisplaySettingsStore().showCostEstimate == true)
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

    // MARK: - Empty pins persistence

    @Test("an emptied pinned list persists and round-trips (icon-only menu bar)")
    func emptyPinsRoundTrip() {
        clean(); defer { clean() }
        let first = DisplaySettingsStore()
        first.menuBarConfig.pinned = []
        let second = DisplaySettingsStore()
        #expect(second.menuBarConfig.pinned.isEmpty)
    }

    // MARK: - Enterprise first-run defaults

    @Test("fresh install + enterprise plan seeds enterprise defaults and persists them")
    func enterpriseFirstRunSeedsDefaults() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.applyEnterpriseDefaultsIfFirstRun(planType: .enterprise)
        #expect(store.menuBarConfig == .enterpriseDefault)
        #expect(store.popoverConfig == .enterpriseDefault)
        // Persisted: a fresh instance decodes the seeded configs.
        let second = DisplaySettingsStore()
        #expect(second.menuBarConfig == .enterpriseDefault)
        #expect(second.popoverConfig == .enterpriseDefault)
    }

    @Test("non-enterprise plans never seed or save anything")
    func nonEnterprisePlansAreNoOps() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        for plan in [PlanType.pro, .max, .team, .free, .unknown] {
            store.applyEnterpriseDefaultsIfFirstRun(planType: plan)
        }
        #expect(store.menuBarConfig == MenuBarConfig())
        #expect(store.popoverConfig == PopoverConfig())
        #expect(UserDefaults.standard.data(forKey: "menuBarConfig") == nil)
        #expect(UserDefaults.standard.data(forKey: "popoverConfig") == nil)
    }

    @Test("configs saved before the plan resolved are never migrated")
    func savedConfigsAreNeverMigrated() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        // User edits while the plan is still unknown - both configs save.
        store.menuBarConfig.separator = "|"
        store.popoverConfig.showPacing = false

        store.applyEnterpriseDefaultsIfFirstRun(planType: .enterprise)
        #expect(store.menuBarConfig.separator == "|")
        #expect(store.menuBarConfig.pinned == MenuBarConfig().pinned)
        #expect(store.popoverConfig.showPacing == false)
        #expect(store.popoverConfig.hiddenMetrics.isEmpty)
    }

    @Test("each config is checked independently - only the never-saved one is seeded")
    func partialSaveSeedsOnlyMissingConfig() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.menuBarConfig.separator = "|" // menu bar saved, popover untouched

        store.applyEnterpriseDefaultsIfFirstRun(planType: .enterprise)
        #expect(store.menuBarConfig.separator == "|")
        #expect(store.menuBarConfig.pinned == MenuBarConfig().pinned)
        #expect(store.popoverConfig == .enterpriseDefault)
    }

    @Test("seeding is one-shot: later user edits survive a second plan resolution")
    func seedingIsOneShot() {
        clean(); defer { clean() }
        let store = DisplaySettingsStore()
        store.applyEnterpriseDefaultsIfFirstRun(planType: .enterprise)
        store.menuBarConfig.pinned = [.init(id: .fiveHour)]

        store.applyEnterpriseDefaultsIfFirstRun(planType: .enterprise)
        #expect(store.menuBarConfig.pinned == [.init(id: .fiveHour)])
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
