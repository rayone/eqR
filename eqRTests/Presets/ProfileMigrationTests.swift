import Foundation
import Testing

@MainActor
struct ProfileMigrationTests {
    private let defaults: InMemoryDefaults
    private let settings: SettingsStore

    init() {
        defaults = InMemoryDefaults()
        settings = SettingsStore(defaults: defaults)
    }

    @Test func removedBuiltInIsCopiedToUserPreset() {
        // Slot uses "Spoken Word", which was removed in the new built-ins
        let legacySpokenWord = LegacyBuiltInProfiles.profile(named: "Spoken Word")
        #expect(legacySpokenWord != nil)

        settings.deviceStates = [
            "speakers": DeviceEQState(profileName: "Spoken Word")
        ]

        ProfileMigration.migrateBuiltInsIfNeeded(settings: settings)

        #expect(settings.hasMigratedParametricBuiltIns)
        #expect(settings.deviceStates["speakers"]?.profileName == "Spoken Word")

        let userPreset = settings.userProfiles.first { $0.name == "Spoken Word" }
        #expect(userPreset != nil)
        #expect(!userPreset!.isBuiltIn)
        #expect(userPreset?.filters == legacySpokenWord?.filters)
        #expect(userPreset?.preamp == legacySpokenWord?.preamp)
    }

    @Test func redefinedBuiltInIsCopiedUnderNonCollidingName() {
        // Slot uses "Acoustic", which exists in new built-ins but with changed definition
        let legacyAcoustic = LegacyBuiltInProfiles.profile(named: "Acoustic")
        #expect(legacyAcoustic != nil)

        settings.deviceStates = [
            "headphones": DeviceEQState(profileName: "Acoustic")
        ]

        ProfileMigration.migrateBuiltInsIfNeeded(settings: settings)

        #expect(settings.hasMigratedParametricBuiltIns)
        // Since "Acoustic" is a new built-in, the user preset copy is named "Acoustic 2"
        #expect(settings.deviceStates["headphones"]?.profileName == "Acoustic 2")

        let userPreset = settings.userProfiles.first { $0.name == "Acoustic 2" }
        #expect(userPreset != nil)
        #expect(!userPreset!.isBuiltIn)
        #expect(userPreset?.filters == legacyAcoustic?.filters)
        #expect(userPreset?.preamp == legacyAcoustic?.preamp)
    }

    @Test func userPresetCollidingWithNewBuiltInIsRenamed() {
        // User had a custom preset named "Balanced", which collides with new "Balanced" built-in
        let customFilters = [EQFilter(kind: .bell, frequency: 500, gain: 4, q: 1.0, colorIndex: 0)]
        let customPreset = EQProfile(
            name: "Balanced",
            filters: customFilters,
            preamp: -1.0,
            autoGain: false
        )
        settings.userProfiles = [customPreset]
        settings.deviceStates = [
            "desk": DeviceEQState(profileName: "Balanced")
        ]

        ProfileMigration.migrateBuiltInsIfNeeded(settings: settings)

        #expect(settings.hasMigratedParametricBuiltIns)
        // The user preset was renamed to avoid collision
        let renamedPreset = settings.userProfiles.first { $0.name == "Balanced 2" }
        #expect(renamedPreset != nil)
        #expect(renamedPreset?.filters == customFilters)
        #expect(renamedPreset?.preamp == -1.0)

        // The slot was repointed to the renamed user preset
        #expect(settings.deviceStates["desk"]?.profileName == "Balanced 2")
    }

    @Test func secondRunIsANoOp() {
        settings.deviceStates = [
            "speakers": DeviceEQState(profileName: "Lounge")
        ]

        ProfileMigration.migrateBuiltInsIfNeeded(settings: settings)

        let userProfilesAfterFirst = settings.userProfiles
        let deviceStatesAfterFirst = settings.deviceStates

        #expect(userProfilesAfterFirst.count == 1)
        #expect(userProfilesAfterFirst.first?.name == "Lounge")

        // Second run with flag already set
        ProfileMigration.migrateBuiltInsIfNeeded(settings: settings)
        #expect(settings.userProfiles == userProfilesAfterFirst)
        #expect(settings.deviceStates == deviceStatesAfterFirst)

        // Forced second run is also idempotent
        ProfileMigration.migrateBuiltInsIfNeeded(settings: settings, force: true)
        #expect(settings.userProfiles == userProfilesAfterFirst)
        #expect(settings.deviceStates == deviceStatesAfterFirst)
    }

