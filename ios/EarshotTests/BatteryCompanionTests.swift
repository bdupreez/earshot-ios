import XCTest
@testable import Earshot

// Pure parser/selection policy tests; no claim of Simulator radio or physical AirPods telemetry.
final class BatteryCompanionTests: XCTestCase {
    func testStandardBatteryRequiresExactlyOneValidPercentageByte() {
        for percent in 0...100 { XCTAssertEqual(BatteryCompanionPolicy.batteryLevel(Data([UInt8(percent)])), percent) }
        for data in [Data(), Data([101]), Data([255]), Data([50, 0])] { XCTAssertNil(BatteryCompanionPolicy.batteryLevel(data)) }
    }

    func testOnlyStandardBatteryServiceCharacteristicPairCanBeRead() {
        XCTAssertTrue(BatteryCompanionPolicy.allowsRead(service: "180f", characteristic: "2a19"))
        XCTAssertTrue(BatteryCompanionPolicy.allowsRead(service: "0000180F-0000-1000-8000-00805F9B34FB", characteristic: "00002A19-0000-1000-8000-00805F9B34FB"))
        for pair in [("FEBE", "2A19"), ("180F", "2A00"), ("66666666-6666-6666-6666-666666666666", "2A19"), ("", "")] {
            XCTAssertFalse(BatteryCompanionPolicy.allowsRead(service: pair.0, characteristic: pair.1))
        }
    }

    func testSelectionRequiresAnExplicitDiscoveredBatterySource() {
        let selected = UUID(), stranger = UUID()
        let devices = [BatteryCompanionDevice(id: selected, name: "Selected BAS source", rssi: -50, advertisesBatteryService: true),
                       BatteryCompanionDevice(id: stranger, name: "Nearby Apple advert", rssi: -20, advertisesBatteryService: false)]
        XCTAssertTrue(BatteryCompanionPolicy.allowsSelection(selected, discovered: devices))
        XCTAssertFalse(BatteryCompanionPolicy.allowsSelection(stranger, discovered: devices), "RSSI or an Apple name must never authorize a BAS read")
        XCTAssertFalse(BatteryCompanionPolicy.allowsSelection(UUID(), discovered: devices))
    }

    func testDiscoveryCollectionsAreBoundedAndRefreshExistingIdentity() {
        var devices = [BatteryCompanionDevice]()
        for index in 0..<100 {
            devices = BatteryCompanionPolicy.updating(.init(id: UUID(), name: "Source\(index)", rssi: -50, advertisesBatteryService: true), in: devices, limit: BatteryCompanionPolicy.maximumDevices)
        }
        XCTAssertEqual(devices.count, BatteryCompanionPolicy.maximumDevices)
        let refreshed = BatteryCompanionDevice(id: devices[10].id, name: "Updated advert", rssi: -30, advertisesBatteryService: true)
        devices = BatteryCompanionPolicy.updating(refreshed, in: devices, limit: BatteryCompanionPolicy.maximumDevices)
        XCTAssertEqual(devices.first, refreshed)
        XCTAssertEqual(Set(devices.map(\.id)).count, devices.count)
        XCTAssertEqual(devices.count, BatteryCompanionPolicy.maximumDevices)
        XCTAssertTrue(BatteryCompanionPolicy.updating(refreshed, in: devices, limit: 0).isEmpty)
    }

    func testSameSourceRereadWaitsForPreviousCancellationAcknowledgement() {
        let source = UUID()
        var lifecycle = BatteryReadLifecycle()
        XCTAssertEqual(lifecycle.request(source), .connect(source))
        XCTAssertTrue(lifecycle.accepts(source))
        // Successful reads close their connection. The next tap can arrive before didDisconnect.
        XCTAssertEqual(lifecycle.cancel(), .cancel(source))
        XCTAssertEqual(lifecycle.request(source), .none)
        XCTAssertEqual(lifecycle.phase, .disconnecting(source))
        XCTAssertFalse(lifecycle.accepts(source), "Queued old GATT callbacks must not become the reread's result")
        XCTAssertEqual(lifecycle.terminal(source), .connect(source))
        XCTAssertEqual(lifecycle.phase, .active(source))
        XCTAssertNil(lifecycle.pendingID)
        XCTAssertTrue(lifecycle.accepts(source))
    }

