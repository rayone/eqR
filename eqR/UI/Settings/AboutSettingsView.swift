import SwiftUI

/// What eqR is, where it came from, and what it costs.
///
/// The same four facts the system panel showed, in the app's own hand: the mark,
/// the version, one sentence, and the copyright. The copyright and licence keep
/// the smallest type, as they do in every About on the system — they are a
/// statement of fact rather than something to read.
struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 10) {
            AppMark()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            VStack(spacing: 3) {
                Text("eqR")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.TokyoNight.fg)
                Text(versionLine)
                    .font(Theme.Font.value)
                    .foregroundStyle(Theme.TokyoNight.comment)
            }

            Text("Equalizes everything you hear, with no driver and nothing left behind.")
                .font(Theme.Font.label)
                .foregroundStyle(Theme.TokyoNight.fgDark)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Text(copyright)
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.TokyoNight.comment)
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
