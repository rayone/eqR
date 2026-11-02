import SwiftUI

/// Output trim, in its own column to the right of the editing area.
///
/// Two filters can boost the same frequency, and the chain has no idea how much
/// headroom the source had — so a boosted preset can ask for more than there is
/// and clip. This is where it is given back. It sits beside the editor rather
/// than on the output row because it belongs to the sound the preset describes,
/// not to where that sound is going.
///
/// Named *Preamp* rather than *Global Gain*: it is the term Music.app uses on
/// the same control, so the audience that knows any equalizer already knows this
/// word, and it is also what AutoEQ and headphone-correction profiles call the
/// value — so an imported one will line up with the label without translation.
///
/// Drag the slider, or double-click it to return to the preset's trim. The value reads out
/// under the track rather than in a field: the plot above already shows the
/// whole curve moving with it, so this only has to say where it is.
struct GlobalGainView: View {
    enum Mode: String, CaseIterable {
        case preamp = "Preamp"
        // Persisted identifier: retain the existing selection across the label rename.
        case spatial = "3D"
    }

    @ObservedObject var profileManager: ProfileManager
    let isEnabled: Bool

    @AppStorage("masterOutputMode") private var mode: Mode = .preamp
    @AppStorage(Theme.themeModeKey) private var themeMode = "TokyoNight"
    @State private var isDragging = false
    @State private var isHovering = false

    private static let scaleGap: CGFloat = 6

    /// Width of the Auto / Reset switch — the word plus a little, centred under the
    /// track it governs.
    private static let autoWidth: CGFloat = 46

    var body: some View {
        // The same track / caption rhythm a band column has — see
        // `Theme.BandRow` — so this track starts and ends exactly level with the
        // band tracks beside it. The title is not in here: it is mounted on the
        // block's own border, as the editor's tabs are on theirs.
        VStack(spacing: 2) {
            GeometryReader { proxy in
                let trackHeight = max(
                    proxy.size.height - Theme.BandRow.chromeHeight,
                    Theme.BandRow.minSliderHeight
                )
                switch mode {
                case .preamp:
                    preampContent(trackHeight: trackHeight)
                case .spatial:
                    spatialContent(trackHeight: trackHeight)
                }
            }
        }
        .frame(width: Theme.globalGainWidth - Theme.blockPadding * 2)
        // Fills the row so this block and the editor beside it are the same
        // height, and so the track above has a height to grow into.
        .frame(maxHeight: .infinity)
        // The same clearance the editor block gives its tabs. Both blocks lose
        // it from the top, so the tracks stay level.
        .padding(.top, Theme.borderLabelClearance)
        .contentBlock()
        // Segmented picker on the block's top border.
        .borderLabel {
            Picker("Output Mode", selection: $mode) {
                Text("Preamp").tag(Mode.preamp)
                Text("Space").tag(Mode.spatial)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Output Mode")
        }
        .opacity(isEnabled ? 1.0 : 0.65)
        .help(
            mode == .preamp
                ? "Output trim applied after the whole chain; use it to give back the headroom a boosted preset takes"
                : "Space stereo width control; widen the soundstage or collapse to mono"
        )
    }

    private func preampContent(trackHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            Text(BandFormat.gain(profileManager.currentPreamp))
                .font(Theme.Font.value)
                .foregroundStyle(
                    profileManager.currentPreamp == 0 && !profileManager.isAutoGain
                        ? AnyShapeStyle(.tertiary)
                        : AnyShapeStyle(.secondary)
                )
                .frame(height: Theme.BandRow.valueHeight)
                .accessibilityHidden(true)

            VerticalGainSlider(
                value: preamp,
                range: BuiltInProfiles.preampRange,
                step: 0.5,
                isEnabled: isEnabled,
                isActive: isDragging || isHovering,
                onDragChange: { isDragging = $0 },
                onReset: { profileManager.resetPreamp() }
            )
            .frame(width: Theme.BandRow.columnWidth, height: trackHeight)
            .help(
                profileManager.isAutoGain
                    ? String(
                        localized:
                            "Set automatically while Auto is on; drag to set it by hand",
                        comment: "Preamp slider help tag, while automatic gain is on")
                    : String(
                        localized:
                            "Drag to set; double-click to return to the preset’s value",
                        comment: "Preamp slider help tag")
            )
            .overlay(alignment: .topLeading) {
                GainScale(
                    range: BuiltInProfiles.preampRange,
                    trackHeight: trackHeight,
                    side: .trailing,
                    showsUnit: false,
                    trackGap: Self.scaleGap
                )
                .offset(x: Theme.BandRow.columnWidth)
            }
            .onHover { isHovering = $0 }
            .accessibilityLabel("Preamp")
            .accessibilityValue(
                String(
                    localized:
                        "\(String(format: "%+.1f", profileManager.currentPreamp)) decibels",
                    comment: "Gain, for VoiceOver, such as “+2.5 decibels”"))

            autoToggle
        }
        .frame(maxWidth: .infinity)
    }

