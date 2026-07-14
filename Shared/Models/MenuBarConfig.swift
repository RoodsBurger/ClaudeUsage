import Foundation

/// How a pin's leading label renders: the metric's SF Symbol, its short text
/// label ("5h", "7d", ...), or nothing.
enum MetricPrefixStyle: String, Codable, CaseIterable, Sendable { case symbol, shortLabel, none }

/// How a pin's numeric value renders. `dollars` only applies to the Extra
/// Credits pin - every other metric falls back to `percentUsed` if it's ever
/// set (defensive; the settings UI never offers it for other metrics).
enum MetricValueStyle: String, Codable, CaseIterable, Sendable { case percentUsed, percentRemaining, dollars }

/// Which pins render in the status item.
/// - `all`: every visible pin, separator-joined.
/// - `highestRisk`: only the pin whose current zone is riskiest (ties keep
///   pinned order).
/// - `rotate`: one pin at a time, advancing on a timer.
enum MenuBarDisplayMode: String, Codable, CaseIterable, Sendable { case all, highestRisk, rotate }

/// `risk` colors every value by its `RiskZone`/`PacingZone`; `monochrome`
/// renders everything in the system label color.
enum MenuBarColorMode: String, Codable, CaseIterable, Sendable { case monochrome, risk }

/// One pinned metric's rendering options.
struct PinnedMetricConfig: Codable, Equatable, Identifiable, Sendable {
    var id: MetricID
    var prefix: MetricPrefixStyle
    var value: MetricValueStyle
    var showCountdown: Bool

    init(
        id: MetricID,
        prefix: MetricPrefixStyle = .shortLabel,
        value: MetricValueStyle = .percentUsed,
        showCountdown: Bool = false
    ) {
        self.id = id
        self.prefix = prefix
        self.value = value
        self.showCountdown = showCountdown
    }

    private enum CodingKeys: String, CodingKey {
        case id, prefix, value, showCountdown
    }

    /// Missing keys fall back to the same defaults as the memberwise init, so
    /// a config saved by an older build of this struct (fewer fields) still
    /// decodes cleanly instead of failing the whole `MenuBarConfig` decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(MetricID.self, forKey: .id)
        prefix = try container.decodeIfPresent(MetricPrefixStyle.self, forKey: .prefix) ?? .shortLabel
        value = try container.decodeIfPresent(MetricValueStyle.self, forKey: .value) ?? .percentUsed
        showCountdown = try container.decodeIfPresent(Bool.self, forKey: .showCountdown) ?? false
    }
}

/// Full configuration for the menu-bar status item. Persisted as JSON in
/// UserDefaults under `menuBarConfig` by `DisplaySettingsStore`; a decode
/// failure (or a fresh install) falls back to `MenuBarConfig()`.
struct MenuBarConfig: Codable, Equatable, Sendable {
    var pinned: [PinnedMetricConfig]
    var displayMode: MenuBarDisplayMode
    var rotateSeconds: Int
    var colorMode: MenuBarColorMode
    var showIcon: Bool
    var separator: String
    var fixedWidth: Bool

    init(
        pinned: [PinnedMetricConfig] = [.init(id: .fiveHour), .init(id: .sevenDay)],
        displayMode: MenuBarDisplayMode = .all,
        rotateSeconds: Int = 5,
        colorMode: MenuBarColorMode = .risk,
        showIcon: Bool = true,
        separator: String = "\u{00B7}",
        fixedWidth: Bool = false
    ) {
        self.pinned = pinned
        self.displayMode = displayMode
        self.rotateSeconds = rotateSeconds
        self.colorMode = colorMode
        self.showIcon = showIcon
        self.separator = separator
        self.fixedWidth = fixedWidth
    }

    private enum CodingKeys: String, CodingKey {
        case pinned, displayMode, rotateSeconds, colorMode, showIcon, separator, fixedWidth
    }

    /// Missing keys fall back to the matching field of a fresh default config,
    /// so adding a field later (or a partially-written JSON blob) never fails
    /// the whole decode - only decoder-level corruption (not valid JSON, or a
    /// `pinned` entry with no `id`) does, and that's handled by the caller
    /// falling back to `MenuBarConfig()` entirely.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MenuBarConfig()
        pinned = try container.decodeIfPresent([PinnedMetricConfig].self, forKey: .pinned) ?? defaults.pinned
        displayMode = try container.decodeIfPresent(MenuBarDisplayMode.self, forKey: .displayMode) ?? defaults.displayMode
        rotateSeconds = try container.decodeIfPresent(Int.self, forKey: .rotateSeconds) ?? defaults.rotateSeconds
        colorMode = try container.decodeIfPresent(MenuBarColorMode.self, forKey: .colorMode) ?? defaults.colorMode
        showIcon = try container.decodeIfPresent(Bool.self, forKey: .showIcon) ?? defaults.showIcon
        separator = try container.decodeIfPresent(String.self, forKey: .separator) ?? defaults.separator
        fixedWidth = try container.decodeIfPresent(Bool.self, forKey: .fixedWidth) ?? defaults.fixedWidth
    }

    /// First-run defaults for enterprise plans, where the 5h/weekly windows
    /// are typically untracked and the org spend pool is the metric that
    /// matters: the Extra Credits pin in dollars (prefixed "Org" via the
    /// enterprise short label) plus Design. Applied only when no config was
    /// ever saved - see `DisplaySettingsStore.applyEnterpriseDefaultsIfFirstRun`.
    static var enterpriseDefault: MenuBarConfig {
        MenuBarConfig(pinned: [
            .init(id: .extraCredits, value: .dollars),
            .init(id: .design),
        ])
    }
}

extension MetricID {
    /// Metrics selectable in the menu-bar "add a pin" menu. `sessionReset`
    /// is excluded - it's not an independent pin in the new engine, its old
    /// role is now the `showCountdown` flag on any percentage pin. `opus` and
    /// `cowork` are excluded too - they're popover-only (see `MetricID.opus`),
    /// `MenuBarRenderer` has no percentage/reset wiring for them.
    static var menuBarPinnable: [MetricID] {
        allCases.filter { $0 != .sessionReset && $0 != .opus && $0 != .cowork }
    }

    /// SF Symbol shown when a pin's `prefix` is `.symbol`.
    var menuBarSymbolName: String {
        switch self {
        case .fiveHour:      return "bolt.fill"
        case .sevenDay:      return "calendar"
        case .sonnet:        return "quote.opening"
        case .design:        return "paintbrush.pointed.fill"
        case .fable:         return "books.vertical.fill"
        case .extraCredits:  return "creditcard.fill"
        case .sessionPacing, .weeklyPacing: return "speedometer"
        case .serviceStatus: return "dot.radiowaves.left.and.right"
        case .sessionReset:  return "clock.arrow.circlepath"
        case .opus:          return "crown.fill"
        case .cowork:        return "person.2.fill"
        }
    }
}
