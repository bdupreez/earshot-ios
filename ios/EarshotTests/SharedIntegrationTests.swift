// AI-assisted iOS port attempt of HellzYeahh/earshot (MIT). Original contributors retain credit.
import XCTest
@testable import Earshot

final class SharedIntegrationTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var queue: EarshotCommandQueue { .init(directory: directory) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("EarshotQueueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testAllCommandPayloadsRoundTripAndValidate() throws {
        let values: [EarshotCommandPayload] = [.listeningMode(index: 4), .listeningRole(.quiet), .listeningRole(.aware), .noiseLevel(7.5), .hardwareEQ(bass: -10, mid: 2, treble: 10), .localPreset(id: "flat"), .runRule(id: "commute")]
        for value in values {
            try value.validate()
            XCTAssertEqual(try JSONDecoder().decode(EarshotCommandPayload.self, from: JSONEncoder().encode(value)), value)
        }
    }

    func testLatestSettingReplacesOldRequestAndDoubleTapDeduplicates() throws {
        let original = try XCTUnwrap(queue.enqueue(.listeningRole(.quiet), now: now))
        let duplicate = try XCTUnwrap(queue.enqueue(.listeningRole(.quiet), now: now.addingTimeInterval(0.5)))
        XCTAssertEqual(original.id, duplicate.id)
        try queue.enqueue(.noiseLevel(3), now: now)
        try queue.enqueue(.listeningMode(index: 4), now: now.addingTimeInterval(1))
        try queue.enqueue(.listeningRole(.aware), now: now.addingTimeInterval(2))
        try queue.enqueue(.noiseLevel(8), now: now.addingTimeInterval(3))
        let pending = try queue.consumePending(now: now.addingTimeInterval(4))
        XCTAssertEqual(pending.commands.map(\.payload), [.listeningRole(.aware), .noiseLevel(8)])
        XCTAssertEqual(pending.expiredCount, 0)
        XCTAssertTrue(try queue.consumePending(now: now.addingTimeInterval(5)).commands.isEmpty)
    }

    func testConsumedRequestIDCannotReplayButNewInvocationCanRun() throws {
        let id = UUID()
        try queue.enqueue(.runRule(id: "commute"), id: id, now: now)
        XCTAssertEqual(try queue.consumePending(now: now).commands.count, 1)
        XCTAssertNil(try queue.enqueue(.runRule(id: "commute"), id: id, now: now.addingTimeInterval(1)))
        XCTAssertTrue(try queue.consumePending(now: now.addingTimeInterval(1)).commands.isEmpty)
        try queue.enqueue(.runRule(id: "commute"), now: now.addingTimeInterval(2))
        XCTAssertEqual(try queue.consumePending(now: now.addingTimeInterval(2)).commands.count, 1)
    }

    func testExpiredRequestNeverExecutesAndDiscardCountIsConsumedOnce() throws {
        try queue.enqueue(.hardwareEQ(bass: 2, mid: 0, treble: -2), now: now)
        let result = try queue.consumePending(now: now.addingTimeInterval(121))
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(result.expiredCount, 1)
        XCTAssertEqual(try queue.consumePending(now: now.addingTimeInterval(122)).expiredCount, 0)
    }

    func testInvalidParametersCannotEnterQueue() throws {
        let invalid: [EarshotCommandPayload] = [.listeningMode(index: -1), .listeningMode(index: 255), .noiseLevel(.nan), .noiseLevel(.infinity), .noiseLevel(-0.1), .noiseLevel(11), .hardwareEQ(bass: 11, mid: 0, treble: 0), .hardwareEQ(bass: 0, mid: .nan, treble: 0), .localPreset(id: " "), .runRule(id: String(repeating: "x", count: 257))]
        for value in invalid { XCTAssertThrowsError(try queue.enqueue(value, now: now)) }
        XCTAssertTrue(try queue.consumePending(now: now).commands.isEmpty)
    }

