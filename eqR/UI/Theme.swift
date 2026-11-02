import AppKit
import SwiftUI

/// The app's design tokens, in one place so the sidebar, the graph, and the
/// band row can't drift apart.
enum Theme {
    /// The colour of eqR's *data* — the response curve, its fill, the
    /// ladder's nodes, and the slider handles. Fixed rather than the user's
    /// accent, the way Activity Monitor's graphs and Battery's charts are fixed:
    /// a reading shouldn't change meaning because someone picked a different
    /// accent.
    ///
    /// Controls are deliberately *not* this colour. Switches, sliders, the tab
    /// switcher, and list selection all take the system accent, so the window
    /// says "system utility" first and "eqR" second.
    ///
    /// A warm neutral rather than a hue, and that is the point. The eight
    /// `BandColor` entries already cover the wheel, so any coloured curve
    /// swallows whichever band colour is its neighbour: green did it to a green
    /// band, amber did it to an orange one sitting on the line. Neutral makes
    /// the curve the measurement and colour the labelling, so no palette entry
    /// can collide with it — including ones added later.
    ///
    /// Warm, not grey: both values run red > green > blue, so the line keeps the
    /// window's temperature rather than reading as chrome. And neutral is not
    /// faint — the spectrum behind it is drawn at 5% and 13% of `primary`, so a
    /// 1.5 pt line at eleven-to-one stands well clear of it.
    ///
    /// Two values, because one cannot serve both grounds. Measured against the
    /// window's own background: 11.8:1 on the dark appearance and 12.0:1 on the
    /// light one, where the amber they replace scored 7.7:1 and 5.4:1. Pure
    /// white would have been 14:1 and glaring. `ThemeTests` holds both above the
    /// 3:1 that graphical objects need.
    static let signal = Color(
        nsColor: NSColor(name: "eqRSignal") { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(srgbRed: 0.871, green: 0.847, blue: 0.816, alpha: 1)  // #DED8D0
                : NSColor(srgbRed: 0.239, green: 0.208, blue: 0.180, alpha: 1)  // #3D352E
        })

    /// Border shared by every block and by the plot, so the plot reads as one of
    /// them rather than as a panel with different rules.
    static let blockBorder = Color.primary.opacity(0.10)

    /// TokyoNight Night Theme palette from `Tokyonight_night_theme.json`.
    enum TokyoNight {
        static let bg = Color(red: 26 / 255.0, green: 27 / 255.0, blue: 38 / 255.0)
        static let bgDark = Color(red: 22 / 255.0, green: 22 / 255.0, blue: 30 / 255.0)
        static let bgHighlight = Color(red: 41 / 255.0, green: 46 / 255.0, blue: 66 / 255.0)
        static let bgVisual = Color(red: 40 / 255.0, green: 52 / 255.0, blue: 87 / 255.0)
        static let fg = Color(red: 192 / 255.0, green: 202 / 255.0, blue: 245 / 255.0)
        static let fgDark = Color(red: 169 / 255.0, green: 177 / 255.0, blue: 214 / 255.0)
        static let comment = Color(red: 86 / 255.0, green: 95 / 255.0, blue: 137 / 255.0)
        static let blue = Color(red: 122 / 255.0, green: 162 / 255.0, blue: 247 / 255.0)
        static let cyan = Color(red: 125 / 255.0, green: 207 / 255.0, blue: 255 / 255.0)
        static let teal = Color(red: 26 / 255.0, green: 188 / 255.0, blue: 156 / 255.0)
        static let green = Color(red: 158 / 255.0, green: 206 / 255.0, blue: 106 / 255.0)
        static let yellow = Color(red: 224 / 255.0, green: 175 / 255.0, blue: 104 / 255.0)
        static let orange = Color(red: 255 / 255.0, green: 158 / 255.0, blue: 100 / 255.0)
        static let magenta = Color(red: 187 / 255.0, green: 154 / 255.0, blue: 247 / 255.0)
        static let purple = Color(red: 157 / 255.0, green: 124 / 255.0, blue: 216 / 255.0)
        static let red = Color(red: 247 / 255.0, green: 118 / 255.0, blue: 142 / 255.0)
        static let border = Color(red: 41 / 255.0, green: 46 / 255.0, blue: 66 / 255.0)
        static let borderHighlight = Color(red: 39 / 255.0, green: 161 / 255.0, blue: 185 / 255.0)

