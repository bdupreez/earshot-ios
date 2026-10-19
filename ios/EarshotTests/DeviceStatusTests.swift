import XCTest
@testable import Earshot

final class DeviceStatusTests: XCTestCase {
    func testDeviceStatusAcceptsOnlyValidReadOnlyReports() {
        var status = BoseDeviceStatus()
        XCTAssertNil(status.microphoneMuted)
        XCTAssertTrue(status.receive(packet(2, 21, [1])))
        XCTAssertEqual(status.microphoneMuted, true)
        XCTAssertFalse(status.receive(packet(2, 21, [2])))
        XCTAssertFalse(status.receive(BmapPacket(block: 2, function: 21, operation: .get, payload: Data([0]))))
        XCTAssertEqual(status.microphoneMuted, true)
        XCTAssertTrue(status.receive(packet(2, 16, [2])))
        XCTAssertEqual(status.operationMode, .firmwareUpdateOnly)
        XCTAssertFalse(status.receive(packet(2, 16, [3])))
        XCTAssertEqual(status.operationMode, .firmwareUpdateOnly)
        XCTAssertTrue(status.receive(packet(4, 18, [2])))
        XCTAssertEqual(status.availableToConnect, .unknown)
        XCTAssertFalse(status.receive(packet(4, 18, [3])))
        XCTAssertFalse(status.receive(packet(2, 21, [])))
    }

    func testButtonEventsNeedOnlyDocumentedThreeBytesAndRetainReceiptTime() throws {
        var status = BoseDeviceStatus()
        let stamp = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(status.receive(packet(2, 12, [128, 9])))
        XCTAssertTrue(status.receive(packet(2, 12, [128, 9, 19]), receivedAt: stamp))
        let press = try XCTUnwrap(status.lastButtonEvent)
        XCTAssertEqual(press.receivedAt, stamp)
        XCTAssertEqual(press.summary, "Shortcut button · Long press · Spatial audio")
        XCTAssertTrue(status.receive(packet(2, 12, [250, 249, 248]), receivedAt: stamp))
        XCTAssertTrue(status.lastButtonEvent?.summary.contains("Unknown action 248") == true)
    }

    @MainActor
    func testLEPreferenceUsesStartOnlyInformationCheckAndRemainsDistinctFromPhoneTransport() throws {
        var status = BoseDeviceStatus()
        XCTAssertTrue(status.receive(packet(0, 23, [1])))
        XCTAssertEqual(status.leAudioSupported, true)
        XCTAssertFalse(status.receive(packet(4, 19, [])))
        XCTAssertTrue(status.receive(packet(4, 19, [5])))
        let preference = try XCTUnwrap(status.lePreference)
        XCTAssertTrue(preference.supported)
        XCTAssertFalse(preference.preferred)
        XCTAssertTrue(preference.prohibited)
        XCTAssertEqual(try BoseCommands.checkLEAudioPreference.encode().hexString, "04130500")
        XCTAssertNoThrow(try BmapWriteGuard.check(BoseCommands.checkLEAudioPreference))
        XCTAssertFalse(BmapProtocolScanner.addresses.contains(BmapAddress(4, 19)), "The GET-only scanner must not call START-only functions")
    }

    func testExtendedPairedProfilesAreReadFromReportedMACAndRedactedInDiagnostics() throws {
        let address = Data([0x10, 0, 0, 0, 0, 2])
        let report = address + Data([0b0_1011, 0b0_0011, 0, 0, 3, 1])
        var status = BoseDeviceStatus()
        XCTAssertTrue(status.receive(BmapPacket(block: 4, function: 6, operation: .status, payload: report)))
        let info = try XCTUnwrap(status.extendedProfiles[address.hexString])
        XCTAssertEqual(info.pairedClassic, [0, 1, 3])
        XCTAssertEqual(info.connectedClassic, [0, 1])
        XCTAssertEqual(info.pairedLE, [0, 1])
        XCTAssertEqual(info.connectedLE, [0])
        XCTAssertTrue(info.summary.contains("A2DP, HFP, SPP, LE unicast, LE broadcast"))
        XCTAssertEqual(try BoseCommands.queryDeviceExtendedInfo(address).payload, address)
        XCTAssertThrowsError(try BoseCommands.queryDeviceExtendedInfo(Data([1, 2])))
        XCTAssertFalse(BmapDiagnostics.summary(BmapPacket(block: 4, function: 6, operation: .status, payload: report)).contains(address.hexString))
        XCTAssertFalse(status.receive(packet(4, 6, [0, 0, 0, 0, 0, 0, 1, 1])))
    }

    private func packet(_ block: UInt8, _ function: UInt8, _ bytes: [UInt8]) -> BmapPacket {
        BmapPacket(block: block, function: function, operation: .status, payload: Data(bytes))
    }
}
