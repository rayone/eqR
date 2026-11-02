import SwiftUI

/// What eqR is, where it came from, and what it costs.
///
/// The same four facts the system panel showed, in the app's own hand: the mark,
/// the version, one sentence, and the two places worth going. The copyright and
/// licence keep the smallest type, as they do in every About on the system —
/// they are a statement of fact rather than something to read.
struct AboutSettingsView: View {
    private static let repository = URL(string: "https://github.com/eqr/eqr")!
    /// The release list rather than this version's tag: a tag exists only once
    /// the release is cut, so a build made between releases would link to a 404.
    private static let releases = URL(string: "https://github.com/eqr/eqr/releases")!
    @AppStorage(Theme.themeModeKey) private var themeMode = "TokyoNight"

    var body: some View {
        VStack(spacing: 10) {
            AppMark()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text("eqR")
                    .font(Theme.Font.title)
                    .foregroundStyle(themeMode == "TokyoNight" ? Theme.TokyoNight.fg : .primary)
                Text(versionLine)
                    .font(Theme.Font.value)
                    .foregroundStyle(
                        themeMode == "TokyoNight" ? Theme.TokyoNight.comment : .secondary)
            }

            Text("Equalizes everything you hear, with no driver and nothing left behind.")
                .font(Theme.Font.label)
                .foregroundStyle(themeMode == "TokyoNight" ? Theme.TokyoNight.fgDark : .secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            HStack(spacing: 14) {
                Link("Source Code", destination: Self.repository)
                Link("Release Notes", destination: Self.releases)
            }
            .font(Theme.Font.label)

            Text(copyright)
                .font(Theme.Font.secondary)
                .foregroundStyle(
                    themeMode == "TokyoNight"
                        ? Theme.TokyoNight.comment : Color(nsColor: .tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .background(WindowBackground())
    }

    /// Read from the bundle rather than written here, so a release cannot ship
    /// an About that disagrees with itself.
    private var versionLine: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return String(
            localized: "Version \(version ?? "—")", comment: "About: the app’s version number")
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }
}
