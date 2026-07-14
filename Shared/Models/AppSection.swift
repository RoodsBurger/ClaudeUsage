import Foundation

/// Top-level navigation in the window app. Three spaces -> Stats (dashboard),
/// History (JSONL usage over time), Settings (all configuration).
enum AppSpace: String, CaseIterable {
    case monitoring
    case history
    case settings

    var labelKey: String {
        switch self {
        case .monitoring: "sidebar.monitoring"
        case .history:    "sidebar.history"
        case .settings:   "sidebar.settings"
        }
    }

    var label: String { String(localized: String.LocalizationValue(labelKey)) }

    var iconName: String {
        switch self {
        case .monitoring: "gauge.high"
        case .history:    "clock.arrow.circlepath"
        case .settings:   "gearshape.fill"
        }
    }
}

/// Sub-sections inside the Settings space. Every configuration screen lives
/// here -> general preferences first, then display / pacing / notifications.
/// Order drives the sub-sidebar display.
enum SettingsSection: String, CaseIterable {
    case general
    case pacing
    case menuBar
    case popover
    case notifications

    var labelKey: String {
        switch self {
        case .general:       "sidebar.general"
        case .menuBar:       "sidebar.display"
        case .popover:       "sidebar.popover"
        case .pacing:        "sidebar.pacing"
        case .notifications: "sidebar.notifications"
        }
    }

    var label: String { String(localized: String.LocalizationValue(labelKey)) }

    var iconName: String {
        switch self {
        case .general:       "slider.horizontal.3"
        case .menuBar:       "menubar.rectangle"
        case .popover:       "rectangle.inset.filled"
        case .pacing:        "speedometer"
        case .notifications: "bell.fill"
        }
    }
}

/// Parsed navigation target sent via `Notification.Name.navigateToSection`.
struct NavigationTarget: Equatable {
    let space: AppSpace
    let settingsSection: SettingsSection?

    init(space: AppSpace, settingsSection: SettingsSection? = nil) {
        self.space = space
        self.settingsSection = settingsSection
    }

    /// Parse from a payload string. Recognised values :
    /// - `"monitoring"`, `"history"`, `"settings"` -> AppSpace only
    /// - `"settings.general"`, `"settings.display"`, ... -> space + sub-section
    static func parse(_ payload: String) -> NavigationTarget? {
        // Nested "settings.xxx" form.
        if payload.hasPrefix("settings.") {
            let sub = String(payload.dropFirst("settings.".count))
            if sub.isEmpty { return NavigationTarget(space: .settings) }
            if let section = SettingsSection(rawValue: sub) {
                return NavigationTarget(space: .settings, settingsSection: section)
            }
            return nil
        }
        // Top-level space.
        if let space = AppSpace(rawValue: payload) {
            return NavigationTarget(space: space)
        }
        return nil
    }
}
