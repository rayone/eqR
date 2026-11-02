import SwiftUI

/// The eqR mark, drawn as vectors rather than scaled down from the app icon.
///
/// `NSApp.applicationIconImage` is the *composed* macOS icon: the system adds a
/// bezel with a bright specular rim, and the legacy `AppIcon.icns` bakes in its
/// own rounded rect whose radius doesn't match the system mask. At sidebar size
/// both show up as pale fringes along the edges. Drawing the shapes directly is
/// crisp at any size and in either appearance.
///
/// Geometry mirrors `design/logo.svg` — dark neon aesthetic with 5 spectrum bars,
/// expressed as fractions so it scales to whatever frame it's given.
struct AppMark: View {
    private static let backgroundColors: [Color] = [
        Color(.sRGB, red: 0x10 / 255.0, green: 0x15 / 255.0, blue: 0x24 / 255.0, opacity: 1),
        Color(.sRGB, red: 0x05 / 255.0, green: 0x04 / 255.0, blue: 0x0C / 255.0, opacity: 1),
    ]

    private static let rimGradient = LinearGradient(
        gradient: Gradient(stops: [
            .init(
                color: Color(
                    .sRGB, red: 0x00 / 255.0, green: 0xDD / 255.0, blue: 0xF1 / 255.0, opacity: 1),
                location: 0),
            .init(
                color: Color(
                    .sRGB, red: 0x3B / 255.0, green: 0x63 / 255.0, blue: 0xFF / 255.0, opacity: 1),
                location: 0.5),
            .init(
                color: Color(
                    .sRGB, red: 0xCE / 255.0, green: 0x19 / 255.0, blue: 0xF3 / 255.0, opacity: 1),
                location: 1.0),
        ]),
        startPoint: UnitPoint(x: 64.0 / 1024.0, y: 128.0 / 1024.0),
        endPoint: UnitPoint(x: 960.0 / 1024.0, y: 896.0 / 1024.0)
    )

    private static let spectrumGradient = LinearGradient(
        gradient: Gradient(stops: [
            .init(
                color: Color(
                    .sRGB, red: 0x00 / 255.0, green: 0xDD / 255.0, blue: 0xF1 / 255.0, opacity: 1),
                location: 0),
            .init(
                color: Color(
                    .sRGB, red: 0x39 / 255.0, green: 0x7A / 255.0, blue: 0xFF / 255.0, opacity: 1),
                location: 0.5),
            .init(
                color: Color(
                    .sRGB, red: 0xDA / 255.0, green: 0x20 / 255.0, blue: 0xF2 / 255.0, opacity: 1),
                location: 1.0),
        ]),
        startPoint: UnitPoint(x: 270.0 / 1024.0, y: 0.5),
        endPoint: UnitPoint(x: 754.0 / 1024.0, y: 0.5)
    )

    /// Five bars from logo.svg: x=248, 360, 472, 584, 696; width=80; rx=40
    private static let bars: [(x: CGFloat, y: CGFloat, height: CGFloat)] = [
        (248.0 / 1024.0, 450.0 / 1024.0, 124.0 / 1024.0),
        (360.0 / 1024.0, 376.0 / 1024.0, 272.0 / 1024.0),
        (472.0 / 1024.0, 280.0 / 1024.0, 464.0 / 1024.0),
        (584.0 / 1024.0, 376.0 / 1024.0, 272.0 / 1024.0),
        (696.0 / 1024.0, 450.0 / 1024.0, 124.0 / 1024.0),
    ]
    private static let barWidth: CGFloat = 80.0 / 1024.0
    private static let barCornerRadius: CGFloat = 40.0 / 1024.0
    private static let backgroundCornerRadius: CGFloat = 216.0 / 1024.0
    private static let rimCornerRadius: CGFloat = 208.0 / 1024.0

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack(alignment: .topLeading) {
                // Background plate
                RoundedRectangle(
                    cornerRadius: side * Self.backgroundCornerRadius, style: .continuous
                )
                .fill(
                    RadialGradient(
                        colors: Self.backgroundColors, center: UnitPoint(x: 0.45, y: 0.32),
                        startRadius: 0, endRadius: side * 0.85)
                )
                .frame(width: side * (984.0 / 1024.0), height: side * (984.0 / 1024.0))
                .offset(x: side * (20.0 / 1024.0), y: side * (20.0 / 1024.0))

                // Rim stroke
                RoundedRectangle(
                    cornerRadius: side * Self.rimCornerRadius, style: .continuous
                )
                .strokeBorder(Self.rimGradient, lineWidth: max(1, side * (9.0 / 1024.0)))
                .frame(width: side * (966.0 / 1024.0), height: side * (966.0 / 1024.0))
                .offset(x: side * (29.0 / 1024.0), y: side * (29.0 / 1024.0))

                // Spectrum bars
                ZStack(alignment: .topLeading) {
                    ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, bar in
                        RoundedRectangle(
                            cornerRadius: side * Self.barCornerRadius, style: .continuous
                        )
                        .frame(width: side * Self.barWidth, height: side * bar.height)
                        .offset(x: side * bar.x, y: side * bar.y)
                    }
                }
                .foregroundStyle(Self.spectrumGradient)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
