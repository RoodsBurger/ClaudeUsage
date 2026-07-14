import SwiftUI
import AppKit

/// Data-point risk → semantic pastel color. The single source of gauge color.
enum RiskZone: String, Sendable, CaseIterable {
    case ok, warning, critical

    var color: Color {
        switch self {
        case .ok: DS.Pastel.green
        case .warning: DS.Pastel.amber
        case .critical: DS.Pastel.coral
        }
    }

    var nsColor: NSColor {
        switch self {
        case .ok: DS.Pastel.NS.green
        case .warning: DS.Pastel.NS.amber
        case .critical: DS.Pastel.NS.coral
        }
    }

    /// The menu bar's risk-dot color: the pastel on a dark bar, the deepened
    /// (higher-contrast) variant on a light bar.
    func dotColor(menuBarIsDark: Bool) -> NSColor {
        switch self {
        case .ok: menuBarIsDark ? DS.Pastel.NS.green : DS.Pastel.NS.greenDeep
        case .warning: menuBarIsDark ? DS.Pastel.NS.amber : DS.Pastel.NS.amberDeep
        case .critical: menuBarIsDark ? DS.Pastel.NS.coral : DS.Pastel.NS.coralDeep
        }
    }

    /// Threshold ladder used when Smart Color is off (percent used vs user thresholds).
    static func forPercent(_ pct: Int, thresholds: UsageThresholds) -> RiskZone {
        if pct >= thresholds.criticalPercent { return .critical }
        if pct >= thresholds.warningPercent { return .warning }
        return .ok
    }
}

extension PacingZone {
    /// chill=green, onTrack=blue (active/info), warning=amber, hot=coral.
    var semanticColor: Color {
        switch self {
        case .chill: DS.Pastel.green
        case .onTrack: DS.Pastel.blue
        case .warning: DS.Pastel.amber
        case .hot: DS.Pastel.coral
        }
    }

    var semanticNSColor: NSColor {
        switch self {
        case .chill: DS.Pastel.NS.green
        case .onTrack: DS.Pastel.NS.blue
        case .warning: DS.Pastel.NS.amber
        case .hot: DS.Pastel.NS.coral
        }
    }

    /// The menu bar's risk-dot color for a pacing metric, mirroring
    /// `RiskZone.dotColor`: the pastel on a dark bar, the deepened variant
    /// on a light one.
    func dotColor(menuBarIsDark: Bool) -> NSColor {
        switch self {
        case .chill: menuBarIsDark ? DS.Pastel.NS.green : DS.Pastel.NS.greenDeep
        case .onTrack: menuBarIsDark ? DS.Pastel.NS.blue : DS.Pastel.NS.blueDeep
        case .warning: menuBarIsDark ? DS.Pastel.NS.amber : DS.Pastel.NS.amberDeep
        case .hot: menuBarIsDark ? DS.Pastel.NS.coral : DS.Pastel.NS.coralDeep
        }
    }
}
