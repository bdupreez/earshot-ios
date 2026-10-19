import XCTest
@testable import Earshot

final class WiFiLatencyTests: XCTestCase {
    func testExperimentalLatencyUsesSigned16BigEndianAndReportedRange() throws {
        XCTAssertEqual(try BoseCommands.setLatency(210, reportedRange: 0...520).encode().hexString, "0507020200d2")
        XCTAssertEqual(try BoseCommands.setLatency(-2, reportedRange: -100...100).payload, Data([0xff, 0xfe]))
        XCTAssertThrowsError(try BoseCommands.setLatency(521, reportedRange: 0...520))
        XCTAssertThrowsError(try BoseCommands.setLatency(32_768, reportedRange: 0...32_768))
        XCTAssertNoThrow(try BmapWriteGuard.check(BoseCommands.setLatency(210, reportedRange: 0...520)))
    }

    func testLatencyRejectsMalformedRangeOrCurrentValue() throws {
        let parsed = try XCTUnwrap(BoseLatency.parse(Data(hex: "0000020800d2")!))
        XCTAssertEqual(parsed.range, 0...520)
        XCTAssertEqual(parsed.current, 210)
        XCTAssertNil(BoseLatency.parse(Data(hex: "0208000000d2")!))
        XCTAssertNil(BoseLatency.parse(Data(hex: "000002080209")!))
        XCTAssertNil(BoseLatency.parse(Data([0, 0, 2])))
    }

    func testForegroundSSIDRulesFireOncePerObservedJoin() {
        var joins = ForegroundWiFiJoinTracker()
        XCTAssertTrue(joins.observe("Home Wi-Fi"))
        XCTAssertFalse(joins.observe("Home Wi-Fi"))
        XCTAssertFalse(joins.observe(""))
        XCTAssertEqual(joins.lastObservedSSID, "Home Wi-Fi")
        // Unavailable information/background pauses do not call disconnected().
        XCTAssertFalse(joins.observe("Home Wi-Fi"))
        XCTAssertTrue(joins.disconnected())
        XCTAssertFalse(joins.disconnected())
        XCTAssertTrue(joins.observe("Home Wi-Fi"))
        XCTAssertTrue(joins.observe("Office"))
    }

    @MainActor
    func testWiFiObserverDoesNotReadOrRequestAccessDuringInitialization() throws {
        let suite = "earshot.wifi-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let observer = WiFiObserver(defaults: defaults)
        XCTAssertFalse(observer.isEnabled)
        XCTAssertNil(observer.ssid)
        observer.setActive(false)
        observer.requestAccess()
        XCTAssertFalse(observer.isEnabled, "A background request must not opt in or prompt")
        XCTAssertFalse(defaults.bool(forKey: "earshot.wifi-observer.enabled"))
        observer.disable()
        XCTAssertNil(observer.ssid)
    }
}
