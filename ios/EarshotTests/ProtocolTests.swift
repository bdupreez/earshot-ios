import XCTest
@testable import Earshot

final class ProtocolTests: XCTestCase {
    private func hex(_ value: String) -> Data { Data(hex: value)! }

    func testGoldenCommandFrames() throws {
        XCTAssertEqual(try BoseCommands.get(BmapAddress(2, 2)).encode().hexString, "02020100")
        XCTAssertEqual(try BoseCommands.selectMode(index: 1).encode().hexString, "1f0305020100")
        XCTAssertEqual(try BoseCommands.setAudio(BoseAudioSettings(cancellingLevel: 5)).encode().hexString, "1f0a02050500000001")
        XCTAssertEqual(try BoseCommands.subscribeNotifications.encode().hexString, "0902020501800422b7")
    }

    func testFlagsRoundTripAllOperations() throws {
        for operation in BmapOperation.allCases {
            let original = BmapPacket(block: 1, function: 7, operation: operation,
                payload: hex("f60a0000f60afe01f60afa02"), deviceID: 2, port: 1)
            let encoded = try original.encode()
            XCTAssertEqual(Array(encoded)[2], 0x90 | operation.rawValue)
            XCTAssertEqual(BmapPacket.decodeOne(encoded), original)
        }
        XCTAssertThrowsError(try BmapPacket(block: 0, function: 1, operation: .get, payload: Data(repeating: 0, count: 256)).encode())
    }

    func testFragmentedConcatenatedFrames() throws {
        let battery = BmapPacket(block: 2, function: 2, operation: .status, payload: hex("5affff00"))
        let mode = BmapPacket(block: 31, function: 3, operation: .result, payload: Data([1]))
        let bytes = try battery.encode() + mode.encode()
        var buffer = BmapFrameBuffer()
        XCTAssertTrue(buffer.feed(Data(bytes.prefix(3))).isEmpty)
        XCTAssertEqual(buffer.feed(Data(bytes.dropFirst(3).prefix(6))), [battery])
        XCTAssertEqual(buffer.feed(Data(bytes.dropFirst(9))), [mode])
        XCTAssertTrue(buffer.pending.isEmpty)
    }

    func testInvalidHeaderCannotPassLiveness() {
        XCTAssertNil(BmapPacket.decodeOne(hex("02020900")))
        XCTAssertNil(BmapPacket.decodeOne(hex("1f0a0305050000")))
        XCTAssertFalse(BoseCommands.liveness.answersLivenessProbe)
        XCTAssertFalse(BmapPacket(block: 2, function: 2, operation: .status).answersLivenessProbe)
        XCTAssertFalse(BmapPacket(block: 0, function: 1, operation: .processing).answersLivenessProbe)
        XCTAssertTrue(BmapPacket(block: 0, function: 1, operation: .status).answersLivenessProbe)
        var buffer = BmapFrameBuffer()
        XCTAssertTrue(buffer.feed(hex("ff550900" )).isEmpty)
        XCTAssertEqual(buffer.desyncCount, 1)
        XCTAssertEqual(buffer.droppedBytes, 4)
        XCTAssertTrue(buffer.pending.isEmpty)
    }

    func testSingleOutboundSafetyGuard() throws {
        for block: UInt8 in [3, 18] {
            for operation in BmapOperation.allCases where operation != .get {
                XCTAssertThrowsError(try BmapWriteGuard.check(BmapPacket(block: block, function: 2, operation: operation)))
            }
            XCTAssertNoThrow(try BmapWriteGuard.check(BmapPacket(block: block, function: 2, operation: .get)))
        }
        for address in [BmapAddress(7, 5), BmapAddress(7, 6), BmapAddress(7, 11), BmapAddress(4, 7)] {
            XCTAssertThrowsError(try BmapWriteGuard.check(BmapPacket(block: address.block, function: address.function, operation: .start)))
        }
        XCTAssertNoThrow(try BmapWriteGuard.check(BoseCommands.selectMode(index: 1)))
    }

