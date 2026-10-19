// AI-assisted port of HellzYeahh/earshot's selected/deep Lab GET discovery (MIT).
// Replies below are explicit unit fixtures, not physical device compatibility evidence.
import XCTest
@testable import Earshot

final class DeepScanTests: XCTestCase {
    func testDeepPlanPreservesUpstream64By64BoundsAndEverySafetyExclusion() {
        let plan = BmapScanPlan.deep
        XCTAssertEqual(plan.addresses.count, 3897)
        XCTAssertEqual(Set(plan.addresses).count, plan.addresses.count)
        XCTAssertEqual(plan.addresses.first, BmapAddress(0, 0))
        XCTAssertEqual(plan.addresses.last, BmapAddress(63, 63))
        XCTAssertEqual(plan.maximumEstimatedMinutes, 72)
        XCTAssertTrue(plan.addresses.allSatisfy(BmapScanPlan.allows))
        for block in [3, 18, 22] { XCTAssertFalse(plan.addresses.contains { $0.block == block }) }
        for address in BmapScanPlan.excludedAddresses { XCTAssertFalse(plan.addresses.contains(address)) }
    }

    func testSelectedPlanUsesCanonicalBlockOrderAndRejectsOutOfRangeInputs() {
        let defaults = BmapScanPlan.selected(blocks: [1, 2, 31])
        XCTAssertEqual(defaults.addresses.count, 121)
        XCTAssertEqual(BmapScanPlan.selected(blocks: [1, 2]).addresses.count, 82)
        XCTAssertEqual(BmapScanPlan.selected(blocks: [-1, 64, 2, 1], maximumFunction: 1).addresses,
                       [BmapAddress(1, 0), BmapAddress(1, 1), BmapAddress(2, 0), BmapAddress(2, 1)])
        XCTAssertTrue(BmapScanPlan.selected(blocks: [], maximumFunction: 63).addresses.isEmpty)
        XCTAssertTrue(BmapScanPlan.selected(blocks: [1], maximumFunction: -1).addresses.isEmpty)
        XCTAssertTrue(BmapScanPlan.selected(blocks: [1], maximumFunction: 64).addresses.isEmpty)
        XCTAssertTrue(BmapScanPlan.documented.addresses.allSatisfy(BmapScanPlan.allows))
    }

    @MainActor func testBroaderPlanSendsOnlyGETAndDistinguishesReplyFromRefusal() async throws {
        let scanner = BmapProtocolScanner()
        var sent = [BmapPacket]()
        scanner.start(plan: .selected(blocks: [40], maximumFunction: 1)) { packet in
            sent.append(packet)
            scanner.receive(packet) // A local GET echo is not a successful device response.
            scanner.receive(BmapPacket(block: packet.block, function: packet.function,
                                       operation: packet.function == 0 ? .status : .error,
                                       payload: Data([packet.function == 0 ? 1 : 4])))
        }
        try await waitForCompletion(scanner)
        XCTAssertEqual(sent.map(\.address), [BmapAddress(40, 0), BmapAddress(40, 1)])
        XCTAssertTrue(sent.allSatisfy { $0.operation == .get && $0.payload.isEmpty })
        XCTAssertEqual(scanner.total, 2)
        XCTAssertEqual(scanner.completed, 2)
        XCTAssertEqual(scanner.results.map(\.succeeded), [true, false])
        XCTAssertTrue(scanner.results[1].response.contains("Function not supported"))
    }

    @MainActor func testEchoOnlyTimesOutAndCannotClaimSuccess() async throws {
        let scanner = BmapProtocolScanner()
        scanner.start(plan: .selected(blocks: [40], maximumFunction: 0)) { scanner.receive($0) }
        try await waitForCompletion(scanner)
        XCTAssertEqual(scanner.results.count, 1)
        XCTAssertFalse(scanner.results[0].succeeded)
        XCTAssertTrue(scanner.results[0].response.contains("No response"))
    }