    @Test func untouchedUserPresetsAndFlatAreUntouched() {
        let customPreset = EQProfile(
            name: "My Custom EQ",
            filters: BuiltInProfiles.emptyBandChain(),
            preamp: -2.0
        )
        settings.userProfiles = [customPreset]
        settings.deviceStates = [
            "speakers": DeviceEQState(profileName: "Flat"),
            "headphones": DeviceEQState(profileName: "My Custom EQ"),
        ]

        ProfileMigration.migrateBuiltInsIfNeeded(settings: settings)

        #expect(settings.userProfiles.map(\.name) == ["My Custom EQ"])
        #expect(settings.deviceStates["speakers"]?.profileName == "Flat")
        #expect(settings.deviceStates["headphones"]?.profileName == "My Custom EQ")
    }

    @Test func multipleSlotsShareOneUserPresetCopy() {
        // Two devices and an alternate slot all use "Rock"
        settings.deviceStates = [
            "device1": DeviceEQState(
                profileName: "Rock",
                alternate: WorkingState(profileName: "Rock")
            ),
            "device2": DeviceEQState(profileName: "Rock"),
        ]

        ProfileMigration.migrateBuiltInsIfNeeded(settings: settings)

        // Only one "Rock" user preset created
        #expect(settings.userProfiles.count == 1)
        #expect(settings.userProfiles.first?.name == "Rock")
        #expect(settings.deviceStates["device1"]?.profileName == "Rock")
        #expect(settings.deviceStates["device1"]?.alternate?.profileName == "Rock")
        #expect(settings.deviceStates["device2"]?.profileName == "Rock")
    }

    @Test func alternateSlotIsMigrated() {
        // Slot A on Flat, Slot B on Acoustic
        settings.deviceStates = [
            "device1": DeviceEQState(
                profileName: "Flat",
                alternate: WorkingState(profileName: "Acoustic")
            )
        ]

        ProfileMigration.migrateBuiltInsIfNeeded(settings: settings)

        #expect(settings.deviceStates["device1"]?.profileName == "Flat")
        #expect(settings.deviceStates["device1"]?.alternate?.profileName == "Acoustic 2")
        #expect(settings.userProfiles.map(\.name) == ["Acoustic 2"])
    }

    @Test func spaceRenamePreservesWorkingEditsAndBothSlots() {
        let edits = [EQFilter(kind: .bell, frequency: 700, gain: 3, q: 2)]
        settings.activeProfileName = "3D Wide"
        settings.deviceStates = [
            "speakers": DeviceEQState(
                profileName: "3D Wide", filters: edits, preamp: -5,
                spatialWidth: 1.7,
                alternate: WorkingState(
                    profileName: "3D Wide", filters: edits, preamp: -4, spatialWidth: 1.4))
        ]
        ProfileMigration.migrateSpacePresetIfNeeded(settings: settings)
        let state = settings.deviceStates["speakers"]
        #expect(state?.profileName == "Space")
        #expect(state?.alternate?.profileName == "Space")
        #expect(state?.filters == edits && state?.preamp == -5 && state?.spatialWidth == 1.7)
        #expect(state?.alternate?.filters == edits && state?.alternate?.spatialWidth == 1.4)
        #expect(settings.activeProfileName == "Space")
        let migrated = settings.deviceStates
        ProfileMigration.migrateSpacePresetIfNeeded(settings: settings)
        #expect(settings.deviceStates == migrated)
    }

    @Test func spaceRenameDoesNotShadowAUserPresetWithTheNewName() {
        let custom = [EQFilter(kind: .lowShelf, frequency: 120, gain: -3, q: 0.7)]
        settings.userProfiles = [
            EQProfile(name: "Space", filters: custom),
            EQProfile(name: "Space 2", filters: []),
        ]
        settings.deviceStates = [
            "speakers": DeviceEQState(
                profileName: "3D Wide", alternate: WorkingState(profileName: "Space"))
        ]
        ProfileMigration.migrateSpacePresetIfNeeded(settings: settings)
        #expect(settings.deviceStates["speakers"]?.profileName == "Space")
        #expect(settings.deviceStates["speakers"]?.alternate?.profileName == "Space 3")
        #expect(settings.userProfiles.first?.name == "Space 3")
        #expect(settings.userProfiles.first?.filters == custom)
    }

    @Test func userPresetNamed3DWideIsNotRenamed() {
        let custom = [EQFilter(kind: .bell, frequency: 400, gain: -6, q: 1)]
        settings.userProfiles = [EQProfile(name: "3D Wide", filters: custom)]
        settings.deviceStates = ["speakers": DeviceEQState(profileName: "3D Wide")]
        ProfileMigration.migrateSpacePresetIfNeeded(settings: settings)
        #expect(settings.deviceStates["speakers"]?.profileName == "3D Wide")
        #expect(settings.userProfiles.first?.filters == custom)
        #expect(settings.userProfiles.first?.name == "3D Wide")
    }
}
