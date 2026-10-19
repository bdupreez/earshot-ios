// AI-assisted iOS port attempt of HellzYeahh/earshot (MIT). Original contributors retain credit.
import AppIntents
import XCTest
@testable import Earshot

final class ListeningControlIntentTests: XCTestCase {
    func testControlDestinationsRoundTripToSemanticRequestsWithoutAssumingSlotNumbers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EarshotControlTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = EarshotCommandQueue(directory: directory)
        for (destination, role) in [(EarshotListeningDestination.quiet, EarshotListeningRole.quiet), (.aware, .aware)] {
            let decoded = try JSONDecoder().decode(EarshotListeningDestination.self, from: JSONEncoder().encode(destination))
            let intent = requireOpenIntent(OpenEarshotListeningIntent(target: decoded))
            try queue.enqueue(intent.target.requestPayload)
            XCTAssertEqual(try queue.consumePending().commands.map(\.payload), [.listeningRole(role)])
        }
    }

    func testLatestControlRequestReplacesOlderModeAndIsConsumedOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EarshotControlTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = EarshotCommandQueue(directory: directory)
        let quiet = OpenEarshotListeningIntent(target: .quiet)
        let aware = OpenEarshotListeningIntent(target: .aware)
        try queue.enqueue(quiet.target.requestPayload)
        try queue.enqueue(aware.target.requestPayload)
        XCTAssertEqual(try queue.consumePending().commands.map(\.payload), [.listeningRole(.aware)])
        XCTAssertTrue(try queue.consumePending().commands.isEmpty)
    }

    // Compile-time conformance is part of the public control-opening contract.
    private func requireOpenIntent<T: OpenIntent>(_ intent: T) -> T { intent }
}