    @MainActor func testForegroundLossAndCancellationStopFurtherQueries() async throws {
        let scanner = BmapProtocolScanner()
        var active = true
        var sent = [BmapPacket]()
        scanner.start(plan: .selected(blocks: [40], maximumFunction: 63), mayContinue: { active }) { packet in
            sent.append(packet)
            active = false
        }
        try await waitForCompletion(scanner)
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(scanner.results.isEmpty)
        XCTAssertTrue(scanner.status.contains("foreground"))
        scanner.start(plan: .deep) { packet in sent.append(packet); scanner.cancel() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(scanner.isScanning)
        XCTAssertEqual(sent.count, 2)
        XCTAssertTrue(scanner.results.isEmpty)
    }

    func testKnownPrivateDiscoveryFieldsRemainRedacted() {
        for address in [BmapAddress(0, 6), BmapAddress(0, 20), BmapAddress(1, 1), BmapAddress(4, 6), BmapAddress(22, 4)] {
            let summary = BmapDiagnostics.summary(BmapPacket(block: address.block, function: address.function, operation: .status, payload: Data("PRIVATE-DEVICE".utf8)))
            XCTAssertTrue(summary.contains("redacted"))
            XCTAssertFalse(summary.contains(Data("PRIVATE-DEVICE".utf8).hexString))
        }
    }

    func testDiagnosticCorrelationStartsAtActualTransmissionAndExpires() {
        let address = BmapAddress(1, 24)
        let start = Date(timeIntervalSince1970: 100)
        let id = UUID()
        var isolation = BmapDiagnosticReadIsolation()
        isolation.enqueue(id: id, address: address)
        XCTAssertTrue(isolation.blocksMutation(at: address, now: start.addingTimeInterval(30)))
        XCTAssertFalse(isolation.containsTransmitted(address, at: start), "A queued read cannot claim an earlier device error.")
        isolation.transmitted(id: id, at: start.addingTimeInterval(30))
        XCTAssertTrue(isolation.containsTransmitted(address, at: start.addingTimeInterval(37.9)))
        XCTAssertFalse(isolation.containsTransmitted(address, at: start.addingTimeInterval(38)))
        XCTAssertFalse(isolation.blocksMutation(at: address, now: start.addingTimeInterval(38)))
        XCTAssertFalse(isolation.blocksMutation(at: BmapAddress(1, 7), now: start.addingTimeInterval(31)))
    }

    func testCancellationDropsUnsentReadsButFinishesPartialFrameWithoutCorruptingWire() throws {
        let first = BoseCommands.get(BmapAddress(1, 24))
        let cancelled = BoseCommands.get(BmapAddress(2, 2))
        let normal = BoseCommands.get(BmapAddress(0, 1))
        let frames = try [
            BmapOutgoingFrame(data: first.encode(), address: first.address, diagnosticID: UUID(), operation: .get),
            BmapOutgoingFrame(data: cancelled.encode(), address: cancelled.address, diagnosticID: UUID(), operation: .get),
            BmapOutgoingFrame(data: normal.encode(), address: normal.address, diagnosticID: nil, operation: .get)
        ]
        let retained = BmapOutgoingFrame.retainingAfterDiagnosticCancel(frames, partialWriteOffset: 2)
        XCTAssertEqual(retained.map(\.address), [first.address, normal.address])
        var buffer = BmapFrameBuffer()
        let prefix = Data(frames[0].data.prefix(2))
        let remainder = Data(retained[0].data.dropFirst(2)) + retained[1].data
        XCTAssertEqual(buffer.feed(prefix + remainder), [first, normal])
        XCTAssertEqual(BmapOutgoingFrame.retainingAfterDiagnosticCancel(frames, partialWriteOffset: 0).map(\.address), [normal.address])
    }

    @MainActor func testScanCannotStartWhileARealMutationIsAwaitingItsReply() {
        let fixture = storeFixture(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.trackSentRequest(BoseCommands.setToggle(function: 24, enabled: true))
        var sends = 0
        let scanner = fixture.store.bluetooth.protocolScanner
        scanner.start(plan: .selected(blocks: [1], maximumFunction: 24)) { _ in sends += 1 }
        XCTAssertFalse(scanner.isScanning)
        XCTAssertEqual(sends, 0)
        XCTAssertTrue(scanner.status.contains("awaiting a report"))
        fixture.store.receive(BmapPacket(block: 1, function: 24, operation: .error, payload: Data([8])))
        XCTAssertEqual(fixture.store.commandFailureVersion, 1, "The actual mutation refusal must still fail its command.")
    }

    @MainActor func testScanErrorCannotPoisonSupportOrHideAnUnrelatedWriteFailure() throws {
        let fixture = storeFixture(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        let scanner = store.bluetooth.protocolScanner
        let now = Date(timeIntervalSince1970: 100)
        let id = UUID()
        store.liveFunctions.insert("1.24")
        scanner.queuedDiagnosticRead(id: id, address: BmapAddress(1, 24))
        scanner.transmittedDiagnosticRead(id: id, at: now)
        store.trackSentRequest(try BoseCommands.setEQ(band: 0, value: 2))
        store.bluetooth.routeVerifiedResponse(BmapPacket(block: 1, function: 24, operation: .error, payload: Data([5])), at: now.addingTimeInterval(1))
        XCTAssertTrue(store.supports(1, 24))
        XCTAssertEqual(store.commandFailureVersion, 0)
        store.bluetooth.routeVerifiedResponse(BmapPacket(block: 1, function: 7, operation: .error, payload: Data([8])), at: now.addingTimeInterval(1))
        XCTAssertEqual(store.commandFailureVersion, 1, "Isolation is exact-address; a real different-address refusal must reach the store.")
        store.bluetooth.routeVerifiedResponse(BmapPacket(block: 1, function: 24, operation: .error, payload: Data([4])), at: now.addingTimeInterval(9))
        XCTAssertFalse(store.supports(1, 24), "Beyond the bounded window ordinary error handling resumes.")
    }

    @MainActor func testValidStatusPushStillUpdatesStoreDuringDiagnosticQuarantine() {
        let fixture = storeFixture(); defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        let id = UUID()
        let now = Date(timeIntervalSince1970: 100)
        store.saved.autoPause = false
        store.bluetooth.protocolScanner.queuedDiagnosticRead(id: id, address: BmapAddress(1, 24))
        store.bluetooth.protocolScanner.transmittedDiagnosticRead(id: id, at: now)
        store.bluetooth.routeVerifiedResponse(BmapPacket(block: 1, function: 24, operation: .status, payload: Data([1])), at: now.addingTimeInterval(1))
        XCTAssertTrue(store.saved.autoPause)
        XCTAssertTrue(store.supports(1, 24))
    }

    @MainActor func testMutationGuardCoversActiveScanAndLateCancelledReadWithoutBlockingOtherAddresses() {
        let scanner = BmapProtocolScanner()
        scanner.start(plan: .selected(blocks: [1], maximumFunction: 24)) { _ in }
        let mutation = BoseCommands.setToggle(function: 24, enabled: true)
        XCTAssertTrue(scanner.mutationAccessError(for: mutation)?.contains("Stop the read-only scan") == true)
        let id = UUID()
        let now = Date(timeIntervalSince1970: 100)
        scanner.queuedDiagnosticRead(id: id, address: mutation.address)
        scanner.cancel()
        XCTAssertNotNil(scanner.mutationAccessError(for: mutation, at: now), "A partial/queued read remains protected until actually transmitted or discarded.")
        scanner.transmittedDiagnosticRead(id: id, at: now.addingTimeInterval(30))
        XCTAssertNotNil(scanner.mutationAccessError(for: mutation, at: now.addingTimeInterval(37)))
        XCTAssertNil(scanner.mutationAccessError(for: BoseCommands.setToggle(function: 27, enabled: true), at: now.addingTimeInterval(37)))
        XCTAssertNil(scanner.mutationAccessError(for: mutation, at: now.addingTimeInterval(38)))
        XCTAssertNil(scanner.mutationAccessError(for: BoseCommands.get(mutation.address), at: now.addingTimeInterval(37)))
        scanner.resetDiagnosticConnection()
        XCTAssertFalse(scanner.isolatesDiagnosticError(BmapPacket(block: 1, function: 24, operation: .error, payload: Data([5])), at: now.addingTimeInterval(31)))
    }

    @MainActor func testTimedOutScanCompletionDiscardsUnsentBackpressuredRead() async throws {
        let scanner = BmapProtocolScanner()
        var frames = [BmapOutgoingFrame]()
        scanner.onCancel = {
            let retained = BmapOutgoingFrame.retainingAfterDiagnosticCancel(frames, partialWriteOffset: 0)
            let kept = Set(retained.compactMap(\.diagnosticID))
            for id in frames.compactMap(\.diagnosticID) where !kept.contains(id) { scanner.discardedDiagnosticRead(id: id) }
            frames = retained
        }
        scanner.start(plan: .selected(blocks: [40], maximumFunction: 0)) { packet in
            let id = UUID()
            scanner.queuedDiagnosticRead(id: id, address: packet.address)
            frames.append(BmapOutgoingFrame(data: try packet.encode(), address: packet.address, diagnosticID: id, operation: .get))
            // Simulate output backpressure: the frame has not been transmitted.
        }
        try await waitForCompletion(scanner)
        XCTAssertEqual(scanner.completed, 1)
        XCTAssertFalse(scanner.results[0].succeeded)
        XCTAssertTrue(frames.isEmpty, "Finishing a timeout must discard unsent diagnostic traffic, just like explicit cancellation.")
        XCTAssertTrue(scanner.diagnosticReads.queued.isEmpty)
        XCTAssertNil(scanner.mutationAccessError(for: BmapPacket(block: 40, function: 0, operation: .setGet)))
    }

    @MainActor private func storeFixture() -> (store: AppStore, defaults: UserDefaults, suite: String) {
        let suite = "EarshotDiagnosticIsolation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppStore(defaults: defaults, arguments: []), defaults, suite)
    }

    @MainActor private func waitForCompletion(_ scanner: BmapProtocolScanner) async throws {
        for _ in 0..<250 {
            if !scanner.isScanning { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The bounded fixture scan did not finish.")
        scanner.cancel()
    }
}
