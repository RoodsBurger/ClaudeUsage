import Testing
import Foundation
import SwiftUI

@Suite("GaugeColorResolver")
struct GaugeColorResolverTests {

    private var thresholds: UsageThresholds { .default }

    // MARK: - mode decision

    @Test func smartEnabledWithWindowSelectsSmart() {
        // A positive window keeps smart even for metrics without a reset date
        // (e.g. Opus/Cowork): the smart path handles the missing reset internally.
        #expect(GaugeColorResolver.mode(smartColorEnabled: true, windowDuration: 5 * 3600) == .smart)
    }

    @Test func smartDisabledSelectsThreshold() {
        #expect(GaugeColorResolver.mode(smartColorEnabled: false, windowDuration: 5 * 3600) == .threshold)
    }

    @Test func smartEnabledButNoWindowSelectsThreshold() {
        // e.g. the Extra Credits pool has no window (windowDuration 0) -> threshold ladder.
        #expect(GaugeColorResolver.mode(smartColorEnabled: true, windowDuration: 0) == .threshold)
    }

    // MARK: - threshold mode equals the RiskZone ladder and ignores time inputs

    @Test func thresholdColorMatchesRiskZoneLadder() {
        let resolved = GaugeColorResolver.color(
            mode: .threshold,
            utilization: 95,
            resetDate: Date().addingTimeInterval(3600),
            windowDuration: 5 * 3600,
            thresholds: thresholds,
            pacingMargin: 10,
            profile: .default
        )
        let direct = RiskZone.forPercent(95, thresholds: thresholds).color
        #expect(resolved == direct)
    }

    @Test func thresholdZoneMatchesRiskZoneLadder() {
        let resolved = GaugeColorResolver.zone(
            mode: .threshold,
            utilization: 95,
            resetDate: nil,
            windowDuration: 0,
            thresholds: thresholds,
            pacingMargin: 10,
            profile: .default
        )
        #expect(resolved == .critical)
    }

    @Test func thresholdColorIgnoresResetDate() {
        let withReset = GaugeColorResolver.color(
            mode: .threshold,
            utilization: 50,
            resetDate: Date().addingTimeInterval(60),
            windowDuration: 5 * 3600,
            thresholds: thresholds,
            pacingMargin: 10,
            profile: .default
        )
        let withoutReset = GaugeColorResolver.color(
            mode: .threshold,
            utilization: 50,
            resetDate: nil,
            windowDuration: 5 * 3600,
            thresholds: thresholds,
            pacingMargin: 10,
            profile: .default
        )
        #expect(withReset == withoutReset)
    }

    // MARK: - smart mode matches SmartColor.risk -> riskZone for the same inputs

    @Test func smartColorMatchesRiskZone() {
        let now = Date()
        let reset = now.addingTimeInterval(2 * 3600)
        let resolved = GaugeColorResolver.color(
            mode: .smart,
            utilization: 80,
            resetDate: reset,
            windowDuration: 5 * 3600,
            thresholds: thresholds,
            pacingMargin: 10,
            now: now,
            profile: .default
        )
        let risk = SmartColor.risk(
            utilization: 80,
            resetDate: reset,
            windowDuration: 5 * 3600,
            pacingMargin: 10,
            now: now,
            profile: .default
        )
        let direct = SmartColor.riskZone(forRisk: risk, params: SmartColorProfile.default.parameters).color
        #expect(resolved == direct)
    }

    @Test func smartNSColorMatchesRiskZone() {
        let now = Date()
        let reset = now.addingTimeInterval(2 * 3600)
        let resolved = GaugeColorResolver.nsColor(
            mode: .smart,
            utilization: 80,
            resetDate: reset,
            windowDuration: 5 * 3600,
            thresholds: thresholds,
            pacingMargin: 10,
            now: now,
            profile: .default
        )
        let risk = SmartColor.risk(
            utilization: 80,
            resetDate: reset,
            windowDuration: 5 * 3600,
            pacingMargin: 10,
            now: now,
            profile: .default
        )
        let direct = SmartColor.riskZone(forRisk: risk, params: SmartColorProfile.default.parameters).nsColor
        #expect(resolved == direct)
    }
}