        static let nsBg = NSColor(
            srgbRed: 26 / 255.0, green: 27 / 255.0, blue: 38 / 255.0, alpha: 1)
        static let nsBgDark = NSColor(
            srgbRed: 22 / 255.0, green: 22 / 255.0, blue: 30 / 255.0, alpha: 1)
        static let nsBgHighlight = NSColor(
            srgbRed: 41 / 255.0, green: 46 / 255.0, blue: 66 / 255.0, alpha: 1)
        static let nsBgVisual = NSColor(
            srgbRed: 40 / 255.0, green: 52 / 255.0, blue: 87 / 255.0, alpha: 1)
        static let nsFg = NSColor(
            srgbRed: 192 / 255.0, green: 202 / 255.0, blue: 245 / 255.0, alpha: 1)
        static let nsFgDark = NSColor(
            srgbRed: 169 / 255.0, green: 177 / 255.0, blue: 214 / 255.0, alpha: 1)
        static let nsBlue = NSColor(
            srgbRed: 122 / 255.0, green: 162 / 255.0, blue: 247 / 255.0, alpha: 1)
        static let nsCyan = NSColor(
            srgbRed: 125 / 255.0, green: 207 / 255.0, blue: 255 / 255.0, alpha: 1)
        static let nsBorder = NSColor(
            srgbRed: 41 / 255.0, green: 46 / 255.0, blue: 66 / 255.0, alpha: 1)
        static let nsBorderHighlight = NSColor(
            srgbRed: 39 / 255.0, green: 161 / 255.0, blue: 185 / 255.0, alpha: 1)
        static let nsComment = NSColor(
            srgbRed: 86 / 255.0, green: 95 / 255.0, blue: 137 / 255.0, alpha: 1)
    }

    /// The `UserDefaults` key holding the selected theme. One definition: the
    /// settings picker writes it, the window's appearance follows it, and the
    /// tests reset it — three readers, one literal.
    static let themeModeKey = "appThemeMode"

    /// True when the TokyoNight palette owns the main window.
    ///
    /// A plain `UserDefaults` read rather than something observable: the views
    /// that draw palette colours are AppKit-hosted canvases and layers, and the
    /// palette reaching them is `Theme.applyAppearance()` re-resolving the
    /// window's appearance, which redraws everything beneath it. Reading the
    /// key here keeps SwiftUI's `WindowBackground` and `SpectrumBackdrop` —
    /// which hold `@AppStorage(Self.themeModeKey)` for their own invalidation —
    /// and this computed answer in agreement by construction.
    static var isTokyoNight: Bool {
        (UserDefaults.standard.string(forKey: Self.themeModeKey) ?? "TokyoNight")
            == "TokyoNight"
    }

    /// Forces the dark appearance on the application while TokyoNight is
    /// active, restoring the system's choice otherwise.
    ///
    /// TokyoNight paints its own surfaces — the window background, the block
    /// fills, the plot — but everything the palette does *not* paint resolves
    /// against the appearance it is drawn in: the text hierarchies, the
    /// controls, the sidebar's vibrant material, and `Theme.signal` itself,
    /// which is a dynamic colour. On a Mac in Light mode those resolved light,
    /// and dark text sat on the dark canvas — the theme read as a black window
    /// with nothing legible in it, which is how it came to be reported as
    /// invisible. Resolving the window in `darkAqua` is what the palette's
    /// values were measured against.
    ///
    /// Called at launch and whenever the setting changes; the observer in
    /// `AppDelegate` owns the timing, so this stays a pure write.
    @MainActor
    static func applyAppearance() {
        NSApp.appearance = isTokyoNight ? NSAppearance(named: .darkAqua) : nil
    }

