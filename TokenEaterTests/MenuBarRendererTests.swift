import Testing
import Foundation
import AppKit

/// Regression coverage for `MenuBarRenderer.gaugeColor`'s smart-mode path,
/// expressed against validated (u, e) scenarios from `SmartColorTests` so the
/// expected zone is grounded in the risk model rather than hand-picked.
/// `gaugeColor` takes its inputs directly (no `RenderData`), so this suite is
/// untouched by the menu-bar engine rewrite.
@Suite("MenuBarRenderer.gaugeColor smart-mode regression")
struct MenuBarRendererSmartRegressionTests {

    private let thresholds = UsageThresholds.default // warning: 60, critical: 85
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let window: TimeInterval = 5 * 3600 // 300 min

    private func reset(_ minutesAway: Double) -> Date {
        now.addingTimeInterval(minutesAway * 60)
    }

    private func color(_ utilization: Int, minutesRemaining: Double) -> NSColor {
        MenuBarRenderer.gaugeColor(
            pct: utilization,
            resetDate: reset(minutesRemaining),
            windowDuration: window,
            monochrome: false,
            smartEnabled: true,
            thresholds: thresholds,
            pacingMargin: 10,
            smartColorProfile: .balanced,
            now: now
        )
    }

    @Test("100% utilization is always critical, regardless of time remaining")
    func hardCapAlwaysCritical() {
        #expect(color(100, minutesRemaining: 20) == RiskZone.critical.nsColor)
        #expect(color(100, minutesRemaining: 240) == RiskZone.critical.nsColor)
    }

    @Test("95% with 5 min remaining is critical (matches SmartColorTests u=0.95 e=0.983 -> hot)")
    func criticalLowTime() {
        #expect(color(95, minutesRemaining: 5) == RiskZone.critical.nsColor)
    }

    @Test("low utilization near reset stays ok")
    func lowUtilizationStaysOk() {
        #expect(color(30, minutesRemaining: 15) == RiskZone.ok.nsColor)
    }

    @Test("80% used at 50% elapsed is critical (matches SmartColorTests u=0.80 e=0.50 -> hot)")
    func highUtilizationAheadOfPaceEscalates() {
        // e=0.50 on a 300min window -> 150min remaining.
        #expect(color(80, minutesRemaining: 150) == RiskZone.critical.nsColor)
    }

    @Test("72% with calm pacing stays ok (matches SmartColorTests u=0.72 e=0.84 -> chill)")
    func highAbsoluteCalmPacingStaysOk() {
        // e=0.84 on a 300min window -> 48min remaining.
        #expect(color(72, minutesRemaining: 48) == RiskZone.ok.nsColor)
    }
}

/// Covers the windowless-metric colouring rule that keeps Extra Credits in
/// agreement across the menu bar, popover, and dashboard: Smart Color
/// is time-aware, so a metric with no reset window must use the static
/// threshold ladder instead of the profile-based absolute-risk colour.
/// `gaugeColor` is untouched by the engine rewrite, so this suite is too.
@Suite("MenuBarRenderer.gaugeColor (windowless fallback)")
struct MenuBarGaugeColorTests {

    private let thresholds = UsageThresholds.default // warning 60, critical 85
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("windowless metric uses the threshold ladder even when Smart Color is on")
    func windowlessUsesThresholds() {
        let observed = MenuBarRenderer.gaugeColor(
            pct: 67, resetDate: nil, windowDuration: 0,
            monochrome: false, smartEnabled: true,
            thresholds: thresholds,
            pacingMargin: 10, smartColorProfile: .balanced, now: now
        )
        #expect(observed == RiskZone.forPercent(67, thresholds: thresholds).nsColor)
        let risk = SmartColor.risk(
            utilization: 67, resetDate: nil, windowDuration: 0,
            pacingMargin: 10, now: now, profile: .balanced
        )
        let smartWindowless = SmartColor.riskZone(forRisk: risk, params: SmartColorProfile.balanced.parameters).nsColor
        #expect(observed != smartWindowless)
    }

