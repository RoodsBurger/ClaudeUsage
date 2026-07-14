import Testing
import SwiftUI

@Suite("Semantic Colors")
struct SemanticColorTests {

    // MARK: - RiskZone tests

    @Test("RiskZone has 3 cases")
    func riskZoneHasThreeCases() {
        #expect(RiskZone.allCases.count == 3)
    }

    @Test("RiskZone.ok has the pastel green color")
    func riskZoneOkIsGreen() {
        #expect(RiskZone.ok.color == DS.Pastel.green)
    }

    @Test("RiskZone.warning has the pastel amber color")
    func riskZoneWarningIsOrange() {
        #expect(RiskZone.warning.color == DS.Pastel.amber)
    }

    @Test("RiskZone.critical has the pastel coral color")
    func riskZoneCriticalIsRed() {
        #expect(RiskZone.critical.color == DS.Pastel.coral)
    }

    @Test("RiskZone.ok has the pastel green NSColor")
    func riskZoneOkNSColorIsSystemGreen() {
        #expect(RiskZone.ok.nsColor == DS.Pastel.NS.green)
    }

    @Test("RiskZone.warning has the pastel amber NSColor")
    func riskZoneWarningNSColorIsSystemOrange() {
        #expect(RiskZone.warning.nsColor == DS.Pastel.NS.amber)
    }

    @Test("RiskZone.critical has the pastel coral NSColor")
    func riskZoneCriticalNSColorIsSystemRed() {
        #expect(RiskZone.critical.nsColor == DS.Pastel.NS.coral)
    }

    // MARK: - RiskZone.dotColor (menu bar)

    @Test("dotColor uses the plain pastel on a dark menu bar")
    func dotColorOnDarkBarUsesPastel() {
        #expect(RiskZone.ok.dotColor(menuBarIsDark: true) == DS.Pastel.NS.green)
        #expect(RiskZone.warning.dotColor(menuBarIsDark: true) == DS.Pastel.NS.amber)
        #expect(RiskZone.critical.dotColor(menuBarIsDark: true) == DS.Pastel.NS.coral)
    }

    @Test("dotColor uses the deepened variant on a light menu bar")
    func dotColorOnLightBarUsesDeepenedVariant() {
        #expect(RiskZone.ok.dotColor(menuBarIsDark: false) == DS.Pastel.NS.greenDeep)
        #expect(RiskZone.warning.dotColor(menuBarIsDark: false) == DS.Pastel.NS.amberDeep)
        #expect(RiskZone.critical.dotColor(menuBarIsDark: false) == DS.Pastel.NS.coralDeep)
    }

    // MARK: - RiskZone.forPercent tests

    @Test("forPercent returns ok when at 0% with default thresholds")
    func forPercentReturnsOkAt0Percent() {
        let thresholds = UsageThresholds.default
        #expect(RiskZone.forPercent(0, thresholds: thresholds) == .ok)
    }

    @Test("forPercent returns ok when below warning threshold")
    func forPercentReturnsOkBelowWarningThreshold() {
        let thresholds = UsageThresholds.default
        #expect(RiskZone.forPercent(59, thresholds: thresholds) == .ok)
    }

    @Test("forPercent returns warning when at warning threshold")
    func forPercentReturnsWarningAtWarningThreshold() {
        let thresholds = UsageThresholds.default
        #expect(RiskZone.forPercent(60, thresholds: thresholds) == .warning)
    }

    @Test("forPercent returns warning when between warning and critical")
    func forPercentReturnsWarningBetweenThresholds() {
        let thresholds = UsageThresholds.default
        #expect(RiskZone.forPercent(70, thresholds: thresholds) == .warning)
    }

    @Test("forPercent returns critical when at critical threshold")
    func forPercentReturnsCriticalAtCriticalThreshold() {
        let thresholds = UsageThresholds.default
        #expect(RiskZone.forPercent(85, thresholds: thresholds) == .critical)
    }

    @Test("forPercent returns critical when at 100%")
    func forPercentReturnsCriticalAt100Percent() {
        let thresholds = UsageThresholds.default
        #expect(RiskZone.forPercent(100, thresholds: thresholds) == .critical)
    }

