import XCTest
@testable import Earshot

final class BluetoothDeviceTests: XCTestCase {
    private func hex(_ value: String) -> Data { Data(hex: value)! }

    func testReconnectBudgetAndExplicitUserStop() {
        let id = UUID()
        var policy = BluetoothReconnectPolicy(enabled: true, rememberedID: id, userStopped: false)
        XCTAssertEqual((0..<6).compactMap { _ in policy.nextDelay() }, [1, 2, 4, 8, 16, 30])
        XCTAssertNil(policy.nextDelay())
        XCTAssertTrue(policy.exhausted)
        policy.manualDisconnect()
        XCTAssertFalse(policy.eligible)
        XCTAssertNil(policy.nextDelay())
        policy.resume()
        XCTAssertFalse(policy.eligible, "Returning from demo/background must not override a manual disconnect")
        policy.manualConnection()
        XCTAssertTrue(policy.eligible)
        XCTAssertEqual(policy.nextDelay(), 1)
        policy.verified(id)
        XCTAssertEqual(policy.attempts, 0)
    }

    func testReconnectRequiresOptInRememberedDeviceAndActiveMode() {
        var policy = BluetoothReconnectPolicy(enabled: false, rememberedID: UUID(), userStopped: false)
        XCTAssertNil(policy.nextDelay())
        policy.enable(true)
        policy.suspended = true
        XCTAssertNil(policy.nextDelay())
        policy.resume()
        XCTAssertEqual(policy.nextDelay(), 1)
        policy.rememberedID = nil
        XCTAssertNil(policy.nextDelay())
    }

    func testMuteOpenChannelIsProbedBeforeBeingDeclaredDisconnected() {
        let start = Date(timeIntervalSince1970: 0)
        var monitor = BluetoothLivenessMonitor(lastResponse: start)
        XCTAssertEqual(monitor.tick(at: start.addingTimeInterval(120)), .none, "Idle subscriptions must not be polled")
        for second in [1.0, 2.0, 3.0] { monitor.sentRequest(at: start.addingTimeInterval(second)) }
        XCTAssertEqual(monitor.tick(at: start.addingTimeInterval(4)), .none)
        XCTAssertEqual(monitor.tick(at: start.addingTimeInterval(4.5)), .sendProbe)
        XCTAssertEqual(monitor.tick(at: start.addingTimeInterval(6)), .none)
        XCTAssertEqual(monitor.tick(at: start.addingTimeInterval(7.5)), .disconnect)
        monitor.received(at: start.addingTimeInterval(8))
        XCTAssertEqual(monitor.tick(at: start.addingTimeInterval(120)), .none)
    }

    @MainActor
    func testRememberedPreferenceRestorationDoesNotFakeAConnection() throws {
        let suite = "earshot.bluetooth-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(UUID().uuidString, forKey: "earshot.bluetooth.identifier")
        defaults.set("My Bose headphones", forKey: "earshot.bluetooth.name")
        defaults.set(true, forKey: "earshot.bluetooth.reconnect")
        let bluetooth = HeadphoneBluetooth(defaults: defaults)
        XCTAssertTrue(bluetooth.reconnectEnabled)
        XCTAssertEqual(bluetooth.rememberedDeviceName, "My Bose headphones")
        XCTAssertFalse(bluetooth.isConnected)
        XCTAssertFalse(bluetooth.isReconnecting)
        bluetooth.disconnect()
        XCTAssertTrue(defaults.bool(forKey: "earshot.bluetooth.manual-stop"))
        bluetooth.forgetRememberedDevice()
        XCTAssertNil(bluetooth.rememberedDeviceName)
        XCTAssertNil(defaults.string(forKey: "earshot.bluetooth.identifier"))
    }

    func testSourceCommandsMatchUpstreamBoseLayouts() throws {
        let address = hex("2cda46000002")
        XCTAssertEqual(try BoseCommands.source(action: .connect, address: address).encode().hexString, "04010507002cda46000002")
        XCTAssertEqual(try BoseCommands.source(action: .disconnect, address: address).encode().hexString, "040205062cda46000002")
        XCTAssertEqual(try BoseCommands.source(action: .remove, address: address).encode().hexString, "040305062cda46000002")
        XCTAssertEqual(try BoseCommands.source(action: .route, address: address).encode().hexString, "040c0507822cda46000002")
        XCTAssertEqual(try BoseCommands.pairingMode(enabled: true).encode().hexString, "0408050101")
        XCTAssertThrowsError(try BoseCommands.source(action: .connect, address: Data(repeating: 0, count: 6)))
        XCTAssertThrowsError(try BoseCommands.source(action: .remove, address: hex("010203")))
        XCTAssertNoThrow(try BmapWriteGuard.check(BoseCommands.source(action: .remove, address: address)))
        XCTAssertThrowsError(try BmapWriteGuard.check(BmapPacket(block: 4, function: 7, operation: .start)))
    }

