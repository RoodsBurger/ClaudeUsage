import AppKit

enum MenuBarRenderer {
    /// Everything the renderer needs to draw one frame of the status item.
    /// Pure value type - no store references - so `buildLine(data:)` and
    /// `render(_:)` are unit-testable without touching AppKit's live status
    /// bar or any `@MainActor` store.
    struct RenderData: Equatable {
        let menuBarConfig: MenuBarConfig
        /// Index into the visible-pins list for `.rotate` display mode.
        /// Wrapped modulo the visible count, so any non-negative value works.
        let rotateIndex: Int

        let hasConfig: Bool
        let hasError: Bool
        let thresholds: UsageThresholds
        let smartColorEnabled: Bool
        let smartColorProfile: SmartColorProfile
        let pacingMargin: Double

        let fiveHourPct: Int
        let sevenDayPct: Int
        let sonnetPct: Int
        let designPct: Int
        let fablePct: Int
        let extraCreditsPct: Int

        /// True once the API has returned a `five_hour` bucket at all -
        /// independent of whether `resetsAt` is populated, since Anthropic can
        /// return the bucket with `utilization: 0` and no reset date between
        /// two 5h windows. Keeps session-scoped pins visible with a neutral
        /// placeholder instead of vanishing during a lull.
        let hasFiveHourBucket: Bool
        let hasWeeklyPacing: Bool
        let hasSessionPacing: Bool
        let hasDesign: Bool
        let hasFable: Bool
        let hasExtraCredits: Bool

        let fiveHourResetDate: Date?
        let sevenDayResetDate: Date?
        let sonnetResetDate: Date?
        let designResetDate: Date?
        let fableResetDate: Date?

        /// User's countdown presentation (relative / absolute / both) for
        /// every `showCountdown` span.
        let resetDisplayFormat: ResetDisplayFormat

        /// Relative countdown text ("1h39", "3d 14h", ...), appended after
        /// the value when a pin's `showCountdown` is on.
        let fiveHourReset: String
        let sevenDayReset: String
        let sonnetReset: String
        let designReset: String
        let fableReset: String

        /// Absolute countdown text ("20:30", "Thu 19:00", ...), the second
        /// half of the `.absolute` / `.both` formats.
        let fiveHourResetAbsolute: String
        let sevenDayResetAbsolute: String
        let sonnetResetAbsolute: String
        let designResetAbsolute: String
        let fableResetAbsolute: String

        let sessionPacingDelta: Int
        let sessionPacingZone: PacingZone
        let weeklyPacingDelta: Int
        let weeklyPacingZone: PacingZone
        let sessionPacingDisplayMode: PacingDisplayMode
        let weeklyPacingDisplayMode: PacingDisplayMode

        /// Extra Credits pool usage in the currency's minor unit (e.g. cents),
        /// formatted through `CurrencyFormatter` when a pin's value style is
        /// `.dollars`. The monthly limit feeds the fixed-width worst case.
        let extraCreditsUsedMinorUnits: Double
        let extraCreditsLimitMinorUnits: Double
        let extraCreditsCurrency: String

        // Outage badge - set by StatusBarController from VendorStatusStore.
        let outageActive: Bool
        let outageHealth: VendorHealth
        let nextPollSeconds: Int?

        /// True when the status item's current effective appearance resolves
        /// to `.darkAqua` - drives adaptive text color (`DS.Pastel.NS.textOnDark`
        /// vs `.textOnLight`) and, in `.risk` colorMode, which pastel variant
        /// (plain vs deepened) colors each metric's risk dot. Menu bar text
        /// must stay legible against the actual desktop showing through the
        /// translucent bar, which can differ from the app's own light/dark
        /// appearance - see `StatusBarController`.
        let menuBarIsDark: Bool