    @Test("windowed metric still uses Smart Color when enabled")
    func windowedUsesSmart() {
        let reset = now.addingTimeInterval(180 * 60) // 3h left on a 5h window
        let observed = MenuBarRenderer.gaugeColor(
            pct: 80, resetDate: reset, windowDuration: 5 * 3600,
            monochrome: false, smartEnabled: true,
            thresholds: thresholds,
            pacingMargin: 10, smartColorProfile: .balanced, now: now
        )
        let risk = SmartColor.risk(
            utilization: 80, resetDate: reset, windowDuration: 5 * 3600,
            pacingMargin: 10, now: now, profile: .balanced
        )
        let expectedSmart = SmartColor.riskZone(forRisk: risk, params: SmartColorProfile.balanced.parameters).nsColor
        #expect(observed == expectedSmart)
    }

    @Test("smart disabled always uses the threshold ladder")
    func smartDisabledUsesThresholds() {
        let reset = now.addingTimeInterval(180 * 60)
        let observed = MenuBarRenderer.gaugeColor(
            pct: 80, resetDate: reset, windowDuration: 5 * 3600,
            monochrome: false, smartEnabled: false,
            thresholds: thresholds,
            pacingMargin: 10, smartColorProfile: .balanced, now: now
        )
        #expect(observed == RiskZone.forPercent(80, thresholds: thresholds).nsColor)
    }

    @Test("monochrome wins over everything")
    func monochromeWins() {
        let observed = MenuBarRenderer.gaugeColor(
            pct: 67, resetDate: nil, windowDuration: 0,
            monochrome: true, smartEnabled: true,
            thresholds: thresholds,
            pacingMargin: 10, smartColorProfile: .balanced, now: now
        )
        #expect(observed == NSColor.labelColor)
    }
}

/// Shared factory for `MenuBarRenderer.RenderData` in the buildLine/imaging
/// suites below - a fully-populated, deterministic baseline (threshold mode,
/// not smart) with every override a test needs exposed as a parameter.
private func makeRenderData(
    pinned: [PinnedMetricConfig] = [.init(id: .fiveHour, prefix: .none), .init(id: .sevenDay, prefix: .none)],
    displayMode: MenuBarDisplayMode = .all,
    rotateSeconds: Int = 5,
    colorMode: MenuBarColorMode = .risk,
    showIcon: Bool = true,
    separator: String = "|",
    fixedWidth: Bool = false,
    rotateIndex: Int = 0,
    hasConfig: Bool = true,
    hasError: Bool = false,
    smartColorEnabled: Bool = false,
    fiveHourPct: Int = 30,
    sevenDayPct: Int = 30,
    sonnetPct: Int = 30,
    designPct: Int = 30,
    fablePct: Int = 30,
    extraCreditsPct: Int = 30,
    hasFiveHourBucket: Bool = true,
    hasWeeklyPacing: Bool = true,
    hasSessionPacing: Bool = true,
    hasDesign: Bool = true,
    hasFable: Bool = true,
    hasExtraCredits: Bool = true,
    resetDisplayFormat: ResetDisplayFormat = .relative,
    fiveHourReset: String = "1h39",
    fiveHourResetAbsolute: String = "20:30",
    sessionPacingDelta: Int = 0,
    sessionPacingZone: PacingZone = .onTrack,
    weeklyPacingDelta: Int = 0,
    weeklyPacingZone: PacingZone = .onTrack,
    extraCreditsUsedMinorUnits: Double = 4200,
    extraCreditsLimitMinorUnits: Double = 500_000,
    extraCreditsCurrency: String = "USD",
    isEnterprise: Bool = false,
    outageActive: Bool = false,
    outageHealth: VendorHealth = .healthy,
    nextPollSeconds: Int? = nil,
    menuBarIsDark: Bool = true
) -> MenuBarRenderer.RenderData {
    MenuBarRenderer.RenderData(
        menuBarConfig: MenuBarConfig(
            pinned: pinned,
            displayMode: displayMode,
            rotateSeconds: rotateSeconds,
            colorMode: colorMode,
            showIcon: showIcon,
            separator: separator,
            fixedWidth: fixedWidth
        ),
        rotateIndex: rotateIndex,
        hasConfig: hasConfig,
        hasError: hasError,
        thresholds: .default,
        smartColorEnabled: smartColorEnabled,
        smartColorProfile: .balanced,
        pacingMargin: 10,
        fiveHourPct: fiveHourPct,
        sevenDayPct: sevenDayPct,
        sonnetPct: sonnetPct,
        designPct: designPct,
        fablePct: fablePct,
        extraCreditsPct: extraCreditsPct,
        hasFiveHourBucket: hasFiveHourBucket,
        hasWeeklyPacing: hasWeeklyPacing,
        hasSessionPacing: hasSessionPacing,
        hasDesign: hasDesign,
        hasFable: hasFable,
        hasExtraCredits: hasExtraCredits,
        fiveHourResetDate: nil,
        sevenDayResetDate: nil,
        sonnetResetDate: nil,
        designResetDate: nil,
        fableResetDate: nil,
        resetDisplayFormat: resetDisplayFormat,
        fiveHourReset: fiveHourReset,
        sevenDayReset: "3d 14h",
        sonnetReset: "3d 14h",
        designReset: "3d 14h",
        fableReset: "3d 14h",
        fiveHourResetAbsolute: fiveHourResetAbsolute,
        sevenDayResetAbsolute: "Thu 19:00",
        sonnetResetAbsolute: "Thu 19:00",
        designResetAbsolute: "Thu 19:00",
        fableResetAbsolute: "Thu 19:00",
        sessionPacingDelta: sessionPacingDelta,
        sessionPacingZone: sessionPacingZone,
        weeklyPacingDelta: weeklyPacingDelta,
        weeklyPacingZone: weeklyPacingZone,
        sessionPacingDisplayMode: .dotDelta,
        weeklyPacingDisplayMode: .dotDelta,
        extraCreditsUsedMinorUnits: extraCreditsUsedMinorUnits,
        extraCreditsLimitMinorUnits: extraCreditsLimitMinorUnits,
        extraCreditsCurrency: extraCreditsCurrency,
        isEnterprise: isEnterprise,
        outageActive: outageActive,
        outageHealth: outageHealth,
        nextPollSeconds: nextPollSeconds,
        menuBarIsDark: menuBarIsDark
    )
}

