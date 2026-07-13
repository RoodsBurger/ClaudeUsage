import Foundation

/// User-configured warning/critical percentages for threshold-mode gauge
/// coloring (used when Smart Color is off). See `RiskZone.forPercent(_:thresholds:)`.
struct UsageThresholds: Codable, Equatable {
    var warningPercent: Int
    var criticalPercent: Int

    static let `default` = UsageThresholds(warningPercent: 60, criticalPercent: 85)
}