        /// Fixed sample usage data for the settings live preview: every
        /// availability flag is true so no configured pin ever vanishes, and
        /// the percentages span the ok/warning/critical zones so risk
        /// coloring is visible. Only the configuration inputs (the config
        /// itself, thresholds, smart color, formats) come from the caller -
        /// the usage numbers are deliberately NOT live so the preview shows
        /// the full configuration even with no usage data (fresh install,
        /// auth error).
        static func sample(
            config: MenuBarConfig,
            rotateIndex: Int = 0,
            thresholds: UsageThresholds = .default,
            smartColorEnabled: Bool = false,
            smartColorProfile: SmartColorProfile = .balanced,
            pacingMargin: Double = 10,
            resetDisplayFormat: ResetDisplayFormat = .relative,
            sessionPacingDisplayMode: PacingDisplayMode = .dotDelta,
            weeklyPacingDisplayMode: PacingDisplayMode = .dotDelta,
            menuBarIsDark: Bool = true
        ) -> RenderData {
            RenderData(
                menuBarConfig: config,
                rotateIndex: rotateIndex,
                hasConfig: true,
                hasError: false,
                thresholds: thresholds,
                smartColorEnabled: smartColorEnabled,
                smartColorProfile: smartColorProfile,
                pacingMargin: pacingMargin,
                fiveHourPct: 42,
                sevenDayPct: 18,
                sonnetPct: 61,
                designPct: 7,
                fablePct: 84,
                extraCreditsPct: 28,
                hasFiveHourBucket: true,
                hasWeeklyPacing: true,
                hasSessionPacing: true,
                hasDesign: true,
                hasFable: true,
                hasExtraCredits: true,
                fiveHourResetDate: nil,
                sevenDayResetDate: nil,
                sonnetResetDate: nil,
                designResetDate: nil,
                fableResetDate: nil,
                resetDisplayFormat: resetDisplayFormat,
                fiveHourReset: "2h13",
                sevenDayReset: "3d 14h",
                sonnetReset: "5d 2h",
                designReset: "1d 8h",
                fableReset: "6d 1h",
                fiveHourResetAbsolute: "20:30",
                sevenDayResetAbsolute: "Thu 19:00",
                sonnetResetAbsolute: "Sat 09:00",
                designResetAbsolute: "Wed 07:30",
                fableResetAbsolute: "May 12 09:00",
                sessionPacingDelta: 2,
                sessionPacingZone: .onTrack,
                weeklyPacingDelta: 12,
                weeklyPacingZone: .warning,
                sessionPacingDisplayMode: sessionPacingDisplayMode,
                weeklyPacingDisplayMode: weeklyPacingDisplayMode,
                extraCreditsUsedMinorUnits: 14_250,  // $142.50
                extraCreditsLimitMinorUnits: 50_000, // $500
                extraCreditsCurrency: "USD",
                outageActive: false,
                outageHealth: .healthy,
                nextPollSeconds: nil,
                menuBarIsDark: menuBarIsDark
            )
        }
    }

    private static var cachedImage: NSImage?
    private static var cachedData: RenderData?

    static func render(_ data: RenderData) -> NSImage {
        if let cached = cachedImage, let prev = cachedData, prev == data {
            return cached
        }

        let image = renderUncached(data)
        cachedImage = image
        cachedData = data
        return image
    }

    /// Same rendering pipeline as `render(_:)` but never touches or updates
    /// the static cache. Useful for live previews that may differ from the
    /// status bar's current state and shouldn't poison it.
    static func renderUncached(_ data: RenderData) -> NSImage {
        if data.outageActive {
            return renderWithOutageBadge(data)
        }
        if !data.hasConfig || data.hasError {
            return renderLogoTemplate()
        }
        return renderPinnedMetrics(data)
    }

    // MARK: - Color helpers

    /// Resolves the gauge colour for a flat percentage.
    ///
    /// Smart Color is a *time-aware* risk model: it projects current usage
    /// against the time left in a reset window. A metric with no reset window
    /// (e.g. the Extra Credits pool) has nothing to project against, so it
    /// falls back to the static warning/critical threshold ladder. This is the
    /// rule that keeps Extra Credits coloured identically in the menu bar, the
    /// popover, and the dashboard. Internal (not private) so the
    /// windowless-fallback rule is unit-testable in isolation; `now` is
    /// injectable for deterministic tests.
    static func gaugeColor(
        pct: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        monochrome: Bool,
        smartEnabled: Bool,
        thresholds: UsageThresholds,
        pacingMargin: Double,
        smartColorProfile: SmartColorProfile,
        now: Date = Date()
    ) -> NSColor {
        if monochrome { return .labelColor }
        return GaugeColorResolver.nsColor(
            mode: GaugeColorResolver.mode(smartColorEnabled: smartEnabled, windowDuration: windowDuration),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now,
            profile: smartColorProfile
        )
    }

