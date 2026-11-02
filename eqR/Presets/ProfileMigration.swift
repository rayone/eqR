import Foundation

/// Handles one-time migration of user presets and device states from eqR's
/// legacy 22 built-ins to the new set of 10 parametric presets.
enum ProfileMigration {
    /// Migrates user presets and device states if not already migrated.
    ///
    /// Preserves existing sounds on update:
    /// - User presets colliding with new built-ins (e.g. "Balanced") are renamed
    ///   so they are not shadowed or lost, and any device slots using them are repointed.
    /// - Device state slots using old built-ins that were removed (e.g. "Rock", "Lounge", "Spoken Word")
    ///   or whose definitions changed (e.g. "Acoustic") are saved as user presets with their
    ///   legacy values and repointed, creating at most one copy per preset.
    /// - Flat and untouched user presets remain unchanged.
    @MainActor
    static func migrateBuiltInsIfNeeded(settings: SettingsStore, force: Bool = false) {
        guard force || !settings.hasMigratedParametricBuiltIns else { return }

        var userProfiles = settings.userProfiles
        var deviceStates = settings.deviceStates
        let newBuiltIns = BuiltInProfiles.all
        let newBuiltInNames = Set(newBuiltIns.map(\.name))

        // Names currently taken by new built-ins or user presets
        var takenNames = newBuiltInNames.union(userProfiles.map(\.name))

        func makeUnique(from name: String) -> String {
            guard takenNames.contains(name) else { return name }
            var suffix = 2
            while takenNames.contains("\(name) \(suffix)") {
                suffix += 1
            }
            return "\(name) \(suffix)"
        }

        // Remapping for slot profile names: oldName -> newName
        var slotNameRemapping: [String: String] = [:]

        // Step 1: User presets whose names collide with a new built-in must be renamed
        // so they are not shadowed or dropped by PresetLibrary.
        for i in 0..<userProfiles.count {
            let currentName = userProfiles[i].name
            if newBuiltInNames.contains(currentName) {
                let newName = makeUnique(from: currentName)
                userProfiles[i].name = newName
                takenNames.insert(newName)
                slotNameRemapping[currentName] = newName
            }
        }

        // Existing user preset names after collision renaming
        let existingUserPresetNames = Set(userProfiles.map(\.name))

        // Step 2: Legacy built-in copies created during this migration
        var legacyCopies: [String: String] = [:]

        func processSlotProfileName(_ profileName: String) -> String {
            // Already remapped (e.g. from user preset collision)
            if let remapped = slotNameRemapping[profileName] {
                return remapped
            }

            // Flat is unchanged
            guard profileName != BuiltInProfiles.defaultProfileName else {
                return profileName
            }

            // If the slot points to an existing user preset, leave it alone
            if existingUserPresetNames.contains(profileName) {
                return profileName
            }

            // Check if this was a legacy built-in
            guard let legacyProfile = LegacyBuiltInProfiles.profile(named: profileName) else {
                return profileName
            }

            // Check if it was removed or if its definition changed
            let newMatching = newBuiltIns.first { $0.name == profileName }
            let needsMigration = (newMatching == nil) || !isSameProfile(legacyProfile, newMatching!)

            guard needsMigration else {
                return profileName
            }

            // Return cached copy if already created for another slot
            if let existingCopy = legacyCopies[profileName] {
                return existingCopy
            }

            // Determine target name: old name if free, else uniquify
            let targetName = makeUnique(from: profileName)
            takenNames.insert(targetName)

            var copy = legacyProfile
            copy.name = targetName
            copy.isBuiltIn = false
            userProfiles.append(copy)

            legacyCopies[profileName] = targetName
            slotNameRemapping[profileName] = targetName
            return targetName
        }

        // Repoint device states across all output devices
        for (deviceUID, var state) in deviceStates {
            state.profileName = processSlotProfileName(state.profileName)

            if var alternate = state.alternate {
                alternate.profileName = processSlotProfileName(alternate.profileName)
                state.alternate = alternate
            }

            deviceStates[deviceUID] = state
        }

        // Migrate legacy activeProfileName if present
        if let activeName = settings.activeProfileName {
            settings.activeProfileName = processSlotProfileName(activeName)
        }

        settings.userProfiles = userProfiles
        settings.deviceStates = deviceStates
        settings.hasMigratedParametricBuiltIns = true
    }

    /// Rename only the built-in identity; user-named presets and working edits survive.
    @MainActor
    static func migrateSpacePresetIfNeeded(settings: SettingsStore) {
        guard !settings.hasMigratedSpacePreset else { return }
        var profiles = settings.userProfiles
        var names = Set(profiles.map(\.name)).union(BuiltInProfiles.all.map(\.name))
        var remapping: [String: String] = [:]
        if !profiles.contains(where: { $0.name == "3D Wide" }) {
            remapping["3D Wide"] = "Space"
        }
        if let index = profiles.firstIndex(where: { $0.name == "Space" }) {
            var suffix = 2
            while names.contains("Space \(suffix)") { suffix += 1 }
            let renamed = "Space \(suffix)"
            profiles[index].name = renamed
            names.insert(renamed)
            remapping["Space"] = renamed
        }
        var states = settings.deviceStates
        for (device, var state) in states {
            state.profileName = remapping[state.profileName] ?? state.profileName
            if var alternate = state.alternate {
                alternate.profileName = remapping[alternate.profileName] ?? alternate.profileName
                state.alternate = alternate
            }
            states[device] = state
        }
        if let name = settings.activeProfileName {
            settings.activeProfileName = remapping[name] ?? name
        }
        settings.userProfiles = profiles
        settings.deviceStates = states
        settings.hasMigratedSpacePreset = true
    }

    private static func isSameProfile(_ a: EQProfile, _ b: EQProfile) -> Bool {
        a.preamp == b.preamp
            && a.autoGain == b.autoGain
            && a.spatialWidth == b.spatialWidth
            && a.filters == b.filters
    }
}