    func testRapidSourceChangesConnectOnlyLatestAfterOldConnectionTerminates() {
        let first = UUID(), second = UUID(), latest = UUID()
        var lifecycle = BatteryReadLifecycle()
        XCTAssertEqual(lifecycle.request(first), .connect(first))
        XCTAssertEqual(lifecycle.request(second), .cancel(first))
        XCTAssertEqual(lifecycle.request(latest), .none)
        XCTAssertEqual(lifecycle.pendingID, latest)
        XCTAssertFalse(lifecycle.accepts(first))
        XCTAssertFalse(lifecycle.accepts(latest))
        XCTAssertEqual(lifecycle.terminal(first), .connect(latest))
        XCTAssertTrue(lifecycle.accepts(latest))
        XCTAssertEqual(lifecycle.terminal(first), .none, "An old source callback must not end the new source's read")
        XCTAssertTrue(lifecycle.accepts(latest))
    }

    func testCancelWhileWaitingDiscardsRereadWithoutReleasingOldConnectionEarly() {
        let source = UUID()
        var lifecycle = BatteryReadLifecycle()
        XCTAssertEqual(lifecycle.request(source), .connect(source))
        XCTAssertEqual(lifecycle.cancel(), .cancel(source))
        XCTAssertEqual(lifecycle.request(source), .none)
        // User cancellation, timeout and leaving the foreground all take this path.
        XCTAssertEqual(lifecycle.cancel(), .none)
        XCTAssertNil(lifecycle.pendingID)
        XCTAssertEqual(lifecycle.phase, .disconnecting(source))
        XCTAssertEqual(lifecycle.cancel(), .none, "Cancellation must not enqueue repeated radio operations")
        XCTAssertEqual(lifecycle.terminal(source), .none)
        XCTAssertEqual(lifecycle.phase, .idle)
        XCTAssertFalse(lifecycle.accepts(source))
    }

    func testUnrelatedTerminalCallbackCannotReleaseAnotherSourcesCancellation() {
        let old = UUID(), next = UUID(), unrelated = UUID()
        var lifecycle = BatteryReadLifecycle()
        XCTAssertEqual(lifecycle.request(old), .connect(old))
        XCTAssertEqual(lifecycle.request(next), .cancel(old))
        XCTAssertEqual(lifecycle.terminal(unrelated), .none)
        XCTAssertEqual(lifecycle.terminal(next), .none, "A queued source has not connected yet")
        XCTAssertEqual(lifecycle.phase, .disconnecting(old))
        XCTAssertEqual(lifecycle.pendingID, next)
        XCTAssertEqual(lifecycle.terminal(old), .connect(next))
    }

    func testRadioResetDropsQueuedIntentAndIgnoresLateTerminalCallback() {
        let old = UUID(), next = UUID()
        var lifecycle = BatteryReadLifecycle()
        XCTAssertEqual(lifecycle.request(old), .connect(old))
        XCTAssertEqual(lifecycle.request(next), .cancel(old))
        lifecycle.reset()
        XCTAssertEqual(lifecycle.phase, .idle)
        XCTAssertNil(lifecycle.pendingID)
        XCTAssertEqual(lifecycle.terminal(old), .none)
        XCTAssertFalse(lifecycle.accepts(next))
        XCTAssertEqual(lifecycle.request(next), .connect(next), "A new explicit request may start after availability returns")
        XCTAssertEqual(lifecycle.terminal(old), .none)
        XCTAssertTrue(lifecycle.accepts(next))
    }

