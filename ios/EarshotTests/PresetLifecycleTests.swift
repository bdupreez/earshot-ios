import XCTest
@testable import Earshot

final class PresetLifecycleTests: XCTestCase {
    func testImportRejectsOversizedTextCollectionsAndFilterArrays() throws {
        XCTAssertThrowsError(try PresetCodec.importPresets(text: String(repeating: "x", count: PresetValidation.maximumFileBytes + 1)))
        XCTAssertThrowsError(try PresetCodec.importPresets(text: "[]"))
        let tooMany = Array(repeating: userPreset(), count: PresetValidation.maximumPresets + 1)
        XCTAssertThrowsError(try PresetCodec.importPresets(text: PresetCodec.encodePresets(tooMany)))
        var excessive = userPreset()
        excessive.bands = Array(repeating: EQBand(frequencyHz: 1000, gainDb: 0), count: 129)
        XCTAssertThrowsError(try PresetCodec.importPresets(text: PresetCodec.encodePresets([excessive])))
    }

    func testValidationRejectsInvalidAndUnsafeEdits() {
        var preset = userPreset()
        preset.name = " \n "
        XCTAssertThrowsError(try PresetValidation.validated(preset))
        preset = userPreset(); preset.bands = []
        XCTAssertThrowsError(try PresetValidation.validated(preset))
        preset = userPreset(); preset.bands[0].frequencyHz = .infinity
        XCTAssertThrowsError(try PresetValidation.validated(preset))
        preset = userPreset(); preset.bands[0].q = 0
        XCTAssertThrowsError(try PresetValidation.validated(preset))
        preset = userPreset(); preset.preampDb = 4
        XCTAssertThrowsError(try PresetValidation.validated(preset))
        preset = userPreset(); preset.bands = Array(repeating: EQBand(frequencyHz: 1000, gainDb: 15), count: 12)
        XCTAssertThrowsError(try PresetValidation.validated(preset))
    }

    func testGraphicConversionPreservesCanonicalGainsAndCanRestoreParametricExactly() {
        let original = EQPreset(id: "original", name: "Original", bands: [
            EQBand(frequencyHz: 105, gainDb: 4.5, q: 0.7, type: .lowShelf),
            EQBand(frequencyHz: 2400, gainDb: -3.2, q: 5.4),
            EQBand(frequencyHz: 12_000, gainDb: 2.5, q: 0.9, type: .highShelf, enabled: false)
        ], preampDb: -4)
        var draft = PresetEditorDraft(preset: original)
        draft.useGraphicLayout()
        XCTAssertTrue(draft.graphic)
        XCTAssertEqual(draft.preset.bands.count, 10)
        XCTAssertTrue(draft.preset.bands.contains { abs($0.gainDb) > 1 })
        XCTAssertEqual(draft.preset.name, original.name)
        XCTAssertEqual(draft.preset.preampDb, original.preampDb)
        let graphic = draft.preset.bands
        draft.useParametricLayout()
        XCTAssertEqual(draft.preset.bands, graphic, "Changing editor layouts must not erase graphic edits")
        draft.restoreParametricFilters()
        XCTAssertEqual(draft.preset, original, "Shelf type, Q, disabled flag and gain must survive exact restoration")
        let gains = [-2.0, -1, 0, 1, 2, 3, 4, 5, 6, 7]
        let canonical = GraphicEQ.bandsFromGains(gains)
        XCTAssertEqual(GraphicEQ.approximateBands(from: canonical), canonical)
    }

    func testAutomaticHeadroomCanCompensateMoreThanThirtyDecibels() throws {
        let preset = EQPreset(id: "overlap", name: "Overlap", bands: Array(repeating: EQBand(frequencyHz: 1000, gainDb: 15, q: 1), count: 3))
        let preamp = Headroom.recommendedPreampDb(bands: preset.bands)
        XCTAssertLessThan(preamp, -40)
        let samples = (0..<24_000).map { Float(0.1 * sin(2 * Double.pi * 1000 * Double($0) / 48_000)) }
        let rendered = try NativeEQRenderer.render(samples: samples, preset: preset, preamp: preamp)
        func rms(_ values: [Float]) -> Double {
            let tail = values.dropFirst(4096)
            return sqrt(tail.reduce(0) { $0 + Double($1 * $1) } / Double(tail.count))
        }
        XCTAssertEqual(rms(rendered) / rms(samples), 1, accuracy: 0.1)
    }