    /// The `RiskZone` a percent-based metric currently sits in, independent of
    /// `colorMode` - used both for `highestRisk` selection and for the
    /// `.risk`-mode dot color. The single place a metric's zone is resolved;
    /// text color comes from `textColor`, the dot from `appendDot`.
    private static func metricZone(pct: Int, resetDate: Date?, windowDuration: TimeInterval, data: RenderData) -> RiskZone {
        GaugeColorResolver.zone(
            mode: GaugeColorResolver.mode(smartColorEnabled: data.smartColorEnabled, windowDuration: windowDuration),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: data.thresholds,
            pacingMargin: data.pacingMargin,
            profile: data.smartColorProfile
        )
    }

    /// Adaptive text color for every metric's label/value/separator/countdown
    /// - near-white on a dark menu bar, near-black on a light one, so text
    /// stays legible over whatever wallpaper shows through the translucent
    /// bar. Risk color lives in `appendDot`; this never varies with `colorMode`.
    private static func textColor(_ data: RenderData) -> NSColor {
        data.menuBarIsDark ? DS.Pastel.NS.textOnDark : DS.Pastel.NS.textOnLight
    }

    /// Prepends a small (~7pt) filled circle in `color` - the sole carrier of
    /// risk information now that metric text is adaptive-colored. Callers
    /// only invoke this in `.risk` colorMode.
    private static func appendDot(_ color: NSColor, to str: NSMutableAttributedString) {
        str.append(NSAttributedString(string: "\u{25CF} ", attributes: [
            .font: NSFont.systemFont(ofSize: 7, weight: .bold),
            .foregroundColor: color,
        ]))
    }

