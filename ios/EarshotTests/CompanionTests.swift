// Fixture and on-disk tests for the AI-assisted port of HellzYeahh/earshot (MIT).
// These do not claim physical headset, microphone routing or spoken-audio verification.
import AVFoundation
import XCTest
@testable import Earshot

final class CompanionTests: XCTestCase {
    func testPreferencesMigrateMissingKeysAndKeepValidRecordsBesideMalformedOnes() throws {
        let json = Data(#"{"outputEQ":{"a":{"enabled":true,"presetID":"bass"},"b":{"enabled":"broken"},"c":{"enabled":false}},"outputActions":{"a":"cycleEQ","b":"future_action"}}"#.utf8)
        let decoded = try JSONDecoder().decode(HeadsetPreferences.self, from: json)
        XCTAssertTrue(decoded.rememberEQ)
        XCTAssertTrue(decoded.spokenFeedback)
        XCTAssertEqual(decoded.defaultAction, .none)
        XCTAssertEqual(decoded.outputEQ["a"], .preset("bass"))
        XCTAssertEqual(decoded.outputEQ["c"], .off)
        XCTAssertNil(decoded.outputEQ["b"])
        XCTAssertEqual(decoded.action(for: "a"), .cycleEQ)
        XCTAssertEqual(decoded.action(for: "b"), .none)
    }

    func testOutputMemoryRetainsOffAndKeepsSameNameDistinctUIDs() throws {
        var settings = HeadsetPreferences()
        XCTAssertTrue(settings.remember(.preset("bass"), outputID: "output-A"))
        XCTAssertTrue(settings.remember(.off, outputID: "output-B"))
        XCTAssertTrue(settings.setAction(.voiceMemo, outputID: "output-A"))
        let restored = try JSONDecoder().decode(HeadsetPreferences.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored.outputEQ["output-A"], .preset("bass"))
        XCTAssertEqual(restored.outputEQ["output-B"], .off)
        XCTAssertEqual(restored.action(for: "output-A"), .voiceMemo)
        XCTAssertEqual(restored.action(for: nil), .none)
    }

    func testPreferenceCapsAndOverrideRemovalPreserveExistingOutputs() {
        var settings = HeadsetPreferences()
        for index in 0..<HeadsetPreferences.maximumOutputs {
            XCTAssertTrue(settings.remember(.off, outputID: "output-\(index)"))
            XCTAssertTrue(settings.setAction(.cycleEQ, outputID: "output-\(index)"))
        }
        XCTAssertFalse(settings.remember(.off, outputID: "overflow"))
        XCTAssertFalse(settings.setAction(.voiceMemo, outputID: "overflow"))
        XCTAssertTrue(settings.remember(.preset("vocal"), outputID: "output-0"))
        XCTAssertTrue(settings.setAction(nil, outputID: "output-0"))
        XCTAssertEqual(settings.action(for: "output-0"), .none)
        XCTAssertEqual(settings.outputEQ.count, 100)
    }

    func testMemoryRestoreDistinguishesMissingChoiceOffDeletedPresetAndDisabledPolicy() {
        XCTAssertEqual(HeadsetEQRestoreDecision.decide(selection: nil, enabled: true, availableIDs: ["bass"]), .unchanged)
        XCTAssertEqual(HeadsetEQRestoreDecision.decide(selection: .off, enabled: true, availableIDs: []), .apply(nil))
        XCTAssertEqual(HeadsetEQRestoreDecision.decide(selection: .preset("bass"), enabled: true, availableIDs: ["bass"]), .apply("bass"))
        XCTAssertEqual(HeadsetEQRestoreDecision.decide(selection: .preset("removed"), enabled: true, availableIDs: ["bass"]), .forgetMissing)
        XCTAssertEqual(HeadsetEQRestoreDecision.decide(selection: .preset("bass"), enabled: false, availableIDs: ["bass"]), .unchanged)
    }

    func testCyclePreservesPresetOrderWrapsAndHandlesDeletedCurrentID() {
        XCTAssertEqual(CompanionEQCycle.next(presetIDs: ["flat", "bass", "flat", "vocal"], currentID: "bass"), "vocal")
        XCTAssertEqual(CompanionEQCycle.next(presetIDs: ["flat", "bass"], currentID: "bass"), "flat")
        XCTAssertEqual(CompanionEQCycle.next(presetIDs: ["flat", "bass"], currentID: "deleted"), "flat")
        XCTAssertNil(CompanionEQCycle.next(presetIDs: [], currentID: nil))
    }

    func testFieldThemeMigrationRetainsLightDarkAndUnrelatedSettings() throws {
        let old = try JSONDecoder().decode(SavedAppState.self, from: Data(#"{"theme":"Dark","sidetone":3,"boost":4}"#.utf8))
        XCTAssertEqual(old.theme, "Dark")
        XCTAssertEqual(old.visualStyle, .field)
        XCTAssertEqual(old.sidetone, 3)
        XCTAssertEqual(old.boost, 4)
        var updated = old
        updated.visualStyle = .system
        let restored = try JSONDecoder().decode(SavedAppState.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(restored.visualStyle, .system)
        XCTAssertEqual(restored.theme, "Dark")
        XCTAssertEqual(restored.sidetone, 3)
    }

    func testUnknownFutureVisualStyleFallsBackWithoutResettingPreferences() throws {
        let state = try JSONDecoder().decode(SavedAppState.self, from: Data(#"{"visualStyle":"future","theme":"Light","eq":[1,2,3]}"#.utf8))
        XCTAssertEqual(state.visualStyle, .field)
        XCTAssertEqual(state.theme, "Light")
        XCTAssertEqual(state.eq, [1, 2, 3])
    }

    @MainActor func testExplicitMemoryPersistsAndCycleNeverOverwritesIt() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let companion = HeadsetCompanion(defaults: fixture.defaults, observeAudioRoute: false, memoDirectory: fixture.directory)
        companion.preferences.spokenFeedback = false
        var active: String? = "flat"
        var applied = [String?]()
        companion.currentEQ = { (true, active) }
        companion.applyEQ = { active = $0; applied.append($0) }
        let output = CompanionAudioOutput(id: "a", name: "Headphones", kind: "BluetoothA2DPOutput", isHeadphones: true)
        companion.acceptOutput(output)
        companion.rememberExplicitPick("bass")
        XCTAssertEqual(companion.preferences.outputEQ["a"], .preset("bass"))
        XCTAssertEqual(companion.cycleEQ(), "qc_ultra")
        XCTAssertEqual(companion.preferences.outputEQ["a"], .preset("bass"))
        companion.acceptOutput(nil)
        companion.acceptOutput(output)
        XCTAssertEqual(applied.last!, "bass")
        let relaunched = HeadsetCompanion(defaults: fixture.defaults, observeAudioRoute: false, memoDirectory: fixture.directory)
        XCTAssertEqual(relaunched.preferences.outputEQ["a"], .preset("bass"))
        XCTAssertFalse(relaunched.preferences.spokenFeedback)
    }

    @MainActor func testOffMemoryRestoresOncePerOutputChangeAndNeverPretendsControlConnectivity() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let companion = HeadsetCompanion(defaults: fixture.defaults, observeAudioRoute: false, memoDirectory: fixture.directory)
        let output = CompanionAudioOutput(id: "wired", name: "Wired headphones", kind: "Headphones", isHeadphones: true)
        var calls = 0
        companion.applyEQ = { XCTAssertNil($0); calls += 1 }
        companion.acceptOutput(output)
        companion.rememberExplicitPick(nil)
        companion.acceptOutput(nil)
        companion.acceptOutput(output)
        companion.acceptOutput(output)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(companion.output, output)
        companion.acceptOutput(.init(id: "speaker", name: "iPhone", kind: "Speaker", isHeadphones: false))
        companion.rememberExplicitPick("bass")
        XCTAssertNil(companion.preferences.outputEQ["speaker"])
        XCTAssertEqual(calls, 1)
    }

    @MainActor func testDeletedPresetMemoryIsForgottenWithoutApplyingAnotherPreset() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let companion = HeadsetCompanion(defaults: fixture.defaults, observeAudioRoute: false, memoDirectory: fixture.directory)
        companion.preferences.outputEQ["a"] = .preset("deleted")
        var calls = 0
        companion.applyEQ = { _ in calls += 1 }
        companion.acceptOutput(.init(id: "a", name: "Headphones", kind: "Bluetooth", isHeadphones: true))
        XCTAssertNil(companion.preferences.outputEQ["a"])
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(companion.status.contains("removed"))
    }

    func testMemoCapacityAndFileNamesCannotEscapeOwnedDirectory() throws {
        let directory = URL(fileURLWithPath: "/tmp/earshot-fixture")
        let id = UUID(), file = CompanionMemoStorage.url(id: id, directory: directory)
        XCTAssertEqual(file.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().pathComponents,
                       directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents)
        XCTAssertEqual(file.lastPathComponent, "\(id.uuidString).m4a")
        XCTAssertEqual(CompanionMemoStorage.identifier(for: file), id)
        XCTAssertNil(CompanionMemoStorage.identifier(for: directory.appendingPathComponent("other.m4a")))
        XCTAssertTrue(CompanionMemoStorage.mayRecord(count: 99, bytes: 0))
        XCTAssertFalse(CompanionMemoStorage.mayRecord(count: 100, bytes: 0))
        XCTAssertFalse(CompanionMemoStorage.mayRecord(count: 1, bytes: CompanionMemoStorage.maximumBytes))
        XCTAssertEqual(CompanionMemoStorage.maximumSeconds, 1800)
    }

    func testCleanupRemovesOnlyExpiredOwnedPartialFiles() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let now = Date()
        let expired = CompanionMemoStorage.url(id: UUID(), directory: fixture.directory, pending: true)
        let recent = CompanionMemoStorage.url(id: UUID(), directory: fixture.directory, pending: true)
        let saved = CompanionMemoStorage.url(id: UUID(), directory: fixture.directory)
        let unrelated = fixture.directory.appendingPathComponent("unrelated.pending.m4a")
        for url in [expired, recent, saved, unrelated] { try Data([1]).write(to: url) }
        for url in [expired, saved, unrelated] { try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-90_000)], ofItemAtPath: url.path) }
        try CompanionMemoStorage.cleanExpiredPartials(in: fixture.directory, now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
        for url in [recent, saved, unrelated] { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
    }

    @MainActor func testActualAudioMemoPersistsAcrossLibraryRelaunchAndDeletesOnlySelectedFile() throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let id = UUID(), secondID = UUID()
        for memoID in [id, secondID] { try writeAudio(to: CompanionMemoStorage.url(id: memoID, directory: fixture.directory)) }
        let library = CompanionVoiceMemos(directory: fixture.directory)
        XCTAssertEqual(library.recordings.count, 2)
        XCTAssertTrue(library.recordings.allSatisfy { $0.duration > 0 && $0.bytes > 0 })
        let relaunched = CompanionVoiceMemos(directory: fixture.directory)
        XCTAssertEqual(Set(relaunched.recordings.map(\.id)), [id, secondID])
        relaunched.delete(id)
        XCTAssertEqual(relaunched.recordings.map(\.id), [secondID])
        XCTAssertFalse(FileManager.default.fileExists(atPath: CompanionMemoStorage.url(id: id, directory: fixture.directory).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: CompanionMemoStorage.url(id: secondID, directory: fixture.directory).path))
    }

    @MainActor func testBackgroundMemoStartIsRefusedBeforeRequestingPermissionOrCreatingAudio() async throws {
        let fixture = try Fixture(); defer { fixture.clean() }
        let library = CompanionVoiceMemos(directory: fixture.directory)
        await library.startRecording()
        XCTAssertFalse(library.isRecording)
        XCTAssertTrue(library.status.contains("Open Earshot"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    private func writeAudio(to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410))
        buffer.frameLength = 4410
        for frame in 0..<4410 { buffer.floatChannelData![0][frame] = Float(0.01 * sin(Double(frame) * 0.1)) }
        let writer = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
        try writer.write(from: buffer)
    }

    private struct Fixture {
        let suite = "CompanionTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let directory: URL
        init() throws {
            defaults = UserDefaults(suiteName: suite)!
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func clean() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
    }
}
