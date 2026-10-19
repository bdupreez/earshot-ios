import Foundation

// Read-only layouts from upstream Earshot Battery.kt and DeviceManagement.kt,
// by HellzYeahh and contributors (MIT). These are device reports, not iOS audio state.
enum BoseOperationMode: UInt8, Equatable, Sendable {
    case unknown = 0, normal = 1, firmwareUpdateOnly = 2
    var title: String {
        switch self { case .unknown: return "Unknown"; case .normal: return "Normal"; case .firmwareUpdateOnly: return "Firmware update only" }
    }
}

enum BoseConnectionAvailability: UInt8, Equatable, Sendable {
    case unavailable = 0, available = 1, unknown = 2
    var title: String {
        switch self { case .unavailable: return "Unavailable"; case .available: return "Available"; case .unknown: return "Unknown" }
    }
}

struct BoseLEPreference: Equatable, Sendable {
    let flags: UInt8
    var supported: Bool { flags & 1 != 0 }
    var preferred: Bool { flags & 2 != 0 }
    var prohibited: Bool { flags & 4 != 0 }
    static func parse(_ data: Data) -> BoseLEPreference? { data.first.map { BoseLEPreference(flags: $0) } }
    var summary: String {
        "Supported: \(supported ? "yes" : "no") · preferred: \(preferred ? "yes" : "no") · prohibited: \(prohibited ? "yes" : "no")"
    }
}

struct BoseButtonEvent: Equatable, Sendable {
    let button: UInt8
    let event: UInt8
    let action: UInt8
    let receivedAt: Date
    static func parse(_ data: Data, receivedAt: Date = .now) -> BoseButtonEvent? {
        let bytes = Array(data)
        guard bytes.count >= 3 else { return nil }
        return BoseButtonEvent(button: bytes[0], event: bytes[1], action: bytes[2], receivedAt: receivedAt)
    }
    var summary: String {
        let buttons: [UInt8: String] = [0: "CNC button", 1: "Reserved", 2: "Voice assistant", 3: "Right shortcut", 4: "Left shortcut", 16: "Action button", 128: "Shortcut button"]
        let events: [UInt8: String] = [0: "Reserved", 1: "Rising edge", 2: "Falling edge", 3: "Short press", 4: "Single press", 5: "Press and hold", 6: "Double press", 7: "Double press and hold", 8: "Triple press", 9: "Long press", 10: "Very long press", 11: "Very very long press", 12: "Very very very long press"]
        return "\(buttons[button] ?? "Button \(button)") · \(events[event] ?? "Event \(event)") · \(BoseButtonShortcut.name(Int(action)))"
    }
}

/// One store value for optional status. Reset it on device changes; no defaults imply hardware.
struct BoseDeviceStatus: Equatable {
    var microphoneMuted: Bool?
    var operationMode: BoseOperationMode?
    var lastButtonEvent: BoseButtonEvent?
    var leAudioSupported: Bool?
    var lePreference: BoseLEPreference?
    var availableToConnect: BoseConnectionAvailability?
    var extendedProfiles: [String: BoseDeviceExtendedInfo] = [:]

    @discardableResult
    mutating func receive(_ packet: BmapPacket, receivedAt: Date = .now) -> Bool {
        guard [.status, .result].contains(packet.operation) else { return false }
        switch packet.address {
        case BmapAddress(2, 21):
            guard let byte = packet.payload.first, byte <= 1 else { return false }
            microphoneMuted = byte != 0
        case BmapAddress(2, 16):
            guard let byte = packet.payload.first, let mode = BoseOperationMode(rawValue: byte) else { return false }
            operationMode = mode
        case BmapAddress(2, 12):
            guard let event = BoseButtonEvent.parse(packet.payload, receivedAt: receivedAt) else { return false }
            lastButtonEvent = event
        case BmapAddress(0, 23):
            guard let byte = packet.payload.first, byte <= 1 else { return false }
            leAudioSupported = byte != 0
        case BmapAddress(4, 19):
            guard let preference = BoseLEPreference.parse(packet.payload) else { return false }
            lePreference = preference
        case BmapAddress(4, 18):
            guard let byte = packet.payload.first, let availability = BoseConnectionAvailability(rawValue: byte) else { return false }
            availableToConnect = availability
        case BmapAddress(4, 6):
            guard let info = BoseDeviceExtendedInfo.parse(packet.payload), info.address.contains(where: { $0 != 0 }) else { return false }
            extendedProfiles[info.address.hexString] = info
        default: return false
        }
        return true
    }
}

extension BoseCommands {
    /// START-only informational check. Never send GET here: fw 10.12 returns error5 for GET.
    static let checkLEAudioPreference = BmapPacket(block: 4, function: 19, operation: .start)
    static let readRoutingSupport = get(BmapAddress(4, 12))
}

extension BoseDeviceExtendedInfo {
    var summary: String {
        let classic = [0: "A2DP", 1: "HFP", 2: "AVRCP", 3: "SPP", 4: "iAP"]
        let le = [0: "LE unicast", 1: "LE broadcast"]
        func names(_ bits: Set<Int>, in table: [Int: String]) -> [String] { bits.sorted().map { table[$0] ?? "Profile \($0)" } }
        let paired = names(pairedClassic, in: classic) + names(pairedLE, in: le)
        let connected = names(connectedClassic, in: classic) + names(connectedLE, in: le)
        return "Paired: \(paired.isEmpty ? "none reported" : paired.joined(separator: ", "))\nConnected: \(connected.isEmpty ? "none reported" : connected.joined(separator: ", "))"
    }
}
