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

    @MainActor private func waitForCompletion(_ scanner: BmapProtocolScanner) async throws {
        for _ in 0..<250 {
            if !scanner.isScanning { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The bounded fixture scan did not finish.")
        scanner.cancel()
    }
}
