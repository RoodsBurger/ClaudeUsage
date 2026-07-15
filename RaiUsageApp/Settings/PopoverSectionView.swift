import SwiftUI

/// Settings sub-section for the popover: which metric rows show, in what
/// order, and which optional sections (pacing chips, spend, timestamp) are
/// on. Mirrors `MenuBarSectionView`'s idiom - native `Form`, live preview,
/// binds directly to `settingsStore.display.popoverConfig` (a genuinely
/// stored `@Published` property, never a computed one) so element-level
/// bindings stay AttributeGraph-safe. Independent of `MenuBarConfig` - no
/// shared storage, no coupling.
struct PopoverSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    /// Read-only, for the enterprise-aware spend-section label.
    @EnvironmentObject private var usageStore: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader(
                String(localized: "sidebar.popover"),
                subtitle: String(localized: "sidebar.popover.subtitle")
            )

            Form {
                previewSection
                metricsSection
                sectionsSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { ensureActivityRows() }
        .onChange(of: usageStore.planType) { _, _ in ensureActivityRows() }
    }

    private var isEnterprise: Bool { usageStore.planType == .enterprise }

    /// On enterprise, migrates a saved config that predates the activity
    /// metrics: appends them (hidden, opt-in) to `metricOrder` so they appear
    /// in the list below and reorder like any other row. One-shot per metric -
    /// a config that already contains them is untouched. No-op elsewhere, so
    /// personal configs never change.
    private func ensureActivityRows() {
        guard isEnterprise else { return }
        var config = settingsStore.display.popoverConfig
        var changed = false
        for metric in [MetricID.fiveHourActivity, .sevenDayActivity] where !config.metricOrder.contains(metric) {
            config.metricOrder.append(metric)
            config.hiddenMetrics.insert(metric)
            changed = true
        }
        if changed { settingsStore.display.popoverConfig = config }
    }

    // MARK: - Live preview

    private var previewSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    PopoverPreviewCard(config: settingsStore.display.popoverConfig)
                    Text(String(localized: "settings.popover.preview"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Metrics

    /// The rows the list renders: the saved order, minus the enterprise-only
    /// activity metrics on personal plans (they add no value where the API
    /// windows exist - see `MetricID.menuBarPinnable(isEnterprise:)`).
    private var displayedMetricOrder: [MetricID] {
        settingsStore.display.popoverConfig.metricOrder.filter { isEnterprise || !$0.isActivity }
    }

    private var metricsSection: some View {
        Section {
            List {
                ForEach(displayedMetricOrder, id: \.self) { metric in
                    metricRow(metric)
                }
                .onMove(perform: moveMetrics)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: rowListHeight)

            Text(String(localized: "settings.popover.metrics.footer"))
                .settingsHelperCaption()
        } header: {
            Text(String(localized: "settings.popover.metrics.header"))
        }
    }

    /// Applies a drag-reorder expressed in displayed-list indices. On
    /// enterprise the displayed list IS `metricOrder`, so this is the plain
    /// move; on a personal plan with a stale enterprise config, the filtered
    /// activity entries re-append after the reordered visible rows.
    private func moveMetrics(from source: IndexSet, to destination: Int) {
        var visible = displayedMetricOrder
        visible.move(fromOffsets: source, toOffset: destination)
        let filteredOut = settingsStore.display.popoverConfig.metricOrder.filter { !visible.contains($0) }
        settingsStore.display.popoverConfig.metricOrder = visible + filteredOut
    }

    private var rowListHeight: CGFloat {
        let rows = displayedMetricOrder.count
        return min(CGFloat(max(rows, 1)) * 32 + 8, 240)
    }

    private func metricRow(_ metric: MetricID) -> some View {
        let config = settingsStore.display.popoverConfig
        let isVisible = config.isVisible(metric)
        return HStack(spacing: 10) {
            Button {
                toggleVisibility(metric)
            } label: {
                Image(systemName: isVisible ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isVisible ? DS.Pastel.green : .secondary)
            }
            .buttonStyle(.plain)

            Text(metric.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isVisible ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    /// Every metric can be hidden, session and weekly included - the popover
    /// collapses its metrics block when the list ends up empty.
    private func toggleVisibility(_ metric: MetricID) {
        var config = settingsStore.display.popoverConfig
        config.setVisible(metric, !config.isVisible(metric))
        settingsStore.display.popoverConfig = config
    }

    // MARK: - Sections

    /// Enterprise renames the spend section to "Organization usage".
    private var spendToggleLabel: String {
        usageStore.planType == .enterprise
            ? String(localized: "metric.orgUsage")
            : String(localized: "settings.popover.showSpend")
    }

    private var sectionsSection: some View {
        Section {
            Toggle(String(localized: "settings.popover.showPacing"), isOn: $settingsStore.display.popoverConfig.showPacing)
                .tint(DS.Pastel.green)
            Toggle(spendToggleLabel, isOn: $settingsStore.display.popoverConfig.showSpend)
                .tint(DS.Pastel.green)
            Toggle(String(localized: "settings.popover.showTimestamp"), isOn: $settingsStore.display.popoverConfig.showTimestamp)
                .tint(DS.Pastel.green)

            Text(String(localized: "settings.popover.sections.footer"))
                .settingsHelperCaption()
        } header: {
            Text(String(localized: "settings.popover.sections.header"))
        }
    }
}

// MARK: - Live preview card

/// Faithful, static mockup of the real popover: reuses `PopoverMetricRow` /
/// `PopoverMetricRowView` for the configurable rows (so they're pixel-identical
/// to the real popover), with small self-contained header/spend/footer mockups
/// (the timestamp lives in the footer, mirroring `PopoverFooterToolbar`) instead
/// of the live-store-bound `PopoverView` subviews - a settings preview shouldn't
/// host a live "Quit" button or read the real account's data.
private struct PopoverPreviewCard: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var usageStore: UsageStore
    let config: PopoverConfig

    private var rows: [PopoverRowEntry] {
        PopoverView.sampleRows(
            config: config,
            settingsStore: settingsStore,
            isEnterprise: usageStore.planType == .enterprise
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            // Mirrors the real popover: the metrics block collapses entirely
            // when every row is toggled off.
            if !rows.isEmpty {
                Divider()
                VStack(spacing: 10) {
                    ForEach(rows) { entry in
                        switch entry {
                        case .metric(let row):
                            PopoverMetricRowView(row: row)
                        case .activity(let row):
                            PopoverActivityRowView(row: row)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }

            if config.showSpend {
                Divider()
                spendMock
            }

            Divider()
            footerMock
        }
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Palette.glassBorderLo, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RiskZone.ok.color.opacity(0.15))
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
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var spendMock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(usageStore.planType == .enterprise
                     ? String(localized: "metric.orgUsage")
                     : String(localized: "dashboard.extra.title"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("28%")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(RiskZone.ok.color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Pastel.track)
                    Capsule()
                        .fill(RiskZone.ok.color)
                        .frame(width: geo.size.width * 0.28)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // Mirrors the real `PopoverFooterToolbar`: leading refresh (+ timestamp when
    // enabled), then a trailing utility group with a hairline before quit.
    private var footerMock: some View {
        HStack {
            footerIcon("arrow.clockwise")
            if config.showTimestamp {
                Text(String(localized: "settings.popover.preview.timestamp"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
            Spacer()
            HStack(spacing: 12) {
                footerIcon("macwindow")
                footerIcon("gearshape.fill")
                Rectangle()
                    .fill(DS.Pastel.border)
                    .frame(width: 1, height: 16)
                footerIcon("power")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func footerIcon(_ system: String) -> some View {
        Image(systemName: system)
            .font(.system(size: 11, weight: .medium))
            .frame(width: 20, height: 20)
            .foregroundStyle(.secondary)
    }
}
