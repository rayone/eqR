import Foundation

/// The predefined profiles shipped with eqR.
///
/// Built-in presets are parametric curves derived from equalizerapoguide.com's
/// tested Equalizer APO settings. Each loads as parametric filters with the
/// eleven ISO octave ladder bands sitting flat at 0 dB, leaving the Graphic
/// sliders free for user adjustments.
///
/// Every preset uses a fixed output trim (preamp) chosen to keep peaks below
/// full scale across the spectrum, preventing clipping without requiring
/// automatic gain adjustments. "Flat" remains the neutral baseline and default
/// profile.
enum BuiltInProfiles {
    static let frequencies: [Double] = [
        32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000, 20_000,
    ]

    /// Q of the ladder's bells: one octave of bandwidth, matching the spacing.
    static let defaultQ = 1.41

    /// Q of the shelves the presets reach for. For a shelf this is the knee,
    /// and 0.7 is the gentle slope that arrives at its plateau without a bump
    /// at the corner.
    static let shelfQ = 0.7

    static let gainRange: ClosedRange<Double> = -12...12

    /// Number of ladder slots, and so the number of sliders. Fixed by design:
    /// arbitrary centre frequencies live in free filters, not in a reshaped
    /// ladder.
    static var bandCount: Int { frequencies.count }

    /// How many filters the user may add on top of the ladder.
    ///
    /// A budget rather than a formality: each one is another pass over the
    /// buffer in `EQProcessor.processChannel`, and a listening application has
    /// no use for thirty of them.
    static let maxFreeFilters = 16

    /// Output trim range, matching the band range so the two read as one scale.
    static let preampRange: ClosedRange<Double> = -12...12

    /// Limits for the free filters' own parameters.
    /// AutoEq parametric gain bounds, independent of the graphic ladder.
    static let filterGainRange: ClosedRange<Double> = -20...20
    static let filterFrequencyRange: ClosedRange<Double> = 20...20_000
    /// Q for shelves and pass filters. Raising it does not make them narrower:
    /// a shelf overshoots and a pass filter grows a resonant bump at its corner,
    /// which is why AutoEq itself holds shelves at 0.7.
    static let filterQRange: ClosedRange<Double> = 0.1...10
    /// Q for a bell, which is the one shape a higher Q only narrows.
    ///
    /// Sixteen, about a twelfth of an octave, reaches the sharp resonances
    /// in-ear headphones are corrected with and a single whine to notch out.
    /// Not further, because a narrow boost rings: it keeps sounding for about
    /// Q / (π f) after the music stops, 51 ms at 100 Hz here against 32 ms at
    /// the old ceiling of 10. Studio EQs go to 40 or 100; a listening EQ has no
    /// use for that, and every step past this is ringing nobody asked for.
    static let bellQRange: ClosedRange<Double> = 0.1...16

    /// The Q range for a filter of `kind`.
    static func qRange(for kind: EQFilter.Kind) -> ClosedRange<Double> {
        kind == .bell ? bellQRange : filterQRange
    }