    private func spatialContent(trackHeight: CGFloat) -> some View {
        VStack(spacing: 6) {
            Text(spatialWidthDisplay)
                .font(Theme.Font.value)
                .foregroundStyle(
                    profileManager.currentSpatialWidth == 1.0
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(.primary)
                )
                .frame(height: Theme.BandRow.valueHeight)
                .accessibilityHidden(true)

            VerticalGainSlider(
                value: spatialWidth,
                range: 0.0...2.0,
                step: 0.05,
                neutralValue: 1.0,
                isEnabled: isEnabled,
                isActive: isDragging || isHovering,
                onDragChange: { isDragging = $0 },
                onReset: { profileManager.resetSpatialWidth() }
            )
            .frame(width: Theme.BandRow.columnWidth, height: trackHeight)
            .help("Drag to widen or narrow stereo image; double-click to reset to 100%")
            .onHover { isHovering = $0 }
            .accessibilityLabel("Space Stereo Width")
            .accessibilityValue(spatialWidthDisplay)

            spatialResetToggle
        }
        .frame(maxWidth: .infinity)
    }

    private var spatialWidthDisplay: String {
        let percent = Int((profileManager.currentSpatialWidth * 100).rounded())
        if percent == 0 {
            return "MONO"
        } else {
            return "\(percent)%"
        }
    }

    private var spatialResetToggle: some View {
        Button {
            profileManager.resetSpatialWidth()
        } label: {
            Text("100%", comment: "Neutral Space widening reset button")
                .font(Theme.Font.labelEmphasized)
                .kerning(0.6)
                .frame(width: Self.autoWidth, height: Theme.BandRow.labelHeight)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            profileManager.currentSpatialWidth != 1.0
                                ? Theme.currentAccentColor.opacity(0.18)
                                : (themeMode == "TokyoNight"
                                    ? Theme.TokyoNight.bgHighlight : Color.primary.opacity(0.05))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(
                            profileManager.currentSpatialWidth != 1.0
                                ? Theme.currentAccentColor.opacity(0.55)
                                : (themeMode == "TokyoNight"
                                    ? Theme.TokyoNight.border : Color.primary.opacity(0.12)),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(
                    profileManager.currentSpatialWidth != 1.0
                        ? AnyShapeStyle(Theme.currentAccentColor)
                        : (themeMode == "TokyoNight"
                            ? AnyShapeStyle(Theme.TokyoNight.fgDark) : AnyShapeStyle(.secondary))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Reset Space Width")
        .help("Reset Space stereo width to 100% (neutral)")
    }

    /// The mode switch for the trim, in the row a band column spends naming its
    /// frequency.
    ///
    /// It stood on its side until every column gained a value row above its
    /// track: with the trim's own value moved up there, this row came free, and
    /// a switch that reads left to right needs no excuse made for it.
    ///
    /// While it is on, the slider still moves: dragging it switches Auto off,
    /// so the slider is never a control that silently refuses.
    private var autoToggle: some View {
        Button {
            profileManager.setAutoGain(!profileManager.isAutoGain)
        } label: {
            Text("AUTO", comment: "Automatic gain switch, written in capitals as a badge")
                .font(Theme.Font.labelEmphasized)
                .kerning(0.6)
                // Sized to the word, not to the column: a switch stretched the
                // full width would read as a bar across the bottom of the block
                // rather than as one control.
                .frame(width: Self.autoWidth, height: Theme.BandRow.labelHeight)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(
                            profileManager.isAutoGain
                                ? Theme.currentAccentColor.opacity(0.18)
                                : (themeMode == "TokyoNight"
                                    ? Theme.TokyoNight.bgHighlight : Color.primary.opacity(0.05))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(
                            profileManager.isAutoGain
                                ? Theme.currentAccentColor.opacity(0.55)
                                : (themeMode == "TokyoNight"
                                    ? Theme.TokyoNight.border : Color.primary.opacity(0.12)),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(
                    profileManager.isAutoGain
                        ? AnyShapeStyle(Theme.currentAccentColor)
                        : (themeMode == "TokyoNight"
                            ? AnyShapeStyle(Theme.TokyoNight.fgDark) : AnyShapeStyle(.secondary))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("Automatic gain")
        .accessibilityValue(
            profileManager.isAutoGain
                ? String(localized: "On", comment: "Switch state, for VoiceOver")
                : String(localized: "Off", comment: "Switch state, for VoiceOver")
        )
        .accessibilityAddTraits(profileManager.isAutoGain ? [.isSelected] : [])
        .help(
            profileManager.isAutoGain
                ? String(
                    localized:
                        "The trim is computed from the chain; turn this off to set it by hand",
                    comment: "Automatic gain help tag, while on")
                : String(
                    localized:
                        "Compute the trim from the chain, so a boosted preset stays at the loudness it started from",
                    comment: "Automatic gain help tag, while off")
        )
    }

    private var preamp: Binding<Double> {
        Binding(
            get: { profileManager.currentPreamp },
            set: { profileManager.takeOverPreamp($0) }
        )
    }

    private var spatialWidth: Binding<Double> {
        Binding(
            get: { profileManager.currentSpatialWidth },
            set: { profileManager.setSpatialWidth($0) }
        )
    }
}
