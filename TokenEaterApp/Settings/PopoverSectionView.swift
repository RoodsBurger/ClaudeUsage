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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
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

    private var metricsSection: some View {
        Section {
            List {
                ForEach(settingsStore.display.popoverConfig.metricOrder, id: \.self) { metric in
                    metricRow(metric)
                }
                .onMove { source, destination in
                    settingsStore.display.popoverConfig.metricOrder.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: rowListHeight)
        } header: {
            Text(String(localized: "settings.popover.metrics.header"))
        } footer: {
            Text(String(localized: "settings.popover.metrics.footer"))
        }
    }

    private var rowListHeight: CGFloat {
        let rows = settingsStore.display.popoverConfig.metricOrder.count
        return min(CGFloat(max(rows, 1)) * 32 + 8, 240)
    }

    private func metricRow(_ metric: MetricID) -> some View {
        let config = settingsStore.display.popoverConfig
        let isVisible = !config.hiddenMetrics.contains(metric)
        let locked = isVisible && !config.canHide(metric)
        return HStack(spacing: 10) {
            Button {
                toggleVisibility(metric)
            } label: {
                Image(systemName: isVisible ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isVisible ? DS.Palette.accentSettings : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(locked)
            .help(locked ? String(localized: "settings.popover.metrics.lastVisible") : "")

            Text(metric.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isVisible ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    /// At-least-one guard lives on the model (`PopoverConfig.canHide`) - this
    /// just calls it before flipping `hiddenMetrics`.
    private func toggleVisibility(_ metric: MetricID) {
        var config = settingsStore.display.popoverConfig
        if config.hiddenMetrics.contains(metric) {
            config.hiddenMetrics.remove(metric)
        } else {
            guard config.canHide(metric) else { return }
            config.hiddenMetrics.insert(metric)
        }
        settingsStore.display.popoverConfig = config
    }

    // MARK: - Sections

    private var sectionsSection: some View {
        Section {
            Toggle(String(localized: "settings.popover.showPacing"), isOn: $settingsStore.display.popoverConfig.showPacing)
            Toggle(String(localized: "settings.popover.showSpend"), isOn: $settingsStore.display.popoverConfig.showSpend)
            Toggle(String(localized: "settings.popover.showTimestamp"), isOn: $settingsStore.display.popoverConfig.showTimestamp)
        } header: {
            Text(String(localized: "settings.popover.sections.header"))
        } footer: {
            Text(String(localized: "settings.popover.sections.footer"))
        }
    }
}

// MARK: - Live preview card

/// Faithful, static mockup of the real popover: reuses `PopoverMetricRow` /
/// `PopoverMetricRowView` for the configurable rows (so they're pixel-identical
/// to the real popover), with small self-contained header/spend/timestamp/footer
/// mockups instead of the live-store-bound `PopoverView` subviews - a settings
/// preview shouldn't host a live "Quit" button or read the real account's data.
private struct PopoverPreviewCard: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    let config: PopoverConfig

    private var rows: [PopoverMetricRow] {
        PopoverView.sampleMetricRows(config: config, settingsStore: settingsStore)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            VStack(spacing: 10) {
                ForEach(rows) { row in
                    PopoverMetricRowView(row: row)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if config.showSpend {
                Divider()
                spendMock
            }
            if config.showTimestamp {
                Divider()
                Text(String(localized: "settings.popover.preview.timestamp"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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
                Image(systemName: "gauge.high")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RiskZone.ok.color)
            }
            Text("TokenEater")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var spendMock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "dashboard.extra.title"))
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

    private var footerMock: some View {
        HStack(spacing: 0) {
            ForEach(["arrow.clockwise", "macwindow", "gearshape.fill", "power"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