@Suite("MenuBarRenderer.buildLine")
struct MenuBarBuildLineTests {

    // These ordering/separator/selection tests are about pin logic, not the
    // risk dot, so they force `.monochrome` to keep `line.string` a plain
    // "label value" string - the dot's own presence/absence is covered by
    // the dedicated dot-glyph tests below.

    @Test("all mode renders every visible pin in pinned order, separator-joined")
    func allModeOrderAndSeparator() {
        let data = makeRenderData(
            pinned: [
                .init(id: .fiveHour, prefix: .none, value: .percentUsed),
                .init(id: .sevenDay, prefix: .none, value: .percentUsed),
            ],
            displayMode: .all,
            colorMode: .monochrome,
            separator: "|",
            fiveHourPct: 12,
            sevenDayPct: 77
        )
        let line = MenuBarRenderer.buildLine(data: data)
        #expect(line.string == "12% | 77%")
    }

    @Test("all mode respects a custom separator")
    func allModeCustomSeparator() {
        let data = makeRenderData(
            pinned: [
                .init(id: .fiveHour, prefix: .none, value: .percentUsed),
                .init(id: .sevenDay, prefix: .none, value: .percentUsed),
            ],
            displayMode: .all,
            colorMode: .monochrome,
            separator: "\u{2022}",
            fiveHourPct: 5,
            sevenDayPct: 6
        )
        let line = MenuBarRenderer.buildLine(data: data)
        #expect(line.string == "5% \u{2022} 6%")
    }

    @Test("highestRisk picks the pin whose zone is riskiest")
    func highestRiskPicksMaxZone() {
        // Threshold mode (smartColorEnabled: false): warning 60, critical 85.
        // fiveHour=30 -> ok, sevenDay=90 -> critical. sevenDay must win.
        let data = makeRenderData(
            pinned: [
                .init(id: .fiveHour, prefix: .none, value: .percentUsed),
                .init(id: .sevenDay, prefix: .none, value: .percentUsed),
            ],
            displayMode: .highestRisk,
            colorMode: .monochrome,
            fiveHourPct: 30,
            sevenDayPct: 90
        )
        let line = MenuBarRenderer.buildLine(data: data)
        #expect(line.string == "90%")
    }

