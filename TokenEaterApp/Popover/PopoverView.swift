import SwiftUI

/// The menu bar popover layout. Renders the metric rows and optional sections
/// `PopoverConfig` selects, in the configured order - see
/// `Shared/Models/PopoverConfig.swift` and `PopoverSectionView`. Width 340,
/// hairline-separated sections (`separator`, a solid `DS.Pastel.border` fill
/// rather than the near-invisible system `Divider()`), system material
/// background (see `StatusBarController.makePopoverPanel`), and semantic
/// `RiskZone` / `PacingZone` colors only - no hex, no raw opacity chrome.
struct PopoverView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var vendorStatusStore: VendorStatusStore

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeaderRow(worstZone: worstZone)

            separator

            if vendorStatusStore.isDegraded && vendorStatusStore.claudeStatus != nil {
                VendorStatusBanner()
                separator
            }

            if usageStore.hasError {
                PopoverErrorBanner()
                separator
            }

            metricsSection

            if popoverConfig.showSpend, let extra = usageStore.extraUsage, extra.isEnabled {
                separator
                PopoverSpendSection(extra: extra)
            }

            if popoverConfig.showTimestamp {
                separator
                PopoverTimestampRow()
            }

            // Unconditional: the footer always gets a separator above it,
            // whether or not the timestamp row (or any other optional
            // section) is showing.
            separator
            PopoverFooterToolbar()
        }
        .frame(width: 340)
    }

    /// Visible hairline between popover sections. Replaces the system
    /// `Divider()`, which reads as nearly invisible on the popover's
    /// translucent `.popover` material.
    private var separator: some View {
        Rectangle()
            .fill(DS.Pastel.border)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }

    private var metricsSection: some View {
        VStack(spacing: 10) {
            ForEach(metricRows) { row in
                PopoverMetricRowView(row: row)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Worst (highest-severity) `RiskZone` across every rendered metric row,
    /// used for the header's tinted status disc.
    private var worstZone: RiskZone {
        metricRows.map(\.zone).max(by: { $0.rank < $1.rank }) ?? .ok
    }

    // MARK: - Row building

    private var popoverConfig: PopoverConfig { settingsStore.display.popoverConfig }

    /// Metrics session/weekly/sonnet always count as "available" (the popover
    /// showed them unconditionally before this became configurable); Opus,
    /// Cowork, Fable and Design only count once the API has actually returned
    /// that bucket, same as `UsageStore.has*` always gated them.
    private var availableMetrics: Set<MetricID> {
        var available: Set<MetricID> = [.fiveHour, .sevenDay, .sonnet]
        if usageStore.hasOpus { available.insert(.opus) }
        if usageStore.hasCowork { available.insert(.cowork) }
        if usageStore.hasFable { available.insert(.fable) }
        if usageStore.hasDesign { available.insert(.design) }
        return available
    }

    /// The configured, visible, available metrics, in the user's chosen order.
    private var metricRows: [PopoverMetricRow] {
        popoverConfig.visibleMetrics(available: availableMetrics).compactMap(metricRow)
    }

    private func metricRow(for metric: MetricID) -> PopoverMetricRow? {
        let showPacing = popoverConfig.showPacing
        switch metric {
        case .fiveHour:
            return row(
                id: "session",
                label: String(localized: "metric.session"),
                pct: usageStore.fiveHourPct,
                resetDate: usageStore.lastUsage?.fiveHour?.resetsAtDate,
                windowDuration: 5 * 3600,
                resetText: usageStore.fiveHourReset,
                pacing: showPacing ? usageStore.fiveHourPacing : nil
            )
        case .sevenDay:
            return row(
                id: "weekly",
                label: String(localized: "metric.weekly"),
                pct: usageStore.sevenDayPct,
                resetDate: usageStore.lastUsage?.sevenDay?.resetsAtDate,
                windowDuration: 7 * 86_400,
                resetText: usageStore.sevenDayReset,
                pacing: showPacing ? usageStore.pacingResult : nil
            )
        case .opus:
            let resetDate = usageStore.lastUsage?.sevenDayOpus?.resetsAtDate
            return row(
                id: "opus",
                label: String(localized: "metric.opus"),
                pct: usageStore.opusPct,
                resetDate: resetDate,
                windowDuration: 7 * 86_400,
                resetText: ResetCountdownFormatter.weekly(from: resetDate).relative,
                pacing: nil
            )
        case .sonnet:
            return row(
                id: "sonnet",
                label: String(localized: "metric.sonnet"),
                pct: usageStore.sonnetPct,
                resetDate: usageStore.lastUsage?.sevenDaySonnet?.resetsAtDate,
                windowDuration: 7 * 86_400,
                resetText: usageStore.sonnetReset,
                pacing: nil
            )
        case .cowork:
            let resetDate = usageStore.lastUsage?.sevenDayCowork?.resetsAtDate
            return row(
                id: "cowork",
                label: String(localized: "metric.cowork"),
                pct: usageStore.coworkPct,
                resetDate: resetDate,
                windowDuration: 7 * 86_400,
                resetText: ResetCountdownFormatter.weekly(from: resetDate).relative,
                pacing: nil
            )
        case .fable:
            return row(
                id: "fable",
                label: String(localized: "metric.fable"),
                pct: usageStore.fablePct,
                resetDate: usageStore.lastUsage?.sevenDayFable?.resetsAtDate,
                windowDuration: 7 * 86_400,
                resetText: usageStore.fableReset,
                pacing: nil
            )
        case .design:
            return row(
                id: "design",
                label: String(localized: "metric.design"),
                pct: usageStore.designPct,
                resetDate: usageStore.lastUsage?.sevenDayDesign?.resetsAtDate,
                windowDuration: 7 * 86_400,
                resetText: usageStore.designReset,
                pacing: nil
            )
        // Not offered by `PopoverConfig` (extraCredits/pacing/status/reset are
        // their own sections or menu-bar-only) - never reached in practice.
        case .extraCredits, .sessionPacing, .weeklyPacing, .serviceStatus, .sessionReset:
            return nil
        }
    }

    private func row(
        id: String,
        label: String,
        pct: Int,
        resetDate: Date?,
        windowDuration: TimeInterval,
        resetText: String,
        pacing: PacingResult?
    ) -> PopoverMetricRow {
        PopoverMetricRow(
            id: id,
            label: label,
            pct: pct,
            zone: PopoverColors.riskZone(pct: pct, resetDate: resetDate, windowDuration: windowDuration, settings: settingsStore),
            resetText: resetText,
            pacing: pacing
        )
    }
}

// MARK: - Settings preview sample data

extension PopoverView {
    /// Sample metric rows for the Settings live preview - every metric in
    /// `MetricID.popoverDefaultOrder` gets a plausible value, spanning the
    /// ok/warning/critical zones, so every configured row stays visible in
    /// the preview regardless of the live account's actual data.
    static func sampleMetricRows(config: PopoverConfig, settingsStore: SettingsStore) -> [PopoverMetricRow] {
        let available = Set(MetricID.popoverDefaultOrder)
        return config.visibleMetrics(available: available).compactMap { metric in
            sampleRow(for: metric, showPacing: config.showPacing, settingsStore: settingsStore)
        }
    }

    private static let sampleValues: [MetricID: (pct: Int, resetText: String)] = [
        .fiveHour: (42, "2h13"),
        .sevenDay: (61, "3d 14h"),
        .opus: (15, "5d 2h"),
        .sonnet: (33, "4d 9h"),
        .cowork: (8, "6d 20h"),
        .fable: (71, "1d 8h"),
        .design: (24, "2d 22h"),
    ]

    private static func sampleRow(for metric: MetricID, showPacing: Bool, settingsStore: SettingsStore) -> PopoverMetricRow? {
        guard let sample = sampleValues[metric] else { return nil }
        let windowDuration: TimeInterval = metric == .fiveHour ? 5 * 3600 : 7 * 86_400
        let zone = PopoverColors.riskZone(pct: sample.pct, resetDate: nil, windowDuration: windowDuration, settings: settingsStore)
        let pacing: PacingResult? = {
            guard showPacing, metric == .fiveHour || metric == .sevenDay else { return nil }
            return PacingResult(
                delta: metric == .fiveHour ? 4 : -8,
                expectedUsage: 50,
                actualUsage: metric == .fiveHour ? 54 : 42,
                zone: metric == .fiveHour ? .warning : .onTrack,
                message: "",
                resetDate: nil
            )
        }()
        return PopoverMetricRow(id: metric.rawValue, label: metric.label, pct: sample.pct, zone: zone, resetText: sample.resetText, pacing: pacing)
    }
}

// MARK: - Row model

/// Not private: `PopoverSectionView`'s live preview reuses this and
/// `PopoverMetricRowView` directly via `PopoverView.sampleMetricRows(config:settingsStore:)`
/// so the preview stays pixel-identical to the real popover rows.
struct PopoverMetricRow: Identifiable {
    let id: String
    let label: String
    let pct: Int
    let zone: RiskZone
    let resetText: String
    /// Non-nil only for session/weekly, and only once `PacingCalculator` has
    /// enough data to project a pace. Its presence is what "shows" the chip -
    /// there is no separate visibility toggle left to gate it on.
    let pacing: PacingResult?
}

private extension RiskZone {
    /// ok < warning < critical, for reducing a set of zones to the worst one.
    var rank: Int {
        switch self {
        case .ok: 0
        case .warning: 1
        case .critical: 2
        }
    }
}

// MARK: - Header

private struct PopoverHeaderRow: View {
    @EnvironmentObject private var usageStore: UsageStore
    let worstZone: RiskZone

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(worstZone.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
            }

            HStack(spacing: 6) {
                Text("RaiUsage")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if usageStore.planType != .unknown {
                    Text(usageStore.planType.displayLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.Pastel.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(DS.Pastel.blue.opacity(0.12)))
                }
            }

            Spacer(minLength: 8)

            Button {
                Task { await usageStore.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(usageStore.isLoading)
            .help(String(localized: "contextmenu.refresh"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - Metric row (stacked: label/percent, full-width bar, reset/pacing)

struct PopoverMetricRowView: View {
    let row: PopoverMetricRow

    private var showsThirdLine: Bool { !row.resetText.isEmpty || row.pacing != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Text("\(row.pct)%")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Pastel.track)
                    Capsule()
                        .fill(row.zone.color)
                        .frame(width: geo.size.width * CGFloat(min(max(row.pct, 0), 100)) / 100)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 6)

            if showsThirdLine {
                HStack {
                    Text(row.resetText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    Spacer()

                    if let pacing = row.pacing {
                        Text("\(pacing.delta >= 0 ? "+" : "")\(Int(pacing.delta))%")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(pacing.zone.semanticColor)
                    }
                }
            }
        }
    }
}

// MARK: - Spend section (Extra Credits)

private struct PopoverSpendSection: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let extra: ExtraUsage

    private var used: Double { extra.usedCredits ?? 0 }
    private var limit: Double { extra.monthlyLimit ?? 0 }
    private var pct: Int { extra.percent }
    private var tint: Color { RiskZone.forPercent(pct, thresholds: settingsStore.thresholds).color }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "dashboard.extra.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pct)%")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            if limit > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Pastel.track)
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100)
                    }
                }
                .frame(height: 6)

                HStack(spacing: 4) {
                    Text(CurrencyFormatter.formatMinorUnits(used, currencyCode: extra.currency, locale: Locale(identifier: "en_US")))
                        .monospacedDigit()
                    Text(String(localized: "dashboard.extra.separator"))
                        .foregroundStyle(.tertiary)
                    Text(CurrencyFormatter.formatMinorUnits(limit, currencyCode: extra.currency, locale: Locale(identifier: "en_US")))
                        .monospacedDigit()
                    Spacer()
                    Text(String(localized: "dashboard.extra.monthly"))
                        .foregroundStyle(.tertiary)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "dashboard.extra.noLimit"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Timestamp

private struct PopoverTimestampRow: View {
    @EnvironmentObject private var usageStore: UsageStore

    @State private var lastUpdateText = ""
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(displayText)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .onAppear { refreshText() }
            .onReceive(timer) { _ in refreshText() }
            .onChange(of: usageStore.lastUpdate) { _, _ in refreshText() }
    }

    private var displayText: String {
        let text = lastUpdateText.isEmpty
            ? String(localized: "menubar.updated.never")
            : lastUpdateText
        return String(format: String(localized: "menubar.updated"), text)
    }

    private func refreshText() {
        if let date = usageStore.lastUpdate {
            lastUpdateText = date.formatted(.relative(presentation: .named))
        }
    }
}

// MARK: - Footer toolbar

private struct PopoverFooterToolbar: View {
    @EnvironmentObject private var usageStore: UsageStore

    var body: some View {
        HStack {
            toolbarButton(system: "arrow.clockwise", help: "contextmenu.refresh", disabled: usageStore.isLoading) {
                Task { await usageStore.refresh(force: true) }
            }
            Spacer()
            HStack(spacing: 14) {
                toolbarButton(system: "macwindow", help: "contextmenu.open") {
                    NotificationCenter.default.post(name: .openDashboard, object: nil)
                }
                toolbarButton(system: "gearshape.fill", help: "menubar.settings") {
                    NotificationCenter.default.post(name: .openDashboard, object: nil, userInfo: ["section": "settings"])
                }
            }
            // Detach quit from the utility pair, RaiDrive-style.
            Spacer().frame(width: 18)
            toolbarButton(system: "power", help: "menubar.quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func toolbarButton(
        system: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(disabled)
        .help(NSLocalizedString(help, comment: ""))
    }
}
