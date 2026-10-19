import XCTest
@testable import Earshot

final class NoiseSemanticsTests: XCTestCase {
    func testLiveNoiseKeepsRequestedLevelWhileWindOrANCOffMasksIt() throws {
        let wind = BoseAudioSettings(cancellingLevel: 3, spatial: 1, windBlock: true, ancEnabled: true)
        XCTAssertTrue(wind.cncMasked)
        XCTAssertEqual(try BoseCommands.setAudio(wind).payload, Data([7, 0, 1, 1, 1]))
        let off = BoseAudioSettings(cancellingLevel: 3, spatial: 0, windBlock: false, ancEnabled: false)
        XCTAssertTrue(off.cncMasked)
        XCTAssertEqual(try BoseCommands.setAudio(off).payload, Data([7, 0, 0, 0, 0]))
        XCTAssertFalse(BoseAudioSettings(cancellingLevel: 3).cncMasked)
    }

    func testCompactWindEchoUsesEffectiveLevelWithoutChangingWrittenLevel() throws {
        let slot = try mode(statusLength: 47, wireLevel: 7, wind: false)
        let requested = BoseAudioSettings(cancellingLevel: 3, spatial: 0, windBlock: true, ancEnabled: true)
        let write = try BoseCommands.writeMode(slot, settings: requested)
        XCTAssertEqual(write.payload.count, 39)
        XCTAssertEqual(Array(write.payload.suffix(4)), [7, 0, 0, 1], "Keep upstream's requested CNC byte unchanged")

        // Observed compact firmware stores CNC 0 when wind is on (UI level 10).
        let report = try mode(statusLength: 47, wireLevel: 0, wind: true)
        XCTAssertEqual(requested.expectedModeReport(for: slot), report.settings)
        XCTAssertEqual(requested.cancellingLevel, 3, "Only the comparison target is adjusted")
    }

    func testCompactRuleDoesNotRewriteOtherLayoutsOrWindOff() throws {
        let requested = BoseAudioSettings(cancellingLevel: 3, windBlock: true)
        for length in [44, 45, 46, 48] {
            XCTAssertEqual(requested.expectedModeReport(for: try mode(statusLength: length, wireLevel: 7, wind: false)), requested)
        }
        XCTAssertEqual(requested.expectedModeReport(for: nil), requested)
        let noWind = BoseAudioSettings(cancellingLevel: 3, windBlock: false)
        XCTAssertEqual(noWind.expectedModeReport(for: try mode(statusLength: 47, wireLevel: 7, wind: false)), noWind)
    }

    func testDirectCNCQuantizationAndProtectedEnableFlagUseActualReportedState() throws {
        let locked = try XCTUnwrap(BoseCNCState.parse(Data([3, 0, 3]))) // 3 steps, enabled, cannot toggle
        let request = BoseAudioSettings(cancellingLevel: 3, ancEnabled: false)
        XCTAssertFalse(locked.userCanToggle)
        XCTAssertEqual(try BoseCommands.setDirectNoise(request, state: locked).payload, Data([1, 1]))
        let expected = try locked.expectedDirectReport(for: request)
        XCTAssertEqual(expected.cancellingLevel, 5)
        XCTAssertTrue(expected.ancEnabled)

        let toggleable = try XCTUnwrap(BoseCNCState.parse(Data([6, 0, 1])))
        XCTAssertEqual(try toggleable.step(forLevel: 1), 4, "Upstream rounds a half step towards the requested cancelling level")
        XCTAssertEqual(try BoseCommands.setDirectNoise(level: 1, steps: 6).payload, Data([4, 1]))
        XCTAssertEqual(try BoseCommands.setDirectNoise(request, state: toggleable).payload.last, 0)
        XCTAssertFalse(try toggleable.expectedDirectReport(for: request).ancEnabled)
        XCTAssertThrowsError(try toggleable.step(forLevel: 11))
    }

    func testDirectCNCRejectsMalformedReportsAndPreservesLevelEndpoints() throws {
        for bytes: [UInt8] in [[], [1, 0, 1], [3, 3, 1], [3, 0]] { XCTAssertNil(BoseCNCState.parse(Data(bytes))) }
        for steps: UInt8 in [2, 3, 6, 11, 255] {
            let state = try XCTUnwrap(BoseCNCState.parse(Data([steps, 0, 0])))
            XCTAssertEqual(try state.step(forLevel: 10), 0)
            XCTAssertEqual(try state.step(forLevel: 0), Int(steps) - 1)
            XCTAssertEqual(state.cancellingLevel, 10)
            let aware = try XCTUnwrap(BoseCNCState.parse(Data([steps, steps - 1, 0])))
            XCTAssertEqual(aware.cancellingLevel, 0)
        }
    }

    @MainActor
    func testRoutingCanBeRecheckedReadOnlyAndCurrentModeCanBeReread() throws {
        XCTAssertTrue(BoseCommands.refresh.contains(BoseCommands.readRoutingSupport))
        XCTAssertTrue(BmapProtocolScanner.addresses.contains(BmapAddress(4, 12)))
        XCTAssertEqual(try BoseCommands.readRoutingSupport.encode().hexString, "040c0100")
        XCTAssertEqual(try BoseCommands.readCurrentMode.encode().hexString, "1f030100")
        XCTAssertNoThrow(try BmapWriteGuard.check(BoseCommands.readRoutingSupport))
        XCTAssertNoThrow(try BmapWriteGuard.check(BoseCommands.readCurrentMode))
    }