    @Test("highestRisk ties keep pinned order (first pin wins)")
    func highestRiskTiesKeepPinnedOrder() {
        let data = makeRenderData(
            pinned: [
                .init(id: .sevenDay, prefix: .none, value: .percentUsed),
                .init(id: .fiveHour, prefix: .none, value: .percentUsed),
            ],
            displayMode: .highestRisk,
            colorMode: .monochrome,
            fiveHourPct: 90,
            sevenDayPct: 90
        )
        let line = MenuBarRenderer.buildLine(data: data)
        // Both are critical (90% >= 85 threshold); sevenDay is first in `pinned`.
        #expect(line.string == "90%")
        // Disambiguate which metric actually rendered via distinct percentages.
        let reordered = makeRenderData(
            pinned: [
                .init(id: .sevenDay, prefix: .none, value: .percentUsed),
                .init(id: .fiveHour, prefix: .none, value: .percentUsed),
            ],
            displayMode: .highestRisk,
            colorMode: .monochrome,
            fiveHourPct: 99,
            sevenDayPct: 86
        )
        // Both still critical (>= 85), tie keeps pinned order -> sevenDay (86%), not fiveHour (99%).
        #expect(MenuBarRenderer.buildLine(data: reordered).string == "86%")
    }

    @Test("rotate wraps the index by the visible pin count")
    func rotateWrapsByIndex() {
        let pins: [PinnedMetricConfig] = [
            .init(id: .fiveHour, prefix: .none, value: .percentUsed),
            .init(id: .sevenDay, prefix: .none, value: .percentUsed),
            .init(id: .sonnet, prefix: .none, value: .percentUsed),
        ]
        let values = [0: "11%", 1: "22%", 2: "33%", 3: "11%", 4: "22%"]
        for (index, expected) in values {
            let data = makeRenderData(
                pinned: pins,
                displayMode: .rotate,
                colorMode: .monochrome,
                rotateIndex: index,
                fiveHourPct: 11, sevenDayPct: 22, sonnetPct: 33
            )
            #expect(MenuBarRenderer.buildLine(data: data).string == expected, "index \(index)")
        }
    }

