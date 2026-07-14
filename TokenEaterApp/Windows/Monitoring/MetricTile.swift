import SwiftUI

// MARK: - Tile descriptor + MetricTile

struct TileDescriptor {
    let id: String
    let label: String
    let icon: String
    let pct: Int
    let resetText: String?
    let resetDate: Date?
    let windowDuration: TimeInterval
}

struct MetricTile: View {
    let id: String
    let label: String
    let icon: String
    let pct: Int
    let resetText: String?
    let resetDate: Date?
    let windowDuration: TimeInterval
    let smartEnabled: Bool
    let pacingMargin: Double
    let smartProfile: SmartColorProfile
    let thresholds: UsageThresholds
    /// 7d insights snapshot when the tile family has data. Nil for
    /// design / cowork tiles where the JSONL feed has nothing relevant.
    let insights: TileInsightsSnapshot?
    /// True once the insights store has done its first load. Lets the
    /// inline insights row show a "loading" placeholder vs a "no data" one.
    let insightsLoaded: Bool

    @State private var isHovered: Bool = false
    /// Tapping the tile inline-reveals the 7d insights row below the
    /// front content, in the same card - no flip, no blur.
    @State private var isExpanded: Bool = false

    var body: some View {
        let color = GaugeColorResolver.color(
            mode: GaugeColorResolver.mode(smartColorEnabled: smartEnabled, windowDuration: windowDuration),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: thresholds,
            pacingMargin: pacingMargin,
            profile: smartProfile
        )
        let clamped = CGFloat(min(max(pct, 0), 100)) / 100
        let border = isHovered ? color.opacity(0.4) : DS.Pastel.border

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                frontContent(color: color, clamped: clamped)
                if isExpanded {
                    insightsRow(color: color)
                }
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 124, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Pastel.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
        }
        .buttonStyle(CardPressStyle(isHovered: isHovered, accent: color, cornerRadius: DS.Radius.card))
        .onHover { hovering in
            withAnimation(DS.Motion.springSnap) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private func frontContent(color: Color, clamped: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color.opacity(0.8))
                    .frame(width: 14)
                Text(label.uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // Icon-only affordance - the whole tile is tappable, this
                // just signals "more" without adding copy.
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(pct)")
                    .font(.system(size: 30, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(pct)))
                    .animation(DS.Motion.easeInOut, value: pct)
                Text("%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(color.opacity(0.55))
                    .baselineOffset(3)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.Pastel.track)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: geo.size.width * clamped, height: 3)
                }
            }
            .frame(height: 3)
            .animation(DS.Motion.easeInOut, value: pct)

            Group {
                if let resetText, !resetText.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(String(localized: "dashboard.hero.resetsIn").uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.tertiary)
                        Text(resetText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        if let resetDate {
                            Text("·")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary.opacity(0.5))
                            Text(absoluteResetText(date: resetDate))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(" ")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.clear)
                }
            }
            .lineLimit(1)
        }
    }

    /// "16:32" for sub-day windows (5h), "Tue 16:32" for multi-day
    /// windows (7d weeklies). Stays compact + monospaced so it sits
    /// discretely next to the countdown without competing for space.
    private func absoluteResetText(date: Date) -> String {
        if windowDuration <= 24 * 3600 {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// Inline "details" row shown below the front content when expanded.
    /// When `insights` is available (weekly, sonnet, opus tiles) shows a
    /// compact 7d breakdown; otherwise falls back to a minimal placeholder.
    @ViewBuilder
    private func insightsRow(color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(DS.Pastel.border)
                .frame(height: 1)

            if let snapshot = insights {
                richInsights(snapshot: snapshot, color: color)
            } else if !insightsLoaded {
                Text("Loading...")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                fallbackInsights()
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func richInsights(snapshot: TileInsightsSnapshot, color: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text("7D")
                .font(DS.Typography.micro)
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let delta = snapshot.deltaPercent {
                Text(String(format: "%+.0f%%", delta))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(delta >= 0 ? DS.Pastel.amber : DS.Pastel.green)
                    .monospacedDigit()
            }
        }

        sparklineBars(snapshot.sparkline, color: color)

        HStack(alignment: .firstTextBaseline, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("TOTAL")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.tertiary)
                Text(TokenFormatter.compact(snapshot.total))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            if let heaviest = snapshot.heaviestDay {
                VStack(alignment: .leading, spacing: 1) {
                    Text("PEAK")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 4) {
                        Text(heaviest.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(TokenFormatter.compact(heaviest.tokens))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Fallback when no JSONL family data exists for this tile (design /
    /// cowork). Keeps the row useful by surfacing the full reset date
    /// instead of leaving it empty.
    @ViewBuilder
    private func fallbackInsights() -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            if let resetDate {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RESETS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.tertiary)
                    Text(resetDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            Text(windowText)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    /// 7-bar mini chart showing daily totals. Bars share their height
    /// scale with the maximum value in the series so the relative
    /// distribution reads correctly even when totals are tiny. Flat
    /// fill (no gradient) per bar, matching the app's solid data-viz bars.
    private func sparklineBars(_ values: [Int], color: Color) -> some View {
        let maxValue = max(values.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                let h = CGFloat(value) / CGFloat(maxValue)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(2, 32 * h))
                    .opacity(value > 0 ? 1 : 0.18)
            }
        }
        .frame(height: 32)
        .padding(.top, 2)
    }

    private var windowText: String {
        let hours = Int(windowDuration / 3600)
        if hours <= 24 { return "\(hours)h rolling" }
        let days = Int(windowDuration / 86_400)
        return "\(days)d rolling"
    }
}
