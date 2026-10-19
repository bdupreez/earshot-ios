import Foundation

// Wire layouts from upstream Earshot's DeviceManagement.kt, Settings.kt and
// docs/bmap-from-bose-app-13.3.4.md §3.8, by HellzYeahh and contributors (MIT).
enum BoseSourceAction: UInt8, CaseIterable, Hashable, Identifiable {
    case connect = 1, disconnect = 2, remove = 3, route = 12
    var id: UInt8 { rawValue }
    var title: String {
        switch self {
        case .connect: return "Connect source"
        case .disconnect: return "Disconnect source"
        case .remove: return "Forget paired source"
        case .route: return "Request active source"
        }
    }
}

extension BoseCommands {
    static func source(action: BoseSourceAction, address: Data) throws -> BmapPacket {
        guard address.count == 6, address.contains(where: { $0 != 0 }) else {
            throw BmapFailure.invalidPacket("A source must have a complete nonzero Bluetooth address reported by the headphones.")
        }
        let prefix: Data
        switch action {
        case .connect: prefix = Data([0x00])
        case .route: prefix = Data([0x82])
        case .disconnect, .remove: prefix = Data()
        }
        return BmapPacket(block: 4, function: action.rawValue, operation: .start, payload: prefix + address)
    }

    static func pairingMode(enabled: Bool) -> BmapPacket {
        BmapPacket(block: 4, function: 8, operation: .start, payload: Data([enabled ? 1 : 0]))
    }

    static func queryDeviceInfo(_ address: Data) throws -> BmapPacket {
        guard address.count == 6 else { throw BmapFailure.invalidPacket("A device-info query needs a six-byte address.") }
        return BmapPacket(block: 4, function: 5, operation: .get, payload: address)
    }

    static func queryDeviceExtendedInfo(_ address: Data) throws -> BmapPacket {
        guard address.count == 6 else { throw BmapFailure.invalidPacket("A device-info query needs a six-byte address.") }
        return BmapPacket(block: 4, function: 6, operation: .get, payload: address)
    }
}

struct BoseVoicePromptsState: Equatable {
    let enabled: Bool
    let language: UInt8
    let installedLanguages: Set<Int>?

    static func parse(_ data: Data) -> BoseVoicePromptsState? {
        let bytes = Array(data)
        guard let flags = bytes.first else { return nil }
        return BoseVoicePromptsState(enabled: flags & 0x20 != 0, language: flags & 0x1f,
            installedLanguages: bytes.count >= 5 ? BoseParsers.bitset(Data(bytes[1..<5])) : nil)
    }

    static let languages: [UInt8: String] = [0: "UK English", 1: "US English", 2: "French", 3: "Italian", 4: "German",
        5: "European Spanish", 6: "Mexican Spanish", 7: "Brazilian Portuguese", 8: "Mandarin", 9: "Korean",
        10: "Russian", 11: "Polish", 12: "Hebrew", 13: "Turkish", 14: "Dutch", 15: "Japanese", 16: "Cantonese",
        17: "Arabic", 18: "Swedish", 19: "Danish", 20: "Norwegian", 21: "Finnish", 22: "Hindi"]
}

struct BoseDeviceInfo: Equatable {
    let address: Data
    let flags: UInt8
    let name: String?
    var connected: Bool { flags & 1 != 0 }
    var isLocal: Bool { flags & 2 != 0 }

    static func parse(_ data: Data) -> BoseDeviceInfo? {
        let bytes = Array(data)
        guard bytes.count >= 7 else { return nil }
        let offset = bytes[6] & 4 != 0 ? 10 : 9
        let name = bytes.count > offset ? String(decoding: bytes.dropFirst(offset).prefix { $0 != 0 }, as: UTF8.self).trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)) : nil
        return BoseDeviceInfo(address: Data(bytes.prefix(6)), flags: bytes[6], name: name?.isEmpty == false ? name : nil)
    }
}

struct BoseDeviceExtendedInfo: Equatable {
    let address: Data
    let pairedClassic: Set<Int>
    let connectedClassic: Set<Int>
    let pairedLE: Set<Int>
    let connectedLE: Set<Int>

    static func parse(_ data: Data) -> BoseDeviceExtendedInfo? {
        let bytes = Array(data)
        guard bytes.count >= 8 else { return nil }
        return BoseDeviceExtendedInfo(address: Data(bytes.prefix(6)), pairedClassic: BoseParsers.bitset(Data([bytes[6]])),
            connectedClassic: BoseParsers.bitset(Data([bytes[7]])),
            pairedLE: bytes.count > 10 ? BoseParsers.bitset(Data([bytes[10] & 3])) : [],
            connectedLE: bytes.count > 11 ? BoseParsers.bitset(Data([bytes[11] & 3])) : [])
    }
}

extension BoseBattery {
    /// Minutes are a device estimate, not computed from the percentage; 0xffff remains unknown.
    var remainingMinutes: Int? {
        readings.first(where: { $0.component == 4 })?.remainingMinutes
            ?? readings.filter { $0.component == 1 || $0.component == 2 }.compactMap(\.remainingMinutes).min()
            ?? readings.first(where: { $0.component == 0 })?.remainingMinutes
    }
}

extension BoseParsers {
    static func routedSource(_ packet: BmapPacket) -> Data? {
        let offset: Int
        switch packet.operation {
        case .result: offset = 1
        case .status: offset = 2
        default: return nil
        }
        guard packet.address == BmapAddress(4, 12), packet.payload.count >= offset + 6 else { return nil }
        return Data(packet.payload.dropFirst(offset).prefix(6))
    }

    /// ERROR 5 establishes a function exists but rejects GET; it is not an authentication gate.
    /// Routing ERROR 4 may mean the target is not streaming, so it never establishes support.
    static func sourceCapability(_ packet: BmapPacket) -> (action: BoseSourceAction, supported: Bool)? {
        guard packet.block == 4, let action = BoseSourceAction(rawValue: packet.function) else { return nil }
        if packet.operation == .error {
            guard let error = packet.errorCode else { return nil }
            if error == 3 || error == 4 && action != .route { return (action, false) }
            if error == 5 { return (action, true) }
            return nil
        }
        if packet.operation == .status || packet.operation == .result {
            if action == .connect { return packet.payload.count >= 3 || packet.operation == .result ? (action, true) : nil }
            return (action, true)
        }
        return nil
    }
}
