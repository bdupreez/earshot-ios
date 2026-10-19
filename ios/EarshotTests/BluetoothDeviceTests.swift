import XCTest
import CoreFoundation
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

    // Native transport regressions for the AI-assisted port of HellzYeahh/earshot (MIT).
    // These exercise the real queue, Foundation stream and run loop, without a Bluetooth device.
    func testANCValueBurstsKeepOnlyNewestUnsentValueAndTrailingModeRead() throws {
        for direct in [false, true] {
            var queue = BmapOutputQueue()
            let modeRead = try outputFrame(BoseCommands.readCurrentMode)
            for index in 0..<1_000 {
                let newest = try cncFrame(UInt8(index % 11), direct: direct)
                XCTAssertTrue(try queue.enqueue(newest))
                _ = try queue.enqueue(modeRead)
                XCTAssertLessThanOrEqual(queue.frames.count, 2, "Unsent slider values must not fill the transport queue")
                XCTAssertEqual(queue.frames.first?.data, newest.data)
                XCTAssertEqual(queue.frames.last?.data, modeRead.data, "Read current mode after the newest value, rather than before it")
            }
            XCTAssertFalse(try queue.enqueue(modeRead), "An identical associated mode read needs only one queued request")
            XCTAssertEqual(queue.frames.count, 2)
        }
    }

    func testPartialCNCFrameAndPriorityProbePreserveDecodableWireOrder() throws {
        var queue = BmapOutputQueue()
        let original = try cncFrame(1)
        let newest = try cncFrame(9)
        let probe = try outputFrame(BoseCommands.liveness)
        let modeRead = try outputFrame(BoseCommands.readCurrentMode)
        let start = Date(timeIntervalSince1970: 1_000)
        var wire = Data()
        try queue.enqueue(original)
        XCTAssertNil(try queue.writeNext(at: start) { data in
            wire.append(data.prefix(2)); return 2
        })
        XCTAssertEqual(queue.partialWriteOffset, 2)
        try queue.enqueue(cncFrame(3))
        try queue.enqueue(modeRead)
        try queue.enqueue(newest)
        try queue.enqueue(probe, priority: true)
        XCTAssertEqual(queue.frames.first?.data, original.data, "A started frame must finish byte for byte")
        XCTAssertEqual(queue.frames.dropFirst().first?.data, probe.data, "Priority is applied only after the partial frame")
        XCTAssertEqual(queue.frames.filter { $0.address == newest.address }.map(\.data), [original.data, newest.data])

        var completed = [BmapOutgoingFrame]()
        for index in 0..<10 where !queue.frames.isEmpty {
            if let frame = try queue.writeNext(at: start.addingTimeInterval(Double(index)), write: { data in
                wire.append(data); return data.count
            }) { completed.append(frame) }
        }
        XCTAssertTrue(queue.frames.isEmpty)
        var parser = BmapFrameBuffer()
        let decoded = parser.feed(wire)
        XCTAssertEqual(decoded.map(\.address), [original.address, probe.address, newest.address, modeRead.address])
        XCTAssertEqual(decoded.map { try? $0.encode() }, completed.map { Optional($0.data) })
        XCTAssertEqual(parser.desyncCount, 0)
        XCTAssertTrue(parser.pending.isEmpty)
    }

    func testANCReplacementNeverCrossesDiscreteReadOrDiagnosticBarriers() throws {
        let diagnosticID = UUID()
        let barriers = [
            try outputFrame(BoseCommands.selectMode(index: 1)),
            try outputFrame(BoseCommands.setEQ(band: 0, value: 4)),
            try outputFrame(BoseCommands.get(BmapAddress(2, 2))),
            try outputFrame(BoseCommands.readCurrentMode, diagnosticID: diagnosticID)
        ]
        for barrier in barriers {
            var queue = BmapOutputQueue()
            let old = try cncFrame(1)
            let newest = try cncFrame(8)
            let read = try outputFrame(BoseCommands.readCurrentMode)
            try queue.enqueue(old); try queue.enqueue(read)
            try queue.enqueue(barrier)
            try queue.enqueue(newest); try queue.enqueue(read)
            XCTAssertEqual(queue.frames.map(\.data), [old.data, read.data, barrier.data, newest.data, read.data])
            XCTAssertEqual(queue.frames[2].diagnosticID, barrier.diagnosticID)
        }
    }

    func testANCCoalescingPreservesDistinctRoutesAddressesAndNonabsoluteFrames() throws {
        let candidates = [
            try cncFrame(1),
            try cncFrame(2, direct: true),
            try cncFrame(3, deviceID: 1),
            try cncFrame(4, port: 1),
            try outputFrame(BmapPacket(block: 31, function: 10, operation: .setGet, payload: Data([1]))),
            try outputFrame(BmapPacket(block: 1, function: 5, operation: .set, payload: Data([1, 1])))
        ]
        var queue = BmapOutputQueue()
        for frame in candidates { try queue.enqueue(frame) }
        XCTAssertEqual(queue.frames.map(\.data), candidates.map(\.data), "Coalescing is restricted to the exact absolute command and route")
        let newest = try cncFrame(10)
        try queue.enqueue(newest)
        XCTAssertEqual(queue.frames.map(\.data), candidates.map(\.data) + [newest.data], "A malformed/discrete command remains an ordering barrier")

        var routed = BmapOutputQueue()
        for frame in candidates.prefix(4) { try routed.enqueue(frame) }
        try routed.enqueue(newest)
        XCTAssertEqual(routed.frames.map(\.data), candidates.prefix(4).map(\.data) + [newest.data], "A different route/address conservatively ends a replacement run")
        let sameRouteLatest = try cncFrame(7)
        try routed.enqueue(sameRouteLatest)
        XCTAssertEqual(routed.frames.map(\.data), candidates.prefix(4).map(\.data) + [sameRouteLatest.data])

        for invalid in [
            BmapOutgoingFrame(data: newest.data + Data([0]), address: newest.address, diagnosticID: nil, operation: .setGet),
            BmapOutgoingFrame(data: newest.data, address: BmapAddress(1, 5), diagnosticID: nil, operation: .setGet),
            BmapOutgoingFrame(data: newest.data, address: newest.address, diagnosticID: nil, operation: .get)
        ] {
            var inconsistent = BmapOutputQueue()
            try inconsistent.enqueue(invalid)
            try inconsistent.enqueue(newest)
            XCTAssertEqual(inconsistent.frames.map(\.data), [invalid.data, newest.data], "Invalid encoded length or metadata must not authorize replacement")
        }
    }

    func testQueueReplacesAtCapacityAndRejectsUnrelatedOverflowAtomically() throws {
        var queue = BmapOutputQueue()
        let barrier = try outputFrame(BoseCommands.get(BmapAddress(2, 2)))
        for _ in 0..<(BmapOutputQueue.capacity - 1) { try queue.enqueue(barrier) }
        try queue.enqueue(cncFrame(1))
        XCTAssertEqual(queue.frames.count, BmapOutputQueue.capacity)
        let newest = try cncFrame(10)
        XCTAssertTrue(try queue.enqueue(newest), "Capacity must be checked after replacing an unsent absolute value")
        XCTAssertEqual(queue.frames.last?.data, newest.data)
        let before = queue.frames.map(\.data)
        XCTAssertThrowsError(try queue.enqueue(barrier))
        XCTAssertEqual(queue.frames.map(\.data), before)
        XCTAssertEqual(queue.partialWriteOffset, 0)

        var duplicateRead = BmapOutputQueue()
        for _ in 0..<(BmapOutputQueue.capacity - 2) { try duplicateRead.enqueue(barrier) }
        try duplicateRead.enqueue(newest)
        let read = try outputFrame(BoseCommands.readCurrentMode)
        try duplicateRead.enqueue(read)
        XCTAssertFalse(try duplicateRead.enqueue(read), "An already queued mode read must not fail only because the queue is full")
        XCTAssertEqual(duplicateRead.frames.count, BmapOutputQueue.capacity)
    }

    func testRealMemoryStreamPacesWholeFramesAndCompletesPartialDiagnosticOnlyOnce() throws {
        var queue = BmapOutputQueue()
        let diagnostic = try outputFrame(BoseCommands.get(BmapAddress(2, 2)), diagnosticID: UUID())
        let normal = try outputFrame(BoseCommands.get(BmapAddress(1, 7)))
        try queue.enqueue(diagnostic); try queue.enqueue(normal)
        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }
        let start = Date(timeIntervalSince1970: 2_000)
        XCTAssertNil(try queue.writeNext(at: start) { _ in 0 })
        XCTAssertEqual(queue.partialWriteOffset, 0)
        XCTAssertNil(try queue.writeNext(at: start) { data in self.write(data.prefix(2), to: stream) })
        XCTAssertEqual(queue.partialWriteOffset, 2)
        let sent = try queue.writeNext(at: start) { self.write($0, to: stream) }
        XCTAssertEqual(sent?.diagnosticID, diagnostic.diagnosticID)
        XCTAssertEqual(queue.lastFrameSent, start)
        XCTAssertEqual(queue.partialWriteOffset, 0)
        var prematureWrites = 0
        XCTAssertNil(try queue.writeNext(at: start.addingTimeInterval(BmapOutputQueue.minFrameInterval / 2)) { data in
            prematureWrites += 1; return self.write(data, to: stream)
        })
        XCTAssertEqual(prematureWrites, 0)
        XCTAssertEqual(try queue.writeNext(at: start.addingTimeInterval(BmapOutputQueue.minFrameInterval + 0.001)) {
            self.write($0, to: stream)
        }?.data, normal.data)
        XCTAssertNil(try queue.writeNext(at: start.addingTimeInterval(1)) { self.write($0, to: stream) })
        XCTAssertEqual(stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data, diagnostic.data + normal.data)
    }

    func testDiagnosticCancelDropsOnlyUnstartedReadsAndResetClearsPumpState() throws {
        var queue = BmapOutputQueue()
        let partial = try outputFrame(BoseCommands.get(BmapAddress(2, 2)), diagnosticID: UUID())
        let cancelled = try outputFrame(BoseCommands.readCurrentMode, diagnosticID: UUID())
        let normal = try cncFrame(6)
        try queue.enqueue(partial); try queue.enqueue(cancelled); try queue.enqueue(normal)
        let start = Date(timeIntervalSince1970: 3_000)
        XCTAssertNil(try queue.writeNext(at: start) { _ in 2 })
        XCTAssertEqual(queue.cancelDiagnostics(), [try XCTUnwrap(cancelled.diagnosticID)])
        XCTAssertEqual(queue.frames.map(\.data), [partial.data, normal.data])
        XCTAssertEqual(queue.partialWriteOffset, 2)
        XCTAssertEqual(try queue.writeNext(at: start) { $0.count }?.diagnosticID, partial.diagnosticID)
        XCTAssertTrue(queue.cancelDiagnostics().isEmpty)
        queue.reset()
        XCTAssertTrue(queue.frames.isEmpty)
        XCTAssertEqual(queue.partialWriteOffset, 0)
        try queue.enqueue(normal)
        XCTAssertEqual(try queue.writeNext(at: start) { $0.count }?.data, normal.data, "Reconnect/reset must not inherit the old frame delay")
    }

    func testProductionPumpTimerDrainsMemoryStreamInNondefaultCommonRunLoopMode() throws {
        var queue = BmapOutputQueue()
        let first = try outputFrame(BoseCommands.get(BmapAddress(2, 2)))
        let second = try outputFrame(BoseCommands.get(BmapAddress(1, 7)))
        try queue.enqueue(first); try queue.enqueue(second)
        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }
        let mode = RunLoop.Mode("EarshotTransportTrackingTest.\(UUID().uuidString)")
        CFRunLoopAddCommonMode(CFRunLoopGetCurrent(), CFRunLoopMode(rawValue: mode.rawValue as CFString))
        var firedModes = [RunLoop.Mode?]()
        var completed = [Data]()
        var failures = [Error]()
        let timer = BmapOutputPumpTimer.make(interval: 0.01, runLoop: .current) { _ in
            firedModes.append(RunLoop.current.currentMode)
            do {
                if let frame = try queue.writeNext(at: Date(), write: { self.write($0, to: stream) }) {
                    completed.append(frame.data)
                }
            } catch { failures.append(error) }
        }
        defer { timer.invalidate() }
        let deadline = Date().addingTimeInterval(0.6)
        while !queue.frames.isEmpty, Date() < deadline {
            RunLoop.current.run(mode: mode, before: min(deadline, Date().addingTimeInterval(0.025)))
        }
        XCTAssertTrue(failures.isEmpty, "\(failures)")
        XCTAssertTrue(queue.frames.isEmpty, "The paced pump must keep running while the default run-loop mode is inactive")
        XCTAssertEqual(completed, [first.data, second.data])
        XCTAssertTrue(firedModes.contains { $0 == mode })
        XCTAssertEqual(stream.property(forKey: .dataWrittenToMemoryStreamKey) as? Data, first.data + second.data)
        timer.invalidate()
        let countAfterInvalidation = firedModes.count
        RunLoop.current.run(mode: mode, before: Date().addingTimeInterval(0.03))
        XCTAssertEqual(firedModes.count, countAfterInvalidation)
    }

    private func outputFrame(_ packet: BmapPacket, diagnosticID: UUID? = nil) throws -> BmapOutgoingFrame {
        BmapOutgoingFrame(data: try packet.encode(), address: packet.address, diagnosticID: diagnosticID, operation: packet.operation)
    }

    private func cncFrame(_ wireLevel: UInt8, direct: Bool = false, deviceID: UInt8 = 0, port: UInt8 = 0) throws -> BmapOutgoingFrame {
        try outputFrame(BmapPacket(block: direct ? 1 : 31, function: direct ? 5 : 10, operation: .setGet,
            payload: direct ? Data([wireLevel, 1]) : Data([wireLevel, 0, 0, 0, 1]), deviceID: deviceID, port: port))
    }

    private func write(_ data: Data, to stream: OutputStream) -> Int {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return stream.write(base, maxLength: data.count)
        }
    }
}