    func testBatteryUsesComponentIDsAndUnknownSentinels() {
        XCTAssertEqual(BoseBattery.parse(hex("5affff00")).percent, 90)
        let earbuds = BoseBattery.parse(hex("3cffff0132ffff0246ffff0450ffff03"))
        XCTAssertEqual(earbuds.percent, 70)
        XCTAssertEqual(earbuds.readings.map(\.component), [1, 2, 4, 3])
        XCTAssertEqual(BoseBattery.parse(hex("3cffff0132ffff02")).percent, 50)
        XCTAssertNil(BoseBattery.parse(hex("ffffff00")).percent)
        XCTAssertNil(BoseBattery.parse(Data()).percent)
        XCTAssertEqual(BoseBattery.parse(hex("320078")).readings.first?.remainingMinutes, 120)
    }

    func testSignedEQCaptureAndWrite() throws {
        let bands = BoseEQBand.parse(hex("f60a0000f60afe01f60afa02"))
        XCTAssertEqual(bands.map(\.value), [0, -2, -6])
        XCTAssertEqual(bands.map(\.min), [-10, -10, -10])
        XCTAssertEqual(bands.map(\.max), [10, 10, 10])
        XCTAssertEqual(try BoseCommands.setEQ(band: 1, value: -2).payload, hex("fe01"))
        XCTAssertThrowsError(try BoseCommands.setEQ(band: 0, value: 11))
    }

    func testNoiseInversionAndStepCount() throws {
        XCTAssertEqual(BoseAudioSettings.parse(hex("0000000001"))?.cancellingLevel, 10)
        XCTAssertEqual(BoseAudioSettings.parse(hex("0a00020101"))?.cancellingLevel, 0)
        XCTAssertEqual(try BoseCommands.setAudio(BoseAudioSettings(cancellingLevel: 10, spatial: 2, windBlock: true)).payload, hex("0000020101"))
        XCTAssertEqual(try BoseCommands.setDirectNoise(level: 0, steps: 11).payload, hex("0a01"))
        XCTAssertEqual(try BoseCommands.setDirectNoise(level: 10, steps: 11).payload, hex("0001"))
        XCTAssertThrowsError(try BoseCommands.setDirectNoise(level: 5, steps: 1))
        XCTAssertNil(BoseAudioSettings.parse(Data([0, 0])))
    }

    func testModeStatusUsesWindAt46AndPreservesPrompt() throws {
        var raw = [UInt8](repeating: 0, count: 48)
        raw[0] = 4; raw[2] = 10; raw[3] = 1; raw[4] = 1
        raw.replaceSubrange(6..<10, with: Array("Home".utf8))
        raw[41] = 0x1d; raw[45] = 1; raw[46] = 0; raw[47] = 1
        let mode = try XCTUnwrap(BoseMode.parse(Data(raw)))
        XCTAssertEqual(mode.displayName, "Home")
        XCTAssertEqual(mode.editable, true)
        XCTAssertFalse(mode.settings.windBlock)
        let write = try BoseCommands.writeMode(mode)
        XCTAssertEqual(write.payload.count, 40)
        XCTAssertEqual(Array(write.payload)[2], 10)
        XCTAssertEqual(Array(write.payload)[38], 0)
        XCTAssertTrue(try XCTUnwrap(BoseMode.parse(write.payload)).settings.ancEnabled)
        raw[3] = 0
        XCTAssertThrowsError(try BoseCommands.writeMode(XCTUnwrap(BoseMode.parse(Data(raw)))))
    }

    func testModeLayoutAdaptsToObservedFirmwareLength() throws {
        for (statusLength, writeLength) in [(44, 37), (45, 39), (47, 39), (48, 40)] {
            var bytes = [UInt8](repeating: 0, count: statusLength)
            bytes[0] = 4; bytes[3] = 1
            let mode = try XCTUnwrap(BoseMode.parse(Data(bytes)))
            XCTAssertEqual(try BoseCommands.writeMode(mode).payload.count, writeLength)
        }
    }

    func testBigEndianFavoritesAndCapabilities() throws {
        let favorites = try XCTUnwrap(BoseParsers.favorites(hex("0b0037")))
        XCTAssertEqual(favorites.indices, [0, 1, 2, 4, 5])
        XCTAssertEqual(try BoseCommands.setFavorites(indices: [0, 8, 10], totalModes: 11).payload, hex("0b0501"))
        let capabilities = try XCTUnwrap(BoseModesCapabilities.parse(hex("04070000007f02")))
        XCTAssertEqual(capabilities.totalModes, 11)
        XCTAssertEqual(capabilities.minimumFavorites, 2)
        XCTAssertTrue(capabilities.ancToggle)
        XCTAssertTrue(capabilities.spatial)
    }