    @Test("dollars value style renders only for extraCredits")
    func dollarsOnlyForExtraCredits() {
        let ecData = makeRenderData(
            pinned: [.init(id: .extraCredits, prefix: .none, value: .dollars)],
            displayMode: .all,
            colorMode: .monochrome,
            extraCreditsUsedMinorUnits: 4200,
            extraCreditsCurrency: "USD"
        )
        let ecLine = MenuBarRenderer.buildLine(data: ecData).string
        #expect(ecLine.hasPrefix("$"))
        #expect(!ecLine.contains("%"))

        // A non-extraCredits pin with `.dollars` set (never offered by the UI,
        // but decodable) falls back to a plain percentage instead.
        let fiveHourData = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .dollars)],
            displayMode: .all,
            colorMode: .monochrome,
            fiveHourPct: 42
        )
        #expect(MenuBarRenderer.buildLine(data: fiveHourData).string == "42%")
    }

    @Test("percentRemaining is 100 minus the used percentage")
    func percentRemaining() {
        let data = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentRemaining)],
            displayMode: .all,
            colorMode: .monochrome,
            fiveHourPct: 30
        )
        #expect(MenuBarRenderer.buildLine(data: data).string == "70%")
    }

    @Test("percentRemaining clamps at 0 when used exceeds 100")
    func percentRemainingClamps() {
        let data = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentRemaining)],
            displayMode: .all,
            colorMode: .monochrome,
            fiveHourPct: 140
        )
        #expect(MenuBarRenderer.buildLine(data: data).string == "0%")
    }

    @Test("monochrome ignores risk zones - no zone color and no dot renders, text uses the adaptive color")
    func monochromeIgnoresZones() {
        let data = makeRenderData(
            pinned: [
                .init(id: .fiveHour, prefix: .none, value: .percentUsed),
                .init(id: .sevenDay, prefix: .none, value: .percentUsed),
            ],
            displayMode: .all,
            colorMode: .monochrome,
            fiveHourPct: 10,   // would be ok (green) in risk mode
            sevenDayPct: 95    // would be critical (red) in risk mode
        )
        let line = MenuBarRenderer.buildLine(data: data)
        var colors = Set<NSColor>()
        line.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: line.length)) { value, _, _ in
            if let color = value as? NSColor { colors.insert(color) }
        }
        #expect(!colors.contains(RiskZone.ok.nsColor))
        #expect(!colors.contains(RiskZone.critical.nsColor))
        // Every span (value, separator) resolves to the single adaptive
        // text color; `menuBarIsDark` defaults to true in this factory.
        #expect(colors == [DS.Pastel.NS.textOnDark])
        // No risk dot glyph in monochrome mode.
        #expect(!line.string.contains("\u{25CF}"))
    }

    @Test("risk color mode paints a zone-colored dot per metric; value text itself stays adaptive")
    func riskModeUsesZoneColors() {
        let data = makeRenderData(
            pinned: [
                .init(id: .fiveHour, prefix: .none, value: .percentUsed),
                .init(id: .sevenDay, prefix: .none, value: .percentUsed),
            ],
            displayMode: .all,
            colorMode: .risk,
            fiveHourPct: 10,   // ok
            sevenDayPct: 95    // critical
        )
        let line = MenuBarRenderer.buildLine(data: data)
        var colors = Set<NSColor>()
        line.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: line.length)) { value, _, _ in
            if let color = value as? NSColor { colors.insert(color) }
        }
        #expect(colors.contains(RiskZone.ok.dotColor(menuBarIsDark: true)))
        #expect(colors.contains(RiskZone.critical.dotColor(menuBarIsDark: true)))
        // The percentage text, separator, and any label all resolve to the
        // single adaptive text color - only the dot varies by zone. Exactly
        // 3 distinct colors total: the 2 zone dots + the 1 adaptive text color.
        #expect(colors.contains(DS.Pastel.NS.textOnDark))
        #expect(colors.count == 3)
    }

    @Test(".risk color mode prepends a small risk dot before each metric")
    func riskModeEmitsDotGlyph() {
        let data = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentUsed)],
            displayMode: .all,
            colorMode: .risk,
            fiveHourPct: 42
        )
        #expect(MenuBarRenderer.buildLine(data: data).string.contains("\u{25CF}"))
    }

    @Test(".monochrome color mode emits no risk dot")
    func monochromeEmitsNoDotGlyph() {
        let data = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentUsed)],
            displayMode: .all,
            colorMode: .monochrome,
            fiveHourPct: 42
        )
        #expect(!MenuBarRenderer.buildLine(data: data).string.contains("\u{25CF}"))
    }

    @Test("text color is adaptive: near-white on a dark menu bar, near-black on a light one")
    func adaptiveTextColorFollowsMenuBarAppearance() {
        func colors(_ line: NSAttributedString) -> Set<NSColor> {
            var result = Set<NSColor>()
            line.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: line.length)) { value, _, _ in
                if let color = value as? NSColor { result.insert(color) }
            }
            return result
        }
        let darkData = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentUsed)],
            colorMode: .monochrome,
            fiveHourPct: 42,
            menuBarIsDark: true
        )
        let lightData = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentUsed)],
            colorMode: .monochrome,
            fiveHourPct: 42,
            menuBarIsDark: false
        )
        #expect(colors(MenuBarRenderer.buildLine(data: darkData)) == [DS.Pastel.NS.textOnDark])
        #expect(colors(MenuBarRenderer.buildLine(data: lightData)) == [DS.Pastel.NS.textOnLight])
    }

    @Test("risk dot uses the deepened pastel variant on a light menu bar")
    func riskDotUsesDeepenedVariantOnLightBar() {
        let data = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentUsed)],
            displayMode: .all,
            colorMode: .risk,
            fiveHourPct: 95, // critical
            menuBarIsDark: false
        )
        var colors = Set<NSColor>()
        let line = MenuBarRenderer.buildLine(data: data)
        line.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: line.length)) { value, _, _ in
            if let color = value as? NSColor { colors.insert(color) }
        }
        #expect(colors.contains(RiskZone.critical.dotColor(menuBarIsDark: false)))
        #expect(!colors.contains(RiskZone.critical.dotColor(menuBarIsDark: true)))
    }

    @Test("no visible pins renders an empty line")
    func emptyWhenNothingVisible() {
        let data = makeRenderData(
            pinned: [.init(id: .design, prefix: .none)],
            hasDesign: false
        )
        #expect(MenuBarRenderer.buildLine(data: data).length == 0)
    }

    @Test("zero pins renders icon-only: empty line, template logo image, zero fixed width")
    func zeroPinsRendersIconOnly() {
        let data = makeRenderData(pinned: [], fixedWidth: true)
        #expect(MenuBarRenderer.buildLine(data: data).length == 0)
        #expect(MenuBarRenderer.fixedWidthMeasurement(data: data) == 0)
        // The imaging pipeline falls back to the template logo - the same
        // icon-only rendering as the unconfigured state, never blank.
        let image = MenuBarRenderer.renderUncached(data)
        #expect(image.isTemplate == true)
        #expect(image.size.width > 0)
    }

    @Test("zero pins renders the logo in every display mode")
    func zeroPinsLogoInEveryMode() {
        for mode in MenuBarDisplayMode.allCases {
            let data = makeRenderData(pinned: [], displayMode: mode)
            #expect(MenuBarRenderer.buildLine(data: data).length == 0, "\(mode)")
            #expect(MenuBarRenderer.renderUncached(data).isTemplate == true, "\(mode)")
        }
    }

    @Test("Extra Credits short label reads Org on enterprise, EC elsewhere")
    func enterpriseShortLabel() {
        let pin = PinnedMetricConfig(id: .extraCredits, prefix: .shortLabel, value: .percentUsed)
        let normal = makeRenderData(pinned: [pin], colorMode: .monochrome, isEnterprise: false)
        let enterprise = makeRenderData(pinned: [pin], colorMode: .monochrome, isEnterprise: true)
        #expect(MenuBarRenderer.buildLine(data: normal).string == "EC 30%")
        #expect(MenuBarRenderer.buildLine(data: enterprise).string == "Org 30%")
    }

    @Test("enterprise leaves every other pin's short label unchanged")
    func enterpriseLeavesOtherLabelsAlone() {
        let pins: [PinnedMetricConfig] = [
            .init(id: .fiveHour, prefix: .shortLabel, value: .percentUsed),
            .init(id: .sevenDay, prefix: .shortLabel, value: .percentUsed),
        ]
        let normal = makeRenderData(pinned: pins, colorMode: .monochrome, isEnterprise: false)
        let enterprise = makeRenderData(pinned: pins, colorMode: .monochrome, isEnterprise: true)
        #expect(MenuBarRenderer.buildLine(data: normal).string == MenuBarRenderer.buildLine(data: enterprise).string)
    }

    @Test("enterprise worst-case width still covers the live rendered line")
    func enterpriseWorstCaseCoversNatural() {
        let pin = PinnedMetricConfig(id: .extraCredits, prefix: .shortLabel, value: .dollars)
        let data = makeRenderData(pinned: [pin], fixedWidth: true, isEnterprise: true)
        let naturalWidth = MenuBarRenderer.buildLine(data: data).size().width
        #expect(MenuBarRenderer.fixedWidthMeasurement(data: data) >= naturalWidth)
    }

    @Test("same countdown pin renders three distinct strings across the three formats")
    func countdownHonorsResetDisplayFormat() {
        let pin = PinnedMetricConfig(id: .fiveHour, prefix: .none, value: .percentUsed, showCountdown: true)
        func line(_ format: ResetDisplayFormat) -> String {
            MenuBarRenderer.buildLine(data: makeRenderData(
                pinned: [pin],
                displayMode: .all,
                colorMode: .monochrome,
                fiveHourPct: 30,
                resetDisplayFormat: format,
                fiveHourReset: "1h39",
                fiveHourResetAbsolute: "20:30"
            )).string
        }
        #expect(line(.relative) == "30% 1h39")
        #expect(line(.absolute) == "30% 20:30")
        #expect(line(.both) == "30% 1h39 - 20:30")
    }

    @Test("countdown falls back to the available half when one side is empty in .both")
    func countdownBothFallsBackWhenHalfEmpty() {
        let pin = PinnedMetricConfig(id: .fiveHour, prefix: .none, value: .percentUsed, showCountdown: true)
        let data = makeRenderData(
            pinned: [pin],
            displayMode: .all,
            colorMode: .monochrome,
            fiveHourPct: 30,
            resetDisplayFormat: .both,
            fiveHourReset: "1h39",
            fiveHourResetAbsolute: ""
        )
        #expect(MenuBarRenderer.buildLine(data: data).string == "30% 1h39")
    }

    @Test("sample preview data renders every pinnable metric when all are pinned")
    func samplePreviewRendersEveryPin() {
        // The settings live preview is sample-driven so pins never vanish on a
        // machine with no usage data. Every availability flag in the sample
        // must be true: with all pinnable metrics pinned, the all-mode line
        // has to contain every pin (separator count == pins - 1).
        let pins = MetricID.menuBarPinnable.map { PinnedMetricConfig(id: $0, prefix: .none) }
        let config = MenuBarConfig(pinned: pins, displayMode: .all, separator: "|")
        let line = MenuBarRenderer.buildLine(data: .sample(config: config))
        let separators = line.string.filter { $0 == "|" }.count
        #expect(separators == pins.count - 1)
    }
}

