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

struct BoseButtonShortcut: Equatable {
    let button: UInt8
    let event: UInt8
    let action: UInt8
    let supported: Set<Int>
    static func parse(_ data: Data) -> BoseButtonShortcut? {
        let bytes = Array(data)
        guard bytes.count >= 7 else { return nil }
        let supported = BoseParsers.bitset(Data(bytes[3..<7]))
        guard supported.contains(Int(bytes[2])) else { return nil }
        return BoseButtonShortcut(button: bytes[0], event: bytes[1], action: bytes[2], supported: supported)
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
