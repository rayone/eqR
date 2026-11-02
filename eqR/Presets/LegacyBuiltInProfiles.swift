// swift-format-ignore-file
import Foundation

/// The 22 legacy built-in profiles shipped with eqR versions before the
/// 10 parametric presets update.
///
/// Retained exclusively for the one-time migration on first launch after update,
/// so that users who were using an old built-in preset keep their exact sound
/// as a user preset.
enum LegacyBuiltInProfiles {
    static let shelfQ = 0.7

    static let all: [EQProfile] = [
        profile("Flat",           [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        profile("Acoustic",       [1.75, 1.75, 4, 1, 2, 1.5, 2.5, 3, 3.5, 2, 2],
                [EQFilter(kind: .bell, frequency: 2_800, gain: 2, q: 1.2, colorIndex: 0),
                 EQFilter(kind: .lowShelf, frequency: 120, gain: 3.25, q: shelfQ, colorIndex: 1)]),
        profile("Bass Booster",   [3, 2.5, 2, 1.5, 0.75, 0, 0, 0, 0, 0, 0],
                [EQFilter(kind: .lowShelf, frequency: 120, gain: 4, q: shelfQ, colorIndex: 0)]),
        profile("Bass Reducer",   [-2.75, -2.25, -3.5, -2.5, -1.25, 0, 0, 0, 0, 0, 0],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: -3.25, q: shelfQ, colorIndex: 0)]),
        profile("Classical",      [1.75, 1.5, 3, 2.5, -1.5, -1.5, 0, 2, 3, 1.5, 1.5],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 3, q: shelfQ, colorIndex: 0),
                 EQFilter(kind: .highShelf, frequency: 10_000, gain: 2, q: shelfQ, colorIndex: 1)]),
        profile("Dance",          [1.75, 3.25, 5, 0, 2, 3.5, 5, 4.5, 3.5, 0, 0],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 3.75, q: shelfQ, colorIndex: 0)]),
        profile("Deep",           [3, 2, 1.5, 1, 3, 2.5, 1.5, -2, -3.5, -1.75, -1.75],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 2.5, q: shelfQ, colorIndex: 0),
                 EQFilter(kind: .highShelf, frequency: 10_000, gain: -2.25, q: shelfQ, colorIndex: 1)]),
        profile("Electronic",     [2.25, 2, 1.5, 0, -2, 2, 1, 1.5, 4, 1.75, 1.75],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 2.5, q: shelfQ, colorIndex: 0),
                 EQFilter(kind: .highShelf, frequency: 10_000, gain: 3, q: shelfQ, colorIndex: 1)]),
        profile("Hip-Hop",        [2.5, 2, 1.5, 3, -1, -1, 1.5, -0.5, 2, 1, 1],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 3, q: shelfQ, colorIndex: 0),
                 EQFilter(kind: .highShelf, frequency: 9_000, gain: 1.25, q: shelfQ, colorIndex: 1)]),
        profile("Jazz",           [1.5, 1.25, 1.5, 2, -1.5, -1.5, 0, 1.5, 3, 1.5, 1.5],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 2.5, q: shelfQ, colorIndex: 0),
                 EQFilter(kind: .highShelf, frequency: 10_000, gain: 2, q: shelfQ, colorIndex: 1)]),
        profile("Latin",          [2.25, 1.5, 0, 0, -1.5, -1.5, -1.5, 0, 3, 1.25, 1.25],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 2.25, q: shelfQ, colorIndex: 0),
                 EQFilter(kind: .highShelf, frequency: 10_000, gain: 2, q: shelfQ, colorIndex: 1)]),
        profile("Loudness",       [3.5, 2.5, 0, 0, -2, 0, -1, -4.5, 5, 1, 1],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 2.25, q: shelfQ, colorIndex: 0)]),
        profile("Lounge",         [-3, -1.5, -0.5, 1.5, 4, 2.5, 0, -1.5, 2, 1, 1]),
        profile("Piano",          [3, 2, 0, 2.5, 3, 1.5, 3.5, 4.5, 3, 1.5, 1.5],
                [EQFilter(kind: .highShelf, frequency: 10_000, gain: 2.5, q: shelfQ, colorIndex: 0)]),
        profile("Pop",            [-1.5, -1, 0, 2, 4, 4, 2, 0, -1, -1.5, -1.5]),
        profile("R&B",            [1.75, 3.75, 5.5, 1.5, -3, -1.5, 2, 2.5, 3, 1.5, 1.5],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 4, q: shelfQ, colorIndex: 0),
                 EQFilter(kind: .highShelf, frequency: 10_000, gain: 2.25, q: shelfQ, colorIndex: 1)]),
        profile("Rock",           [2, 1.5, 3, 1.5, -0.5, -1, 0.5, 2.5, 3.5, 1.75, 1.75],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 3.5, q: shelfQ, colorIndex: 0),
                 EQFilter(kind: .highShelf, frequency: 10_000, gain: 2.5, q: shelfQ, colorIndex: 1)]),
        profile("Small Speakers", [2.75, 2.25, 3.5, 2.5, 1.25, 0, -1.25, -2.5, -3.5, -1.75, -1.75],
                [EQFilter(kind: .lowShelf, frequency: 90, gain: 3.5, q: shelfQ, colorIndex: 0),
                 EQFilter(kind: .highShelf, frequency: 10_000, gain: -2.5, q: shelfQ, colorIndex: 1)]),
        profile("Spoken Word",    [-3.5, -0.5, 0, 0.5, 3.5, 4.5, 5, 4.5, 2.5, 0, 0]),
        profile("Treble Booster", [0, 0, 0, 0, 0, 1.25, 2.5, 3.5, 4.5, 3.5, 2],
                [EQFilter(kind: .highShelf, frequency: 9_000, gain: 2, q: shelfQ, colorIndex: 0)]),
        profile("Treble Reducer", [0, 0, 0, 0, 0, -1.25, -2.5, -3.5, -4.5, -2.25, -2.25],
                [EQFilter(kind: .highShelf, frequency: 10_000, gain: -3.25, q: shelfQ, colorIndex: 0)]),
        profile("Vocal Booster",  [-1.5, -3, -3, 1.5, 3.5, 3.5, 3, 1.5, 0, -1.5, -1.5]),
    ]

    static func profile(named name: String) -> EQProfile? {
        all.first { $0.name == name }
    }

    private static func profile(
        _ name: String,
        _ gains: [Double],
        _ filters: [EQFilter] = []
    ) -> EQProfile {
        assert(gains.count == BuiltInProfiles.frequencies.count)
        return EQProfile(
            name: name,
            filters: gains.enumerated().map { EQFilter.band(slot: $0, gain: $1) } + filters,
            preamp: 0,
            autoGain: true,
            spatialWidth: 1.0,
            isBuiltIn: false
        )
    }
}