    func testRemoveAndReorderPreserveRemainingFiltersAndKeepOneBand() {
        var preset = userPreset()
        preset.bands = [EQBand(frequencyHz: 100, gainDb: 1), EQBand(frequencyHz: 500, gainDb: 2), EQBand(frequencyHz: 5000, gainDb: 3)]
        var draft = PresetEditorDraft(preset: preset)
        draft.moveFilter(from: 2, to: 0)
        XCTAssertEqual(draft.preset.bands.map(\.frequencyHz), [5000, 100, 500])
        draft.removeFilters(at: IndexSet([0, 2]))
        XCTAssertEqual(draft.preset.bands, [preset.bands[0]])
        draft.removeFilters(at: IndexSet(integer: 0))
        XCTAssertEqual(draft.preset.bands.count, 1)
        draft.moveFilter(from: 8, to: 0)
        XCTAssertEqual(draft.preset.bands.count, 1)
    }

    @MainActor
    func testCreateEditAndRenameCustomPresetPreserveIdentityAndProtectBuiltIns() throws {
        let fixture = makeStore(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        var custom = try store.createUserPreset(BuiltInPresets.bassBoost)
        XCTAssertNotEqual(custom.id, BuiltInPresets.bassBoost.id)
        XCTAssertFalse(custom.isBuiltIn)
        XCTAssertNotEqual(custom.name, BuiltInPresets.bassBoost.name)
        let id = custom.id
        custom.bands[0].gainDb = 2
        try store.updateUserPreset(custom)
        XCTAssertEqual(store.saved.customPresets.count, 1)
        XCTAssertEqual(store.preset.id, id)
        XCTAssertEqual(store.preset.bands[0].gainDb, 2)
        try store.renameUserPreset(id: id, name: "  My commute  ")
        XCTAssertEqual(store.preset.name, "My commute")
        XCTAssertThrowsError(try store.updateUserPreset(BuiltInPresets.flat))
        XCTAssertThrowsError(try store.renameUserPreset(id: "flat", name: "Changed"))
        XCTAssertThrowsError(try store.renameUserPreset(id: id, name: "   "))
        XCTAssertEqual(BuiltInPresets.bassBoost.bands[0].gainDb, 5)
    }

    @MainActor
    func testDeleteUsesSafeFallbackAndLeavesOtherSelectionAlone() throws {
        let fixture = makeStore(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        let first = try store.createUserPreset(userPreset(name: "One", gain: 2))
        let second = try store.createUserPreset(userPreset(name: "Two", gain: 4))
        store.deleteUserPreset(id: first.id)
        XCTAssertEqual(store.preset.id, second.id)
        store.deleteUserPreset(id: second.id)
        XCTAssertEqual(store.saved.presetID, "flat")
        XCTAssertTrue(store.saved.customPresets.isEmpty)
        store.deleteUserPreset(id: "flat")
        XCTAssertEqual(store.preset, BuiltInPresets.flat)
        XCTAssertNotNil(store.message)
    }

    @MainActor
    func testDeletingReferencedPresetLeavesActionableRuleReference() throws {
        let fixture = makeStore(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        let preset = try store.createUserPreset(userPreset())
        var rule = AutomationRule(name: "Morning music")
        rule.actions = [.preset(preset.id)]
        store.saved.rules = [rule]
        store.deleteUserPreset(id: preset.id)
        XCTAssertTrue(store.message?.contains("Morning music") == true)
        XCTAssertEqual(store.saved.rules.first?.effectiveActions, [.preset(preset.id)])
    }

    @MainActor
    func testImportRegeneratesCollidingIDsAndSkipsRepeatedContent() throws {
        let fixture = makeStore(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        let incoming = [userPreset(name: "Collision", gain: 2), userPreset(name: "Collision", gain: 4)]
        let text = try PresetCodec.encodePresets(incoming)
        let first = try store.importUserPresets(text: text)
        XCTAssertEqual(first, PresetImportSummary(imported: 2, skippedDuplicates: 0))
        XCTAssertEqual(Set(store.saved.customPresets.map(\.id)).count, 2)
        XCTAssertFalse(store.saved.customPresets.contains { $0.id == "source" })
        XCTAssertEqual(Set(store.saved.customPresets.map(\.name)).count, 2)
        let second = try store.importUserPresets(text: text)
        XCTAssertEqual(second, PresetImportSummary(imported: 0, skippedDuplicates: 2))
        XCTAssertEqual(store.saved.customPresets.count, 2)
    }

    @MainActor
    func testImportValidationAndLibraryCapAreAtomic() throws {
        let fixture = makeStore(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        var invalid = userPreset(name: "Invalid"); invalid.bands = []
        let text = try PresetCodec.encodePresets([userPreset(), invalid])
        XCTAssertThrowsError(try store.importUserPresets(text: text))
        XCTAssertTrue(store.saved.customPresets.isEmpty)
        XCTAssertEqual(store.saved.presetID, "flat")
        store.saved.customPresets = (0..<250).map { index in
            EQPreset(id: "p\(index)", name: "Preset \(index)", bands: [EQBand(frequencyHz: Double(100 + index * 50), gainDb: 1)])
        }
        let full = store.saved.customPresets
        XCTAssertThrowsError(try store.createUserPreset(userPreset()))
        XCTAssertThrowsError(try store.importUserPresets(text: PresetCodec.encodePresets([userPreset()])))
        XCTAssertEqual(store.saved.customPresets, full)
    }

    @MainActor
    func testPresetEditsAndAudioOptionsPersistAndLegacyStateGetsDefaults() throws {
        let fixture = makeStore(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        let preset = try store.createUserPreset(userPreset())
        try store.renameUserPreset(id: preset.id, name: "Saved name")
        store.saved.audioOptions.automaticHeadroom = false
        store.saved.audioOptions.manualPreampDb = -7.5
        store.saved.audioOptions.limiterEnabled = false
        let restored = AppStore(defaults: fixture.defaults, arguments: [])
        XCTAssertEqual(restored.preset.id, preset.id)
        XCTAssertEqual(restored.preset.name, "Saved name")
        XCTAssertEqual(restored.saved.audioOptions, store.saved.audioOptions)
        XCTAssertEqual(restored.effectiveAudioPreamp, -7.5)
        let legacy = try JSONDecoder().decode(SavedAppState.self, from: Data(#"{"presetID":"bass","boost":2}"#.utf8))
        XCTAssertEqual(legacy.audioOptions, AudioPlaybackOptions())
        XCTAssertEqual(legacy.presetID, "bass")
    }

    @MainActor
    func testNormalizationRepairsIdentityAndRetainsRecoveryDataBeforeExclusion() throws {
        let fixture = makeStore(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        var reserved = userPreset(name: "Flat", gain: 2); reserved.id = "flat"; reserved.isBuiltIn = true
        var duplicate = userPreset(name: "Flat", gain: 3); duplicate.id = "flat"
        var invalid = userPreset(); invalid.bands[0].frequencyHz = 90_000
        let original = [reserved, duplicate, invalid]
        store.saved.customPresets = original
        store.saved.presetID = "missing"
        let before = PresetRecovery.latestBackupURL
        XCTAssertNotNil(store.normalizePresetLibrary())
        let backup = try XCTUnwrap(PresetRecovery.latestBackupURL)
        defer { if backup != before { try? FileManager.default.removeItem(at: backup) } }
        XCTAssertEqual(try JSONDecoder().decode([EQPreset].self, from: Data(contentsOf: backup)), original)
        XCTAssertEqual(store.saved.customPresets.count, 2)
        XCTAssertEqual(Set(store.saved.customPresets.map(\.id)).count, 2)
        XCTAssertFalse(store.saved.customPresets.contains { $0.id == "flat" || $0.isBuiltIn })
        XCTAssertEqual(Set(store.saved.customPresets.map(\.name)).count, 2)
        XCTAssertEqual(store.saved.presetID, "flat")
        XCTAssertNil(store.normalizePresetLibrary(), "Normalized records should be stable across launches")
    }

    @MainActor
    func testNormalizationBoundsActiveLibraryButBacksUpEveryOriginalRecord() throws {
        let fixture = makeStore(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        store.saved.customPresets = (0..<251).map { index in EQPreset(id: "p\(index)", name: "Preset \(index)", bands: [EQBand(frequencyHz: 1000, gainDb: 0)]) }
        let before = PresetRecovery.latestBackupURL
        XCTAssertNotNil(store.normalizePresetLibrary())
        let backup = try XCTUnwrap(PresetRecovery.latestBackupURL)
        defer { if backup != before { try? FileManager.default.removeItem(at: backup) } }
        XCTAssertEqual(store.saved.customPresets.count, 250)
        XCTAssertEqual(try JSONDecoder().decode([EQPreset].self, from: Data(contentsOf: backup)).count, 251)
    }

    func testMalformedSavedPresetDoesNotEraseValidPresetsOrUnrelatedPreferences() throws {
        let data = Data(#"{"theme":"Dark","presetID":"valid","customPresets":[{"id":"valid","name":"Saved","bands":[{"frequencyHz":1000,"gainDb":2}]},{"id":"bad","name":"Bad","bands":[{"frequencyHz":-5,"gainDb":2}]}]}"#.utf8)
        let restored = try JSONDecoder().decode(SavedAppState.self, from: data)
        XCTAssertEqual(restored.theme, "Dark")
        XCTAssertEqual(restored.presetID, "valid")
        XCTAssertEqual(restored.customPresets.map(\.id), ["valid"])
    }

    @MainActor
    func testLocalPlayerDurationSeekBoundsAndABComparison() throws {
        let audio = LocalAudioEngine()
        try audio.loadDemo()
        XCTAssertEqual(audio.duration, 12, accuracy: 0.01)
        audio.seek(to: 5)
        XCTAssertEqual(audio.position, 5, accuracy: 0.01)
        XCTAssertFalse(audio.isPlaying)
        audio.skip(seconds: -15)
        XCTAssertEqual(audio.position, 0)
        audio.seek(to: 50)
        XCTAssertEqual(audio.position, audio.duration)
        audio.seek(to: .infinity)
        XCTAssertEqual(audio.position, audio.duration)
        audio.setBypassed(true)
        XCTAssertTrue(audio.isBypassed)
        audio.apply(preset: BuiltInPresets.bassBoost)
        XCTAssertTrue(audio.isBypassed, "Selecting settings must preserve the user's A/B comparison state")
        audio.setBypassed(false)
        audio.stop()
        XCTAssertEqual(audio.position, 0)
    }

    @MainActor
    func testSeekingDuringPlaybackResumesAndPauseFreezesProgress() async throws {
        let audio = LocalAudioEngine()
        defer { audio.stop() }
        try audio.loadDemo()
        audio.playPause()
        XCTAssertTrue(audio.isPlaying, audio.status)
        audio.seek(to: 6)
        XCTAssertTrue(audio.isPlaying, audio.status)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertGreaterThan(audio.position, 6.05)
        audio.playPause()
        let paused = audio.position
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(audio.isPlaying)
        XCTAssertEqual(audio.position, paused, accuracy: 0.01)
    }

    private func userPreset(name: String = "User", gain: Double = 2) -> EQPreset {
        EQPreset(id: "source", name: name, bands: [EQBand(frequencyHz: 1000, gainDb: gain, q: 1)], preampDb: -3)
    }

    @MainActor
    private func makeStore() -> (store: AppStore, defaults: UserDefaults, suite: String) {
        let suite = "EarshotPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AppStore(defaults: defaults, arguments: []), defaults, suite)
    }
}
