import SwiftUI

/// The one and only menu bar popover layout. No variants, no drag-reorder
/// editor: it renders session, weekly, and whatever per-model metrics the API
/// returned, in a fixed order. Width 340, flat `Divider()`-separated sections,
/// system material background (see `StatusBarController.setupPopover`), and
/// semantic `RiskZone` / `PacingZone` colors only - no hex, no raw opacity chrome.
struct PopoverView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var vendorStatusStore: VendorStatusStore

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeaderRow(worstZone: worstZone)

            Divider()

            if vendorStatusStore.isDegraded && vendorStatusStore.claudeStatus != nil {
                VendorStatusBanner()
                Divider()
            }

            if usageStore.hasError {
                PopoverErrorBanner()
                Divider()
            }

            metricsSection

            if let extra = usageStore.extraUsage, extra.isEnabled {
                Divider()
                PopoverSpendSection(extra: extra)
            }

            Divider()
            PopoverTimestampRow()

            Divider()
            PopoverFooterToolbar()
        }
        .frame(width: 340)
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

    /// Session, weekly, then per-model rows in `UsageStore.has*` order.
    /// Nothing is user-configurable: a row appears exactly when the API says
    /// the metric exists.
    private var metricRows: [PopoverMetricRow] {
        var rows: [PopoverMetricRow] = [
            row(
                id: "session",
                label: String(localized: "metric.session"),
                pct: usageStore.fiveHourPct,
                resetDate: usageStore.lastUsage?.fiveHour?.resetsAtDate,
                windowDuration: 5 * 3600,
                resetText: usageStore.fiveHourReset,
                pacing: usageStore.fiveHourPacing
            ),
            row(
                id: "weekly",
                label: String(localized: "metric.weekly"),
                pct: usageStore.sevenDayPct,
                resetDate: usageStore.lastUsage?.sevenDay?.resetsAtDate,
                windowDuration: 7 * 86_400,
                resetText: usageStore.sevenDayReset,
                pacing: usageStore.pacingResult
            ),
        ]

        if usageStore.hasOpus {
            let resetDate = usageStore.lastUsage?.sevenDayOpus?.resetsAtDate
            rows.append(row(
                id: "opus",
                label: String(localized: "metric.opus"),
                pct: usageStore.opusPct,
                resetDate: resetDate,
                windowDuration: 7 * 86_400,
                resetText: ResetCountdownFormatter.weekly(from: resetDate).relative,
                pacing: nil
            ))
        }

        rows.append(row(
            id: "sonnet",
            label: String(localized: "metric.sonnet"),
            pct: usageStore.sonnetPct,
            resetDate: usageStore.lastUsage?.sevenDaySonnet?.resetsAtDate,
            windowDuration: 7 * 86_400,
            resetText: usageStore.sonnetReset,
            pacing: nil
        ))

        if usageStore.hasCowork {
            let resetDate = usageStore.lastUsage?.sevenDayCowork?.resetsAtDate
            rows.append(row(
                id: "cowork",
                label: String(localized: "metric.cowork"),
                pct: usageStore.coworkPct,
                resetDate: resetDate,
                windowDuration: 7 * 86_400,
                resetText: ResetCountdownFormatter.weekly(from: resetDate).relative,
                pacing: nil
            ))
        }

        if usageStore.hasFable {
            rows.append(row(
                id: "fable",
                label: String(localized: "metric.fable"),
                pct: usageStore.fablePct,
                resetDate: usageStore.lastUsage?.sevenDayFable?.resetsAtDate,
                windowDuration: 7 * 86_400,
                resetText: usageStore.fableReset,
                pacing: nil
            ))
        }

        if usageStore.hasDesign {
            rows.append(row(
                id: "design",
                label: String(localized: "metric.design"),
                pct: usageStore.designPct,
                resetDate: usageStore.lastUsage?.sevenDayDesign?.resetsAtDate,
                windowDuration: 7 * 86_400,
                resetText: usageStore.designReset,
                pacing: nil
            ))
        }

        return rows
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

// MARK: - Row model

private struct PopoverMetricRow: Identifiable {
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
                Image(systemName: "gauge.high")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(worstZone.color)
                    .symbolEffect(.pulse, isActive: usageStore.isLoading)
            }

            HStack(spacing: 6) {
                Text("TokenEater")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if usageStore.planType != .unknown {
                    Text(usageStore.planType.displayLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.12)))
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

// MARK: - Metric row + inline pacing chip

private struct PopoverMetricRowView: View {
    let row: PopoverMetricRow

    private static let labelWidth: CGFloat = 52
    private static let pctWidth: CGFloat = 34
    private static let resetWidth: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(row.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.labelWidth, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Pastel.track)
                        Capsule()
                            .fill(row.zone.color)
                            .frame(width: geo.size.width * CGFloat(min(max(row.pct, 0), 100)) / 100)
                    }
                }
                .frame(height: 6)

                Text("\(row.pct)%")
                    .font(.callout)
                    .monospacedDigit()
                    .frame(width: Self.pctWidth, alignment: .trailing)

                Text(row.resetText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: Self.resetWidth, alignment: .trailing)
            }

            if let pacing = row.pacing {
                PopoverPacingChip(pacing: pacing)
                    .padding(.leading, Self.labelWidth + 10)
            }
        }
    }
}

private struct PopoverPacingChip: View {
    let pacing: PacingResult

    var body: some View {
        HStack(spacing: 8) {
            PacingBar(
                actual: pacing.actualUsage,
                expected: pacing.expectedUsage,
                zone: pacing.zone,
                gradient: PopoverColors.zoneGradient(pacing.zone),
                compact: true
            )
            Text("\(pacing.delta >= 0 ? "+" : "")\(Int(pacing.delta))%")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(pacing.zone.semanticColor)
                .frame(minWidth: 32, alignment: .trailing)
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
        HStack(spacing: 0) {
            toolbarButton(system: "arrow.clockwise", help: "contextmenu.refresh", disabled: usageStore.isLoading) {
                Task { await usageStore.refresh(force: true) }
            }
            Spacer()
            toolbarButton(system: "macwindow", help: "contextmenu.open") {
                NotificationCenter.default.post(name: .openDashboard, object: nil)
            }
            Spacer()
            toolbarButton(system: "gearshape.fill", help: "menubar.settings") {
                NotificationCenter.default.post(name: .openDashboard, object: nil, userInfo: ["section": "settings"])
            }
            Spacer()
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
