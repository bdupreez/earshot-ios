import XCTest
@testable import Earshot

// Fixtures and protocol facts adapted from HellzYeahh/earshot (MIT). These are
// parser/simulation tests, not evidence of a physical iPhone Soundcore transport.
final class SoundcoreTests: XCTestCase {
    private func hex(_ value: String) -> Data { Data(hex: value)! }

    func testGoldenRequestANCAndInboundAcknowledgementFrames() throws {
        XCTAssertEqual(try SoundcorePacket(command: 0x0101).encode(), hex("08ee00000001010a0002"))
        XCTAssertEqual(try SoundcorePacket(command: 0x0687, body: Data([1])).encode(), hex("08ee00000006870b00018f"))
        XCTAssertEqual(try SoundcorePacket(command: 0x0681, inbound: true).encode(), hex("09ff00000106810a009a"))
    }

    func testAllChunkBoundariesPreserveInboundFramesAndDoNotTreatEchoAsInbound() throws {
        let packets = [SoundcorePacket(command: 0x0101, body: SoundcoreDemo.fixtureBody(for: .sleepA30), inbound: true), SoundcorePacket(command: 0x0103, body: Data([8, 9]), inbound: true)]
        let wire = try packets[0].encode() + packets[1].encode()
        for split in 0...wire.count {
            var buffer = SoundcoreFrameBuffer()
            XCTAssertEqual(buffer.feed(Data(wire.prefix(split))) + buffer.feed(Data(wire.dropFirst(split))), packets)
            XCTAssertLessThanOrEqual(buffer.pending.count, 4)
        }
        var buffer = SoundcoreFrameBuffer()
        let echo = try XCTUnwrap(buffer.feed(try SoundcorePacket(command: 0x0101).encode()).first)
        XCTAssertFalse(echo.inbound)
    }

    func testNoiseBadChecksumInvalidLengthAndHugeChunksCannotWedgeOrGrowBuffer() throws {
        let valid = try SoundcorePacket(command: 0x0103, body: Data([4, 5]), inbound: true).encode()
        var corrupt = Array(valid); corrupt[corrupt.count - 1] ^= 255
        let invalidLength = Data(SoundcorePacket.inboundPrefix + [1, 1, 0, 0])
        var buffer = SoundcoreFrameBuffer()
        let received = buffer.feed(Data(repeating: 0x33, count: 100_000) + invalidLength + Data(corrupt) + valid)
        XCTAssertEqual(received, [SoundcorePacket(command: 0x0103, body: Data([4, 5]), inbound: true)])
        XCTAssertLessThanOrEqual(buffer.pending.count, 4)
        XCTAssertGreaterThan(buffer.droppedBytes, 100_000)
    }

    func testEncoderBoundsFrameSizeAndRoundTripsMaximumBody() throws {
        XCTAssertThrowsError(try SoundcorePacket(command: 0x0101, body: Data(repeating: 0, count: 2039)).encode())
        let packet = SoundcorePacket(command: 0x0101, body: Data(repeating: 7, count: 2038), inbound: true)
        var buffer = SoundcoreFrameBuffer()
        XCTAssertEqual(buffer.feed(try packet.encode()), [packet])
    }

    func testCatalogueContains35SourceModelsAndClassicIdentifiersAreNotBLEClaims() throws {
        XCTAssertEqual(SoundcoreModel.allCases.count, 35)
        XCTAssertEqual(Set(SoundcoreModel.allCases.map(\.rawValue)).count, 35)
        XCTAssertFalse(SoundcoreModel.liveControlAvailable)
        XCTAssertTrue(SoundcoreModel.transportLimitation.contains("RFCOMM"))
        for model in SoundcoreModel.allCases {
            XCTAssertEqual(SoundcoreModel.fromName(model.displayName), model)
            for uuid in model.classicVendorServiceUUIDs {
                let identified = try XCTUnwrap(SoundcoreModel.fromClassicServiceUUID(uuid.uppercased()))
                // D1202 P31i/R60i share a documented serial/vendor alias and layout.
                XCTAssertEqual(identified.serialPrefix, model.serialPrefix)
            }
            XCTAssertEqual(SoundcoreModel.fromSerial(model.serialPrefix + "A1B2C3D4E5F6")?.serialPrefix, model.serialPrefix)
        }
        XCTAssertEqual(SoundcoreModel.fromClassicServiceUUID("0cf12d31-fac3-4553-bd80-d6832e7b395b"), .r50iNC)
        XCTAssertEqual(SoundcoreModel.fromClassicServiceUUID("0cf12d31-fac3-4553-bd80-d6832e71202c"), .r60iNC)
    }

