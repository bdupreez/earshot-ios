import Combine
import Foundation

struct BmapScanResult: Identifiable {
    let address: BmapAddress
    let response: String
    let succeeded: Bool
    var id: BmapAddress { address }
}

enum BmapScanScope: String, CaseIterable, Identifiable {
    case documented = "Documented reads", selected = "Selected blocks", deep = "Deep GET discovery"
    var id: String { rawValue }
}

struct BmapScanBlock: Identifiable {
    let id: Int
    let name: String
}

/// AI-assisted port of upstream LabScreen's selected-block and 0...63 discovery plans (MIT).
/// The native scanner retains its stricter exclusions, including the separate Print consent boundary.
struct BmapScanPlan {
    let addresses: [BmapAddress]
    static let excludedBlocks: Set<Int> = [3, 18, 22]
    static let excludedAddresses: Set<BmapAddress> = [BmapAddress(4, 7), BmapAddress(7, 5), BmapAddress(7, 6), BmapAddress(7, 11), BmapAddress(4, 19), BmapAddress(31, 1), BmapAddress(31, 6)]
    static let selectableBlocks: [BmapScanBlock] = [
        (0, "Product information"), (1, "Settings"), (2, "Status"), (4, "Device management"),
        (5, "Audio management"), (6, "Call management"), (7, "Control"), (8, "Debug"),
        (9, "Notifications"), (10, "Reserved Bosebuild 1"), (11, "Reserved Bosebuild 2"),
        (12, "Hearing assistance"), (13, "Data collection"), (14, "Heart rate"), (15, "Peer bud"),
        (16, "Voice assistant"), (17, "Wi-Fi"), (19, "Experimental"), (20, "Cloud"),
        (21, "Augmented reality"), (23, "Unknown"), (24, "Unknown"), (25, "Unknown"),
        (26, "Unknown"), (31, "Audio modes")
    ].map { BmapScanBlock(id: $0.0, name: $0.1) }
    static let documentedAddresses: [BmapAddress] = [
        (0, [0, 1, 2, 3, 5, 15, 23]), (1, [0, 2, 3, 4, 5, 7, 9, 10, 11, 24, 27, 34, 37]),
        (2, [0, 2, 5, 16, 21]), (4, [0, 1, 4, 8, 12, 14, 18]), (5, [0, 1, 3, 4, 5, 7]),
        (7, [0, 1, 4]), (9, [0, 2]), (31, [0, 2, 3, 8, 10])
    ].flatMap { (block: UInt8, functions: [UInt8]) in functions.map { BmapAddress(block, $0) } }

    static var documented: Self { .init(addresses: documentedAddresses) }
    static var deep: Self { selected(blocks: Set(0...63), maximumFunction: 63) }
    static func selected(blocks: Set<Int>, maximumFunction: Int = 40) -> Self {
        guard (0...63).contains(maximumFunction) else { return .init(addresses: []) }
        let addresses = blocks.filter { (0...63).contains($0) }.sorted().flatMap { block in
            (0...maximumFunction).map { BmapAddress(UInt8(block), UInt8($0)) }
        }.filter(allows)
        return .init(addresses: addresses)
    }
    static func allows(_ address: BmapAddress) -> Bool {
        address.block <= 63 && address.function <= 63 && !excludedBlocks.contains(Int(address.block)) && !excludedAddresses.contains(address)
    }
    var maximumEstimatedMinutes: Int { Int(ceil(Double(addresses.count) * 1.1 / 60)) }
}

/// Foreground, GET-only diagnostics. A broader discovery plan never authorizes a write.
@MainActor
final class BmapProtocolScanner: ObservableObject {
    @Published private(set) var results: [BmapScanResult] = []
    @Published private(set) var isScanning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var status = "No scan has started."
    private var task: Task<Void, Never>?
    private var waiting: BmapAddress?
    private var reply: BmapPacket?
    private var scanID = UUID()

    static let addresses = BmapScanPlan.documentedAddresses

    func start(addresses requested: [BmapAddress]? = nil, send: @escaping @MainActor (BmapPacket) throws -> Void) {
        // Preserve the original vetted API. Broader discovery requires an explicit plan.
        let queries = (requested ?? Self.addresses).filter { Self.addresses.contains($0) }
        start(plan: BmapScanPlan(addresses: queries), send: send)
    }

    func start(plan: BmapScanPlan, mayContinue: @escaping @MainActor () -> Bool = { true }, send: @escaping @MainActor (BmapPacket) throws -> Void) {
        cancel()
        let generation = scanID
        var seen = Set<BmapAddress>()
        let queries = Array(plan.addresses.filter { BmapScanPlan.allows($0) && seen.insert($0).inserted }.prefix(4096))
        results = []; completed = 0; total = queries.count
        guard !queries.isEmpty, mayContinue() else { status = "No eligible GET queries can run in the foreground."; return }
        isScanning = true; status = "Waiting for actual device responses."
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.scanID == generation {
                    self.waiting = nil; self.reply = nil; self.isScanning = false; self.task = nil
                    if self.completed == self.total { self.status = "Scan finished. Responses, refusals and timeouts are listed separately." }
                }
            }
            for address in queries {
                guard !Task.isCancelled else { return }
                guard mayContinue() else { self.status = "Scan stopped because Earshot left the foreground or the control link closed."; return }
                self.waiting = address; self.reply = nil
                do {
                    try send(BoseCommands.get(address))
                    for _ in 0..<20 {
                        if self.reply != nil { break }
                        guard mayContinue() else { self.status = "Scan stopped because Earshot left the foreground or the control link closed."; return }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    guard !Task.isCancelled else { return }
                    if let packet = self.reply {
                        let message = packet.errorCode.map { BmapFailure.device(address, $0).localizedDescription }
                            ?? BmapDiagnostics.summary(packet)
                        self.results.append(BmapScanResult(address: address, response: String(message.prefix(2048)), succeeded: packet.operation != .error))
                    } else {
                        self.results.append(BmapScanResult(address: address, response: "No response within one second", succeeded: false))
                    }
                    self.completed += 1
                    try await Task.sleep(for: .milliseconds(100))
                } catch is CancellationError { return }
                catch {
                    self.results.append(BmapScanResult(address: address, response: String(error.localizedDescription.prefix(2048)), succeeded: false))
                    self.status = "Scan stopped: \(error.localizedDescription)"
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
        if isScanning { status = "Scan cancelled. Completed responses remain available." }
        scanID = UUID()
        task?.cancel(); task = nil; waiting = nil; reply = nil; isScanning = false
    }
}

enum BmapDiagnostics {
    static func summary(_ packet: BmapPacket) -> String {
        let redact = packet.block == 4 || packet.block == 18 || packet.block == 22 || packet.address == BmapAddress(1, 2)
            || packet.address == BmapAddress(1, 1) || packet.address == BmapAddress(31, 6)
            || packet.block == 0 && [6, 7, 9, 11, 12, 19, 20, 21].contains(packet.function)
        return redact ? "\(packet.operation): \(packet.payload.count) bytes (private data redacted)" : packet.description
    }
}