@Suite("MenuBarRenderer.fixedWidthMeasurement")
struct MenuBarFixedWidthTests {

    @Test("adding a pin never shrinks the worst-case width (all mode)")
    func monotonicInAllMode() {
        let onePin = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentUsed)],
            displayMode: .all,
            fixedWidth: true
        )
        let twoPins = makeRenderData(
            pinned: [
                .init(id: .fiveHour, prefix: .none, value: .percentUsed),
                .init(id: .sevenDay, prefix: .none, value: .percentUsed),
            ],
            displayMode: .all,
            fixedWidth: true
        )
        #expect(MenuBarRenderer.fixedWidthMeasurement(data: twoPins) >= MenuBarRenderer.fixedWidthMeasurement(data: onePin))
    }

    @Test("adding a pin never shrinks the worst-case width (rotate mode)")
    func monotonicInRotateMode() {
        let onePin = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentUsed)],
            displayMode: .rotate,
            fixedWidth: true
        )
        let twoPins = makeRenderData(
            pinned: [
                .init(id: .fiveHour, prefix: .none, value: .percentUsed),
                .init(id: .sevenDay, prefix: .none, value: .percentUsed),
            ],
            displayMode: .rotate,
            fixedWidth: true
        )
        #expect(MenuBarRenderer.fixedWidthMeasurement(data: twoPins) >= MenuBarRenderer.fixedWidthMeasurement(data: onePin))
    }

    @Test("fixed-width measurement in .risk mode is wider than .monochrome - accounts for the dot")
    func fixedWidthAccountsForDot() {
        let riskData = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentUsed)],
            displayMode: .all,
            colorMode: .risk,
            fixedWidth: true
        )
        let monoData = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentUsed)],
            displayMode: .all,
            colorMode: .monochrome,
            fixedWidth: true
        )
        #expect(MenuBarRenderer.fixedWidthMeasurement(data: riskData) > MenuBarRenderer.fixedWidthMeasurement(data: monoData))
    }

    @Test("worst-case width is at least as wide as the natural rendered line")
    func worstCaseAtLeastNatural() {
        let data = makeRenderData(
            pinned: [.init(id: .fiveHour, prefix: .none, value: .percentUsed)],
            displayMode: .all,
            fixedWidth: true,
            fiveHourPct: 4 // narrow "4%" - worst case "100%" must be >= this
        )
        let naturalWidth = MenuBarRenderer.buildLine(data: data).size().width
        #expect(MenuBarRenderer.fixedWidthMeasurement(data: data) >= naturalWidth)
    }

    @Test("dollars pin: measurement is identical across live values and covers each rendered width")
    func dollarsWorstCaseStableAcrossLiveValues() {
        let pin = PinnedMetricConfig(id: .extraCredits, prefix: .none, value: .dollars)
        // Whole-dollar AND cent-bearing amounts within the ceiling (limit
        // $5,000 / "$8,888.88" floor). Cents matter: CurrencyFormatter keeps
        // 2 fraction digits for non-whole balances, so "$999.99" renders
        // wider than a decimals-free "$8,888" would.
        let liveMinorUnits: [Double] = [
            0, 4200, 130_000, 420_000,   // $0, $42, $1,300, $4,200
            130_055, 99_999,             // $1,300.55, $999.99
        ]
        var measurements = Set<CGFloat>()
        for used in liveMinorUnits {
            let data = makeRenderData(
                pinned: [pin],
                displayMode: .all,
                fixedWidth: true,
                extraCreditsUsedMinorUnits: used,
                extraCreditsLimitMinorUnits: 500_000
            )
            let measured = MenuBarRenderer.fixedWidthMeasurement(data: data)
            #expect(measured >= MenuBarRenderer.buildLine(data: data).size().width, "used \(used)")
            measurements.insert(measured)
        }
        #expect(measurements.count == 1)
    }

    @Test("dollars pin: a limit wider than the $8,888 floor raises the measurement")
    func dollarsWorstCaseUsesLimitWhenWider() {
        func measurement(limitMinorUnits: Double) -> CGFloat {
            MenuBarRenderer.fixedWidthMeasurement(data: makeRenderData(
                pinned: [.init(id: .extraCredits, prefix: .none, value: .dollars)],
                displayMode: .all,
                fixedWidth: true,
                extraCreditsLimitMinorUnits: limitMinorUnits
            ))
        }
        // $500 limit -> the "$8,888" floor governs; $150,000 limit -> "$150,000" governs.
        #expect(measurement(limitMinorUnits: 15_000_000) > measurement(limitMinorUnits: 50_000))
    }

    @Test("countdown pin: measurement is identical across live countdown strings, per format")
    func countdownWorstCaseStableAcrossLiveValues() {
        let pin = PinnedMetricConfig(id: .fiveHour, prefix: .none, value: .percentUsed, showCountdown: true)
        let liveCountdowns: [(relative: String, absolute: String)] = [
            ("1h05", "20:30"), ("25min", "08:00"), ("4h44", "23:59"), ("now", "09:15"),
        ]
        for format in ResetDisplayFormat.allCases {
            var measurements = Set<CGFloat>()
            for live in liveCountdowns {
                let data = makeRenderData(
                    pinned: [pin],
                    displayMode: .all,
                    fixedWidth: true,
                    fiveHourPct: 42,
                    resetDisplayFormat: format,
                    fiveHourReset: live.relative,
                    fiveHourResetAbsolute: live.absolute
                )
                let measured = MenuBarRenderer.fixedWidthMeasurement(data: data)
                #expect(
                    measured >= MenuBarRenderer.buildLine(data: data).size().width,
                    "format \(format.rawValue), countdown \(live.relative)/\(live.absolute)"
                )
                measurements.insert(measured)
            }
            #expect(measurements.count == 1, "format \(format.rawValue)")
        }
    }
}

