import SwiftUI

/// Settings sub-section for the menu bar: which metrics are pinned, in what
/// order, how each one renders (icon/label prefix, percent-used vs percent-
/// remaining vs dollars, optional countdown), the overall display mode
/// (all / highest-risk / rotate), and the appearance knobs (color mode, show
/// icon, separator, fixed width). First native `Form` section in the app -
/// binds directly to `settingsStore.display.menuBarConfig` (a genuinely
/// stored `@Published` property, never a computed one) so element-level
/// bindings via `ForEach($...)` stay AttributeGraph-safe.
struct MenuBarSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    /// Read-only, for enterprise-aware labels (Extra Credits -> "Organization
    /// usage" / "Org") in the pin rows, add-menu, and the live preview.
    @EnvironmentObject private var usageStore: UsageStore

    /// Local buffer for the separator field only - it needs length clamping
    /// (1-2 chars) before writing back, which a direct binding can't express.
    @State private var separatorInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader(
                String(localized: "sidebar.display"),
                subtitle: String(localized: "sidebar.display.subtitle")
            ) {
                ClickChip(
                    label: String(localized: "settings.menubar.toggle"),
                    icon: settingsStore.showMenuBar ? "checkmark" : "eye.slash",
                    isActive: settingsStore.showMenuBar,
                    accent: DS.Pastel.green,
                    style: .compact
                ) {
                    settingsStore.showMenuBar.toggle()
                }
            }

            Form {
                previewSection
                pinnedMetricsSection
                displaySection
                appearanceSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { separatorInput = settingsStore.display.menuBarConfig.separator }
        .onChange(of: settingsStore.display.menuBarConfig.separator) { _, new in
            if separatorInput != new { separatorInput = new }
        }
        .onChange(of: separatorInput) { _, new in
            let clamped = String(new.prefix(2))
            if clamped != new { separatorInput = clamped }
            if !clamped.isEmpty, settingsStore.display.menuBarConfig.separator != clamped {
                settingsStore.display.menuBarConfig.separator = clamped
            }
        }
    }

    // MARK: - Live preview

    private var previewSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    // renderUncached: this preview's RenderData deliberately
                    // forces hasConfig/hasError, so it must not overwrite the
                    // shared cache the real status item's render(_:) relies on.
                    // Zero pins yields the template logo (icon-only status
                    // item); template mode + white tint keeps that glyph
                    // visible on the dark capsule, mirroring the menu bar.
                    let image = MenuBarRenderer.renderUncached(previewData)
                    Image(nsImage: image)
                        .renderingMode(image.isTemplate ? .template : .original)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.85)))
                        // The rendered image resolves semantic NSColors (labelColor,
                        // systemGreen, ...) against the current appearance. Force dark
                        // here so its text stays legible on the capsule's dark fill
                        // regardless of the window's actual (system-following) appearance.
                        .colorScheme(.dark)
                    Text(String(localized: "settings.menubar.preview"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    /// Sample-driven (never live UsageStore data) so every configured pin is
    /// always visible - live data would silently drop pins whenever a bucket
    /// is missing (fresh install, auth error), misleading exactly when users
    /// first configure the app. Only the settings being edited flow through.
    private var previewData: MenuBarRenderer.RenderData {
        .sample(
            config: settingsStore.display.menuBarConfig,
            thresholds: settingsStore.thresholds,
            smartColorEnabled: settingsStore.smartColorEnabled,
            smartColorProfile: settingsStore.smartColorProfile,
            pacingMargin: Double(settingsStore.pacingMargin),
            resetDisplayFormat: settingsStore.resetDisplayFormat,
            sessionPacingDisplayMode: settingsStore.sessionPacingDisplayMode,
            weeklyPacingDisplayMode: settingsStore.weeklyPacingDisplayMode,
            isEnterprise: usageStore.planType == .enterprise
        )
    }

    // MARK: - Pinned metrics

    private var pinnedMetricsSection: some View {
        Section {
            List {
                ForEach($settingsStore.display.menuBarConfig.pinned) { $pin in
                    pinnedRow(pin: $pin)
                }
                .onMove { source, destination in
                    settingsStore.display.menuBarConfig.pinned.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: rowListHeight)

            addMetricMenu
        } header: {
            Text(String(localized: "settings.metrics.pinned"))
        } footer: {
            Text(String(localized: "settings.metrics.pinned.footer"))
        }
    }

    private var rowListHeight: CGFloat {
        let rows = settingsStore.display.menuBarConfig.pinned.count
        return min(CGFloat(max(rows, 1)) * 40 + 8, 280)
    }

    private func pinnedRow(pin: Binding<PinnedMetricConfig>) -> some View {
        let metric = pin.wrappedValue.id
        return HStack(spacing: 10) {
            Image(systemName: metric.menuBarSymbolName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(metric.label(planType: usageStore.planType))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(minWidth: 60, alignment: .leading)

            Picker(String(localized: "settings.menubar.prefix"), selection: pin.prefix) {
                ForEach(MetricPrefixStyle.allCases, id: \.self) { style in
                    Text(style.localizedLabel).tag(style)
                }
            }
            .labelsHidden()
            .frame(width: 90)

            if supportsValueStyle(metric) {
                Picker(String(localized: "settings.menubar.value"), selection: pin.value) {
                    ForEach(valueStyles(for: metric), id: \.self) { style in
                        Text(style.localizedLabel).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            if supportsCountdown(metric) {
                Toggle(String(localized: "settings.menubar.countdown"), isOn: pin.showCountdown)
                    .toggleStyle(.checkbox)
                    .tint(DS.Pastel.green)
                    .labelsHidden()
                    .help(String(localized: "settings.menubar.countdown"))
            }

            Spacer(minLength: 0)

            Button {
                removePin(metric)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "settings.menubar.removePin"))
        }
        .padding(.vertical, 2)
    }

    private var availableToAdd: [MetricID] {
        let pinnedIDs = Set(settingsStore.display.menuBarConfig.pinned.map(\.id))
        return MetricID.menuBarPinnable.filter { !pinnedIDs.contains($0) }
    }

    private var addMetricMenu: some View {
        Menu {
            ForEach(availableToAdd, id: \.self) { metric in
                Button(metric.label(planType: usageStore.planType)) {
                    settingsStore.display.menuBarConfig.pinned.append(.init(id: metric))
                }
            }
        } label: {
            Label(String(localized: "settings.menubar.addPin"), systemImage: "plus.circle")
        }
        .disabled(availableToAdd.isEmpty)
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 160)
    }

    /// Every pin is removable - zero pins renders the status item icon-only.
    private func removePin(_ metric: MetricID) {
        settingsStore.display.menuBarConfig.pinned.removeAll { $0.id == metric }
    }

    private func supportsValueStyle(_ id: MetricID) -> Bool {
        switch id {
        case .fiveHour, .sevenDay, .sonnet, .design, .fable, .extraCredits: return true
        case .sessionPacing, .weeklyPacing, .serviceStatus, .sessionReset, .opus, .cowork: return false
        }
    }

    private func valueStyles(for id: MetricID) -> [MetricValueStyle] {
        id == .extraCredits ? MetricValueStyle.allCases : [.percentUsed, .percentRemaining]
    }

    private func supportsCountdown(_ id: MetricID) -> Bool {
        switch id {
        case .fiveHour, .sevenDay, .sonnet, .design, .fable: return true
        case .extraCredits, .sessionPacing, .weeklyPacing, .serviceStatus, .sessionReset, .opus, .cowork: return false
        }
    }

    // MARK: - Display

    /// True when any configured pin actually renders a countdown span, so the
    /// format picker only appears when the choice has a visible effect.
    private var anyPinShowsCountdown: Bool {
        settingsStore.display.menuBarConfig.pinned.contains { $0.showCountdown || $0.id == .sessionReset }
    }

    private var displaySection: some View {
        Section {
            Picker(String(localized: "settings.menubar.mode"), selection: $settingsStore.display.menuBarConfig.displayMode) {
                ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.localizedLabel).tag(mode)
                }
            }
            if settingsStore.display.menuBarConfig.displayMode == .rotate {
                Stepper(
                    value: $settingsStore.display.menuBarConfig.rotateSeconds,
                    in: 1...60
                ) {
                    Text("settings.menubar.rotateSeconds \(settingsStore.display.menuBarConfig.rotateSeconds)")
                }
            }
            if anyPinShowsCountdown {
                Picker(String(localized: "settings.menubar.countdownFormat"), selection: $settingsStore.display.resetDisplayFormat) {
                    ForEach(ResetDisplayFormat.allCases) { format in
                        Text(format.localizedLabel).tag(format)
                    }
                }
            }
        } header: {
            Text(String(localized: "settings.menubar.display"))
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker(String(localized: "settings.menubar.colorMode"), selection: $settingsStore.display.menuBarConfig.colorMode) {
                ForEach(MenuBarColorMode.allCases, id: \.self) { mode in
                    Text(mode.localizedLabel).tag(mode)
                }
            }
            Toggle(String(localized: "settings.menubar.showIcon"), isOn: $settingsStore.display.menuBarConfig.showIcon)
                .tint(DS.Pastel.green)
            HStack {
                Text(String(localized: "settings.menubar.separator"))
                Spacer()
                TextField("", text: $separatorInput)
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
            }
            Toggle(String(localized: "settings.menubar.fixedWidth"), isOn: $settingsStore.display.menuBarConfig.fixedWidth)
                .tint(DS.Pastel.green)
        } header: {
            Text(String(localized: "settings.menubar.appearance"))
        } footer: {
            Text(String(localized: "settings.menubar.fixedWidth.hint"))
        }
    }
}

// MARK: - Localized labels

extension MetricPrefixStyle {
    var localizedLabel: String {
        switch self {
        case .symbol:     return String(localized: "settings.menubar.prefix.symbol")
        case .shortLabel: return String(localized: "settings.menubar.prefix.shortLabel")
        case .none:       return String(localized: "settings.menubar.prefix.none")
        }
    }
}

extension MetricValueStyle {
    var localizedLabel: String {
        switch self {
        case .percentUsed:      return String(localized: "settings.menubar.value.percentUsed")
        case .percentRemaining: return String(localized: "settings.menubar.value.percentRemaining")
        case .dollars:           return String(localized: "settings.menubar.value.dollars")
        }
    }
}

extension MenuBarDisplayMode {
    var localizedLabel: String {
        switch self {
        case .all:         return String(localized: "settings.menubar.mode.all")
        case .highestRisk: return String(localized: "settings.menubar.mode.highestRisk")
        case .rotate:       return String(localized: "settings.menubar.mode.rotate")
        }
    }
}

extension MenuBarColorMode {
    var localizedLabel: String {
        switch self {
        case .monochrome: return String(localized: "settings.menubar.color.mono")
        case .risk:         return String(localized: "settings.menubar.color.risk")
        }
    }
}