    static var currentBlockBorder: Color {
        isTokyoNight ? TokyoNight.border : blockBorder
    }

    static var currentBlockBackground: Color {
        isTokyoNight ? TokyoNight.bgDark : Color.clear
    }

    /// Current control accent: TokyoNight blue when TokyoNight is active, system accent otherwise.
    static var currentAccentColor: Color {
        isTokyoNight ? TokyoNight.blue : .accentColor
    }

    /// Current NSColor accent for AppKit controls and drawing handlers.
    static var currentNSAccentColor: NSColor {
        isTokyoNight ? TokyoNight.nsBlue : .controlAccentColor
    }

    /// Current control hover tint: TokyoNight cyan when TokyoNight is active, system accent otherwise.
    static var currentHoverColor: Color {
        isTokyoNight ? TokyoNight.cyan : .accentColor
    }

    /// Current NSColor hover tint: TokyoNight cyan when TokyoNight is active, system accent otherwise.
    static var currentNSHoverColor: NSColor {
        isTokyoNight ? TokyoNight.nsCyan : .controlAccentColor
    }

    /// Width reserved at the left of the response plot for its dB labels, and
    /// at the left of the band slider row for its own scale.
    static let axisGutter: CGFloat = 52

    /// Why eqR has stepped aside for a recording, where there is room to
    /// say it: the main window, and the setting that controls it. The menu has
    /// room for `recordingPauseTitle` alone.
    static var recordingPauseTitle: String {
        String(
            localized: "Paused While Recording",
            comment: "Heading and menu bar extra row: eqR stepped aside for a screen recording")
    }
    static var recordingPauseExplanation: String {
        String(
            localized:
                "Screen recordings capture both your apps’ sound and eqR’s equalized copy, which sounds doubled. eqR steps aside until the recording stops.",
            comment: "Why eqR pauses while a screen recording captures system audio")
    }

    /// Every size and weight the app is allowed to use.
    ///
    /// Before this there were eight hardcoded point sizes plus three of the
    /// system's semantic styles, and which one a view used depended on when it
    /// was written: the Settings panes had drifted onto `.callout` and
    /// `.caption` while the window used fixed points, so the same kind of text
    /// was a different size on either side of the app.
    ///
    /// Fixed points rather than the semantic styles, deliberately, and the one
    /// real cost is that eqR does not follow Dynamic Type. That trade was
    /// already made — the window and the menu are laid out to fixed sizes and
    /// would break — so this makes it consistent rather than accidental.
    ///
    /// Ten roles. Adding an eleventh should feel like it needs an argument.
    enum Font {
        /// 17 semibold. The app's name in About, and nothing else.
        static let title = SwiftUI.Font.system(size: 17, weight: .semibold)

        /// 13 semibold. The heading of a pane or a block.
        static let heading = SwiftUI.Font.system(size: 13, weight: .semibold)

        /// 13. Row text that names something: a device, a preset, a filter.
        static let body = SwiftUI.Font.system(size: 13)

        /// 12. Labels and controls — the app's default, and most of its chrome.
        static let label = SwiftUI.Font.system(size: 12)

        /// 12 semibold. A label that titles the group beneath it.
        static let labelEmphasized = SwiftUI.Font.system(size: 12, weight: .semibold)

        /// 11. Supporting text: the sentence under a control, an axis legend.
        ///
        /// The floor for prose. Anything smaller was being used for text people
        /// actually had to read, which is where "hard to read" came from.
        static let secondary = SwiftUI.Font.system(size: 11)

        /// 11 medium, monospaced digits. A number that changes as you drag it,
        /// so the row does not twitch between glyph widths.
        static let value = SwiftUI.Font.system(size: 11, weight: .medium).monospacedDigit()

