import Foundation
import Testing

struct BuiltInProfilesTests {
    @Test(arguments: BuiltInProfiles.all) func everyProfileMatchesTheBandLadder(profile: EQProfile)
    {
        #expect(
            profile.bandFilters.map(\.frequency) == BuiltInProfiles.frequencies,
            "\(profile.name) does not sit on the shared band ladder")
    }

    /// Built-in presets load parametric filters with the graphic ladder sitting flat at 0 dB.
    @Test(arguments: BuiltInProfiles.all) func graphicLadderBandsAreFlat(profile: EQProfile) {
        #expect(
            profile.bandFilters.allSatisfy { $0.gain == 0 },
            "\(profile.name) has graphic ladder bands not set to 0 dB"
        )
    }

    /// Every built-in profile must fit within the free filter cap.
    @Test(arguments: BuiltInProfiles.all) func builtInProfilesFitWithinFreeFilterCap(
        profile: EQProfile
    ) {
        #expect(
            profile.freeFilters.count <= BuiltInProfiles.maxFreeFilters,
            "\(profile.name) ships with more filters than maxFreeFilters allows")
        #expect(
            profile.filters.count == BuiltInProfiles.bandCount + profile.freeFilters.count,
            "\(profile.name) is not the ladder followed by its filters")
        for filter in profile.freeFilters {
            #expect(BuiltInProfiles.filterFrequencyRange.contains(filter.frequency))
            #expect(BuiltInProfiles.qRange(for: filter.kind).contains(filter.q))
            #expect(BuiltInProfiles.filterGainRange.contains(filter.gain))
        }
    }

    /// Invariant: every built-in profile's peak response plus its preamp stays at or below 0 dB,
    /// preventing digital clipping without needing automatic attenuation.
    @Test(arguments: BuiltInProfiles.all) func peakBoostPlusPreampStaysBelowFullScale(
        profile: EQProfile
    ) {
        let rate = 48_000.0
        var maxTotal = -Double.infinity
        for i in 0...200 {
            let freq = 20.0 * pow(1_000.0, Double(i) / 200.0)
            let total = response(profile.filters, at: freq, rate: rate) + profile.preamp
            if total > maxTotal {
                maxTotal = total
            }
        }
        #expect(
            maxTotal <= 0.05,
            "\(profile.name) peak response + preamp is \(maxTotal) dB, exceeding full scale"
        )
    }

    private func response(_ filters: [EQFilter], at frequency: Double, rate: Double) -> Double {
        filters.reduce(0.0) {
            $0 + Biquad(filter: $1, sampleRate: rate).magnitudeDB(at: frequency, sampleRate: rate)
        }
    }

    @Test(arguments: BuiltInProfiles.all) func everyBandCarriesItsLadderSlot(profile: EQProfile) {
        #expect(
            profile.bandFilters.map(\.band) == Array(0..<BuiltInProfiles.bandCount),
            "\(profile.name) has bands out of slot order")
    }

    @Test(arguments: BuiltInProfiles.all) func everyGainIsWithinRange(profile: EQProfile) {
        for band in profile.bandFilters {
            #expect(
                BuiltInProfiles.gainRange.contains(band.gain),
                "\(profile.name) at \(band.frequency) Hz is \(band.gain) dB, outside the slider range"
            )
        }
    }

    @Test func namesAreUnique() {
        let names = BuiltInProfiles.all.map(\.name)
        #expect(
            Set(names).count == names.count,
            "built-in profile names must be unique — they are the identifiers")
        #expect(names.count == 10, "exactly ten built-in profiles")
    }

    @Test func flatIsFlatAndIsTheDefault() {
        let flat = BuiltInProfiles.all.first { $0.name == BuiltInProfiles.defaultProfileName }
        #expect(flat != nil)
        #expect(flat?.name == "Flat")
        #expect(flat?.filters.allSatisfy { $0.gain == 0 } ?? false)
        #expect(flat?.freeFilters.isEmpty ?? false)
    }

    @Test func allProfilesAreMarkedBuiltIn() {
        #expect(BuiltInProfiles.all.allSatisfy { $0.isBuiltIn })
    }

    @Test func ladderIsAscending() {
        #expect(BuiltInProfiles.frequencies == BuiltInProfiles.frequencies.sorted())
    }

    /// `isBuiltIn` is deliberately outside `CodingKeys`, because only user
    /// profiles are ever persisted.
    @Test func roundTripDecodingYieldsAUserProfile() throws {
        let original = BuiltInProfiles.all[1]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EQProfile.self, from: data)

        #expect(decoded.name == original.name)
        #expect(decoded.filters == original.filters)
        #expect(!decoded.isBuiltIn, "a decoded profile is always a user profile")
    }

    /// `EQFilter.id` is outside both `CodingKeys` and `==`, so a chain restored
    /// from disk compares equal to the one it was saved from. Without this,
    /// `ProfileManager.isModified` would report every launch as edited.
    @Test func decodedFiltersCompareEqualDespiteFreshIdentifiers() throws {
        let original = BuiltInProfiles.all[3].filters
        let decoded = try JSONDecoder().decode(
            [EQFilter].self, from: JSONEncoder().encode(original))

        #expect(decoded == original)
        #expect(decoded.map(\.id) != original.map(\.id))
    }

    /// Presets written by eqR 1.x stored a `bands` array with no kind, no
    /// enabled flag, and no slot. They have to keep working.
    @Test func legacyBandsPresetMigratesIntoLadderFilters() throws {
        let legacy = """
            {"name":"Old","bands":[
              {"frequency":32,"gain":4,"q":1.41},
              {"frequency":64,"gain":-2,"q":1.41}
            ]}
            """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EQProfile.self, from: legacy)
        #expect(decoded.name == "Old")
        #expect(decoded.filters.count == 2)
        #expect(decoded.filters.map(\.band) == [0, 1])
        #expect(decoded.filters.map(\.gain) == [4, -2])
        #expect(decoded.filters.allSatisfy { $0.kind == .bell && $0.isEnabled })
    }
    // MARK: - Descriptions

    /// Every built-in carries its one line, so no tooltip is ever blank.
    @Test func everyBuiltInHasADescription() {
        for profile in BuiltInProfiles.all {
            let line = BuiltInProfiles.descriptions[profile.name] ?? ""
            #expect(!line.isEmpty, "\(profile.name) has no description")
        }
    }

    /// A renamed or removed preset must not leave its line behind.
    @Test func everyDescriptionNamesABuiltIn() {
        let names = Set(BuiltInProfiles.all.map(\.name))
        for name in BuiltInProfiles.descriptions.keys {
            #expect(names.contains(name), "\(name) is described but not a built-in")
        }
    }

    /// One line: a tooltip, not a paragraph.
    @Test func descriptionsAreOneShortLine() {
        for (name, line) in BuiltInProfiles.descriptions {
            #expect(!line.contains("\n"), "\(name)")
            #expect(line.count <= 110, "\(name) is \(line.count) characters")
        }
    }

    // MARK: - Q

    /// Issue #41: a bell can go narrower, to about a twelfth of an octave. The
    /// other kinds keep the old ceiling, because a higher Q does not narrow
    /// them — it makes a shelf overshoot and a pass filter resonate.
    @Test func onlyABellReachesQSixteen() {
        #expect(BuiltInProfiles.qRange(for: .bell) == 0.1...16)
        for kind in EQFilter.Kind.allCases where kind != .bell {
            #expect(BuiltInProfiles.qRange(for: kind) == 0.1...10, "\(kind.title)")
        }
    }
}