    /// 0/1/2 risk rank for a metric's own zone, independent of `colorMode` -
    /// `highestRisk` selection is driven by real usage risk even when the
    /// display renders monochrome.
    private static func zoneRank(pct: Int, resetDate: Date?, windowDuration: TimeInterval, data: RenderData) -> Int {
        switch metricZone(pct: pct, resetDate: resetDate, windowDuration: windowDuration, data: data) {
        case .ok: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }

    private static func pacingRank(_ zone: PacingZone) -> Int {
        switch zone {
        case .chill, .onTrack: return 0
        case .warning: return 1
        case .hot: return 2
        }
    }

    private static func windowDuration(for metric: MetricID) -> TimeInterval {
        switch metric {
        case .fiveHour: return 5 * 3600
        case .sevenDay, .sonnet, .design, .fable, .opus, .cowork: return 7 * 86_400
        default: return 0
        }
    }

    // MARK: - Outage badge

    /// Composite an outage glyph + mm:ss countdown ahead of the normal content.
    /// When usage data isn't usable (no config / usage error), show the badge
    /// alone - avoids compositing a template logo into a coloured image.
    private static func renderWithOutageBadge(_ data: RenderData) -> NSImage {
        let badge = renderOutageBadgeImage(data)
        let hasMetrics = data.hasConfig && !data.hasError
        guard hasMetrics else { return badge }
        let base = renderPinnedMetrics(data)
        return horizontallyCompose(left: badge, right: base, gap: 5)
    }

    private static func renderOutageBadgeImage(_ data: RenderData) -> NSImage {
        let height: CGFloat = 22
        let tint: NSColor = data.outageHealth == .down ? .systemRed : .systemOrange

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        let glyph = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig)
        let glyphSize = glyph?.size ?? NSSize(width: 12, height: 12)

        var countdown: NSAttributedString?
        if let secs = data.nextPollSeconds {
            let clamped = max(0, secs)
            let text = String(format: "%d:%02d", clamped / 60, clamped % 60)
            countdown = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: tint,
            ])
        }

        let gap: CGFloat = 3
        let textWidth = countdown?.size().width ?? 0
        let width = glyphSize.width + (countdown != nil ? gap + textWidth : 0)
        let img = NSImage(size: NSSize(width: ceil(width) + 2, height: height), flipped: false) { _ in
            glyph?.draw(at: NSPoint(x: 1, y: (height - glyphSize.height) / 2),
                        from: .zero, operation: .sourceOver, fraction: 1)
            if let countdown {
                let ts = countdown.size()
                countdown.draw(at: NSPoint(x: 1 + glyphSize.width + gap, y: (height - ts.height) / 2))
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func horizontallyCompose(left: NSImage, right: NSImage, gap: CGFloat) -> NSImage {
        let height: CGFloat = 22
        let width = left.size.width + gap + right.size.width
        let img = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            left.draw(at: NSPoint(x: 0, y: (height - left.size.height) / 2),
                      from: .zero, operation: .sourceOver, fraction: 1)
            right.draw(at: NSPoint(x: left.size.width + gap, y: (height - right.size.height) / 2),
                       from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: - Pin visibility

    /// The configured pins, filtered down to the ones that currently have
    /// something to show. Order is preserved from `menuBarConfig.pinned`.
    static func visiblePins(_ data: RenderData) -> [PinnedMetricConfig] {
        data.menuBarConfig.pinned.filter { pin in
            switch pin.id {
            case .fiveHour, .sessionReset, .sessionPacing: return data.hasFiveHourBucket
            case .sevenDay: return true
            case .sonnet: return true
            case .design: return data.hasDesign
            case .fable: return data.hasFable
            case .extraCredits: return data.hasExtraCredits
            case .weeklyPacing: return data.hasWeeklyPacing
            case .serviceStatus: return true
            // Popover-only - never actually pinned (excluded from
            // `MetricID.menuBarPinnable`), kept here only for switch exhaustiveness.
            case .opus, .cowork: return false
            }
        }
    }

    // MARK: - Line building (pure, testable)

    /// Builds the full attributed line for the current display mode, without
    /// touching AppKit imaging. Empty when nothing is pinned/visible.
    static func buildLine(data: RenderData) -> NSAttributedString {
        let visible = visiblePins(data)
        guard !visible.isEmpty else { return NSAttributedString() }

        switch data.menuBarConfig.displayMode {
        case .all:
            return buildAllLine(visible, data: data)
        case .highestRisk:
            guard let pin = highestRiskPin(visible, data: data) else { return NSAttributedString() }
            return buildSingle(pin, data: data, worstCase: false)
        case .rotate:
            let index = ((data.rotateIndex % visible.count) + visible.count) % visible.count
            return buildSingle(visible[index], data: data, worstCase: false)
        }
    }

    /// The widest this configuration's line could ever render, used to pad
    /// the status item to a stable width (`fixedWidth`). "All" mode measures
    /// the full worst-case line; single-pin modes take the max width across
    /// every pinned metric's own worst case, since rotation/highest-risk can
    /// land on any of them.
    static func fixedWidthMeasurement(data: RenderData) -> CGFloat {
        let visible = visiblePins(data)
        guard !visible.isEmpty else { return 0 }
        switch data.menuBarConfig.displayMode {
        case .all:
            return ceil(buildAllLine(visible, data: data, worstCase: true).size().width)
        case .highestRisk, .rotate:
            return visible.map { ceil(buildSingle($0, data: data, worstCase: true).size().width) }.max() ?? 0
        }
    }

    private static func buildAllLine(_ pins: [PinnedMetricConfig], data: RenderData, worstCase: Bool = false) -> NSAttributedString {
        let str = NSMutableAttributedString()
        let sepAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular),
            .foregroundColor: textColor(data),
        ]
        for (i, pin) in pins.enumerated() {
            if i > 0 {
                str.append(NSAttributedString(string: " \(data.menuBarConfig.separator) ", attributes: sepAttrs))
            }
            str.append(buildSingle(pin, data: data, worstCase: worstCase))
        }
        return str
    }

    /// Picks the pinned metric with the highest risk rank. Ties keep pinned
    /// order (strict `>` only replaces the running best).
    private static func highestRiskPin(_ pins: [PinnedMetricConfig], data: RenderData) -> PinnedMetricConfig? {
        var best: PinnedMetricConfig?
        var bestScore = -1
        for pin in pins {
            let score = riskScore(pin, data: data)
            if score > bestScore {
                bestScore = score
                best = pin
            }
        }
        return best
    }

    private static func riskScore(_ pin: PinnedMetricConfig, data: RenderData) -> Int {
        switch pin.id {
        case .fiveHour:
            return zoneRank(pct: data.fiveHourPct, resetDate: data.fiveHourResetDate, windowDuration: windowDuration(for: .fiveHour), data: data)
        case .sevenDay:
            return zoneRank(pct: data.sevenDayPct, resetDate: data.sevenDayResetDate, windowDuration: windowDuration(for: .sevenDay), data: data)
        case .sonnet:
            return zoneRank(pct: data.sonnetPct, resetDate: data.sonnetResetDate, windowDuration: windowDuration(for: .sonnet), data: data)
        case .design:
            return zoneRank(pct: data.designPct, resetDate: data.designResetDate, windowDuration: windowDuration(for: .design), data: data)
        case .fable:
            return zoneRank(pct: data.fablePct, resetDate: data.fableResetDate, windowDuration: windowDuration(for: .fable), data: data)
        case .extraCredits:
            return zoneRank(pct: data.extraCreditsPct, resetDate: nil, windowDuration: 0, data: data)
        case .sessionPacing:
            return data.hasSessionPacing ? pacingRank(data.sessionPacingZone) : 0
        case .weeklyPacing:
            return data.hasWeeklyPacing ? pacingRank(data.weeklyPacingZone) : 0
        case .serviceStatus:
            return data.outageHealth.rawValue
        case .sessionReset:
            return zoneRank(pct: data.fiveHourPct, resetDate: data.fiveHourResetDate, windowDuration: windowDuration(for: .fiveHour), data: data)
        // Popover-only - never actually pinned, see `visiblePins`.
        case .opus, .cowork:
            return 0
        }
    }

    // MARK: - Per-pin rendering

    private static func buildSingle(_ pin: PinnedMetricConfig, data: RenderData, worstCase: Bool) -> NSAttributedString {
        switch pin.id {
        case .fiveHour:
            return buildPercentMetric(pin, pct: data.fiveHourPct, resetDate: data.fiveHourResetDate, windowDuration: windowDuration(for: .fiveHour), relative: data.fiveHourReset, absolute: data.fiveHourResetAbsolute, data: data, worstCase: worstCase)
        case .sevenDay:
            return buildPercentMetric(pin, pct: data.sevenDayPct, resetDate: data.sevenDayResetDate, windowDuration: windowDuration(for: .sevenDay), relative: data.sevenDayReset, absolute: data.sevenDayResetAbsolute, data: data, worstCase: worstCase)
        case .sonnet:
            return buildPercentMetric(pin, pct: data.sonnetPct, resetDate: data.sonnetResetDate, windowDuration: windowDuration(for: .sonnet), relative: data.sonnetReset, absolute: data.sonnetResetAbsolute, data: data, worstCase: worstCase)
        case .design:
            return buildPercentMetric(pin, pct: data.designPct, resetDate: data.designResetDate, windowDuration: windowDuration(for: .design), relative: data.designReset, absolute: data.designResetAbsolute, data: data, worstCase: worstCase)
        case .fable:
            return buildPercentMetric(pin, pct: data.fablePct, resetDate: data.fableResetDate, windowDuration: windowDuration(for: .fable), relative: data.fableReset, absolute: data.fableResetAbsolute, data: data, worstCase: worstCase)
        case .extraCredits:
            return buildExtraCreditsMetric(pin, data: data, worstCase: worstCase)
        case .sessionPacing:
            return buildPacingMetric(pin, hasData: data.hasSessionPacing, delta: data.sessionPacingDelta, zone: data.sessionPacingZone, mode: data.sessionPacingDisplayMode, data: data)
        case .weeklyPacing:
            return buildPacingMetric(pin, hasData: true, delta: data.weeklyPacingDelta, zone: data.weeklyPacingZone, mode: data.weeklyPacingDisplayMode, data: data)
        case .serviceStatus:
            return buildServiceStatus(pin, data: data)
        case .sessionReset:
            return buildCountdownOnly(data: data)
        // Popover-only - never actually pinned, see `visiblePins`.
        case .opus, .cowork:
            return NSAttributedString()
        }
    }

    private static let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)

    /// Countdown text attributes - adaptive color, so this is a function of
    /// `data` (menu bar appearance) rather than a static constant.
    private static func countdownAttributes(_ data: RenderData) -> [NSAttributedString.Key: Any] {
        [.font: countdownFont, .foregroundColor: textColor(data)]
    }

    /// `label + value%` for a simple percentage metric (5h/7d/Sonnet/Design/
    /// Fable), plus an optional countdown span honoring `resetDisplayFormat`.
    /// `worstCase` (for `fixedWidthMeasurement`) forces the value to "100" and
    /// the countdown to the widest string the active format can produce.
    private static func buildPercentMetric(
        _ pin: PinnedMetricConfig,
        pct: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        relative: String,
        absolute: String,
        data: RenderData,
        worstCase: Bool
    ) -> NSAttributedString {
        let str = NSMutableAttributedString()
        if data.menuBarConfig.colorMode == .risk {
            let zone = metricZone(pct: pct, resetDate: resetDate, windowDuration: windowDuration, data: data)
            appendDot(zone.dotColor(menuBarIsDark: data.menuBarIsDark), to: str)
        }
        appendPrefix(pin, to: str, data: data)

        let displayPct: Int
        if worstCase {
            displayPct = 100
        } else if pin.value == .percentRemaining {
            displayPct = max(0, 100 - pct)
        } else {
            displayPct = pct
        }
        str.append(NSAttributedString(string: "\(displayPct)%", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: textColor(data),
        ]))

        if pin.showCountdown {
            let text = worstCase
                ? worstCaseCountdownText(format: data.resetDisplayFormat, windowDuration: windowDuration)
                : ResetCountdownFormatter.display(relative: relative, absolute: absolute, format: data.resetDisplayFormat)
            if !text.isEmpty {
                str.append(NSAttributedString(string: " \(text)", attributes: countdownAttributes(data)))
            }
        }
        return str
    }

    /// The widest string the given `ResetDisplayFormat` can produce for the
    /// pin's window, in placeholder digits, so the fixed-width slot never
    /// shrinks as the live countdown drains. Only the font affects the
    /// measured width, so this measures with a color-less attribute set.
    private static func worstCaseCountdownText(format: ResetDisplayFormat, windowDuration: TimeInterval) -> String {
        let isSession = windowDuration <= 5 * 3600
        // Candidate sets mirror ResetCountdownFormatter's output shapes:
        // session relative "1h25"/"25min", weekly relative "3d 14h"/"14h 05";
        // absolute "20:30" same-day, "Thu 19:00" cross-day, weekly "Apr 24 19:00".
        let relativeCandidates = isSession ? ["8h88", "88min"] : ["88min", "88h 88", "8d 88h"]
        let absoluteCandidates = isSession ? ["88:88", "Wed 88:88"] : ["88:88", "Wed 88:88", "May 88 88:88"]
        let measureAttrs: [NSAttributedString.Key: Any] = [.font: countdownFont]
        switch format {
        case .relative: return widest(relativeCandidates, attributes: measureAttrs)
        case .absolute: return widest(absoluteCandidates, attributes: measureAttrs)
        case .both:
            let rel = widest(relativeCandidates, attributes: measureAttrs)
            let abs = widest(absoluteCandidates, attributes: measureAttrs)
            return "\(rel) - \(abs)"
        }
    }

    private static func widest(_ candidates: [String], attributes: [NSAttributedString.Key: Any]) -> String {
        candidates.max { lhs, rhs in
            (lhs as NSString).size(withAttributes: attributes).width
                < (rhs as NSString).size(withAttributes: attributes).width
        } ?? ""
    }

    /// Extra Credits is the only metric `.dollars` renders for; any other
    /// value style still falls back to a plain percentage.
    private static func buildExtraCreditsMetric(_ pin: PinnedMetricConfig, data: RenderData, worstCase: Bool) -> NSAttributedString {
        let str = NSMutableAttributedString()
        if data.menuBarConfig.colorMode == .risk {
            let zone = metricZone(pct: data.extraCreditsPct, resetDate: nil, windowDuration: 0, data: data)
            appendDot(zone.dotColor(menuBarIsDark: data.menuBarIsDark), to: str)
        }
        appendPrefix(pin, to: str, data: data)

        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: textColor(data),
        ]
        let text: String
        switch pin.value {
        case .dollars:
            if worstCase {
                // Ceiling: the pool's monthly limit formatted with forced
                // fraction digits, floored at "$8,888.88" - cents included on
                // both candidates because non-whole balances always render
                // with 2 decimals, wider than any decimals-free string.
                let limitText = CurrencyFormatter.formatMinorUnits(
                    data.extraCreditsLimitMinorUnits,
                    currencyCode: data.extraCreditsCurrency,
                    locale: Locale(identifier: "en_US"),
                    forceFractionDigits: true
                )
                text = widest([limitText, "$8,888.88"], attributes: valueAttributes)
            } else {
                text = CurrencyFormatter.formatMinorUnits(
                    data.extraCreditsUsedMinorUnits,
                    currencyCode: data.extraCreditsCurrency,
                    locale: Locale(identifier: "en_US")
                )
            }
        case .percentRemaining:
            text = "\(worstCase ? 100 : max(0, 100 - data.extraCreditsPct))%"
        case .percentUsed:
            text = "\(worstCase ? 100 : data.extraCreditsPct)%"
        }
        str.append(NSAttributedString(string: text, attributes: valueAttributes))
        return str
    }

    /// Session/weekly pacing row: dot / dot+delta / delta per
    /// `PacingDisplayMode`. The dot glyph is a fixed "\u{25CF}".
    private static let pacingGlyph = "\u{25CF}"

    private static func buildPacingMetric(
        _ pin: PinnedMetricConfig,
        hasData: Bool,
        delta: Int,
        zone: PacingZone,
        mode: PacingDisplayMode,
        data: RenderData
    ) -> NSAttributedString {
        let str = NSMutableAttributedString()
        // Same dot logic as a percent metric's `RiskZone`, mapped through
        // `PacingZone`. Always appended (never conditioned on `hasData`) so
        // the pin's width doesn't change once real pacing data arrives -
        // falls back to the adaptive text color when there's no zone yet.
        if data.menuBarConfig.colorMode == .risk {
            let dotColor = hasData ? zone.dotColor(menuBarIsDark: data.menuBarIsDark) : textColor(data)
            appendDot(dotColor, to: str)
        }
        appendPrefix(pin, to: str, data: data)

        let dotAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: textColor(data),
        ]
        let deltaAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: textColor(data),
        ]
        let sign = delta >= 0 ? "+" : ""
        switch mode {
        case .dot:
            str.append(NSAttributedString(string: pacingGlyph, attributes: dotAttrs))
        case .dotDelta:
            str.append(NSAttributedString(string: pacingGlyph, attributes: dotAttrs))
            str.append(NSAttributedString(string: hasData ? " \(sign)\(delta)%" : " -", attributes: deltaAttrs))
        case .delta:
            str.append(NSAttributedString(string: hasData ? "\(sign)\(delta)%" : "-", attributes: deltaAttrs))
        }
        return str
    }

    private static func buildServiceStatus(_ pin: PinnedMetricConfig, data: RenderData) -> NSAttributedString {
        let str = NSMutableAttributedString()
        let mono = data.menuBarConfig.colorMode == .monochrome
        let symbolName: String
        let color: NSColor
        let fallbackText: String
        switch data.outageHealth {
        case .healthy:  symbolName = "checkmark.circle.fill";         color = mono ? .labelColor : .systemGreen;  fallbackText = "OK"
        case .degraded: symbolName = "exclamationmark.triangle.fill"; color = mono ? .labelColor : .systemOrange; fallbackText = "!"
        case .down:     symbolName = "exclamationmark.triangle.fill"; color = mono ? .labelColor : .systemRed;    fallbackText = "!"
        }

        if data.menuBarConfig.showIcon {
            appendSymbol(symbolName, color: color, to: str)
        } else {
            str.append(NSAttributedString(string: fallbackText, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: color,
            ]))
        }

        if data.outageHealth == .down, let secs = data.nextPollSeconds {
            let clamped = max(0, secs)
            let text = String(format: " %d:%02d", clamped / 60, clamped % 60)
            str.append(NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: color,
            ]))
        }
        return str
    }

    /// `sessionReset` is not offered in the "add a pin" menu - a percentage
    /// pin's `showCountdown` flag covers that role instead. This case only
    /// exists so the switch stays exhaustive if a config is ever decoded with
    /// that id; it renders countdown text alone, no value.
    private static func buildCountdownOnly(data: RenderData) -> NSAttributedString {
        let resolved = ResetCountdownFormatter.display(
            relative: data.fiveHourReset,
            absolute: data.fiveHourResetAbsolute,
            format: data.resetDisplayFormat
        )
        let text = resolved.isEmpty ? "-" : resolved
        let str = NSMutableAttributedString()
        if data.menuBarConfig.colorMode == .risk {
            let zone = metricZone(pct: data.fiveHourPct, resetDate: data.fiveHourResetDate, windowDuration: windowDuration(for: .fiveHour), data: data)
            appendDot(zone.dotColor(menuBarIsDark: data.menuBarIsDark), to: str)
        }
        str.append(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: textColor(data),
        ]))
        return str
    }

    // MARK: - Prefix (icon / short label)

    private static func appendPrefix(_ pin: PinnedMetricConfig, to str: NSMutableAttributedString, data: RenderData) {
        switch pin.prefix {
        case .none:
            return
        case .shortLabel:
            appendShortLabel(pin.id, to: str, data: data)
        case .symbol:
            if data.menuBarConfig.showIcon {
                appendSymbol(pin.id.menuBarSymbolName, color: textColor(data), to: str)
                str.append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 9)]))
            } else {
                appendShortLabel(pin.id, to: str, data: data)
            }
        }
    }

    private static func appendShortLabel(_ id: MetricID, to str: NSMutableAttributedString, data: RenderData) {
        let label = id.shortLabel
        guard !label.isEmpty else { return }
        str.append(NSAttributedString(string: "\(label) ", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: textColor(data),
        ]))
    }

    /// SF Symbol prefix, sized to the surrounding text's cap height so it
    /// sits centered on the baseline instead of towering over/under the text.
    private static func appendSymbol(_ name: String, color: NSColor, to str: NSMutableAttributedString, pointSize: CGFloat = 11) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let glyph = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let capHeight = NSFont.systemFont(ofSize: pointSize).capHeight
        let attachment = NSTextAttachment()
        attachment.image = glyph
        attachment.bounds = CGRect(x: 0, y: (capHeight - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height)
        str.append(NSAttributedString(attachment: attachment))
    }

    // MARK: - Imaging

    private static func renderPinnedMetrics(_ data: RenderData) -> NSImage {
        let line = buildLine(data: data)
        guard line.length > 0 else { return renderLogoTemplate() }

        let height: CGFloat = 22
        var contentWidth = ceil(line.size().width)
        if data.menuBarConfig.fixedWidth {
            contentWidth = max(contentWidth, fixedWidthMeasurement(data: data))
        }

        let imgSize = NSSize(width: contentWidth + 2, height: height)
        let lineSize = line.size()
        let img = NSImage(size: imgSize, flipped: false) { _ in
            line.draw(at: NSPoint(x: 1, y: (height - lineSize.height) / 2))
            return true
        }
        img.isTemplate = false
        return img
    }

    /// App logo silhouette for menu bar (template - macOS renders white/black automatically).
    private static func renderLogoTemplate() -> NSImage {
        let s: CGFloat = 16
        let height: CGFloat = 22
        let imgSize = NSSize(width: s + 2, height: height)
        let scale = s / 300.0
        let yOff = (height - s) / 2

        let img = NSImage(size: imgSize, flipped: true) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.translateBy(x: 1, y: yOff)
            ctx.scaleBy(x: scale, y: scale)

            NSColor.black.setFill()

            let lPath = CGMutablePath()
            let r: CGFloat = 32
            lPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: 300, height: 122), cornerWidth: r, cornerHeight: r)
            lPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: 122, height: 300), cornerWidth: r, cornerHeight: r)
            ctx.addPath(lPath)
            ctx.fillPath(using: .winding)

            let bar1 = CGRect(x: 142, y: 142, width: 158, height: 70)
            let bar2 = CGRect(x: 142, y: 230, width: 158, height: 70)
            let barR: CGFloat = 24
            ctx.addPath(CGPath(roundedRect: bar1, cornerWidth: barR, cornerHeight: barR, transform: nil))
            ctx.fillPath()
            ctx.addPath(CGPath(roundedRect: bar2, cornerWidth: barR, cornerHeight: barR, transform: nil))
            ctx.fillPath()

            return true
        }
        img.isTemplate = true
        return img
    }
}