    func testSliderBurstWritesOnlyOneFinalRequestedLevel() throws {
        let reported = NoiseState(level: 10)
        var draft = NoiseLevelDraft()
        var commits = [NoiseState]()
        draft.begin(reportedLevel: reported.level, canEdit: true)
        for index in 0..<1_000 {
            if let request = draft.update(Double(index % 11), latest: reported, canEdit: true) { commits.append(request) }
        }
        for _ in 0..<100 { XCTAssertNil(draft.update(7, latest: reported, canEdit: true)) }
        XCTAssertTrue(commits.isEmpty, "Dragging and duplicate callbacks must not call the live binding.")
        XCTAssertEqual(draft.level, 7)
        if let request = draft.finish(latest: reported, canEdit: true) { commits.append(request) }
        XCTAssertEqual(commits, [NoiseState(level: 7)])
        XCTAssertEqual(reported.level, 10, "The report stays authoritative until a device reply arrives.")
        XCTAssertFalse(draft.isEditing)
        XCTAssertNil(draft.level)
        XCTAssertNil(draft.finish(latest: reported, canEdit: true))
        XCTAssertNil(draft.update(7, latest: reported, canEdit: true), "A trailing value callback must not duplicate the just-finished request.")
    }

    func testIncomingReportKeepsDragDraftAndFinalCommitMergesLatestFlags() throws {
        var draft = NoiseLevelDraft()
        draft.begin(reportedLevel: 10, canEdit: true)
        XCTAssertNil(draft.update(7, latest: NoiseState(level: 10), canEdit: true))
        let latest = NoiseState(level: 3, enabled: false, wind: false, spatial: 2)
        draft.reportChanged()
        XCTAssertEqual(draft.level, 7, "A report must not snap the thumb while dragging.")
        let request = try XCTUnwrap(draft.finish(latest: latest, canEdit: true))
        XCTAssertEqual(request, NoiseState(level: 7, enabled: false, wind: false, spatial: 2))
        XCTAssertEqual(latest.level, 3)
    }

    func testUnchangedSliderGestureAndInvalidValuesNeverCommit() {
        let reported = NoiseState(level: 7)
        var draft = NoiseLevelDraft()
        draft.begin(reportedLevel: 7, canEdit: true)
        XCTAssertNil(draft.update(7.2, latest: reported, canEdit: true))
        XCTAssertNil(draft.finish(latest: reported, canEdit: true))
        XCTAssertNil(draft.update(7, latest: reported, canEdit: true))
        for invalid in [Double.nan, .infinity, -.infinity] { XCTAssertNil(draft.update(invalid, latest: reported, canEdit: true)) }
    }

    func testCancellationRejectsLateDragUpdatesAndEndButAllowsANewGesture() throws {
        let latest = NoiseState(level: 10)
        var draft = NoiseLevelDraft()
        draft.begin(reportedLevel: 10, canEdit: true)
        XCTAssertNil(draft.update(3, latest: latest, canEdit: true))
        draft.cancel() // Disappearance, inactive scene or a profile/device/mode change.
        XCTAssertNil(draft.level)
        XCTAssertNil(draft.update(7, latest: latest, canEdit: true))
        XCTAssertNil(draft.finish(latest: latest, canEdit: true))
        draft.begin(reportedLevel: 10, canEdit: true)
        XCTAssertNil(draft.update(7, latest: latest, canEdit: true))
        XCTAssertEqual(try XCTUnwrap(draft.finish(latest: latest, canEdit: true)).level, 7)
    }

    func testDisabledControlCancelsDragEvenIfItIsEnabledAgainBeforeRelease() {
        let latest = NoiseState(level: 10)
        var draft = NoiseLevelDraft()
        draft.begin(reportedLevel: 10, canEdit: true)
        XCTAssertNil(draft.update(3, latest: latest, canEdit: true))
        XCTAssertNil(draft.update(4, latest: latest, canEdit: false))
        XCTAssertNil(draft.update(7, latest: latest, canEdit: true))
        XCTAssertNil(draft.finish(latest: latest, canEdit: true))
        XCTAssertNil(draft.update(7, latest: latest, canEdit: false))
        draft.begin(reportedLevel: 10, canEdit: false)
        XCTAssertNil(draft.finish(latest: latest, canEdit: true))
    }

    func testAccessibilityAndKeyboardChangesCommitImmediatelyWithoutTouchCallbacks() throws {
        var draft = NoiseLevelDraft()
        let first = try XCTUnwrap(draft.update(9, latest: NoiseState(level: 10), canEdit: true))
        XCTAssertEqual(first.level, 9)
        XCTAssertFalse(draft.isEditing)
        XCTAssertNil(draft.update(9, latest: NoiseState(level: 10), canEdit: true))
        draft.reportChanged()
        let next = try XCTUnwrap(draft.update(8, latest: first, canEdit: true))
        XCTAssertEqual(next.level, 8)
        draft.reportChanged()
        XCTAssertNil(draft.level, "A report never creates a pending UI gesture.")
        XCTAssertNil(draft.finish(latest: next, canEdit: true))
    }