    func testNameDisambiguationUnknownModelsSPPAndOtherBrandsAreRefused() {
        XCTAssertEqual(SoundcoreModel.fromName("soundcore Liberty 4 NC"), .liberty4NC)
        XCTAssertEqual(SoundcoreModel.fromName("soundcore Liberty 4 Pro"), .liberty4Pro)
        XCTAssertEqual(SoundcoreModel.fromName("soundcore Liberty 5 Pro Max"), .liberty5ProMax)
        XCTAssertEqual(SoundcoreModel.fromName("soundcore P30i"), .r50iNC)
        XCTAssertNil(SoundcoreModel.fromName("JBL soundcore Liberty 5"))
        XCTAssertNil(SoundcoreModel.fromName("Soundcore Life Q30"))
        XCTAssertNil(SoundcoreModel.fromName("soundcore Boom 2"))
        XCTAssertNil(SoundcoreModel.fromClassicServiceUUID("00001101-0000-1000-8000-00805f9b34fb"))
        XCTAssertNil(SoundcoreModel.identifyClassic(uuids: SoundcoreModel.sleepA30.classicVendorServiceUUIDs, name: "Harman"))
    }

    func testBatteryScalesUnknownSentinelsAndPushShapes() {
        XCTAssertEqual(SoundcoreBatteryScale.five.percent(5), 100)
        XCTAssertEqual(SoundcoreBatteryScale.nine.percent(0), 10)
        XCTAssertEqual(SoundcoreBatteryScale.ten.percent(0), 0)
        XCTAssertEqual(SoundcoreBatteryScale.percent.percent(63), 63)
        for scale in [SoundcoreBatteryScale.five, .nine, .ten, .percent] { XCTAssertNil(scale.percent(255)) }
        XCTAssertEqual(SoundcoreStateReader.batteryPush(model: .liberty4NC, body: Data([2, 5, 3])), .init(left: 40, right: 100, casePercent: 60, overall: nil))
        XCTAssertEqual(SoundcoreStateReader.batteryPush(model: .spaceOnePro, body: Data([2])), .init(left: nil, right: nil, casePercent: nil, overall: 30))
        XCTAssertNil(SoundcoreStateReader.batteryPush(model: .liberty4NC, body: Data([2])))
        XCTAssertNil(SoundcoreStateReader.batteryPush(model: .liberty5Pro, body: Data([2, 2])))
        XCTAssertEqual(SoundcoreStateReader.chargingPush(Data([0, 1])), true)
        XCTAssertEqual(SoundcoreStateReader.chargingPush(Data([0, 0])), false)
        XCTAssertNil(SoundcoreStateReader.chargingPush(Data([255, 7])))
    }

    func testEveryModelHasAnExplicitSimulatedStateWithSourceWriteAvailability() throws {
        XCTAssertEqual(SoundcoreModel.allCases.filter(\.hasDocumentedWrites).count, 13)
        for model in SoundcoreModel.allCases {
            let state = try SoundcoreDemo.state(for: model)
            XCTAssertTrue(state.isSimulated)
            XCTAssertNotNil(state.headlinePercent)
            XCTAssertNotNil(state.firmware)
            XCTAssertEqual(state.writable, model.hasDocumentedWrites, model.code)
            if !state.writable { XCTAssertNotNil(state.note); XCTAssertTrue(state.controls.allSatisfy { !$0.enabled }) }
        }
    }

