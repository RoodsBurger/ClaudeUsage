import SwiftUI

/// Descriptor for a history-derived token tile: the enterprise "5H / 7D
/// ACTIVITY" stand-ins and the per-model token tiles. `tokens`/`sessions` are
/// nil until the local JSONL cache has loaded (or when there is no history).
struct ActivityTileDescriptor {
    let id: String
    let label: String
    let icon: String
    let tokens: Int?
    let sessions: Int?
    /// True once the backing store finished its first load - flips the
    /// placeholder from "Loading" to "No local history".
    let loaded: Bool
    /// Optional secondary line shown in place of the session count (e.g. a
    /// per-model share "34% of 7d"). When set it wins over sessions/loading.
    var subtitle: String? = nil
    /// 7 daily token totals for the expand-time mini chart. Nil = no sparkline
    /// (the tile stays static, no expand affordance).
    var sparkline: [Int]? = nil
    /// Per-model tint for the value + sparkline. Nil falls back to the neutral
    /// activity blue.
    var tint: Color? = nil
    /// Heaviest day in the window, shown as the expanded "PEAK" line to match
    /// `MetricTile`'s footer rhythm.
    var peakDay: Date? = nil
    var peakTokens: Int? = nil
}

/// Token tile: a big history-derived count ("14M tokens") sharing `MetricTile`'s
/// card chrome so mixed grid rows stay aligned. With a `sparkline` it expands
/// (in unison with the other tiles) to a colored 7-day daily mini chart;
/// without one it is static.
struct ActivityTile: View {
    let descriptor: ActivityTileDescriptor
    var expanded: Bool = false
    var onToggle: (() -> Void)? = nil

    @State private var isHovered = false

    /// Value + sparkline accent. A raw activity count carries no risk zone, so
    /// it never borrows the gauge's green/amber/coral ladder; a model tile uses
    /// its own identity tint.
    private var accent: Color { descriptor.tint ?? DS.Pastel.blue }
    private var canExpand: Bool { descriptor.sparkline != nil }
    private var borderColor: Color { isHovered ? accent.opacity(0.4) : DS.Pastel.border }

    var body: some View {
        if canExpand, let onToggle {
            Button(action: onToggle) { card }
                .buttonStyle(CardPressStyle(isHovered: isHovered, accent: accent, cornerRadius: DS.Radius.card))
                .onHover { hovering in
                    withAnimation(DS.Motion.springSnap) { isHovered = hovering }
                }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: descriptor.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.8))
                    .frame(width: 14)
                Text(descriptor.label.uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if canExpand {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(descriptor.tokens.map(TokenFormatter.compact) ?? "\u{2014}")
                    .font(.system(size: 30, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                if descriptor.tokens != nil {
                    Text(String(localized: "activity.tokens.unit"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent.opacity(0.55))
                        .baselineOffset(3)
                }
            }

            Group {
                if let subtitle = descriptor.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if let sessions = descriptor.sessions {
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text(ActivityWindowCalculator.sessionsLabel(sessions))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(descriptor.loaded
                         ? String(localized: "activity.noData")
                         : String(localized: "activity.loading"))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)

            // Push the sparkline block to the bottom so it lines up with the
            // other grid tiles' sparklines across the row.
            Spacer(minLength: 0)

            if expanded, let sparkline = descriptor.sparkline {
                Rectangle()
                    .fill(DS.Pastel.border)
                    .frame(height: 1)
                    .padding(.top, 2)
                Text("7D")
                    .font(DS.Typography.micro)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                sparklineBars(sparkline, color: accent)
                if let day = descriptor.peakDay, let peak = descriptor.peakTokens {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PEAK")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(.tertiary)
                        HStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(TokenFormatter.compact(peak))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 124, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Pastel.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    /// 7-bar daily mini chart, height-scaled to the series max. Flat fill,
    /// matching `MetricTile`'s sparkline and the app's solid data-viz bars.
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
}
