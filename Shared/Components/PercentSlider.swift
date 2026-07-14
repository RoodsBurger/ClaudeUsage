import SwiftUI

/// Single-thumb stepped slider drawn with the pastel tokens: a
/// `DS.Pastel.track` capsule, a tint-filled span up to the thumb, and a white
/// thumb that scales + halos on hover/drag (same idioms as `HourRangeSlider`).
/// Custom-drawn because the native `Slider`'s `.tint` track fill renders as an
/// uncolored gray track on some macOS builds - filling the capsule directly
/// keeps the pastel look identical on every system. Snaps to `step`.
struct PercentSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 5
    var tint: Color = DS.Pastel.green
    /// Small `DS.Pastel.border` dots marking each step position on the empty
    /// track. Off by default - the settings percent rows read cleaner bare.
    var showsTicks: Bool = false
    /// VoiceOver label for the slider element (the visible row label lives
    /// outside this view).
    var accessibilityLabelText: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false
    @State private var isHovering = false

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 16
    private let hoverScale: CGFloat = 1.15
    private let dragScale: CGFloat = 1.3
    private let haloRatio: CGFloat = 2.2

    private var span: Double { max(range.upperBound - range.lowerBound, .ulpOfOne) }
    private var stateAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.22, extraBounce: 0.0)
    }

    var body: some View {
        GeometryReader { geo in
            let trackWidth = max(0, geo.size.width - thumbSize)
            let thumbX = fraction(value) * trackWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.Pastel.track)
                    .frame(height: trackHeight)

                if showsTicks {
                    tickDots(trackWidth: trackWidth)
                }

                Capsule()
                    .fill(tint)
                    .frame(width: thumbX + thumbSize / 2, height: trackHeight)

                thumb(x: thumbX)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        update(cursorX: drag.location.x, trackWidth: trackWidth)
                    }
                    .onEnded { _ in isDragging = false }
            )
            .animation(stateAnimation, value: isHovering)
            .animation(stateAnimation, value: isDragging)
        }
        .frame(height: thumbSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabelText))
        .accessibilityValue(Text("\(Int(value))%"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func fraction(_ v: Double) -> CGFloat {
        let clamped = min(max(v, range.lowerBound), range.upperBound)
        return CGFloat((clamped - range.lowerBound) / span)
    }

    private func tickDots(trackWidth: CGFloat) -> some View {
        let count = Int((span / step).rounded()) + 1
        return ForEach(0..<count, id: \.self) { index in
            Circle()
                .fill(DS.Pastel.border)
                .frame(width: 2, height: 2)
                .offset(x: CGFloat(Double(index) * step / span) * trackWidth + thumbSize / 2 - 1)
        }
    }

    private func thumb(x: CGFloat) -> some View {
        let scale = isDragging ? dragScale : (isHovering ? hoverScale : 1.0)
        return ZStack {
            Circle()
                .fill(tint)
                .frame(width: thumbSize * haloRatio, height: thumbSize * haloRatio)
                .opacity(isDragging ? 0.32 : 0.0)
                .blur(radius: 6)
                .allowsHitTesting(false)
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(isDragging ? 0.28 : 0.16), radius: isDragging ? 3 : 1.5, y: isDragging ? 1.5 : 0.5)
                .frame(width: thumbSize, height: thumbSize)
                .scaleEffect(scale)
        }
        .frame(width: thumbSize, height: thumbSize)
        .offset(x: x)
    }

    private func update(cursorX: CGFloat, trackWidth: CGFloat) {
        guard trackWidth > 0 else { return }
        let rawOffset = cursorX - thumbSize / 2
        let frac = Double(max(0, min(trackWidth, rawOffset)) / trackWidth)
        let raw = range.lowerBound + frac * span
        let stepped = range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step
        let clamped = min(max(stepped, range.lowerBound), range.upperBound)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if clamped != value { value = clamped }
        }
    }
}
