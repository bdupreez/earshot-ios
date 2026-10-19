// Test the installed app's actual shared-container boundary, not a mock URL.
// This does not validate signed-device provisioning or another extension process.
import XCTest
@testable import Earshot

final class AppGroupIntegrationTests: XCTestCase {
    func testInstalledSimulatorAppCanAccessItsDeclaredGroupAndReopenQueue() throws {
        let queue = try EarshotShared.commandQueue()
        // Use a unique child directory so this verification cannot consume UI/intent
        // commands or mutate the running app's production pending-command file.
        let directory = queue.directory.appendingPathComponent("test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = EarshotCommandQueue(directory: directory)
        let id = UUID()
        try writer.enqueue(.localPreset(id: "flat"), id: id)
        let reader = EarshotCommandQueue(directory: directory)
        let drain = try reader.consumePending()
        XCTAssertEqual(drain.commands.map(\.id), [id])
        XCTAssertEqual(drain.commands.first?.payload, .localPreset(id: "flat"))
        XCTAssertTrue(try writer.consumePending().commands.isEmpty)
    }
}