    static let all: [EQProfile] = [
        profile("Flat", preamp: 0, autoGain: true, spatialWidth: 1.0, filters: []),
        profile(
            "Balanced",
            preamp: -3.5,
            filters: [
                EQFilter(kind: .bell, frequency: 40, gain: 2.0, q: 0.7, colorIndex: 0),
                EQFilter(kind: .bell, frequency: 300, gain: -2.0, q: 1.1, colorIndex: 1),
                EQFilter(kind: .bell, frequency: 3_000, gain: -3.0, q: 1.4, colorIndex: 2),
                EQFilter(kind: .highShelf, frequency: 10_000, gain: 2.0, q: 0.7, colorIndex: 3),
            ]
        ),
        profile(
            "Bass Boost",
            preamp: -6.5,
            filters: [
                EQFilter(kind: .lowShelf, frequency: 105, gain: 6.0, q: 0.7, colorIndex: 0),
                EQFilter(kind: .bell, frequency: 250, gain: -2.5, q: 1.2, colorIndex: 1),
                EQFilter(kind: .bell, frequency: 3_000, gain: 1.5, q: 1.0, colorIndex: 2),
            ]
        ),
        profile(
            "Acoustic",
            preamp: -2.5,
            filters: [
                EQFilter(kind: .bell, frequency: 200, gain: -1.5, q: 1.0, colorIndex: 0),
                EQFilter(kind: .bell, frequency: 3_000, gain: 1.5, q: 1.2, colorIndex: 1),
                EQFilter(kind: .highShelf, frequency: 10_000, gain: 2.0, q: 0.7, colorIndex: 2),
            ]
        ),
        profile(
            "Voice",
            preamp: -3.5,
            filters: [
                EQFilter(kind: .highPass, frequency: 80, gain: 0, q: 0.71, colorIndex: 0),
                EQFilter(kind: .bell, frequency: 2_800, gain: 3.0, q: 1.1, colorIndex: 1),
                EQFilter(kind: .bell, frequency: 7_000, gain: -2.0, q: 2.5, colorIndex: 2),
            ]
        ),
        profile(
            "Movies & Dialogue",
            preamp: -5.0,
            filters: [
                EQFilter(kind: .bell, frequency: 80, gain: -5.0, q: 0.8, colorIndex: 0),
                EQFilter(kind: .bell, frequency: 1_800, gain: 3.0, q: 1.0, colorIndex: 1),
                EQFilter(kind: .bell, frequency: 3_200, gain: 3.5, q: 1.2, colorIndex: 2),
                EQFilter(kind: .bell, frequency: 8_000, gain: -2.0, q: 1.0, colorIndex: 3),
            ]
        ),
        profile(
            "Footsteps",
            preamp: -6.5,
            filters: [
                EQFilter(kind: .bell, frequency: 60, gain: -4.0, q: 0.8, colorIndex: 0),
                EQFilter(kind: .bell, frequency: 250, gain: -3.0, q: 1.1, colorIndex: 1),
                EQFilter(kind: .bell, frequency: 3_800, gain: 5.0, q: 1.4, colorIndex: 2),
                EQFilter(kind: .bell, frequency: 6_500, gain: 3.5, q: 1.6, colorIndex: 3),
            ]
        ),
        profile(
            "Laptop Speakers",
            preamp: -5.0,
            filters: [
                EQFilter(kind: .bell, frequency: 180, gain: 4.5, q: 1.0, colorIndex: 0),
                EQFilter(kind: .bell, frequency: 900, gain: -3.0, q: 1.5, colorIndex: 1),
                EQFilter(kind: .highShelf, frequency: 8_000, gain: -2.5, q: 0.7, colorIndex: 2),
            ]
        ),
        profile(
            "Night Listening",
            preamp: -4.0,
            filters: [
                EQFilter(kind: .lowShelf, frequency: 100, gain: 3.5, q: 0.7, colorIndex: 0),
                EQFilter(kind: .bell, frequency: 3_000, gain: 2.0, q: 1.0, colorIndex: 1),
                EQFilter(kind: .highShelf, frequency: 10_000, gain: 2.5, q: 0.7, colorIndex: 2),
            ]
        ),
        profile(
            "Space",
            preamp: -6.0,
            spatialWidth: 2.0,
            filters: [
                EQFilter(kind: .highShelf, frequency: 10_000, gain: 2.0, q: 0.7, colorIndex: 0)
            ]
        ),
    ]

    static let defaultProfileName = "Flat"

    /// What each built-in is for, in one line: the preset's tooltip in the
    /// sidebar and the menu.
    static let descriptions: [String: String] = [
        "Flat": String(
            localized: "No change: the sound exactly as it arrives.",
            comment: "Built-in preset description: Flat"),
        "Balanced": String(
            localized:
                "A gentle all-round tune-up: a little low-end weight, less boxiness and glare, more air.",
            comment: "Built-in preset description: Balanced"),
        "Bass Boost": String(
            localized: "More low end without the mud.",
            comment: "Built-in preset description: Bass Boost"),
        "Acoustic": String(
            localized: "Natural detail and air, with a touch less boom.",
            comment: "Built-in preset description: Acoustic"),
        "Voice": String(
            localized: "Speech forward and rumble cut, for podcasts, audiobooks, and calls.",
            comment: "Built-in preset description: Voice"),
        "Movies & Dialogue": String(
            localized: "Clearer voices and tamer explosions.",
            comment: "Built-in preset description: Movies & Dialogue"),
        "Footsteps": String(
            localized:
                "Footsteps and positional cues lifted in games, with the low-end rumble pulled back.",
            comment: "Built-in preset description: Footsteps"),
        "Laptop Speakers": String(
            localized: "More body and less boxiness for thin built-in speakers and cheap earbuds.",
            comment: "Built-in preset description: Laptop Speakers"),
        "Night Listening": String(
            localized: "Fuller lows and highs at low volume.",
            comment: "Built-in preset description: Night Listening"),
        "Space": String(
            localized: "A wider stereo image with extra treble.",
            comment: "Built-in preset description: Space"),
    ]

    /// A chain of eleven ladder filters at 0 dB — the shape every preset starts
    /// from, and what an untouched equalizer is.
    static func emptyBandChain() -> [EQFilter] {
        (0..<bandCount).map { EQFilter.band(slot: $0, gain: 0) }
    }

    private static func profile(
        _ name: String,
        preamp: Double = 0,
        autoGain: Bool = false,
        spatialWidth: Double = 1.0,
        filters: [EQFilter] = []
    ) -> EQProfile {
        EQProfile(
            name: name,
            filters: emptyBandChain() + filters,
            preamp: preamp,
            autoGain: autoGain,
            spatialWidth: spatialWidth,
            isBuiltIn: true
        )
    }
}
