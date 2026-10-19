import Foundation

// Wire facts and safety rules are ported from Earshot's MIT-licensed Kotlin protocol module.
enum BmapOperation: UInt8, CaseIterable, Codable, Sendable {
    case set = 0, get = 1, setGet = 2, status = 3, error = 4, start = 5, result = 6, processing = 7

    var isDeviceResponse: Bool { [.status, .error, .result, .processing].contains(self) }
}

struct BmapAddress: Hashable, Sendable, CustomStringConvertible {
    let block: UInt8
    let function: UInt8
    init(_ block: UInt8, _ function: UInt8) { self.block = block; self.function = function }
    var description: String { "[\(block).\(function)]" }
}

enum BmapFailure: LocalizedError, Equatable {
    case invalidPacket(String)
    case unsafeCommand(String)
    case unavailable(String)
    case device(BmapAddress, UInt8)

    var errorDescription: String? {
        switch self {
        case .invalidPacket(let message), .unsafeCommand(let message), .unavailable(let message): return message
        case .device(let address, let code):
            let reasons: [UInt8: String] = [0: "Unknown error", 1: "Invalid length", 2: "Invalid checksum",
                3: "Function block not supported", 4: "Function not supported",
                5: "This operation is not supported for this function", 6: "Invalid data",
                7: "Data unavailable", 8: "The firmware rejected this value", 9: "Request timed out",
                10: "Not applicable in the current state", 11: "Device not in the paired list", 12: "Headphones are busy",
                19: "Unknown port", 20: "Insecure transport", 24: "Undocumented device error 24", 255: "Block-specific error"]
            return "\(address): \(reasons[code] ?? "Device error \(code)")"
        }
    }
}

struct BmapPacket: Equatable, Sendable, CustomStringConvertible {
    let block: UInt8
    let function: UInt8
    let operation: BmapOperation
    let payload: Data
    let deviceID: UInt8
    let port: UInt8

    init(block: UInt8, function: UInt8, operation: BmapOperation, payload: Data = Data(), deviceID: UInt8 = 0, port: UInt8 = 0) {
        self.block = block; self.function = function; self.operation = operation
        self.payload = payload; self.deviceID = deviceID; self.port = port
    }

    var address: BmapAddress { BmapAddress(block, function) }
    var errorCode: UInt8? { operation == .error ? payload.first : nil }
    var description: String { "\(address) \(operation) \(payload.hexString)" }

    func encode() throws -> Data {
        guard payload.count <= 255, deviceID <= 3, port <= 3 else {
            throw BmapFailure.invalidPacket("BMAP payload must fit 255 bytes; device and port must be 0…3.")
        }
        return Data([block, function, deviceID << 6 | port << 4 | operation.rawValue, UInt8(payload.count)]) + payload
    }

    static func decodeOne(_ data: Data, offset: Int = 0) -> BmapPacket? {
        let bytes = Array(data)
        guard offset >= 0, bytes.count - offset >= 4,
              let operation = BmapOperation(rawValue: bytes[offset + 2] & 0x0f) else { return nil }
        let length = Int(bytes[offset + 3])
        guard bytes.count - offset >= 4 + length else { return nil }
        return BmapPacket(block: bytes[offset], function: bytes[offset + 1], operation: operation,
                          payload: Data(bytes[(offset + 4)..<(offset + 4 + length)]),
                          deviceID: (bytes[offset + 2] >> 6) & 3, port: (bytes[offset + 2] >> 4) & 3)
    }

    var answersLivenessProbe: Bool {
        address == BmapAddress(0, 1) && [.status, .error, .result].contains(operation)
    }
}

struct BmapFrameBuffer {
    private(set) var pending = Data()
    private(set) var desyncCount = 0
    private(set) var droppedBytes = 0

    mutating func feed(_ chunk: Data) -> [BmapPacket] {
        pending.append(chunk)
        var result = [BmapPacket]()
        var consumed = 0
        while let packet = BmapPacket.decodeOne(pending, offset: consumed) {
            result.append(packet)
            consumed += 4 + packet.payload.count
        }
        if consumed > 0 { pending = Data(pending.dropFirst(consumed)) }
        let badHeader = pending.count >= 4 && BmapOperation(rawValue: Array(pending)[2] & 0x0f) == nil
        if badHeader || pending.count > 1_024 {
            droppedBytes += pending.count
            desyncCount += 1
            pending.removeAll()
        }
        return result
    }

    mutating func reset() { pending.removeAll() }
}

enum BmapWriteGuard {
    static func check(_ packet: BmapPacket) throws {
        if packet.operation == .get { return }
        if packet.block == 3 || packet.block == 18 {
            throw BmapFailure.unsafeCommand("Blocked for safety: Earshot never writes to firmware update or authentication blocks (\(packet.address)).")
        }
        if [BmapAddress(7, 5), BmapAddress(7, 6), BmapAddress(7, 11), BmapAddress(4, 7)].contains(packet.address) {
            throw BmapFailure.unsafeCommand("Blocked for safety: \(packet.address) would reset or wipe the headphones.")
        }
        guard [.get, .setGet, .start].contains(packet.operation) else {
            throw BmapFailure.unsafeCommand("Only GET, SET_GET and START requests may be sent to the headphones.")
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
    init?(hex: String) {
        let clean = hex.filter { !$0.isWhitespace }
        guard clean.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        var index = clean.startIndex
        while index < clean.endIndex {
            let end = clean.index(index, offsetBy: 2)
            guard let value = UInt8(clean[index..<end], radix: 16) else { return nil }
            bytes.append(value); index = end
        }
        self.init(bytes)
    }
}