    func testStateSizeIdentityAndLengthRuleIndependentlyBlockWrites() throws {
        let model = SoundcoreModel.liberty5
        let body = SoundcoreDemo.fixtureBody(for: model)
        let longer = try XCTUnwrap(SoundcoreStateReader.parse(model: model, body: body + Data(repeating: 0, count: 6)))
        XCTAssertNotNil(longer.modes)
        XCTAssertFalse(longer.writable)
        XCTAssertTrue(longer.settings.isEmpty)
        XCTAssertNil(longer.casePercent)
        var wrongSerial = Array(body)
        wrongSerial.replaceSubrange(16..<20, with: Array("3955".utf8))
        var wrongLength = Array(body); wrongLength[109] -= 1
        for invalid in [longer, try XCTUnwrap(SoundcoreStateReader.parse(model: model, body: Data(wrongSerial))), try XCTUnwrap(SoundcoreStateReader.parse(model: model, body: Data(wrongLength)))] {
            XCTAssertFalse(invalid.writable)
            XCTAssertThrowsError(try SoundcoreWrites.setAmbient(state: invalid, mode: .normal))
        }
        XCTAssertNil(SoundcoreStateReader.parse(model: model, body: Data([1, 2])))
        XCTAssertNil(SoundcoreStateReader.parse(model: model, body: Data((0..<154).map { UInt8(($0 * 7 + 3) & 255) })))
    }

    func testUnexpectedHeaderStillProvidesReadOnlyFirmwareInsteadOfEnablingWrongLayout() throws {
        let body = SoundcoreDemo.fixtureBody(for: .sleepA20)
        let state = try XCTUnwrap(SoundcoreStateReader.parse(model: .c30i, body: body))
        XCTAssertEqual(state.firmware, "01.91")
        XCTAssertEqual(SoundcoreModel.fromSerial(state.serial), .sleepA20)
        XCTAssertFalse(state.writable)
    }

    func testModeChangePreservesUnknownBytesAndMirrorsOnlyRequiredModels() throws {
        for model in [SoundcoreModel.liberty4NC, .r50iNC, .spaceOne, .spaceOnePro] {
            var raw = Array(SoundcoreDemo.fixtureBody(for: model))
            let layout = try XCTUnwrap(model.layout)
            raw[layout.modeOffset + 1] = 0x31; raw[layout.modeOffset + 4] = 0xa2; raw[layout.modeOffset + 5] = 0x55
            let state = try XCTUnwrap(SoundcoreStateReader.parse(model: model, body: Data(raw)))
            let packet = try SoundcoreWrites.setAmbient(state: state, mode: .transparency)
            var expected = Array(try XCTUnwrap(state.modes).raw); expected[0] = 1
            if layout.codec.mirrorsAmbientAt2 { expected[2] = 1 }
            XCTAssertEqual(packet.body, Data(expected))
            let wind = try SoundcoreWrites.control(state: state, id: "wind", value: 1)
            XCTAssertEqual(Array(wind.body)[4], 0xa3, "Only the writable wind bit changes")
        }
    }

    func testTransitionsAndRangesPreventUndocumentedModeWrites() throws {
        let state = try SoundcoreDemo.state(for: .liberty4NC)
        XCTAssertThrowsError(try SoundcoreWrites.control(state: state, id: "transparency_type", value: 1))
        XCTAssertThrowsError(try SoundcoreWrites.control(state: state, id: "nc_level", value: 5))
        XCTAssertThrowsError(try SoundcoreWrites.control(state: state, id: "nc_type", value: 3))
        let adaptive = try SoundcoreDemo.applying(SoundcoreWrites.control(state: state, id: "nc_type", value: 1), to: state)
        XCTAssertThrowsError(try SoundcoreWrites.control(state: adaptive, id: "nc_level", value: 0))
        let normal = try SoundcoreDemo.applying(SoundcoreWrites.setAmbient(state: state, mode: .normal), to: state)
        XCTAssertThrowsError(try SoundcoreWrites.control(state: normal, id: "wind", value: 1))
        let level = try SoundcoreWrites.control(state: state, id: "nc_level", value: 3)
        XCTAssertEqual(Array(level.body)[1], 0x41)
    }

