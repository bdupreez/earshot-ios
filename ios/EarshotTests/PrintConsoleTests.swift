import XCTest
@testable import Earshot

final class PrintConsoleTests: XCTestCase {
    func testPrintVerbsUseExactUpstreamPacketShapes() throws {
        XCTAssertEqual(try BosePrintCodec.parse("bind uart").encode().hexString, "1603020475617274")
        XCTAssertEqual(try BosePrintCodec.parse("unbind uart").encode().hexString, "1604020475617274")
        XCTAssertEqual(try BosePrintCodec.parse("  VERBOSITY 3 ").encode().hexString, "1605020133")
        XCTAssertEqual(try BosePrintCodec.parse("output 2").encode().hexString, "1602050102")
        XCTAssertEqual(try BosePrintCodec.parse("output").encode().hexString, "16020500")
        XCTAssertEqual(try BosePrintCodec.parse("output -1").payload, Data([0]))
        XCTAssertEqual(try BosePrintCodec.parse("output 300").payload, Data([255]))
        XCTAssertTrue(try BosePrintCodec.parse("output not-a-number").payload.isEmpty, "Preserve upstream's empty output form")
        for line in ["bind uart", "unbind uart", "verbosity 3", "output"] {
            XCTAssertNoThrow(try BmapWriteGuard.check(BosePrintCodec.parse(line)))
        }
    }

    func testOnlyOneWhitelistedCommandAndBoundedUTF8ArgumentsCanBeSent() throws {
        for line in ["reboot", "factory-reset", "3.1 set 01", "", "bind uart\nreset", "bind u\0art", "bind uart\treset"] {
            XCTAssertThrowsError(try BosePrintCodec.parse(line))
        }
        XCTAssertEqual(try BosePrintCodec.parse("bind " + String(repeating: "é", count: 127) + "a").payload.count, 255)
        XCTAssertThrowsError(try BosePrintCodec.parse("bind " + String(repeating: "é", count: 128)))
        XCTAssertThrowsError(try BmapWriteGuard.check(BmapPacket(block: 3, function: 1, operation: .start)))
        XCTAssertThrowsError(try BmapWriteGuard.check(BmapPacket(block: 18, function: 20, operation: .start)))
    }

    func testPrintReplyRendererUsesTextOnlyForPrintableValidUTF8() {
        XCTAssertEqual(BosePrintCodec.render(Data("hello\n\tthere\r\0\0".utf8)), "hello\n\tthere\r")
        XCTAssertEqual(BosePrintCodec.render(Data([1, 2])), "0102")
        XCTAssertEqual(BosePrintCodec.render(Data([0xff, 0xfe])), "fffe")
        XCTAssertEqual(BosePrintCodec.render(Data([0, 65])), "0041")
        XCTAssertEqual(BosePrintCodec.render(Data("�".utf8)), "efbfbd")
        XCTAssertEqual(BosePrintCodec.render(Data()), "")
        let privateReply = BmapPacket(block: 22, function: 2, operation: .status, payload: Data("secret serial".utf8))
        XCTAssertFalse(BmapDiagnostics.summary(privateReply).contains("secret serial"))
    }

    @MainActor
    func testConsoleRequiresConsentVerifiedLinkAndKnownVerbBeforeSend() {
        let console = BosePrintConsole()
        var sends = 0
        XCTAssertFalse(console.submit("bind uart", experimentalEnabled: false, isConnected: true) { _ in sends += 1 })
        XCTAssertFalse(console.submit("output", experimentalEnabled: true, isConnected: false) { _ in sends += 1 })
        XCTAssertFalse(console.submit("reboot", experimentalEnabled: true, isConnected: true) { _ in sends += 1 })
        XCTAssertEqual(sends, 0)
        XCTAssertFalse(console.isRunning)
        XCTAssertTrue(console.status.contains("Unknown Print command"))
    }

    @MainActor
    func testConsoleCollectsOnlyRealInjectedPrintResponsesAndFinishesAfterQuietGap() async throws {
        let console = testConsole()
        var sent: [BmapPacket] = []
        XCTAssertTrue(console.submit("bind uart", experimentalEnabled: true, isConnected: true) { sent.append($0) })
        XCTAssertEqual(sent.map(\.address), [BmapAddress(22, 3)])
        console.receive(BmapPacket(block: 0, function: 3, operation: .status, payload: Data([0x40, 0x82])))
        console.receive(BmapPacket(block: 22, function: 3, operation: .setGet, payload: Data("echo".utf8)))
        XCTAssertEqual(console.entries.count, 1, "Host echoes/unrelated packets are not responses")
        console.receive(reply(3, "bound"))
        console.receive(reply(2, "log line"))
        try await waitUntilFinished(console)
        XCTAssertTrue(console.transcript.contains("bound"))
        XCTAssertTrue(console.transcript.contains("log line"))
        XCTAssertFalse(console.transcript.contains("echo"))
        XCTAssertTrue(console.status.contains("responses collected"))
        let count = console.entries.count
        console.receive(reply(2, "late output"))
        XCTAssertEqual(console.entries.count, count)
    }

