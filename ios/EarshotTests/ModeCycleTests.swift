// AI-assisted iOS port of HellzYeahh/earshot TileCycle tests (MIT).
import XCTest
@testable import Earshot

final class ModeCycleTests: XCTestCase {
    func testPreferredCycleKeepsOrderDeduplicatesAndFiltersUnconfiguredSlots() {
        XCTAssertEqual(EarshotModeCycle.order(preferred: [3, 5, 4, 3, -1, 255], modes: modes), [3, 4])
        XCTAssertEqual(EarshotModeCycle.canonical([4, 1, 4, 255, -1]), [1, 4])
    }

    func testAutomaticCycleFallsBackThroughFavoritesPresetsAndOtherConfiguredModes() {
        XCTAssertEqual(EarshotModeCycle.order(preferred: [], modes: modes), [0, 2, 4])
        let plain = modes.map { EarshotCycleMode(id: $0.id, configured: $0.configured, favorite: false) }
        XCTAssertEqual(EarshotModeCycle.order(preferred: [], modes: plain), [0, 1, 2])
        XCTAssertEqual(EarshotModeCycle.order(preferred: [], modes: [.init(id: 8, configured: true, favorite: false), .init(id: 4, configured: true, favorite: false)]), [4, 8])
        XCTAssertEqual(EarshotModeCycle.order(preferred: [], modes: [.init(id: 4, configured: false, favorite: true)]), [])
        // Pure upstream fallback is usable before load; the foreground executor refuses unloaded devices.
        XCTAssertEqual(EarshotModeCycle.order(preferred: [], modes: []), [0, 1, 2])
        XCTAssertEqual(EarshotModeCycle.order(preferred: [4, 1], modes: []), [4, 1])
    }

    func testNextWrapsAndRecoversFromUnsavedOrUnknownCurrentMode() {
        XCTAssertEqual(EarshotModeCycle.next(current: 1, order: [1, 4]), 4)
        XCTAssertEqual(EarshotModeCycle.next(current: 4, order: [1, 4]), 1)
        XCTAssertEqual(EarshotModeCycle.next(current: 255, order: [1, 4]), 1)
        XCTAssertEqual(EarshotModeCycle.next(current: nil, order: [1, 4]), 1)
        XCTAssertNil(EarshotModeCycle.next(current: 0, order: []))
    }

    func testCycleRequestsRetainDistinctTapsAtMostOnceAndExpireNormally() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ModeCycleQueue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = EarshotCommandQueue(directory: directory)
        let now = Date(timeIntervalSince1970: 1_800_000_000), id = UUID()
        try queue.enqueue(.cycleModes, id: id, now: now)
        try queue.enqueue(.cycleModes, id: id, now: now.addingTimeInterval(0.1))
        try queue.enqueue(.cycleModes, now: now.addingTimeInterval(0.2))
        XCTAssertEqual(try queue.consumePending(now: now.addingTimeInterval(1)).commands.map(\.payload), [.cycleModes, .cycleModes])
        XCTAssertNil(try queue.enqueue(.cycleModes, id: id, now: now.addingTimeInterval(2)))
        XCTAssertTrue(try queue.consumePending(now: now.addingTimeInterval(2)).commands.isEmpty)
        try queue.enqueue(.cycleModes, now: now.addingTimeInterval(3))
        let expired = try queue.consumePending(now: now.addingTimeInterval(124))
        XCTAssertTrue(expired.commands.isEmpty)
        XCTAssertEqual(expired.expiredCount, 1)
    }

    func testOldPayloadSnapshotsAndPreferencesDecodeWithoutCycleFields() throws {
        let role = Data(#"{"listeningRole":{"_0":"quiet"}}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(EarshotCommandPayload.self, from: role), .listeningRole(.quiet))
        let cycle = EarshotCommandPayload.cycleModes
        XCTAssertEqual(try JSONDecoder().decode(EarshotCommandPayload.self, from: JSONEncoder().encode(cycle)), cycle)
        XCTAssertEqual(EarshotListeningDestination.cycle.requestPayload, cycle)
        let old = Data(#"{"updatedAt":0,"connected":false,"demo":false,"profileName":"Bose","modeName":"Unknown","batteries":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(EarshotWidgetSnapshot.self, from: old)
        XCTAssertNil(snapshot.cycleNextModeName)
        XCTAssertNil(snapshot.cycleStatus)
        XCTAssertTrue(try JSONDecoder().decode(SavedAppState.self, from: Data("{}".utf8)).modeCycleModes.isEmpty)
    }

    @MainActor
    func testConfiguredCustomCycleExecutesInDemoAndPersistsAcrossRelaunch() async throws {
        let fixture = makeStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        store.setDemo(true); store.appIsActive = true
        var custom = try XCTUnwrap(store.saved.modes.first { $0.id == 4 })
        custom.name = "Office"; store.saveMode(custom)
        XCTAssertTrue(store.updateModeCycleModes([4, 1, 4]))
        XCTAssertEqual(store.saved.modeCycleModes, [1, 4])
        _ = try await store.executeSharedPayload(.cycleModes)
        XCTAssertEqual(store.saved.currentMode, 1)
        _ = try await store.executeSharedPayload(.cycleModes)
        XCTAssertEqual(store.saved.currentMode, 4)
        _ = try await store.executeSharedPayload(.cycleModes)
        XCTAssertEqual(store.saved.currentMode, 1)
        let restored = AppStore(defaults: fixture.defaults, arguments: [])
        restored.appIsActive = true
        XCTAssertEqual(restored.saved.modeCycleModes, [1, 4])
        XCTAssertEqual(restored.saved.modes.first { $0.id == 4 }?.name, "Office")
        _ = try await restored.executeSharedPayload(.cycleModes)
        XCTAssertEqual(restored.saved.currentMode, 4)
    }

    @MainActor
    func testStaleEmptyUnsupportedAndInvalidCyclesAreActionableWithoutChangingMode() async throws {
        let fixture = makeStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        store.appIsActive = true
        do { _ = try await store.executeSharedPayload(.cycleModes); XCTFail("Offline mode cycle must fail") } catch { XCTAssertTrue(error.localizedDescription.contains("Connect")) }
        store.setDemo(true)
        XCTAssertFalse(store.updateModeCycleModes([4]), "Unconfigured slots cannot be selected")
        XCTAssertFalse(store.updateModeCycleModes([255]))
        XCTAssertTrue(store.saved.modeCycleModes.isEmpty)
        store.saved.modeCycleModes = [99]
        let oldMode = store.saved.currentMode
        do { _ = try await store.executeSharedPayload(.cycleModes); XCTFail("Stale explicit selection must be repaired") } catch { XCTAssertTrue(error.localizedDescription.contains("saved cycle")) }
        XCTAssertEqual(store.saved.currentMode, oldMode)
        XCTAssertTrue(store.updateModeCycleModes([]))
        XCTAssertNil(store.modeCycleRequestError)
        store.selectProfile("nc700")
        XCTAssertTrue(store.modeCycleOrder.isEmpty)
        XCTAssertNotNil(store.modeCycleRequestError)
        store.selectProfile("qc35")
        XCTAssertTrue(store.modeCycleRequestError?.contains("unavailable") == true)
    }

    private var modes: [EarshotCycleMode] {
        (0...5).map { .init(id: $0, configured: $0 != 5, favorite: [0, 2, 4].contains($0)) }
    }

    @MainActor private func makeStore() -> (store: AppStore, defaults: UserDefaults, suite: String) {
        let suite = "earshot.mode-cycle-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppStore(defaults: defaults, arguments: []), defaults, suite)
    }
}