@Suite("MenuBarRenderer.outageBadge")
struct MenuBarOutageBadgeTests {

    @Test("outage badge widens the rendered image vs. no badge")
    func outageBadgeRenders() {
        let base = makeRenderData(outageActive: false)
        let badged = makeRenderData(outageActive: true, outageHealth: .down, nextPollSeconds: 65)

        let baseImg = MenuBarRenderer.renderUncached(base)
        let badgedImg = MenuBarRenderer.renderUncached(badged)

        #expect(badgedImg.isTemplate == false)
        #expect(badgedImg.size.width > baseImg.size.width)
    }

    @Test("pinned serviceStatus with .down is non-template and wider than .healthy")
    func pinnedServiceStatusDownWiderThanHealthy() {
        let healthy = makeRenderData(
            pinned: [.init(id: .serviceStatus)],
            outageHealth: .healthy,
            nextPollSeconds: nil
        )
        let down = makeRenderData(
            pinned: [.init(id: .serviceStatus)],
            outageHealth: .down,
            nextPollSeconds: 125
        )

        let healthyImg = MenuBarRenderer.renderUncached(healthy)
        let downImg = MenuBarRenderer.renderUncached(down)

        #expect(downImg.isTemplate == false)
        #expect(downImg.size.width > healthyImg.size.width)
    }

