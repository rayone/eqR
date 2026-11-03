import SwiftUI

struct SpectrumBackdrop: View {
    let spectrum: SpectrumAnalyzer
    let axis: ResponseAxis
    let plotHeight: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !spectrum.isRunning)) {
            timeline in
            Canvas { context, _ in
                let _ = timeline.date
                let points = spectrum.points
                // Silence would otherwise stroke a flat line along the floor of the
                // plot, which reads as a stray rule under the frequency labels.
                guard points.count > 1, points.contains(where: { $0.level > 0.02 }) else { return }

                var line = Path()
                for (index, point) in points.enumerated() {
                    let position = CGPoint(
                        x: axis.x(point.frequency), y: plotHeight * (1 - CGFloat(point.level)))
                    if index == 0 {
                        line.move(to: position)
                    } else {
                        line.addLine(to: position)
                    }
                }

                var fill = line
                fill.addLine(
                    to: CGPoint(x: axis.x(points[points.count - 1].frequency), y: plotHeight))
                fill.addLine(to: CGPoint(x: axis.x(points[0].frequency), y: plotHeight))
                fill.closeSubpath()

                context.fill(fill, with: .color(Theme.TokyoNight.blue.opacity(0.14)))
                context.stroke(
                    line, with: .color(Theme.TokyoNight.cyan.opacity(0.35)), lineWidth: 1.5)
            }
            .allowsHitTesting(false)
        }
    }
}