    func testStandbyAsymmetricWireLayoutAndUTF8Bounds() throws {
        XCTAssertEqual(BoseParsers.standbyMinutes(hex("a00005")), 1440)
        XCTAssertEqual(try BoseCommands.setStandby(minutes: 1440).payload, hex("a005"))
        XCTAssertEqual(try BoseCommands.setStandby(minutes: 20).payload, hex("14"))
        XCTAssertThrowsError(try BoseCommands.setName(String(repeating: "é", count: 16)))
        XCTAssertNoThrow(try BoseCommands.setName(String(repeating: "é", count: 15)))
        XCTAssertEqual(BoseParsers.customName(hex("00466172676f")), "Fargo")
    }

    func testLEPSMRejectsInvalidAndAcceptsObservedByteOrders() {
        XCTAssertEqual(BoseParsers.psm(hex("80")), 128)
        XCTAssertEqual(BoseParsers.psm(hex("8100")), 129)
        XCTAssertEqual(BoseParsers.psm(hex("0082")), 130)
        XCTAssertNil(BoseParsers.psm(hex("7f")))
        XCTAssertNil(BoseParsers.psm(hex("1101")))
        XCTAssertNil(BoseParsers.psm(Data()))
    }

    func testSettingsRespectPackedAndInvertedFlags() throws {
        XCTAssertEqual(BoseParsers.multipoint(hex("07")), true)
        XCTAssertEqual(BoseParsers.multipoint(hex("01")), false)
        XCTAssertEqual(BoseParsers.touchControls(hex("01")), false)
        XCTAssertEqual(BoseCommands.setTouchControls(enabled: true).payload, hex("00"))
        let voice = try XCTUnwrap(BoseParsers.voicePrompts(hex("41000081020000")))
        XCTAssertEqual(voice.language, 1)
        XCTAssertFalse(voice.enabled)
        XCTAssertEqual(try BoseCommands.setVoicePrompts(enabled: true, language: voice.language).payload, hex("21"))
        XCTAssertEqual(try BoseCommands.setSidetone(level: 3).payload, hex("0103"))
    }

    @MainActor
    func testLiveStateValidatesPayloadBeforeEnablingUI() throws {
        let suite = "earshot.protocol-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults)
        store.saved.batteryAlert = 0
        XCTAssertEqual(store.profile.id, "unknown")
        store.receive(BmapPacket(block: 31, function: 10, operation: .status, payload: hex("0000")))
        XCTAssertFalse(store.supports(31, 10))
        store.receive(BmapPacket(block: 31, function: 10, operation: .status, payload: hex("0000020001")))
        XCTAssertTrue(store.supports(31, 10))
        XCTAssertEqual(store.saved.noise.level, 10)
        XCTAssertEqual(store.saved.noise.spatial, 2)
        store.receive(BmapPacket(block: 31, function: 10, operation: .error, payload: hex("04")))
        XCTAssertFalse(store.supports(31, 10))
    }

    @MainActor
    func testCompactModeDetailRequestsAreBoundedIncludingReentrantReplies() async throws {
        let suite = "earshot.protocol-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let compact = compactModeReport(index: 4)
        var sent: [BmapPacket] = []
        var onSend: ((BmapPacket) -> Void)?
        let store = AppStore(defaults: defaults, arguments: [], packetSender: { packet in
            sent.append(packet); onSend?(packet)
        })
        await Task.yield(); await Task.yield()
        onSend = { [weak store] packet in
            // Bound the fixture itself so a regression fails rather than
            // overflowing the stack on the old synchronous request/reply loop.
            if packet.address == BmapAddress(31, 6), sent.count < 8 {
                store?.receive(BmapPacket(block: 31, function: 6, operation: .result, payload: compact.payload))
            }
        }
        for _ in 0..<300 { store.receive(compact) }
        XCTAssertEqual(sent, [BmapPacket(block: 31, function: 6, operation: .get, payload: Data([4]))])
        XCTAssertNil(store.liveModes[4], "A compact record cannot establish an editable wire layout")
        onSend = nil
        store.receive(compactModeReport(index: 5))
        for _ in 0..<300 { store.receive(compactModeReport(index: 5)) }
        XCTAssertEqual(sent.map(\.payload), [Data([4]), Data([5])], "Each distinct slot receives at most one automatic detail read")
        XCTAssertFalse(store.bluetooth.isConnected, "A sender fixture must not invent a physical connection")
    }