    func testAllWritableModelSettingsUseOnlyTheirOwnCommandsAndReadBackExactly() throws {
        for model in SoundcoreModel.allCases where model.layout?.writable == true {
            let state = try SoundcoreDemo.state(for: model)
            for setting in try XCTUnwrap(model.layout).settings {
                let packet = try SoundcoreWrites.control(state: state, id: setting.id, value: 1)
                XCTAssertEqual(packet.command, setting.command)
                XCTAssertEqual(packet.body.count, setting.autoOff ? 2 : 1)
                let after = try SoundcoreDemo.applying(packet, to: state)
                XCTAssertEqual(after.settings[setting.id], 1)
                XCTAssertTrue(SoundcoreWrites.confirms(before: state, after: after, packet: packet))
            }
        }
    }

    func testAutoOffOffPreservesReportedDurationAndUsesPerModelTimes() throws {
        for model in [SoundcoreModel.p40i, .spaceOne] {
            let original = try SoundcoreDemo.state(for: model)
            let enabled = try SoundcoreDemo.applying(SoundcoreWrites.control(state: original, id: "auto_off", value: 4), to: original)
            let off = try SoundcoreWrites.control(state: enabled, id: "auto_off", value: 0)
            XCTAssertEqual(off.body, Data([0, 3]))
            XCTAssertEqual(try SoundcoreDemo.applying(off, to: enabled).autoOffIndexes["auto_off"], 3)
            XCTAssertThrowsError(try SoundcoreWrites.control(state: original, id: "auto_off", value: 5))
        }
        XCTAssertEqual(SoundcoreModel.p40i.layout?.autoOffMinutes, [10, 20, 30, 60])
        XCTAssertEqual(SoundcoreModel.spaceOne.layout?.autoOffMinutes, [30, 60, 90, 120])
    }

    func testMalformedReportedFlagCannotBecomeAnEnabledSetting() throws {
        var body = Array(SoundcoreDemo.fixtureBody(for: .p40i)); body[141] = 7
        let state = try XCTUnwrap(SoundcoreStateReader.parse(model: .p40i, body: Data(body)))
        XCTAssertNil(state.settings["low_battery_prompt"])
        XCTAssertFalse(try XCTUnwrap(state.controls.first { $0.id == "low_battery_prompt" }).enabled)
        XCTAssertThrowsError(try SoundcoreWrites.control(state: state, id: "low_battery_prompt", value: 1))
    }

    func testPerSourceGuardRejectsDangerousCommandsWrongModelsInboundAndWrongBodyShapes() throws {
        for model in SoundcoreModel.allCases {
            for command in SoundcoreWriteGuard.never { XCTAssertFalse(SoundcoreWriteGuard.allows(model: model, packet: .init(command: command, body: Data([1])))) }
            XCTAssertFalse(SoundcoreWriteGuard.allows(model: model, packet: .init(command: 0xffff)))
            XCTAssertFalse(SoundcoreWriteGuard.allows(model: model, packet: .init(command: 0x0101, body: Data([1]))))
            XCTAssertFalse(SoundcoreWriteGuard.allows(model: model, packet: .init(command: 0x0101, inbound: true)))
        }
        XCTAssertTrue(SoundcoreWriteGuard.allows(model: .liberty4NC, packet: .init(command: 0x0b84, body: Data([1]))))
        XCTAssertFalse(SoundcoreWriteGuard.allows(model: .sleepA30, packet: .init(command: 0x0b84, body: Data([1]))))
        XCTAssertFalse(SoundcoreWriteGuard.allows(model: .liberty4Pro, packet: .init(command: 0x0681, body: Data(repeating: 0, count: 4))))
        XCTAssertFalse(SoundcoreWriteGuard.allows(model: nil, packet: .init(command: 0x0687, body: Data([1]))))
        XCTAssertFalse(SoundcoreWriteGuard.allows(model: .liberty4NC, packet: .init(command: 0x0681, body: Data([1]))))
    }