        /// 11 semibold, monospaced digits. The same, where it is the subject
        /// rather than an annotation.
        static let valueEmphasized = SwiftUI.Font.system(size: 11, weight: .semibold)
            .monospacedDigit()

        /// 11, monospaced. The diagnostics report, which is columns of text
        /// that only line up in a fixed-width face.
        static let report = SwiftUI.Font.system(size: 11, design: .monospaced)

        /// 10, monospaced digits. Tick labels on an axis — glanced at, never
        /// read. The only place below 11, and only ever for numerals.
        static let tick = SwiftUI.Font.system(size: 10).monospacedDigit()
    }

    /// An 8 pt spacing system throughout the content column.
    enum Spacing {
        static let window: CGFloat = 28
        static let section: CGFloat = 24
        static let inner: CGFloat = 12
    }

    /// Inset between a content block's border and what it contains.
    static let blockPadding: CGFloat = 12

    /// Width of the output device control in the header. Fixed rather than
    /// sized to the device name, so it stays on the column's centreline instead
    /// of shifting every time the device changes.
    static let outputControlWidth: CGFloat = 220

    /// Width kept for the Revert button beside the output control, and mirrored
    /// on its other side.
    ///
    /// Reserved whether or not the button is showing. Revert exists only while
    /// there is something to revert, and letting it come and go would slide the
    /// device control sideways the moment a slider is touched — moving the thing
    /// the user is reading while they read it. Measured: a small bezelled button
    /// titled "Revert" is 54 points.
    static let revertSlotWidth: CGFloat = 58

    /// Height of the header row, set by the output control — which carries two
    /// lines now: the device, and the preset playing on it.
    static let headerHeight: CGFloat = 42

    /// Width of the Preamp column beside the editor: a centred track, plus room
    /// on the right for the scale that hangs off it, and nothing spare.
    static let globalGainWidth: CGFloat = 116

    /// Height of a label mounted on a block's top border — the tab strip on the
    /// editor, the title on the trim. The block reserves half of it above itself
    /// so the label has somewhere to hang without overlapping the graph.
    static let borderLabelHeight: CGFloat = 22
    /// How far a border label hangs down into the block it is mounted on.
    ///
    /// Content adds this to its own padding so the gap is measured from the
    /// bottom of the label rather than from the border — otherwise a tab sits
    /// directly on the first row of the thing it names, one point clear of it.
    /// Every block carrying a label adds the same amount, which is also what
    /// keeps the band tracks and the preamp track level.
    static var borderLabelClearance: CGFloat { borderLabelHeight / 2 }

    /// Fixed height of the editing area, so switching tabs changes the controls
    /// and nothing else — no reflow, no jump in the graph above it.
    ///
    /// Sized to the tallest thing that lives there, which is the Global Gain
    /// card, not the band strip. Drop below that and the card clips instead of
    /// the graph giving up a few points.
    static let editorHeight: CGFloat = 248

    enum FilterRow {
        /// One row plus its spacing. The filter list multiplies this to size its
        /// scroll box, so the two must not drift apart. Set by the knobs, which
        /// are the tallest thing in a row.
        static let height: CGFloat = 36

        static let knobDiameter: CGFloat = 24

        /// Height of the column-title row above the list.
        static let headerHeight: CGFloat = 18

        /// Hairline between two rows. Part of a row's pitch, so the list can
        /// size itself to whole rows.
        static let separator: CGFloat = 1

        /// Narrowest a gap between two columns may be. Reached only at the
        /// window's minimum width, where the editor block is about 536 points
        /// wide and the columns, their gaps, and the row's own padding claim 526
        /// of it. Widen a column and the table starts clipping on a 960-point
        /// window.
        static let columnSpacing: CGFloat = 8