    @Test("forPercent honors custom warning threshold")
    func forPercentHonorsCustomWarningThreshold() {
        let thresholds = UsageThresholds(warningPercent: 50, criticalPercent: 80)
        #expect(RiskZone.forPercent(49, thresholds: thresholds) == .ok)
        #expect(RiskZone.forPercent(50, thresholds: thresholds) == .warning)
        #expect(RiskZone.forPercent(79, thresholds: thresholds) == .warning)
    }

    @Test("forPercent honors custom critical threshold")
    func forPercentHonorsCustomCriticalThreshold() {
        let thresholds = UsageThresholds(warningPercent: 50, criticalPercent: 80)
        #expect(RiskZone.forPercent(79, thresholds: thresholds) == .warning)
        #expect(RiskZone.forPercent(80, thresholds: thresholds) == .critical)
    }

    // MARK: - PacingZone semantic colors

    @Test("PacingZone.chill has the pastel green semanticColor")
    func pacingZoneChillIsGreen() {
        #expect(PacingZone.chill.semanticColor == DS.Pastel.green)
    }

    @Test("PacingZone.onTrack has the pastel blue semanticColor")
    func pacingZoneOnTrackIsBlue() {
        #expect(PacingZone.onTrack.semanticColor == DS.Pastel.blue)
    }

    @Test("PacingZone.warning has the pastel amber semanticColor")
    func pacingZoneWarningIsOrange() {
        #expect(PacingZone.warning.semanticColor == DS.Pastel.amber)
    }

    @Test("PacingZone.hot has the pastel coral semanticColor")
    func pacingZoneHotIsRed() {
        #expect(PacingZone.hot.semanticColor == DS.Pastel.coral)
    }

    @Test("PacingZone.chill has the pastel green semanticNSColor")
    func pacingZoneChillNSColorIsSystemGreen() {
        #expect(PacingZone.chill.semanticNSColor == DS.Pastel.NS.green)
    }

    @Test("PacingZone.onTrack has the pastel blue semanticNSColor")
    func pacingZoneOnTrackNSColorIsSystemBlue() {
        #expect(PacingZone.onTrack.semanticNSColor == DS.Pastel.NS.blue)
    }

    @Test("PacingZone.warning has the pastel amber semanticNSColor")
    func pacingZoneWarningNSColorIsSystemOrange() {
        #expect(PacingZone.warning.semanticNSColor == DS.Pastel.NS.amber)
    }

    @Test("PacingZone.hot has the pastel coral semanticNSColor")
    func pacingZoneHotNSColorIsSystemRed() {
        #expect(PacingZone.hot.semanticNSColor == DS.Pastel.NS.coral)
    }

    // MARK: - PacingZone.dotColor (menu bar)

    @Test("PacingZone dotColor uses the plain pastel on a dark menu bar")
    func pacingDotColorOnDarkBarUsesPastel() {
        #expect(PacingZone.chill.dotColor(menuBarIsDark: true) == DS.Pastel.NS.green)
        #expect(PacingZone.onTrack.dotColor(menuBarIsDark: true) == DS.Pastel.NS.blue)
        #expect(PacingZone.warning.dotColor(menuBarIsDark: true) == DS.Pastel.NS.amber)
        #expect(PacingZone.hot.dotColor(menuBarIsDark: true) == DS.Pastel.NS.coral)
    }

    @Test("PacingZone dotColor uses the deepened variant on a light menu bar")
    func pacingDotColorOnLightBarUsesDeepenedVariant() {
        #expect(PacingZone.chill.dotColor(menuBarIsDark: false) == DS.Pastel.NS.greenDeep)
        #expect(PacingZone.onTrack.dotColor(menuBarIsDark: false) == DS.Pastel.NS.blueDeep)
        #expect(PacingZone.warning.dotColor(menuBarIsDark: false) == DS.Pastel.NS.amberDeep)
        #expect(PacingZone.hot.dotColor(menuBarIsDark: false) == DS.Pastel.NS.coralDeep)
    }
}