    func testFunctionEvidenceDoesNotInventRoutingSupportFromEmptyTable() {
        let exists = BmapPacket(block: 4, function: 2, operation: .error, payload: Data([5]))
        XCTAssertEqual(BoseParsers.sourceCapability(exists)?.action, .disconnect)
        XCTAssertEqual(BoseParsers.sourceCapability(exists)?.supported, true)
        let absent = BmapPacket(block: 4, function: 3, operation: .error, payload: Data([4]))
        XCTAssertEqual(BoseParsers.sourceCapability(absent)?.supported, false)
        let emptyRoute = BmapPacket(block: 4, function: 12, operation: .error, payload: Data([4]))
        XCTAssertNil(BoseParsers.sourceCapability(emptyRoute))
        XCTAssertTrue(BmapFailure.device(BmapAddress(4, 2), 5).localizedDescription.contains("operation"))
    }

    func testDeviceInfoRecognizesTheControlPhoneAndPrivacyRedaction() throws {
        let packet = BmapPacket(block: 4, function: 5, operation: .status,
            payload: hex("2cda46000002030203") + Data("My iPhone".utf8))
        let parsed = try XCTUnwrap(BoseDeviceInfo.parse(packet.payload))
        XCTAssertEqual(parsed.name, "My iPhone")
        XCTAssertTrue(parsed.connected)
        XCTAssertTrue(parsed.isLocal)
        let redacted = BmapDiagnostics.summary(packet)
        XCTAssertFalse(redacted.contains("My iPhone"))
        XCTAssertFalse(redacted.contains("2cda46"))
    }

    func testInstalledLanguagesAndRemainingBatteryMinutesUseCapturedLayouts() throws {
        let voice = try XCTUnwrap(BoseVoicePromptsState.parse(hex("41000081020000")))
        XCTAssertEqual(voice.language, 1)
        XCTAssertEqual(voice.installedLanguages, [1, 8, 15])
        XCTAssertEqual(try BoseCommands.setVoicePrompts(enabled: voice.enabled, language: 15).payload, hex("0f"))
        XCTAssertEqual(BoseBattery.parse(hex("32007800")).remainingMinutes, 120)
        XCTAssertNil(BoseBattery.parse(hex("32ffff00")).remainingMinutes)
        XCTAssertEqual(BoseBattery.parse(hex("3c00640132005a02")).remainingMinutes, 90)
    }

    func testModelCatalogueAdaptsBuiltInNamesToReportedCounts() throws {
        let open = try XCTUnwrap(BoseModelFacts.lookup(0x4089))
        XCTAssertEqual(open.builtInLabels(reportedCount: 2), ["Stereo", "Immersion"])
        XCTAssertEqual(open.builtInLabels(reportedCount: 4), ["Stereo", "Immersion", "Cinema", "Mode 4"])
        let qc45 = try XCTUnwrap(BoseModelFacts.lookup(0x4039))
        XCTAssertTrue(qc45.knownAbsent.contains(BmapAddress(31, 10)))
        XCTAssertTrue(qc45.knownAbsent.contains(BmapAddress(1, 24)))
        XCTAssertEqual(BoseModelFacts.lookup(0x402f)?.customCount, 2)
        XCTAssertEqual(BoseModelFacts.lookup(0x4024)?.directNoise, true)
        XCTAssertEqual(qc45.modeDumpCommand.address, BmapAddress(31, 1))
        XCTAssertTrue(qc45.windExcludesNoiseLevel)
        XCTAssertEqual(BoseModelFacts.fromName("Bose QC 2 HP")?.productID, 0x4083)
        XCTAssertEqual(BoseModelFacts.fromName("LE-Bose QC Ultra 2 Earbuds")?.productID, 0x4062)
        XCTAssertEqual(BoseModelFacts.fromName("Bose Ultra Open 2 Earbuds")?.presetNames, ["Stereo", "Immersion", "Cinema"])
        XCTAssertNil(BoseModelFacts.fromName("My listening set"))
    }

    @MainActor
    func testReadOnlyScannerUsesOnlyVettedGETsAndRecordsRealResponses() async throws {
        let scanner = BmapProtocolScanner()
        var sent = [BmapPacket]()
        scanner.start(addresses: [BmapAddress(0, 1), BmapAddress(3, 2), BmapAddress(18, 9), BmapAddress(2, 2)]) { packet in
            sent.append(packet)
            scanner.receive(packet) // An echoed GET must not count as a device response.
            scanner.receive(BmapPacket(block: packet.block, function: packet.function, operation: .status, payload: Data([1])))
        }
        for _ in 0..<100 {
            if !scanner.isScanning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(scanner.isScanning)
        XCTAssertEqual(sent.map(\.address), [BmapAddress(0, 1), BmapAddress(2, 2)])
        XCTAssertTrue(sent.allSatisfy { $0.operation == .get })
        XCTAssertEqual(scanner.results.count, 2)
        XCTAssertTrue(scanner.results.allSatisfy(\.succeeded))
    }

    @MainActor
    func testRestartedScanCannotBeClearedByOldCancelledTask() async throws {
        let scanner = BmapProtocolScanner()
        scanner.start(addresses: [BmapAddress(0, 1)]) { _ in }
        await Task.yield()
        scanner.start(addresses: [BmapAddress(2, 2)]) { packet in
            scanner.receive(BmapPacket(block: packet.block, function: packet.function, operation: .status, payload: Data([50])))
        }
        for _ in 0..<100 {
            if !scanner.isScanning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(scanner.results.map(\.address), [BmapAddress(2, 2)])
        XCTAssertEqual(scanner.completed, 1)
    }
}