    func testQueueCapacityRejectsNewRequestWithoutLosingExistingRules() throws {
        for index in 0..<EarshotCommandQueue.maximumCount { try queue.enqueue(.runRule(id: "rule-\(index)"), now: now) }
        XCTAssertThrowsError(try queue.enqueue(.runRule(id: "overflow"), now: now))
        let values = try queue.consumePending(now: now).commands.map(\.payload)
        XCTAssertEqual(values, (0..<32).map { .runRule(id: "rule-\($0)") })
    }

    func testConcurrentWritersDoNotLoseCommands() async throws {
        let queue = queue
        let time = now
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<32 {
                group.addTask { _ = try queue.enqueue(.runRule(id: "concurrent-\(index)"), now: time) }
            }
            try await group.waitForAll()
        }
        let result = try queue.consumePending(now: time)
        XCTAssertEqual(result.commands.count, 32)
        XCTAssertEqual(Set(result.commands.map(\.id)).count, 32)
        XCTAssertTrue(try queue.consumePending(now: time).commands.isEmpty)
    }

    func testUnreadableQueueIsQuarantinedAndDoesNotPoisonNewRequests() throws {
        let damaged = Data("invalid json request".utf8)
        try damaged.write(to: directory.appendingPathComponent("commands.json"))
        try queue.enqueue(.localPreset(id: "flat"), now: now)
        let result = try queue.consumePending(now: now)
        XCTAssertEqual(result.commands.map(\.payload), [.localPreset(id: "flat")])
        XCTAssertEqual(result.discardedCount, 1)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("commands-unreadable.json")), damaged)
    }

    func testFutureAndDuplicateWireRequestsAreRejected() throws {
        struct Wire: Codable {
            var version = 1
            var pending: [EarshotCommandEnvelope]
            var consumed: [UUID] = []
            var expiredCount = 0
            var discardedCount = 0
        }
        let valid = EarshotCommandEnvelope(id: UUID(), createdAt: now, expiresAt: now.addingTimeInterval(120), payload: .noiseLevel(5))
        let future = EarshotCommandEnvelope(id: UUID(), createdAt: now.addingTimeInterval(90), expiresAt: now.addingTimeInterval(210), payload: .listeningRole(.quiet))
        try JSONEncoder().encode(Wire(pending: [valid, valid, future])).write(to: directory.appendingPathComponent("commands.json"))
        let result = try queue.consumePending(now: now)
        XCTAssertEqual(result.commands, [valid])
        XCTAssertEqual(result.discardedCount, 2)
    }

    func testSnapshotAndShortcutCatalogRoundTripWithoutInventingBatteryValues() throws {
        let name = "dev.earshot.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let snapshot = EarshotWidgetSnapshot(updatedAt: now, connected: true, demo: false, profileName: "Earbuds", modeName: "Custom commute", batteries: [.init(id: "left", name: "Left", percent: 42, remainingMinutes: 125), .init(id: "right", name: "Right", percent: nil), .init(id: "case", name: "Case", percent: 255)])
        let catalog = EarshotIntentCatalog(modes: [.init(id: "4", name: "Custom commute")], presets: [.init(id: "flat", name: "Flat")], rules: [.init(id: "rule", name: "Commute")])
        EarshotShared.save(snapshot: snapshot, catalog: catalog, defaults: defaults)
        XCTAssertEqual(EarshotShared.snapshot(defaults: defaults), snapshot)
        XCTAssertEqual(EarshotShared.catalog(defaults: defaults), catalog)
        XCTAssertEqual(snapshot.batteries[0].remainingDescription, "2h 5m")
        XCTAssertNil(snapshot.batteries[1].validPercent)
        XCTAssertNil(snapshot.batteries[2].validPercent)
        XCTAssertFalse(snapshot.isStale(at: now.addingTimeInterval(299)))
        XCTAssertTrue(snapshot.isStale(at: now.addingTimeInterval(300)))
        XCTAssertTrue(snapshot.isStale(at: now.addingTimeInterval(-61)))
    }
}