    @MainActor
    func testConsoleTimeoutCancellationClearAndNewGenerationDoNotInventReplies() async throws {
        let console = testConsole()
        XCTAssertTrue(console.submit("output", experimentalEnabled: true, isConnected: true) { _ in })
        try await waitUntilFinished(console)
        XCTAssertTrue(console.status.contains("timeout"))
        XCTAssertFalse(console.entries.contains { $0.kind == .response })
        XCTAssertTrue(console.submit("output", experimentalEnabled: true, isConnected: true) { _ in })
        console.cancel()
        XCTAssertTrue(console.submit("output", experimentalEnabled: true, isConnected: true) { _ in })
        console.receive(reply(2, "new request response"))
        try await waitUntilFinished(console)
        XCTAssertTrue(console.transcript.contains("new request response"))
        XCTAssertTrue(console.status.contains("responses collected"))
        XCTAssertTrue(console.submit("output", experimentalEnabled: true, isConnected: true) { _ in })
        console.clear()
        console.receive(reply(2, "ignored after clear"))
        XCTAssertFalse(console.isRunning)
        XCTAssertTrue(console.entries.isEmpty)
        XCTAssertTrue(console.status.contains("cleared"))
    }

    @MainActor
    func testConsoleStopsAtFrameLimitAndBoundsTranscriptAcrossManyCommands() {
        let console = BosePrintConsole(responseLimit: 1)
        for _ in 0..<150 {
            XCTAssertTrue(console.submit("output", experimentalEnabled: true, isConnected: true) { _ in })
            console.receive(reply(2, String(repeating: "x", count: 250)))
            XCTAssertFalse(console.isRunning)
        }
        XCTAssertLessThanOrEqual(console.entries.count, 100)
        XCTAssertLessThanOrEqual(console.entries.reduce(0) { $0 + $1.text.count }, 24_000)
        let count = console.entries.count
        for _ in 0..<100 { console.receive(reply(2, "unsolicited")) }
        XCTAssertEqual(console.entries.count, count)
        XCTAssertFalse(console.transcript.contains("unsolicited"))
        XCTAssertTrue(console.status.contains("Response limit"))
    }

    @MainActor
    func testConsoleCollectionHasDeadlineEvenBeforeAQuietGap() async throws {
        let console = BosePrintConsole(responseTimeout: .milliseconds(10), quietPeriod: .seconds(1), maximumCollection: .milliseconds(20), pollInterval: .milliseconds(2))
        XCTAssertTrue(console.submit("output", experimentalEnabled: true, isConnected: true) { _ in })
        console.receive(reply(2, "stream started"))
        try await waitUntilFinished(console)
        XCTAssertTrue(console.status.contains("time limit"))
    }

    @MainActor
    func testConsoleRendersDeviceErrorsAndTransportSuspensionCancelsCollection() async throws {
        let console = testConsole()
        XCTAssertTrue(console.submit("verbosity 3", experimentalEnabled: true, isConnected: true) { _ in })
        console.receive(BmapPacket(block: 22, function: 5, operation: .error, payload: Data([24])))
        try await waitUntilFinished(console)
        XCTAssertTrue(console.transcript.contains("Undocumented device error 24"))
        XCTAssertTrue(console.status.contains("returned an error"))
        let suite = "earshot.print-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bluetooth = HeadphoneBluetooth(defaults: defaults)
        XCTAssertTrue(bluetooth.printConsole.submit("output", experimentalEnabled: true, isConnected: true) { _ in })
        bluetooth.suspend()
        XCTAssertFalse(bluetooth.printConsole.isRunning)
        XCTAssertFalse(bluetooth.isConnected, "Injected model collection does not fake a transport connection")
        XCTAssertFalse(bluetooth.printConsole.submit("output", experimentalEnabled: true, isConnected: true) { try bluetooth.send($0) })
    }

    @MainActor
    private func testConsole() -> BosePrintConsole {
        BosePrintConsole(responseTimeout: .milliseconds(80), quietPeriod: .milliseconds(10), maximumCollection: .milliseconds(160), pollInterval: .milliseconds(2))
    }

    @MainActor
    private func waitUntilFinished(_ console: BosePrintConsole) async throws {
        for _ in 0..<100 {
            if !console.isRunning { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Console did not finish within the bounded test interval")
        console.cancel()
    }

    private func reply(_ function: UInt8, _ text: String) -> BmapPacket {
        BmapPacket(block: 22, function: function, operation: .status, payload: Data(text.utf8))
    }
}
