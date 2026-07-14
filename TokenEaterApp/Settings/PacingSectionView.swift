import SwiftUI

/// Pacing logic settings: Smart Color (how usage maps to gauge colour and
/// severity), pacing sensitivity, and the workweek schedule (active days +
/// hours). Owns the risk/pace behaviour; the warning/critical thresholds it
/// exposes live on `SettingsStore.display`.
struct PacingSectionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var showSmartColorPopover = false
    @State private var showWorkweekPopover = false
    /// Local Double mirrors for the percent sliders - `Slider` needs a
    /// `BinaryFloatingPoint` binding, the stores hold `Int`.
    /// @State + .onChange instead of Binding(get:set:), per the SwiftUI rules.
    @State private var warningSlider: Double
    @State private var criticalSlider: Double
    @State private var marginSlider: Double

    init(initialWarning: Int, initialCritical: Int, initialMargin: Int) {
        _warningSlider = State(initialValue: Double(initialWarning))
        _criticalSlider = State(initialValue: Double(initialCritical))
        _marginSlider = State(initialValue: Double(initialMargin))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsHeader(
                String(localized: "sidebar.pacing"),
                subtitle: String(localized: "sidebar.pacing.subtitle")
            )

            Form {
                smartColorSection
                if !settingsStore.smartColorEnabled {
                    thresholdsSection
                }
                marginSection
                workweekSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: warningSlider) { _, new in
            let int = Int(new)
            if settingsStore.display.warningThreshold != int { settingsStore.display.warningThreshold = int }
            if int >= settingsStore.display.criticalThreshold { settingsStore.display.criticalThreshold = min(int + 5, 95) }
        }
        .onChange(of: criticalSlider) { _, new in
            let int = Int(new)
            if settingsStore.display.criticalThreshold != int { settingsStore.display.criticalThreshold = int }
            if int <= settingsStore.display.warningThreshold { settingsStore.display.warningThreshold = max(int - 5, 10) }
        }
        .onChange(of: marginSlider) { _, new in
            let int = Int(new)
            if settingsStore.pacingMargin != int { settingsStore.pacingMargin = int }
        }
        .onChange(of: settingsStore.display.warningThreshold) { _, new in
            let d = Double(new); if warningSlider != d { warningSlider = d }
        }
        .onChange(of: settingsStore.display.criticalThreshold) { _, new in
            let d = Double(new); if criticalSlider != d { criticalSlider = d }
        }
        .onChange(of: settingsStore.pacingMargin) { _, new in
            let d = Double(new); if marginSlider != d { marginSlider = d }
        }
    }

    // MARK: - Smart Color

    private var smartColorSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(String(localized: "settings.smartcolor.title"))
                        Button {
                            showSmartColorPopover.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showSmartColorPopover, arrowEdge: .bottom) {
                            smartColorInfoPopover
                                .background(DS.Pastel.base)
                                .preferredColorScheme(.dark)
                        }
                    }
                    Text(String(localized: "settings.smartcolor.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $settingsStore.display.smartColorEnabled)
                    .toggleStyle(.switch)
                    .tint(DS.Pastel.green)
                    .labelsHidden()
            }
            .padding(.vertical, 2)

            if settingsStore.smartColorEnabled {
                smartColorProfilePicker
            }
        }
    }

    // MARK: - Thresholds (only relevant when Smart Color is OFF: smart mode
    // owns its own calibration via the chosen profile).

    private var thresholdsSection: some View {
        Section {
            percentSlider(label: String(localized: "settings.thresholds.warning"), value: $warningSlider, range: 10...90)
            percentSlider(label: String(localized: "settings.thresholds.critical"), value: $criticalSlider, range: 15...95)

            HStack(spacing: 24) {
                Spacer()
                themePreviewGauge(pct: Double(max(settingsStore.display.warningThreshold - 15, 5)), label: "Normal")
                themePreviewGauge(pct: Double(settingsStore.display.warningThreshold + settingsStore.display.criticalThreshold) / 2.0, label: "Warning")
                themePreviewGauge(pct: Double(min(settingsStore.display.criticalThreshold + 5, 100)), label: "Critical")
                Spacer()
            }
            .padding(.vertical, 4)
        } header: {
            Text(String(localized: "settings.thresholds"))
        } footer: {
            Text(String(localized: "settings.thresholds.hint"))
        }
    }

    // MARK: - Pacing sensitivity (margin)

    private var marginSection: some View {
        Section {
            percentSlider(label: String(localized: "settings.pacing.margin.value"), value: $marginSlider, range: 5...30)
            pacingZonesPreview
        } header: {
            Text(String(localized: "settings.pacing.margin"))
        } footer: {
            Text(String(localized: "settings.pacing.margin.hint"))
        }
    }

    // MARK: - Workweek pacing

    private var workweekSection: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Text(String(localized: "settings.pacing.workweek"))
                    Button {
                        showWorkweekPopover.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showWorkweekPopover, arrowEdge: .bottom) {
                        workweekInfoPopover
                            .background(DS.Pastel.base)
                            .preferredColorScheme(.dark)
                    }
                }
                Spacer()
                Toggle("", isOn: $settingsStore.pacing.workweekEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DS.Pastel.green)
            }
            .padding(.vertical, 2)

            if settingsStore.pacingWorkweekEnabled {
                HStack(spacing: 6) {
                    ForEach(orderedWeekdays, id: \.day) { item in
                        dayChip(day: item.day, symbol: item.symbol)
                    }
                }

                Toggle(String(localized: "settings.pacing.workweek.hours"), isOn: $settingsStore.pacing.hoursEnabled)
                    .tint(DS.Pastel.green)

                if settingsStore.pacingHoursEnabled {
                    HStack(spacing: 10) {
                        Text(String(format: "%02d:00", settingsStore.pacingStartHour))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(DS.Pastel.green)
                            .frame(width: 44, alignment: .leading)
                        HourRangeSlider(
                            startHour: $settingsStore.pacing.startHour,
                            endHour: $settingsStore.pacing.endHour
                        )
                        .frame(maxWidth: .infinity)
                        Text(String(format: "%02d:00", settingsStore.pacingEndHour))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(DS.Pastel.green)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        } footer: {
            Text(String(localized: "settings.pacing.workweek.hint"))
        }
    }

    // MARK: - Workweek pacing popover

    private var workweekInfoPopover: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Pastel.green)
                Text(String(localized: "settings.workweek.popover.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Text(String(localized: "settings.workweek.popover.intro"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Divider().opacity(0.18)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                signalRow(
                    index: 1,
                    title: String(localized: "settings.workweek.popover.point1.title"),
                    desc: String(localized: "settings.workweek.popover.point1.desc"),
                    tint: DS.Pastel.green
                )
                signalRow(
                    index: 2,
                    title: String(localized: "settings.workweek.popover.point2.title"),
                    desc: String(localized: "settings.workweek.popover.point2.desc"),
                    tint: RiskZone.warning.color
                )
                signalRow(
                    index: 3,
                    title: String(localized: "settings.workweek.popover.point3.title"),
                    desc: String(localized: "settings.workweek.popover.point3.desc"),
                    tint: DS.Pastel.blue
                )
            }

            HStack(alignment: .top, spacing: DS.Spacing.xs) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
                Text(String(localized: "settings.workweek.popover.footer"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(DS.Spacing.lg)
        .frame(width: 360)
    }

    // MARK: - Workweek pacing day picker

    /// Weekday chips ordered by the user's locale first weekday (Mon-first in
    /// FR, Sun-first in US). `day` is the Gregorian weekday number (1=Sun...7=Sat).
    private var orderedWeekdays: [(day: Int, symbol: String)] {
        let cal = Calendar.current
        let symbols = cal.veryShortWeekdaySymbols // index 0 = Sunday
        let first = cal.firstWeekday // 1...7
        return (0..<7).map { offset in
            let day = ((first - 1 + offset) % 7) + 1
            return (day, symbols[day - 1])
        }
    }

    private func dayChip(day: Int, symbol: String) -> some View {
        let selected = settingsStore.pacingActiveDays.contains(day)
        return Button {
            toggleActiveDay(day)
        } label: {
            Text(symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(selected ? DS.Pastel.green.opacity(0.22) : Color.primary.opacity(0.05))
                )
                .overlay(
                    Circle().stroke(selected ? DS.Pastel.green.opacity(0.6) : Color.primary.opacity(0.1), lineWidth: 1)
                )
                .foregroundStyle(selected ? DS.Pastel.green : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    /// Toggles a day on/off, keeping at least one active day so the pacing
    /// denominator can never hit zero.
    private func toggleActiveDay(_ day: Int) {
        var days = settingsStore.pacingActiveDays
        if days.contains(day) {
            guard days.count > 1 else { return }
            days.remove(day)
        } else {
            days.insert(day)
        }
        settingsStore.pacingActiveDays = days
    }

    // MARK: - Smart Color profile picker

    private var smartColorProfilePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.smartColor.profile.label"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(SmartColorProfile.allCases, id: \.self) { profile in
                    profileCard(profile)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func profileCard(_ profile: SmartColorProfile) -> some View {
        let isActive = settingsStore.smartColorProfile == profile
        let accent = DS.Pastel.green
        return Button {
            settingsStore.smartColorProfile = profile
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: profileIcon(profile))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isActive ? accent : Color.secondary)
                        .frame(width: 16)
                    Text(profileDisplayLabel(profile))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    Spacer(minLength: 0)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(accent)
                    }
                }
                Text(profileHint(for: profile))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? accent.opacity(0.14) : Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isActive ? accent.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func profileIcon(_ profile: SmartColorProfile) -> String {
        switch profile {
        case .patient:  return "tortoise.fill"
        case .balanced: return "equal.circle.fill"
        case .vigilant: return "eye.fill"
        }
    }

    private func profileDisplayLabel(_ profile: SmartColorProfile) -> String {
        switch profile {
        case .patient:  return String(localized: "settings.smartColor.profile.patient")
        case .balanced: return String(localized: "settings.smartColor.profile.balanced")
        case .vigilant: return String(localized: "settings.smartColor.profile.vigilant")
        }
    }

    private func profileHint(for profile: SmartColorProfile) -> String {
        switch profile {
        case .patient:  return String(localized: "settings.smartColor.profile.patient.hint")
        case .balanced: return String(localized: "settings.smartColor.profile.balanced.hint")
        case .vigilant: return String(localized: "settings.smartColor.profile.vigilant.hint")
        }
    }

    // MARK: - Smart Color popover

    private var smartColorInfoPopover: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Pastel.green)
                Text(String(localized: "settings.smartcolor.popover.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Text(String(localized: "settings.smartcolor.popover.intro"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Divider().opacity(0.18)

            VStack(spacing: DS.Spacing.sm) {
                smartColorExample(
                    glyph: "leaf.fill",
                    pct: 95,
                    resetText: "2 min",
                    zoneLabel: String(localized: "settings.smartcolor.popover.example1.label"),
                    color: RiskZone.ok.color,
                    explanation: String(localized: "settings.smartcolor.popover.example1")
                )
                smartColorExample(
                    glyph: "flame.fill",
                    pct: 50,
                    resetText: "5 h",
                    zoneLabel: String(localized: "settings.smartcolor.popover.example2.label"),
                    color: RiskZone.critical.color,
                    explanation: String(localized: "settings.smartcolor.popover.example2")
                )
            }

            Divider().opacity(0.18)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(String(localized: "settings.smartcolor.popover.signals.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.bottom, 2)

                signalRow(
                    index: 1,
                    title: String(localized: "settings.smartcolor.popover.signal.absolute.title"),
                    desc: String(localized: "settings.smartcolor.popover.signal.absolute.desc"),
                    tint: RiskZone.critical.color
                )
                signalRow(
                    index: 2,
                    title: String(localized: "settings.smartcolor.popover.signal.projection.title"),
                    desc: String(localized: "settings.smartcolor.popover.signal.projection.desc"),
                    tint: RiskZone.warning.color
                )
                signalRow(
                    index: 3,
                    title: String(localized: "settings.smartcolor.popover.signal.pacing.title"),
                    desc: String(localized: "settings.smartcolor.popover.signal.pacing.desc"),
                    tint: DS.Pastel.green
                )

                HStack(alignment: .top, spacing: DS.Spacing.xs) {
                    Image(systemName: "function")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                    Text(String(localized: "settings.smartcolor.popover.combine"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)

                HStack(alignment: .top, spacing: DS.Spacing.xs) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                    Text(String(localized: "settings.smartcolor.popover.profile"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(String(localized: "settings.smartcolor.popover.formula"))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .italic()
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DS.Spacing.xxs)
        }
        .padding(DS.Spacing.lg)
        .frame(width: 400)
    }

    private func signalRow(index: Int, title: String, desc: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(tint.opacity(0.14))
                        .overlay(Circle().stroke(tint.opacity(0.45), lineWidth: 0.6))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }
        }
    }

    private func smartColorExample(
        glyph: String,
        pct: Int,
        resetText: String,
        zoneLabel: String,
        color: Color,
        explanation: String
    ) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            VStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                Text("\(pct)%")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                Text(resetText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(zoneLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(color)
                Text(explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(color.opacity(0.28), lineWidth: 1)
                )
        )
    }

    // MARK: - Sliders + previews

    private func percentSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        // Plain HStack, not LabeledContent: the slider fills the whole row
        // between the fixed label and the fixed value column.
        HStack(spacing: 12) {
            Text(label)
            Slider(value: value, in: range, step: 5)
                .tint(DS.Pastel.green)
                .frame(maxWidth: .infinity)
            Text("\(Int(value.wrappedValue))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    /// Live 4-zone preview reflecting the current pacing margin.
    private var pacingZonesPreview: some View {
        let m = Int(marginSlider)
        let chipColors: [(PacingZone, String)] = [
            (.chill,   "< -\(m)%"),
            (.onTrack, "\u{00B1}\(m)%"),
            (.warning, "+\(m)..+\(m * 2)%"),
            (.hot,     "> +\(m * 2)%"),
        ]
        return HStack(spacing: 6) {
            ForEach(Array(chipColors.enumerated()), id: \.offset) { _, entry in
                pacingZoneChip(zone: entry.0, range: entry.1)
            }
        }
        .padding(.vertical, 2)
    }

    private func pacingZoneChip(zone: PacingZone, range: String) -> some View {
        let color = zone.semanticColor
        let label = NSLocalizedString("pacing.zone.\(zone.rawValue.lowercased())", comment: "")
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(range)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(color.opacity(0.45), lineWidth: 0.6)
                )
        )
    }

    private func themePreviewGauge(pct: Double, label: String) -> some View {
        let zone = RiskZone.forPercent(Int(pct), thresholds: settingsStore.thresholds)
        let color = zone.color
        let gradient = LinearGradient(colors: [color, color.lighter()], startPoint: .leading, endPoint: .trailing)
        return VStack(spacing: 4) {
            RingGauge(
                percentage: Int(pct),
                gradient: gradient,
                size: 40
            )
            .overlay {
                Text("\(Int(pct))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}