    func testFailedOrRemoteDisconnectedReadCanRetryWithoutAnotherCancellation() {
        let source = UUID()
        var lifecycle = BatteryReadLifecycle()
        XCTAssertEqual(lifecycle.request(source), .connect(source))
        XCTAssertEqual(lifecycle.terminal(source), .none)
        XCTAssertEqual(lifecycle.phase, .idle)
        XCTAssertEqual(lifecycle.cancel(), .none, "The terminal callback has already closed this connection")
        XCTAssertEqual(lifecycle.request(source), .connect(source))
        XCTAssertTrue(lifecycle.accepts(source))
    }

    func testAppleManufacturerFixtureKeepsBudDirectionAndCharging() throws {
        let advert = try XCTUnwrap(AppleContinuityAdvert.parse(manufacturerData: data(status: 0x2b, buds: 0x89, chargeAndCase: 0x46)))
        XCTAssertEqual(advert.model, 0x1420)
        XCTAssertEqual(advert.leftPercent, 90)
        XCTAssertEqual(advert.rightPercent, 80)
        XCTAssertEqual(advert.casePercent, 60)
        XCTAssertEqual(advert.headlinePercent, 80)
        XCTAssertFalse(advert.leftCharging)
        XCTAssertFalse(advert.rightCharging)
        XCTAssertTrue(advert.caseCharging)
        XCTAssertEqual(advert.modelName, "AirPods Pro (2nd generation)")
        let flipped = try XCTUnwrap(AppleContinuityAdvert.parse(manufacturerData: data(status: 0, buds: 0x98, chargeAndCase: 0x16)))
        XCTAssertEqual(flipped.leftPercent, 90)
        XCTAssertEqual(flipped.rightPercent, 80)
        XCTAssertFalse(flipped.leftCharging)
        XCTAssertTrue(flipped.rightCharging)
    }

    func testAppleUnknownNibblesModelsAndSingleHeadphoneBatteryStayHonest() throws {
        let unknown = try XCTUnwrap(AppleContinuityAdvert.parse(manufacturerData: data(model: 0xffff, status: 0x20, buds: 0xff, chargeAndCase: 0x0f)))
        XCTAssertNil(unknown.leftPercent)
        XCTAssertNil(unknown.rightPercent)
        XCTAssertNil(unknown.casePercent)
        XCTAssertNil(unknown.headlinePercent)
        XCTAssertTrue(unknown.modelName.contains("unknown"))
        let headphones = try XCTUnwrap(AppleContinuityAdvert.parse(manufacturerData: data(model: 0x0a20, status: 0x20, buds: 0xf8, chargeAndCase: 0x0f)))
        XCTAssertTrue(headphones.isHeadphones)
        XCTAssertEqual(headphones.headlinePercent, 80)
        let invalidScale = try XCTUnwrap(AppleContinuityAdvert.parse(manufacturerData: data(status: 0x20, buds: 0xbe, chargeAndCase: 0x0c)))
        XCTAssertNil(invalidScale.headlinePercent)
        XCTAssertNil(invalidScale.casePercent)
    }

    func testAppleParserRejectsWrongCompanySubtypeAndTruncatedBytes() {
        let valid = data(status: 0x20, buds: 0x88, chargeAndCase: 0x08)
        for length in 0..<10 { XCTAssertNil(AppleContinuityAdvert.parse(manufacturerData: Data(valid.prefix(length)))) }
        var wrongCompany = valid; wrongCompany[0] = 0
        XCTAssertNil(AppleContinuityAdvert.parse(manufacturerData: wrongCompany))
        var wrongSubtype = valid; wrongSubtype[2] = 0x10
        XCTAssertNil(AppleContinuityAdvert.parse(manufacturerData: wrongSubtype))
    }

    private func data(model: UInt16 = 0x1420, status: UInt8, buds: UInt8, chargeAndCase: UInt8) -> Data {
        Data([0x4c, 0x00, 0x07, 0x19, 0x01, UInt8(model >> 8), UInt8(model & 0xff), status, buds, chargeAndCase])
    }
}
