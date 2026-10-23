import Foundation

struct BosePairedSource: Identifiable, Equatable {
    let address: Data
    var name: String
    var connected: Bool
    var isLocal = false
    var id: String { address.hexString }
    var displayAddress: String { address.map { String(format: "%02X", $0) }.joined(separator: ":") }

    static func parseList(_ data: Data) -> [BosePairedSource]? {
        let bytes = Array(data)
        guard let flags = bytes.first, (bytes.count - 1).isMultiple(of: 6) else { return nil }
        var sources: [BosePairedSource] = []
        for offset in stride(from: 1, to: bytes.count, by: 6) {
            let address = Data(bytes[offset..<(offset + 6)])
            guard address.contains(where: { $0 != 0 }) else { continue }
            let index = (offset - 1) / 6
            sources.append(BosePairedSource(address: address, name: "Paired device", connected: index < 8 && flags & (1 << index) != 0))
        }
        return sources
    }
}

struct BoseButtonShortcut: Equatable, Identifiable {
    let button: UInt8
    let event: UInt8
    let action: UInt8
    let supported: Set<Int>
    var id: UInt8 { button }
    var title: String {
        [0x80: "Shortcut button", 3: "Right earbud", 4: "Left earbud"][Int(button)] ?? "Button \(button)"
    }
    /// Firmware sends full capability records and three-byte SET_GET echoes.
    /// Reject partial masks; a short echo cannot grant any new write capability.
    static func parse(_ data: Data) -> BoseButtonShortcut? {
        let bytes = Array(data)
        guard bytes.count == 3 || bytes.count >= 7 else { return nil }
        let supported = bytes.count >= 7 ? BoseParsers.bitset(Data(bytes[3..<7])) : []
        guard bytes.count == 3 || !supported.isEmpty else { return nil }
        return BoseButtonShortcut(button: bytes[0], event: bytes[1], action: bytes[2], supported: supported)
    }
    /// Upstream StateMapping keeps each reported button and retains its mask when
    /// firmware echoes only button/event/action. Never borrow another bud's mask.
    static func merging(_ incoming: Self, into records: [Self]) -> [Self] {
        let previous = records.first { $0.button == incoming.button }
        let merged = Self(button: incoming.button, event: incoming.event, action: incoming.action,
                          supported: incoming.supported.isEmpty ? previous?.supported ?? [] : incoming.supported)
        return (records.filter { $0.button != incoming.button } + [merged]).sorted {
            func rank(_ value: UInt8) -> Int { value == 0x80 ? 0 : value == 3 ? 1 : value == 4 ? 2 : 10 + Int(value) }
            return rank($0.button) < rank($1.button)
        }
    }
    static func name(_ action: Int) -> String {
        [0: "Not configured", 1: "Voice assistant", 2: "Cycle noise cancelling", 3: "Battery level", 4: "Play / pause",
         5: "Increase noise cancelling", 6: "Decrease noise cancelling", 7: "Toggle wake word", 8: "Switch device",
         9: "Conversation mode", 10: "Next track", 11: "Previous track", 12: "Fetch notifications", 13: "Wind mode",
         14: "Disabled", 15: "App interaction", 16: "Spotify Tap", 17: "Cycle modes", 18: "Cycle volume presets",
         19: "Spatial audio", 20: "Line-in switch", 21: "Linking", 22: "Local alert", 23: "Remote alert",
         24: "Local and remote alert", 25: "Third-party service", 26: "Smart action", 27: "Alexa"][action] ?? "Unknown action \(action)"
    }
}
