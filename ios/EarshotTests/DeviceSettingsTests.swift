import XCTest
@testable import Earshot

final class DeviceSettingsTests: XCTestCase {
    func testSidetoneLevelAndPersistenceHaveIndependentExactWireBytes() throws {
        XCTAssertEqual(try BoseCommands.setSidetone(level: 3, persist: false).encode().hexString, "010b02020003")
        XCTAssertEqual(try BoseCommands.setSidetone(level: 3, persist: true).payload, Data([1, 3]))
        XCTAssertThrowsError(try BoseCommands.setSidetone(level: 4, persist: false))
    }

    @MainActor
    func testDemoSidetoneLevelChangePreservesChosenPersistenceFlag() async throws {
        let suite = "earshot.sidetone-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults, arguments: [])
        await Task.yield()
        store.setDemo(true)
        XCTAssertEqual(store.sidetonePersist, true)
        store.updateSidetonePersistence(false)
        store.updateSidetone(3)
        XCTAssertEqual(store.sidetonePersist, false)
        XCTAssertEqual(store.saved.sidetone, 3)
        store.updateSidetonePersistence(true)
        XCTAssertEqual(store.saved.sidetone, 3)
        XCTAssertEqual(store.sidetonePersist, true)
    }

    @MainActor
    func testRealSidetoneFlagRequiresValidReportAndOfflineWritesCannotInventState() async throws {
        let suite = "earshot.sidetone-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults, arguments: [])
        await Task.yield()
        XCTAssertNil(store.sidetonePersist)
        store.updateSidetonePersistence(false)
        XCTAssertNil(store.sidetonePersist)
        store.receive(BmapPacket(block: 1, function: 11, operation: .status, payload: Data([0, 3, 15])))
        XCTAssertEqual(store.sidetonePersist, false)
        XCTAssertEqual(store.saved.sidetone, 3)
        store.receive(BmapPacket(block: 1, function: 11, operation: .status, payload: Data([1, 4])))
        XCTAssertEqual(store.sidetonePersist, false)
        store.updateSidetonePersistence(true)
        store.updateSidetone(1)
        XCTAssertEqual(store.sidetonePersist, false)
        XCTAssertEqual(store.saved.sidetone, 3)
        XCTAssertFalse(store.bluetooth.isConnected)
    }
}