    @Test("no config or error falls back to the template logo, even with an active outage badge underneath")
    func noConfigFallsBackToLogoBadgeOnly() {
        let data = makeRenderData(hasConfig: false, outageActive: true, outageHealth: .down, nextPollSeconds: 30)
        let image = MenuBarRenderer.renderUncached(data)
        // Outage badge alone (not composited with the logo) - still non-template.
        #expect(image.isTemplate == false)
    }
}

/// Covers the pin gating: Extra Credits renders in the menu bar only when the
/// paid pool is enabled, otherwise the item must not silently vanish.
@Suite("MenuBarRenderer Extra Credits gating")
struct MenuBarExtraCreditsRenderTests {

    @Test("EC pinned + pool enabled renders a value (non-template image)")
    func renderedWhenEnabled() {
        let data = makeRenderData(
            pinned: [.init(id: .extraCredits)],
            hasExtraCredits: true
        )
        let image = MenuBarRenderer.renderUncached(data)
        #expect(image.isTemplate == false)
        #expect(image.size.width > 0)
    }

    @Test("EC pinned but pool disabled falls back to the logo (template image)")
    func logoFallbackWhenDisabled() {
        let data = makeRenderData(
            pinned: [.init(id: .extraCredits)],
            hasExtraCredits: false
        )
        let image = MenuBarRenderer.renderUncached(data)
        #expect(image.isTemplate == true)
    }
}