    func testDocumentedReadsAreSafeAndSessionInitIsModelSpecific() throws {
        for model in SoundcoreModel.allCases {
            let reads = SoundcoreWriteGuard.documentedReads(for: model)
            XCTAssertEqual(reads.prefix(2).map(\.command), [0x0101, 0x0105])
            XCTAssertTrue(reads.allSatisfy { !$0.isWrite && $0.body.isEmpty && !SoundcoreWriteGuard.never.contains($0.command) })
            XCTAssertEqual(reads.contains { $0.command == 0x0501 }, model == .sleepA30 || model.layout?.sessionInit == true)
        }
        XCTAssertTrue(SoundcoreWriteGuard.allows(model: .liberty5, packet: .init(command: 0x0581)))
        XCTAssertFalse(SoundcoreWriteGuard.allows(model: .space2, packet: .init(command: 0x0581)))
    }

    func testSleepLowCodePromptAndCallSettersAreMutationsAndRequireConfirmedState() throws {
        let state = try SoundcoreDemo.state(for: .sleepA30)
        let cases: [(String, UInt16)] = [("prompt_anc", 0x1077), ("incoming_calls", 0x1075)]
        for (id, command) in cases {
            let packet = try SoundcoreWrites.control(state: state, id: id, value: 1)
            XCTAssertEqual(packet.command, command)
            XCTAssertTrue(packet.isWrite, "Both documented low-code setters must be treated as mutations")
            let after = try SoundcoreDemo.applying(packet, to: state)
            XCTAssertEqual(after.controls.first { $0.id == id }?.value, 1)
            XCTAssertTrue(SoundcoreWrites.confirms(before: state, after: after, packet: packet))
            var unconfirmed = state; unconfirmed.writable = false
            XCTAssertThrowsError(try SoundcoreWriteGuard.check(model: .sleepA30, state: unconfirmed, packet: packet))
            XCTAssertFalse(SoundcoreWriteGuard.allows(model: .sleepA30, packet: .init(command: command)))
            XCTAssertFalse(SoundcoreWriteGuard.allows(model: .liberty4NC, packet: packet))
            XCTAssertFalse(SoundcoreWriteGuard.documentedReads(for: .sleepA30).contains { $0.command == command })
        }
    }

    func testEveryDocumentedSettingCommandIsClassifiedAsMutation() {
        var commands = SoundcoreWriteGuard.sleepFlags
        commands.formUnion([SoundcoreCommands.setSleepTimer, SoundcoreCommands.setSoundModes, SoundcoreCommands.sessionInit])
        for model in SoundcoreModel.allCases {
            commands.formUnion(model.layout?.settings.map(\.command) ?? [])
        }
        for command in commands { XCTAssertTrue(SoundcorePacket(command: command).isWrite, String(format: "%04x", command)) }
        XCTAssertEqual(Set(commands.filter { $0 & 0xff < 0x80 }), [0x1075, 0x1077], "The complete upstream setter inventory has exactly these two low-code exceptions")
        XCTAssertFalse(SoundcorePacket(command: SoundcoreCommands.requestState).isWrite)
        XCTAssertFalse(SoundcorePacket(command: SoundcoreCommands.requestInfo).isWrite)
        XCTAssertFalse(SoundcorePacket(command: SoundcoreCommands.sessionInfo).isWrite)
    }