    func testLifecycleResetCannotReplayAPreviousGesture() {
        var draft = NoiseLevelDraft()
        draft.begin(reportedLevel: 10, canEdit: true)
        XCTAssertNil(draft.update(3, latest: NoiseState(level: 10), canEdit: true))
        draft.cancel()
        draft.reset()
        XCTAssertFalse(draft.isEditing)
        XCTAssertNil(draft.level)
        XCTAssertNil(draft.finish(latest: NoiseState(level: 10), canEdit: true))
    }

    func testEveryEQBandKeepsItsOwnDraftAndCommitsOneSignedFinalValue() {
        var drafts = [SliderValueDraft(), SliderValueDraft(), SliderValueDraft()]
        let targets = [6.0, -4.0, 4.0]
        var committed = [Double?](repeating: nil, count: 3)
        for index in 0..<3 {
            drafts[index].begin(reportedValue: 0, canEdit: true)
            for update in 0..<500 {
                XCTAssertNil(drafts[index].update(Double(update % 21 - 10), reportedValue: 0, range: -10...10, canEdit: true))
            }
            XCTAssertNil(drafts[index].update(targets[index], reportedValue: 0, range: -10...10, canEdit: true))
            drafts[index].reportChanged()
            XCTAssertEqual(drafts[index].value, targets[index], "A live report does not overwrite an active EQ draft.")
            committed[index] = drafts[index].finish(reportedValue: 0, canEdit: true)
            XCTAssertNil(drafts[index].update(targets[index], reportedValue: 0, range: -10...10, canEdit: true))
        }
        XCTAssertEqual(committed, targets.map(Optional.some))
    }

    func testVolumeDraftKeepsUserTargetAcrossReportsAndUsesReportedRange() {
        var draft = SliderValueDraft()
        draft.begin(reportedValue: 50, canEdit: true)
        for _ in 0..<500 { XCTAssertNil(draft.update(90, reportedValue: 50, range: 0...100, canEdit: true)) }
        draft.reportChanged()
        XCTAssertEqual(draft.value, 90)
        XCTAssertEqual(draft.finish(reportedValue: 60, canEdit: true), 90)
        XCTAssertNil(draft.update(90, reportedValue: 60, range: 0...100, canEdit: true))
        draft.reportChanged()
        XCTAssertEqual(draft.update(200, reportedValue: 90, range: 0...100, canEdit: true), 100)
        draft.reportChanged()
        XCTAssertEqual(draft.update(-5, reportedValue: 90, range: 0...100, canEdit: true), 0)
    }

    func testBluetoothSliderCancellationAndUnchangedTargetsDoNotWrite() {
        for range: ClosedRange<Double> in [-10...10, 0...100] {
            var draft = SliderValueDraft()
            draft.begin(reportedValue: 0, canEdit: true)
            XCTAssertNil(draft.update(0, reportedValue: 0, range: range, canEdit: true))
            XCTAssertNil(draft.finish(reportedValue: 0, canEdit: true))
            draft.begin(reportedValue: 0, canEdit: true)
            XCTAssertNil(draft.update(7, reportedValue: 0, range: range, canEdit: true))
            draft.cancel() // Disabled, inactive, removed, or changed device/profile/range.
            XCTAssertNil(draft.value)
            XCTAssertNil(draft.update(8, reportedValue: 0, range: range, canEdit: true))
            XCTAssertNil(draft.finish(reportedValue: 0, canEdit: true))
            XCTAssertNil(draft.update(7, reportedValue: 0, range: range, canEdit: false))
        }
    }

    func testBluetoothSliderAccessibilityUpdatesStayImmediateAndRejectInvalidNumbers() {
        var draft = SliderValueDraft()
        XCTAssertEqual(draft.update(-4, reportedValue: 0, range: -10...10, canEdit: true), -4)
        XCTAssertFalse(draft.isEditing)
        XCTAssertNil(draft.update(-4, reportedValue: 0, range: -10...10, canEdit: true))
        draft.reportChanged()
        XCTAssertEqual(draft.update(-3, reportedValue: -4, range: -10...10, canEdit: true), -3)
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(draft.update(invalid, reportedValue: -3, range: -10...10, canEdit: true))
        }
    }

    private func mode(statusLength: Int, wireLevel: UInt8, wind: Bool) throws -> BoseMode {
        var bytes = [UInt8](repeating: 0, count: statusLength)
        bytes[0] = 2; bytes[3] = 1
        bytes.replaceSubrange(6..<10, with: Array("Work".utf8))
        bytes[42] = wireLevel
        if statusLength >= 47 { bytes[46] = wind ? 1 : 0 }
        if statusLength >= 48 { bytes[47] = 1 }
        return try XCTUnwrap(BoseMode.parse(Data(bytes)))
    }
}
