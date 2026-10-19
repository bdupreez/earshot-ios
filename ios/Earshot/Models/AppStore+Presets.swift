import Foundation

@MainActor
extension AppStore {
    /// Recovery data is written before any persisted record is discarded or transformed.
    @discardableResult
    func normalizePresetLibrary() -> String? {
        let original = saved.customPresets
        var repaired: [EQPreset] = []
        var seen = Set(BuiltInPresets.all.map(\.id))
        var changed = 0
        var discarded = 0
        for candidate in original {
            guard repaired.count < PresetValidation.maximumPresets else { discarded += 1; continue }
            guard var value = try? PresetValidation.validated(candidate) else { discarded += 1; continue }
            if value.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || seen.contains(value.id) { value.id = UUID().uuidString }
            seen.insert(value.id)
            value.isBuiltIn = false
            value.name = PresetValidation.uniqueName(value.name, existing: BuiltInPresets.all + repaired)
            if value != candidate { changed += 1 }
            repaired.append(value)
        }
        let libraryChanged = repaired != original
        if libraryChanged {
            do { _ = try PresetRecovery.save(original) }
            catch { return "The preset library needs repair, but its recovery copy could not be saved: \(error.localizedDescription). Original presets were retained." }
            saved.customPresets = repaired
        }
        let selectedExists = (BuiltInPresets.all + repaired).contains { $0.id == saved.presetID }
        if !selectedExists { saved.presetID = BuiltInPresets.flat.id }
        guard libraryChanged || !selectedExists else { return nil }
        let details = discarded > 0 ? " \(discarded) invalid or excess record\(discarded == 1 ? " was" : "s were") excluded from the active library." : ""
        return "Preset library repaired (\(changed) updated).\(details)" + (libraryChanged ? " Export the original JSON from Sound → Pro EQ → Export recovered preset data." : " The missing selection was reset to Flat.")
    }

    var effectiveAudioPreamp: Double {
        audioGainPlan.preampDb
    }

    var audioGainPlan: AudioGainPlan {
        let sampleRate = audio.processingSampleRate
        let requested = saved.audioOptions.automaticHeadroom ? min(preset.preampDb, Headroom.recommendedPreampDb(bands: preset.bands, sampleRate: sampleRate)) : saved.audioOptions.manualPreampDb.clamped(to: -30...0)
        return AudioGainPlan(bands: preset.bands, requestedPreampDb: requested, boostDb: saved.boost, limiterEnabled: saved.audioOptions.limiterEnabled, sampleRate: sampleRate)
    }

    @discardableResult
    func createUserPreset(_ candidate: EQPreset) throws -> EQPreset {
        guard saved.customPresets.count < PresetValidation.maximumPresets else { throw PresetValidationError.libraryFull }
        var value = try PresetValidation.validated(candidate)
        value.id = UUID().uuidString
        value.isBuiltIn = false
        value.name = PresetValidation.uniqueName(value.name, existing: presets)
        saved.customPresets.append(value)
        choosePreset(value.id)
        return value
    }

    func updateUserPreset(_ candidate: EQPreset) throws {
        guard !candidate.isBuiltIn, BuiltInPresets.byID(candidate.id) == nil else { throw PresetValidationError.protectedPreset }
        guard let index = saved.customPresets.firstIndex(where: { $0.id == candidate.id }) else { throw PresetValidationError.missingPreset }
        var value = try PresetValidation.validated(candidate)
        value.isBuiltIn = false
        value.name = PresetValidation.uniqueName(value.name, existing: presets, excludingID: value.id)
        saved.customPresets[index] = value
        if saved.presetID == value.id { applyAudio() }
    }

    func renameUserPreset(id: String, name: String) throws {
        guard BuiltInPresets.byID(id) == nil else { throw PresetValidationError.protectedPreset }
        guard var value = saved.customPresets.first(where: { $0.id == id }) else { throw PresetValidationError.missingPreset }
        value.name = name
        try updateUserPreset(value)
    }

    func deleteUserPreset(id: String) {
        guard BuiltInPresets.byID(id) == nil else { message = PresetValidationError.protectedPreset.localizedDescription; return }
        guard saved.customPresets.contains(where: { $0.id == id }) else { return }
        let affectedRules = saved.rules.filter { rule in
            rule.effectiveActions.contains { action in
                if case .preset(let referencedID) = action { return referencedID == id }
                return false
            }
        }.map(\.name)
        saved.customPresets.removeAll { $0.id == id }
        if saved.presetID == id { choosePreset(BuiltInPresets.flat.id) }
        if !affectedRules.isEmpty { message = "Preset deleted. Choose another EQ preset in these automation rules before running them: \(affectedRules.joined(separator: ", "))." }
    }

    @discardableResult
    func importUserPresets(text: String, name: String = "Imported preset") throws -> PresetImportSummary {
        let candidates = try PresetCodec.importPresets(text: text, name: name)
        var working = saved.customPresets
        var skipped = 0
        var imported = 0
        var selected: String?
        for candidate in candidates {
            var value = try PresetValidation.validated(candidate)
            let duplicate = (BuiltInPresets.all + working).first { $0.bands == value.bands && $0.preampDb == value.preampDb }
            if let duplicate { skipped += 1; selected = duplicate.id; continue }
            guard working.count < PresetValidation.maximumPresets else { throw PresetValidationError.libraryFull }
            value.id = UUID().uuidString
            value.isBuiltIn = false
            value.name = PresetValidation.uniqueName(value.name, existing: BuiltInPresets.all + working)
            working.append(value)
            selected = value.id
            imported += 1
        }
        // Commit only after every imported record validates and capacity checks pass.
        saved.customPresets = working
        if let selected { choosePreset(selected) }
        return PresetImportSummary(imported: imported, skippedDuplicates: skipped)
    }
}