    @MainActor
    func testRefusedModeDetailReadsStaySuppressedUntilExplicitRefresh() async throws {
        for code: UInt8 in [3, 4, 5] {
            let suite = "earshot.protocol-tests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var sent: [BmapPacket] = []
            var onSend: ((BmapPacket) -> Void)?
            let store = AppStore(defaults: defaults, arguments: [], packetSender: { packet in
                sent.append(packet); onSend?(packet)
            })
            await Task.yield(); await Task.yield()
            store.receive(compactModeReport(index: 4))
            store.receive(BmapPacket(block: 31, function: 6, operation: .error, payload: Data([code])))
            for _ in 0..<100 {
                store.receive(compactModeReport(index: 4))
                store.receive(compactModeReport(index: 5))
            }
            XCTAssertEqual(sent.filter { $0.address == BmapAddress(31, 6) }.count, 1, "Refusal \(code) must not be retried by repeated/dump reports")

            onSend = { [weak store] packet in
                if packet == BoseCommands.subscribeNotifications { store?.receive(self.compactModeReport(index: 5)) }
            }
            store.refresh()
            await Task.yield(); await Task.yield()
            // An unsupported whole block remains disabled for the connection;
            // other refusals may be explicitly retried once by the user.
            let expected = code == 3 ? 1 : 2
            XCTAssertEqual(sent.filter { $0.address == BmapAddress(31, 6) && $0.operation == .get }.count, expected)
            for _ in 0..<100 { store.receive(compactModeReport(index: 5)) }
            XCTAssertEqual(sent.filter { $0.address == BmapAddress(31, 6) && $0.operation == .get }.count, expected)
            onSend = nil
        }
    }

    @MainActor
    func testFullModeReportPreservesEditableLayoutAcrossCompactRepeats() async throws {
        let suite = "earshot.protocol-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var sent: [BmapPacket] = []
        let store = AppStore(defaults: defaults, arguments: [], packetSender: { sent.append($0) })
        await Task.yield(); await Task.yield()
        for (offset, length) in [44, 45, 47, 48].enumerated() {
            let id = UInt8(offset + 4)
            var bytes = [UInt8](repeating: 0, count: length)
            bytes[0] = id; bytes[3] = 1; bytes[42] = 7
            if length == 48 { bytes[47] = 1 }
            bytes.replaceSubrange(6..<10, with: Array("Work".utf8))
            let full = BmapPacket(block: 31, function: 6, operation: .status, payload: Data(bytes))
            store.receive(full)
            for _ in 0..<100 { store.receive(compactModeReport(index: id)) }
            let retained = try XCTUnwrap(store.liveModes[Int(id)])
            XCTAssertEqual(retained.raw, full.payload)
            XCTAssertEqual(retained.editable, true)
            XCTAssertNoThrow(try BoseCommands.writeMode(retained))
        }
        XCTAssertTrue(sent.isEmpty, "An already complete mode needs no automatic detail read")
        XCTAssertFalse(store.canEditMode(4), "An offline fixture still cannot enable physical editing")
    }

    @MainActor
    func testModeDetailBudgetResetsWhenLiveConnectionStateClears() async throws {
        let suite = "earshot.protocol-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var sent: [BmapPacket] = []
        let store = AppStore(defaults: defaults, arguments: [], packetSender: { sent.append($0) })
        // The initial disconnected publisher is deferred by AppStore. Seed a
        // report first, then exercise its actual live-state reset callback.
        store.receive(compactModeReport(index: 4))
        XCTAssertEqual(sent.count, 1)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(store.saved.modes.isEmpty)
        store.receive(compactModeReport(index: 4))
        store.receive(compactModeReport(index: 4))
        XCTAssertEqual(sent.count, 2)
    }

    private func compactModeReport(index: UInt8) -> BmapPacket {
        var bytes = [UInt8](repeating: 0, count: 40)
        bytes[0] = index; bytes[35] = 7; bytes[39] = 1
        bytes.replaceSubrange(3..<7, with: Array("Work".utf8))
        return BmapPacket(block: 31, function: 6, operation: .status, payload: Data(bytes))
    }

