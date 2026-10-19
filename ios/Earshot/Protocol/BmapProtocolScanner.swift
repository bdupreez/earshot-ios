import Combine
import Foundation

struct BmapScanResult: Identifiable {
    let address: BmapAddress
    let response: String
    let succeeded: Bool
    var id: BmapAddress { address }
}

/// Read-only foreground diagnostics from documented upstream Earshot GET addresses (MIT).
/// Never scans firmware, authentication, keys, resets, START-only functions or guessed opcodes.
@MainActor
final class BmapProtocolScanner: ObservableObject {
    @Published private(set) var results: [BmapScanResult] = []
    @Published private(set) var isScanning = false
    @Published private(set) var completed = 0
    private var task: Task<Void, Never>?
    private var waiting: BmapAddress?
    private var reply: BmapPacket?
    private var scanID = UUID()

    static let addresses: [BmapAddress] = [
        (0, [0, 1, 2, 3, 5, 15, 23]), (1, [0, 2, 3, 4, 5, 7, 9, 10, 11, 24, 27, 34, 37]),
        (2, [0, 2, 5, 16, 21]), (4, [0, 1, 4, 8, 12, 14, 18]), (5, [0, 1, 3, 4, 5, 7]),
        (7, [0, 1, 4]), (9, [0, 2]), (31, [0, 2, 3, 8, 10])
    ].flatMap { (block: UInt8, functions: [UInt8]) in functions.map { BmapAddress(block, $0) } }

    func start(addresses requested: [BmapAddress]? = nil, send: @escaping @MainActor (BmapPacket) throws -> Void) {
        cancel()
        let generation = scanID
        var seen = Set<BmapAddress>()
        let queries = (requested ?? Self.addresses).filter { Self.addresses.contains($0) && seen.insert($0).inserted }
        results = []; completed = 0; isScanning = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.scanID == generation { self.waiting = nil; self.reply = nil; self.isScanning = false; self.task = nil }
            }
            for address in queries {
                guard !Task.isCancelled else { return }
                self.waiting = address; self.reply = nil
                do {
                    try send(BoseCommands.get(address))
                    for _ in 0..<20 {
                        if self.reply != nil { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    guard !Task.isCancelled else { return }
                    if let packet = self.reply {
                        let message = packet.errorCode.map { BmapFailure.device(address, $0).localizedDescription }
                            ?? BmapDiagnostics.summary(packet)
                        self.results.append(BmapScanResult(address: address, response: message, succeeded: packet.operation != .error))
                    } else {
                        self.results.append(BmapScanResult(address: address, response: "No response within one second", succeeded: false))
                    }
                    self.completed += 1
                    try await Task.sleep(for: .milliseconds(100))
                } catch is CancellationError { return }
                catch {
                    self.results.append(BmapScanResult(address: address, response: error.localizedDescription, succeeded: false))
                    return
                }
            }
        }
    }

    func receive(_ packet: BmapPacket) {
        guard packet.address == waiting, [.status, .error, .result].contains(packet.operation) else { return }
        reply = packet
    }

    func cancel() {
        scanID = UUID()
        task?.cancel(); task = nil; waiting = nil; reply = nil; isScanning = false
    }
}

enum BmapDiagnostics {
    static func summary(_ packet: BmapPacket) -> String {
        let redact = packet.block == 4 || packet.block == 18 || packet.address == BmapAddress(1, 2)
            || packet.address == BmapAddress(31, 6) || packet.block == 0 && [7, 9, 12].contains(packet.function)
        return redact ? "\(packet.operation): \(packet.payload.count) bytes (private data redacted)" : packet.description
    }
}