    func testSleepA30CapturedStateAndIndependentControlsAreDecoded() throws {
        let body = hex("0101090930312e393130312e39313133303158585858585858585858585800000000000030312e36380000000006dd88" +
            "ddddff0001d4027c0064001e0001ffffff00000100003232000006001e43410000000000020100000000000000000002" +
            "018000000000000004030280000000000000040403800000000000000405048000000000000004010000010701010101" + "010000010100")
        let state = try XCTUnwrap(SoundcoreStateReader.parse(model: .sleepA30, body: body))
        XCTAssertEqual(state.bodySize, 150)
        XCTAssertEqual(state.leftPercent, 100); XCTAssertEqual(state.rightPercent, 100)
        XCTAssertEqual(state.firmware, "01.91"); XCTAssertEqual(state.caseFirmware, "01.68")
        XCTAssertEqual(state.sleep?.ancOn, true); XCTAssertEqual(state.sleep?.tapControlsDisabled, false)
        XCTAssertEqual(state.sleep?.listeningLocal, false); XCTAssertEqual(state.sleep?.budsLinked, true)
        XCTAssertFalse(state.isSimulated, "A parsed reference capture is not a live connection or a generated demo")
    }

    func testSleepAllElevenControlsRoundTripAndPostSleepKeepsTimerBytesSentinel() throws {
        let state = try SoundcoreDemo.state(for: .sleepA30)
        XCTAssertEqual(state.controls.count, 11)
        for control in state.controls {
            let value = control.value == 1 ? 0 : 1
            let packet = try SoundcoreWrites.control(state: state, id: control.id, value: value)
            let changed = try SoundcoreDemo.applying(packet, to: state)
            XCTAssertTrue(SoundcoreWrites.confirms(before: state, after: changed, packet: packet), control.id)
            XCTAssertEqual(changed.controls.first { $0.id == control.id }?.value, value)
            for other in state.controls where other.id != control.id {
                XCTAssertEqual(changed.controls.first { $0.id == other.id }?.value, other.value, "Single-field writes preserve other controls")
            }
        }
        XCTAssertEqual(try SoundcoreWrites.control(state: state, id: "post_sleep_action", value: 1).body, Data([255, 255, 255, 1]))
        XCTAssertFalse(SoundcoreWriteGuard.allows(model: .sleepA30, packet: .init(command: 0x1585, body: Data([1, 30, 0, 0]))), "No guessed sleep-timer payload")
        XCTAssertThrowsError(try SoundcoreWrites.setAmbient(state: state, mode: .transparency))
        XCTAssertThrowsError(try SoundcoreWrites.control(state: state, id: "anc", value: 7))
    }

    func testReadbackIsRequiredAndSimulationCannotMutatePhysicalReports() throws {
        let state = try SoundcoreDemo.state(for: .liberty4NC)
        let packet = try SoundcoreWrites.setAmbient(state: state, mode: .transparency)
        XCTAssertFalse(SoundcoreWrites.confirms(before: state, after: state, packet: packet), "An ACK without a changed report cannot confirm the write")
        let after = try SoundcoreDemo.applying(packet, to: state)
        XCTAssertTrue(SoundcoreWrites.confirms(before: state, after: after, packet: packet))
        let physicalReport = try XCTUnwrap(SoundcoreStateReader.parse(model: state.model, body: state.raw))
        XCTAssertThrowsError(try SoundcoreDemo.applying(packet, to: physicalReport))
        XCTAssertThrowsError(try SoundcoreDemo.applying(.init(command: 0x0101), to: state))
        XCTAssertFalse(SoundcoreWrites.confirms(before: state, after: try SoundcoreDemo.state(for: .p40i), packet: packet))
    }

    func testTLVStateIsReadOnlyAndRejectsTruncatedOrDuplicateTags() throws {
        let state = try SoundcoreDemo.state(for: .liberty5ProMax)
        XCTAssertEqual(state.leftPercent, 80); XCTAssertEqual(state.rightPercent, 65); XCTAssertEqual(state.casePercent, 90)
        XCTAssertEqual(state.ambient, .noiseCancelling)
        XCTAssertFalse(state.writable)
        XCTAssertThrowsError(try SoundcoreWrites.setAmbient(state: state, mode: .normal))
        XCTAssertNil(SoundcoreStateReader.parse(model: .liberty5ProMax, body: Data(state.raw.dropLast())))
        XCTAssertNil(SoundcoreStateReader.parse(model: .liberty5ProMax, body: state.raw + Data([3, 2, 0, 50])))
    }
}