    @MainActor
    func testLiveProductAndSettingCapturesReplaceDemoGuesses() throws {
        let suite = "earshot.protocol-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults)
        store.saved.batteryAlert = 0
        store.receive(BmapPacket(block: 0, function: 3, operation: .status, payload: hex("403901")))
        XCTAssertEqual(store.profile.id, "qc45")
        store.receive(BmapPacket(block: 1, function: 34, operation: .status, payload: hex("01")))
        XCTAssertFalse(store.saved.touchControls)
        store.receive(BmapPacket(block: 1, function: 10, operation: .status, payload: hex("07")))
        XCTAssertTrue(store.saved.multipoint)
        store.receive(BmapPacket(block: 1, function: 4, operation: .status, payload: hex("a00005")))
        XCTAssertEqual(store.saved.autoOff, 1440)
        store.receive(BmapPacket(block: 2, function: 2, operation: .status, payload: hex("3cffff0132ffff0250ffff03")))
        XCTAssertEqual(store.battery, 50)
        XCTAssertEqual(store.batteries, ["Right": 60, "Left": 50, "Case": 80])
    }

    @MainActor
    func testCustomDemoResetActuallyClearsConfiguredFlag() throws {
        let suite = "earshot.protocol-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults)
        store.setDemo(true)
        var mode = try XCTUnwrap(store.saved.modes.first { !$0.builtIn })
        mode.name = "Library"
        store.saveMode(mode)
        XCTAssertEqual(store.saved.modes.first { $0.id == mode.id }?.configured, true)
        store.resetMode(mode.id)
        XCTAssertEqual(store.saved.modes.first { $0.id == mode.id }?.configured, false)
    }

    func testDeviceControlsUseReportedRangesAndBigEndianMasks() throws {
        XCTAssertEqual(try BoseCommands.setVolume(level: 22, maximum: 31).payload, hex("16"))
        XCTAssertThrowsError(try BoseCommands.setVolume(level: 32, maximum: 31))
        XCTAssertEqual(try BoseCommands.playback(action: 2).encode().hexString, "0503050102")
        let button = try XCTUnwrap(BoseButtonShortcut.parse(hex("800913000940020001000201011001")))
        XCTAssertEqual(button.supported, [1, 14, 16, 19])
        XCTAssertEqual(button.action, 19)
        XCTAssertNil(BoseButtonShortcut.parse(hex("80091300000000")))
        let devices = try XCTUnwrap(BosePairedSource.parseList(hex("012cda4600000210b1df000003")))
        XCTAssertEqual(devices.count, 2)
        XCTAssertTrue(devices[0].connected)
        XCTAssertFalse(devices[1].connected)
        XCTAssertNil(BosePairedSource.parseList(hex("010203")))
    }

    @MainActor
    func testLiveDeviceControlsRequireValidReports() throws {
        let suite = "earshot.protocol-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults)
        store.receive(BmapPacket(block: 5, function: 5, operation: .status, payload: hex("1f16")))
        XCTAssertEqual(store.deviceVolume, 22)
        XCTAssertEqual(store.deviceVolumeMaximum, 31)
        store.receive(BmapPacket(block: 5, function: 3, operation: .status, payload: hex("1f")))
        XCTAssertEqual(store.playbackActions, [0, 1, 2, 3, 4])
        store.receive(BmapPacket(block: 1, function: 37, operation: .status, payload: hex("01")))
        XCTAssertEqual(store.leAudio, true)
        store.receive(BmapPacket(block: 5, function: 7, operation: .status, payload: hex("0000020800d2")))
        XCTAssertTrue(store.deviceLatency.contains("210"))
        XCTAssertTrue(store.supports(5, 5))
    }

    @MainActor
    func testPersistedDemoControlsSurviveDeferredBluetoothInitialState() async throws {
        let suite = "earshot.protocol-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var state = SavedAppState()
        state.demo = true
        defaults.set(try JSONEncoder().encode(state), forKey: "earshot.ios.state")
        let store = AppStore(defaults: defaults)
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(store.saved.demo)
        XCTAssertEqual(store.deviceVolumeMaximum, 31)
        XCTAssertEqual(store.deviceVolume, 18)
        XCTAssertNotNil(store.leAudio)
        XCTAssertEqual(store.playbackActions, [0, 1, 2, 3, 4])
        XCTAssertFalse(store.pairedSources.isEmpty)
    }

    @MainActor
    func testMissingAutomationModeDoesNotLogSuccess() throws {
        let suite = "earshot.protocol-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults)
        store.setDemo(true)
        store.runRule(AutomationRule(name: "Missing mode", modeIndex: 200))
        XCTAssertTrue(store.automationLog.isEmpty)
    }
}
