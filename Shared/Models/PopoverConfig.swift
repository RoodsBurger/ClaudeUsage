import Foundation

/// Full configuration for the popover's metric rows and optional sections.
/// Persisted as JSON in UserDefaults under `popoverConfig` by
/// `DisplaySettingsStore`; a decode failure (or a fresh install) falls back to
/// `PopoverConfig()`. Independent of `MenuBarConfig` - separate model, separate
/// storage key, no shared state.
struct PopoverConfig: Codable, Equatable, Sendable {
    /// Ordered metric preference. A metric renders only if it's BOTH listed
    /// here (visible) AND present in the API response (`UsageStore.has*`).
    /// Order here is the render order. Metrics absent from this list are hidden.
    var metricOrder: [MetricID]
    var hiddenMetrics: Set<MetricID>
    /// Inline pacing chips under the session/weekly rows.
    var showPacing: Bool
    /// Extra Credits spend section, still also gated on `extraUsage.isEnabled`.
    var showSpend: Bool
    /// "Updated 2m ago" row.
    var showTimestamp: Bool

    init(
        metricOrder: [MetricID] = MetricID.popoverDefaultOrder,
        hiddenMetrics: Set<MetricID> = [],
        showPacing: Bool = true,
        showSpend: Bool = true,
        showTimestamp: Bool = true
    ) {
        self.metricOrder = metricOrder
        self.hiddenMetrics = hiddenMetrics
        self.showPacing = showPacing
        self.showSpend = showSpend
        self.showTimestamp = showTimestamp
    }

    private enum CodingKeys: String, CodingKey {
        case metricOrder, hiddenMetrics, showPacing, showSpend, showTimestamp
    }

    /// Missing keys fall back to the matching field of a fresh default config,
    /// so adding a field later (or a partially-written JSON blob) never fails
    /// the whole decode - only decoder-level corruption does, and that's
    /// handled by the caller falling back to `PopoverConfig()` entirely.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PopoverConfig()
        metricOrder = try container.decodeIfPresent([MetricID].self, forKey: .metricOrder) ?? defaults.metricOrder
        hiddenMetrics = try container.decodeIfPresent(Set<MetricID>.self, forKey: .hiddenMetrics) ?? defaults.hiddenMetrics
        showPacing = try container.decodeIfPresent(Bool.self, forKey: .showPacing) ?? defaults.showPacing
        showSpend = try container.decodeIfPresent(Bool.self, forKey: .showSpend) ?? defaults.showSpend
        showTimestamp = try container.decodeIfPresent(Bool.self, forKey: .showTimestamp) ?? defaults.showTimestamp
    }

    /// The ordered, visible, API-available metrics to render.
    func visibleMetrics(available: Set<MetricID>) -> [MetricID] {
        metricOrder.filter { !hiddenMetrics.contains($0) && available.contains($0) }
    }

    /// False only for `.fiveHour`/`.sevenDay` when hiding it would leave the
    /// other one hidden too - the popover always keeps at least session or
    /// weekly visible. Every other metric can always be hidden.
    func canHide(_ metric: MetricID) -> Bool {
        guard metric == .fiveHour || metric == .sevenDay else { return true }
        let other: MetricID = metric == .fiveHour ? .sevenDay : .fiveHour
        return !hiddenMetrics.contains(other)
    }
}

extension MetricID {
    /// Metrics the popover can show, in their default render order.
    static var popoverDefaultOrder: [MetricID] {
        [.fiveHour, .sevenDay, .opus, .sonnet, .cowork, .fable, .design]
    }
}
