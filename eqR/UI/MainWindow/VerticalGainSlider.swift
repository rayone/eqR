import SwiftUI

/// Pure-SwiftUI vertical gain slider.
///
/// The system `Slider` is AppKit-backed on macOS and consumes mouse events
/// before SwiftUI gestures on enclosing views run, which made the
/// Lightroom-style double-click reset unreachable over the slider area.
/// Drawing the control natively gives full gesture control: drag adjusts the
/// gain (absolute, snapped to `step`), double-click resets the band, and a
/// plain single click deliberately does nothing so the reset is flicker-free.
struct VerticalGainSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var neutralValue: Double = 0
    let isEnabled: Bool
    /// Hovered or being dragged: the only state in which the band shows its
    /// accent colour, so a row at rest is a quiet ladder of grey tracks.
    let isActive: Bool

    let onDragChange: (Bool) -> Void
    let onReset: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(Theme.themeModeKey) private var themeMode = "TokyoNight"
    static var knobDiameter: CGFloat { Theme.BandRow.knobDiameter }
    private static var trackWidth: CGFloat { Theme.BandRow.trackWidth }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let midX = geometry.size.width / 2
            let travel = height - Self.knobDiameter
            let span = range.upperBound - range.lowerBound
            let knobY = Self.knobCenterY(for: value, in: height, range: range)
            // The neutral point, not the bottom: this is a bipolar control, so
            // the filled part should say how far from flat the band is and in
            // which direction.
            let zeroY = Self.knobCenterY(for: neutralValue, in: height, range: range)

            ZStack {
                Capsule()
                    .fill(
                        themeMode == "TokyoNight"
                            ? Theme.TokyoNight.bgHighlight : Color.primary.opacity(0.18)
                    )
                    .frame(width: Self.trackWidth, height: height - Self.knobDiameter / 2)
                    .position(x: midX, y: height / 2)

                // Deviation from flat, always drawn — quietly at rest so the
                // strip shows the preset's shape at a glance, in the accent
                // while the band is hovered or dragged.
                Capsule()
                    .fill(
                        isActive
                            ? AnyShapeStyle(Color.eqRSignal)
                            : (themeMode == "TokyoNight"
                                ? AnyShapeStyle(Theme.TokyoNight.blue.opacity(0.65))
                                : AnyShapeStyle(Color.primary.opacity(0.35)))
                    )
                    .frame(width: Self.trackWidth, height: abs(zeroY - knobY))
                    .position(x: midX, y: (knobY + zeroY) / 2)

                Circle()
                    .fill(
                        themeMode == "TokyoNight"
                            ? Theme.TokyoNight.fg
                            : (colorScheme == .dark ? Color(white: 0.85) : .white)
                    )
                    .overlay(
                        Circle().strokeBorder(
                            isActive
                                ? Color.eqRSignal
                                : (themeMode == "TokyoNight"
                                    ? Theme.TokyoNight.borderHighlight : Color.black.opacity(0.22)),
                            lineWidth: isActive ? 2 : (themeMode == "TokyoNight" ? 1 : 0.5)
                        )
                    )
                    .shadow(
                        color: .black.opacity(themeMode == "TokyoNight" ? 0.45 : 0.28), radius: 1.5,
                        y: 0.5
                    )
                    .frame(width: Self.knobDiameter, height: Self.knobDiameter)
                    .position(x: midX, y: knobY)
            }
            .animation(.easeOut(duration: 0.12), value: isActive)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        guard isEnabled, travel > 0, span > 0 else { return }
                        onDragChange(true)
                        let fraction =
                            1.0 - Double((drag.location.y - Self.knobDiameter / 2) / travel)
                        let raw = range.lowerBound + span * min(max(fraction, 0), 1)
                        value = (raw / step).rounded() * step
                    }
                    .onEnded { _ in onDragChange(false) }
            )
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard isEnabled else { return }
                    onReset()
                }
            )
            // One detent per step, the same 0.5 dB a drag snaps to, so scrolling
            // and dragging can't land on different values.
            .scrollAdjustable(isEnabled: isEnabled) { steps in
                let raw = value + Double(steps) * step
                value = ((raw / step).rounded() * step).clamped(to: range)
            }
        }
        .accessibilityRepresentation {
            Slider(value: $value, in: range)
        }
    }

    /// Vertical extent of the drawn track.
    ///
    /// The capsule is `knobDiameter / 2` shorter than the control and centred,
    /// so it starts and ends a quarter of a knob in from each end. A scale
    /// beside it keeps its end labels inside this, or `+12` overhangs the top of
    /// the line and `−12` the bottom.
    static func trackBounds(in height: CGFloat) -> ClosedRange<CGFloat> {
        let inset = knobDiameter / 4
        return inset...max(height - inset, inset)
    }

    /// Centre of the knob for a given gain. Shared with the dB scale beside the
    /// row so its marks sit exactly level with the knob travel.
    static func knobCenterY(
        for gain: Double, in height: CGFloat, range: ClosedRange<Double>
    ) -> CGFloat {
        let travel = height - knobDiameter
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return knobDiameter / 2 + travel / 2 }
        let fraction = (gain - range.lowerBound) / span
        return knobDiameter / 2 + travel * CGFloat(1.0 - fraction)
    }
}
