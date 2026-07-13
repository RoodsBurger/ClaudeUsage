import SwiftUI
import AppKit

/// Single source of truth for "smart vs threshold" gauge coloring, shared by
/// the Monitoring dashboard, the popover layouts, and the menu bar.
///
/// Resolves to a `RiskZone` (ok/warning/critical), the single semantic-color
/// vocabulary every data point in the app draws from. The only per-call-site
/// difference beyond that is the gradient's start/end points.
enum GaugeColorMode: Equatable {
    case smart
    case threshold
}

enum GaugeColorResolver {
    /// The decision: Smart Color setting on -> risk-aware; off -> static ramp.
    static func mode(smartColorEnabled: Bool, windowDuration: TimeInterval) -> GaugeColorMode {
        // Smart Color is a time-aware risk model; it needs a window to project
        // over (windowDuration > 0). The smart path itself handles a missing
        // reset date (falls back to absolute risk), so metrics like Opus/Cowork
        // that have a week window but no resets_at still colour via smart.
        // Only metrics with no window at all (e.g. the Extra Credits pool,
        // windowDuration 0) fall back to the static threshold ladder.
        (smartColorEnabled && windowDuration > 0) ? .smart : .threshold
    }

    /// The resolved `RiskZone` for a data point: smart mode maps the
    /// continuous risk score through `SmartColor.riskZone`; threshold mode
    /// maps the raw percentage through the user's warning/critical ladder.
    static func zone(
        mode: GaugeColorMode,
        utilization: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double,
        now: Date = Date(),
        profile: SmartColorProfile
    ) -> RiskZone {
        switch mode {
        case .smart:
            let risk = SmartColor.risk(
                utilization: Double(utilization),
                resetDate: resetDate,
                windowDuration: windowDuration,
                pacingMargin: pacingMargin,
                now: now,
                profile: profile
            )
            return SmartColor.riskZone(forRisk: risk, params: profile.parameters)
        case .threshold:
            return RiskZone.forPercent(utilization, thresholds: thresholds)
        }
    }

    static func color(
        mode: GaugeColorMode,
        utilization: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double,
        now: Date = Date(),
        profile: SmartColorProfile
    ) -> Color {
        zone(
            mode: mode,
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now,
            profile: profile
        ).color
    }

    static func nsColor(
        mode: GaugeColorMode,
        utilization: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double,
        now: Date = Date(),
        profile: SmartColorProfile
    ) -> NSColor {
        zone(
            mode: mode,
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now,
            profile: profile
        ).nsColor
    }

    static func gradient(
        mode: GaugeColorMode,
        utilization: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        thresholds: UsageThresholds,
        pacingMargin: Double,
        now: Date = Date(),
        profile: SmartColorProfile,
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) -> LinearGradient {
        let base = color(
            mode: mode,
            utilization: utilization,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            now: now,
            profile: profile
        )
        return LinearGradient(colors: [base, base.lighter()], startPoint: startPoint, endPoint: endPoint)
    }
}
