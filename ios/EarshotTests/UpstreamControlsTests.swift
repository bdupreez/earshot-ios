// Regression fixtures for Earshot upstream 0.5–0.75 by HellzYeahh and contributors (MIT).
import XCTest
import UIKit
@testable import Earshot

final class UpstreamControlsTests: XCTestCase {
    @MainActor func testBundledFieldFontsAreRegisteredInActualAppHost() {
        for name in ["BarlowCondensed-SemiBold", "Barlow-Regular", "JetBrainsMono-Regular"] {
            XCTAssertNotNil(UIFont(name: name, size: 18), name)
        }
    }

    func testPerButtonMasksSurviveShortEchoWithoutBorrowingCapabilities() throws {
        let right = try XCTUnwrap(BoseButtonShortcut.parse(Data([3, 9, 1, 0, 0, 0, 2])))
        let left = BoseButtonShortcut(button: 4, event: 5, action: 16, supported: [14, 16])
        let echo = try XCTUnwrap(BoseButtonShortcut.parse(Data([3, 9, 1])))
        var records = BoseButtonShortcut.merging(left, into: [right])
        records = BoseButtonShortcut.merging(echo, into: records)
        XCTAssertEqual(records.map(\.button), [3, 4])
        XCTAssertEqual(records[0].supported, [1])
        XCTAssertEqual(records[1].supported, [14, 16])
        let unknown = try XCTUnwrap(BoseButtonShortcut.parse(Data([8, 9, 16])))
        records = BoseButtonShortcut.merging(unknown, into: records)
        XCTAssertTrue(records.last!.supported.isEmpty)
        let unfamiliarCurrent = try XCTUnwrap(BoseButtonShortcut.parse(Data([3, 9, 99, 0, 0, 0, 2])))
        XCTAssertEqual(unfamiliarCurrent.action, 99)
        XCTAssertEqual(unfamiliarCurrent.supported, [1], "An unknown current value must never grant a write outside the device mask.")
        XCTAssertNil(BoseButtonShortcut.parse(Data([3, 9, 1, 0])))
        XCTAssertNil(BoseButtonShortcut.parse(Data([3, 9, 1, 0, 0, 0, 0])))
    }

    @MainActor func testStoreKeepsBothBudsAndVendorDemoHasNoBoseTelemetry() throws {
        let suite = "earshot.upstream.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults, arguments: [])
        store.receive(.init(block: 1, function: 9, operation: .status, payload: Data([4, 5, 1, 0, 0, 0, 2])))
        store.receive(.init(block: 1, function: 9, operation: .status, payload: Data([3, 9, 1, 0, 0, 0, 2])))
        store.receive(.init(block: 1, function: 9, operation: .result, payload: Data([4, 5, 1])))
        XCTAssertEqual(store.shortcutButtons.map(\.button), [3, 4])
        XCTAssertEqual(store.buttonShortcut?.button, 3)
        store.setDemo(true); store.selectProfile("soundcore.D1301")
        XCTAssertTrue(store.connected) // Explicit virtual session, never a physical connection.
        XCTAssertFalse(store.bluetooth.isConnected)
        XCTAssertNil(store.battery)
        XCTAssertNil(store.buttonShortcut)
        XCTAssertTrue(store.shortcutButtons.isEmpty)
        XCTAssertTrue(store.saved.modes.isEmpty)
        XCTAssertFalse(store.supports(1, 7))
        XCTAssertFalse(store.firmware.contains("10.12"))
    }

    func testBoseNameGuessDoesNotRouteOtherBrandsOrQCE2024ToBmap() {
        for name in ["QCY Ultra", "Soundcore Ultra", "Sony Ultra", "Bose QuietComfort Earbuds 2024", "Bose QC Earbuds (2024)"] {
            XCTAssertNil(BoseModelFacts.fromName(name), name)
        }
    }

    func testNewForegroundRequestsPreserveRepeatedToggleActions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EarshotActions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = EarshotCommandQueue(directory: directory)
        let now = Date()
        let payloads: [EarshotCommandPayload] = [.cycleLocalEQ, .voiceMemo, .cycleLocalEQ, .voiceMemo]
        for payload in payloads {
            try queue.enqueue(payload, now: now)
            try payload.validate()
            XCTAssertEqual(try JSONDecoder().decode(EarshotCommandPayload.self, from: JSONEncoder().encode(payload)), payload)
        }
        XCTAssertEqual(try queue.consumePending(now: now).commands.map(\.payload), payloads)
        XCTAssertTrue(try queue.consumePending(now: now).commands.isEmpty)
    }
}
