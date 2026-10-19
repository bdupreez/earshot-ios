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