        /// Widest a gap may grow to.
        ///
        /// The gaps are flexible between these two bounds, so the width a wider
        /// window gives the table is shared by every column instead of pooling
        /// in front of the last one. The ceiling is what stops that from
        /// continuing on a very wide window until the row reads as scattered
        /// controls rather than a table.
        static let columnSpacingMax: CGFloat = 28

        /// Fixed column widths, shared by the title row and every band row so
        /// the two line up without a `Grid` spanning the scroll view between
        /// them.
        ///
        /// Each is sized to its widest content, not to its title: "20000 Hz",
        /// "19999.9 Hz", "+12.0 dB", "16.00", and "High Shelf" are what these have
        /// to hold.
        enum Column {
            /// Colour swatch and band number, up to two digits.
            ///
            /// 34 held the swatch and one digit exactly, and wrapped the second:
            /// two monospaced digits at this size measure 14.6 pt and what was
            /// left over was 14. `ThemeTests` now measures it rather than
            /// trusting the arithmetic in this comment.
            static let index: CGFloat = 38
            /// The swatch button: an 8 pt circle inside a 3 pt hit-target
            /// padding, and the gap between it and the number.
            static let indexSwatch: CGFloat = 14
            static let indexGap: CGFloat = 6
            static let enable: CGFloat = 30
            static let type: CGFloat = 100
            /// Wide enough for a frequency with its decimal, "19999.9 Hz".
            /// At 94 it held "20000 Hz" and clipped an imported "3302.8".
            static let frequency: CGFloat = 108
            static let gain: CGFloat = 92
            static let q: CGFloat = 76
            /// Just the delete button: there is no power icon, because the
            /// Enable switch two columns back is already that control.
            static let actions: CGFloat = 24
        }
    }

    /// The vertical rhythm the Graphic editor and the Preamp column share.
    ///
    /// Both are a value, a track, and a caption. Driving both from these numbers
    /// is what keeps the preamp track starting and ending exactly level with the
    /// band tracks beside it — and what let the Auto switch stand up straight:
    /// the preamp spends its caption row on Auto because its value moved to the
    /// top row every column now has.
    enum BandRow {
        /// Caption under a track — a frequency in the strip, the Auto switch in
        /// the preamp column.
        static let labelHeight: CGFloat = 14
        /// Value above a track. Every column carries one, so the numbers form a
        /// single line across the top of the strip and the preamp reads on it.
        static let valueHeight: CGFloat = 14
        /// The value row and the gap under it.
        static var topChromeHeight: CGFloat { valueHeight + 6 }
        /// Everything in the column that isn't the track: a value above, a
        /// caption below, and the gap on either side of the track.
        static var chromeHeight: CGFloat { topChromeHeight + 6 + labelHeight }
        /// Floor for the track when the window is at its shortest.
        static let minSliderHeight: CGFloat = 96

        static let columnWidth: CGFloat = 26
        static let knobDiameter: CGFloat = 14
        static let trackWidth: CGFloat = 2
    }
}

extension View {
    /// A block in the content column: a border, and the window's own surface
    /// showing through.
    ///
    /// Deliberately no fill. These group controls; they are not surfaces of
    /// their own, and tinting each one turns a single canvas into a stack of
    /// panels. The response plot is the one exception — it *is* a surface, and
    /// keeps its fill.
    func contentBlock() -> some View {
        padding(Theme.blockPadding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.currentBlockBackground)
                    .strokeBorder(Theme.currentBlockBorder, lineWidth: 1)
            )
    }

}

extension UserDefaults {
    /// KVO bridge over the theme key, so `UserDefaults.publisher(for:)` has an
    /// `@objc` property to observe: the publisher needs a declared ObjC
    /// property, and the key lives in defaults, not on the instance. Reads the
    /// very value `Theme.isTokyoNight` reads, so the two cannot disagree.
    @objc dynamic var appThemeMode: String? {
        get { string(forKey: Theme.themeModeKey) }
        set { set(newValue, forKey: Theme.themeModeKey) }
    }
}
