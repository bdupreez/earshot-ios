import Foundation

struct BoseBatteryReading: Equatable, Sendable {
    let component: UInt8
    let percent: Int?
    let remainingMinutes: Int?
    var label: String { [0: "Headphones", 1: "Right", 2: "Left", 3: "Case", 4: "Earbuds"][component] ?? "Component \(component)" }
}

struct BoseBattery: Equatable, Sendable {
    let percent: Int?
    let readings: [BoseBatteryReading]

    static func parse(_ data: Data) -> BoseBattery {
        let bytes = Array(data)
        var readings = [BoseBatteryReading]()
        func percent(_ value: UInt8) -> Int? { value <= 100 ? Int(value) : nil }
        func minutes(_ high: UInt8, _ low: UInt8) -> Int? {
            let value = Int(high) << 8 | Int(low)
            return value == 65_535 ? nil : value
        }
        if (1...3).contains(bytes.count) {
            readings.append(BoseBatteryReading(component: 0, percent: percent(bytes[0]),
                remainingMinutes: bytes.count >= 3 ? minutes(bytes[1], bytes[2]) : nil))
        } else {
            var offset = 0
            while offset + 3 < bytes.count {
                readings.append(BoseBatteryReading(component: bytes[offset + 3], percent: percent(bytes[offset]),
                    remainingMinutes: minutes(bytes[offset + 1], bytes[offset + 2])))
                offset += 4
            }
        }
        let combined = readings.first { $0.component == 4 && $0.percent != nil }?.percent
        let buds = readings.filter { $0.component == 1 || $0.component == 2 }.compactMap(\.percent).min()
        let single = readings.first { $0.component == 0 && $0.percent != nil }?.percent
        return BoseBattery(percent: combined ?? buds ?? single ?? readings.compactMap(\.percent).first, readings: readings)
    }
}

struct BoseEQBand: Equatable, Sendable, Identifiable {
    let id: UInt8
    let min: Int
    let max: Int
    let value: Int
    var name: String { [0: "Bass", 1: "Mid", 2: "Treble"][id] ?? "Band \(id)" }

    static func parse(_ data: Data) -> [BoseEQBand] {
        let bytes = Array(data)
        var result = [BoseEQBand]()
        var offset = 0
        while offset + 3 < bytes.count {
            result.append(BoseEQBand(id: bytes[offset + 3], min: Int(Int8(bitPattern: bytes[offset])),
                max: Int(Int8(bitPattern: bytes[offset + 1])), value: Int(Int8(bitPattern: bytes[offset + 2]))))
            offset += 4
        }
        return result
    }
}

struct BoseAudioSettings: Equatable, Codable, Sendable {
    var cancellingLevel: Int
    var spatial: UInt8
    var windBlock: Bool
    var ancEnabled: Bool

    init(cancellingLevel: Int = 10, spatial: UInt8 = 0, windBlock: Bool = false, ancEnabled: Bool = true) {
        self.cancellingLevel = cancellingLevel; self.spatial = spatial
        self.windBlock = windBlock; self.ancEnabled = ancEnabled
    }

    var cncMasked: Bool { !ancEnabled || windBlock }

    static func parse(_ data: Data) -> BoseAudioSettings? {
        let bytes = Array(data)
        guard bytes.count >= 5 else { return nil }
        return BoseAudioSettings(cancellingLevel: 10 - min(10, Int(bytes[0])), spatial: bytes[2],
                                 windBlock: bytes[3] != 0, ancEnabled: bytes[4] != 0)
    }
}

struct BoseModesCapabilities: Equatable, Sendable {
    let builtIn: Int
    let custom: Int
    let flags: UInt8
    let minimumFavorites: Int
    var totalModes: Int { builtIn + custom }
    var cnc: Bool { flags & 1 != 0 }
    var spatial: Bool { flags & 4 != 0 }
    var wind: Bool { flags & 8 != 0 }
    var favorites: Bool { flags & 16 != 0 }
    var ancToggle: Bool { flags & 32 != 0 }

    static func parse(_ data: Data) -> BoseModesCapabilities? {
        let bytes = Array(data)
        guard bytes.count >= 6 else { return nil }
        return BoseModesCapabilities(builtIn: Int(bytes[0]), custom: Int(bytes[1]), flags: bytes[5],
                                     minimumFavorites: bytes.count >= 7 ? Int(bytes[6]) : 0)
    }
}

struct BoseMode: Identifiable, Sendable {
    let index: UInt8
    let name: String
    let editable: Bool?
    let settings: BoseAudioSettings
    let prompt: (UInt8, UInt8)
    let raw: Data
    var id: UInt8 { index }
    var isEmpty: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.lowercased() == "none" }

    var displayName: String {
        let promptNames: [UInt8: String] = [1: "Quiet", 2: "Aware", 34: "Immersion", 35: "Stereo", 36: "Cinema",
            7: "Commute", 13: "Focus", 10: "Home", 12: "Music", 8: "Outdoor", 14: "Relax",
            20: "Run", 21: "Walk", 11: "Work", 9: "Workout"]
        if prompt.0 == 0, let label = promptNames[prompt.1] { return label }
        return isEmpty ? "Mode \(Int(index) + 1)" : name
    }

    static func parse(_ data: Data) -> BoseMode? {
        let bytes = Array(data)
        guard bytes.count >= 37 else { return nil }
        let isStatus = bytes.count >= 44
        let nameStart = isStatus ? 6 : 3
        let name = String(decoding: bytes[nameStart..<(nameStart + 32)].prefix { $0 != 0 }, as: UTF8.self)
        let cnc = isStatus ? 42 : 35
        let spatial: UInt8 = isStatus ? (bytes.count >= 45 ? bytes[44] : 0) : (bytes.count > 37 ? bytes[37] : 0)
        let wind = isStatus ? bytes.count >= 47 && bytes[46] != 0 : bytes.count > 38 && bytes[38] != 0
        let anc = isStatus ? bytes.count < 48 || bytes[47] != 0 : bytes.count <= 39 || bytes[39] != 0
        return BoseMode(index: bytes[0], name: name, editable: isStatus ? bytes[3] != 0 : nil,
                        settings: BoseAudioSettings(cancellingLevel: 10 - min(10, Int(bytes[cnc])), spatial: spatial,
                                                    windBlock: wind, ancEnabled: anc),
                        prompt: (bytes[1], bytes[2]), raw: data)
    }
}

enum BoseParsers {
    static func multipoint(_ data: Data) -> Bool? { data.first.map { $0 & 0x02 != 0 } }
    static func touchControls(_ data: Data) -> Bool? { data.first.map { $0 & 1 == 0 } }
    static func voicePrompts(_ data: Data) -> (enabled: Bool, language: UInt8)? {
        data.first.map { ($0 & 0x20 != 0, $0 & 0x1f) }
    }

    static func bitset(_ data: Data) -> Set<Int> {
        var result = Set<Int>()
        for (byteIndex, byte) in data.reversed().enumerated() {
            for bit in 0..<8 where byte & (1 << bit) != 0 { result.insert(byteIndex * 8 + bit) }
        }
        return result
    }

    static func favorites(_ data: Data) -> (total: Int, indices: Set<Int>)? {
        guard let total = data.first, data.count >= 2 else { return nil }
        return (Int(total), bitset(Data(data.dropFirst())).filter { $0 < Int(total) })
    }

    static func standbyMinutes(_ data: Data) -> Int? {
        let bytes = Array(data)
        guard let low = bytes.first else { return nil }
        return bytes.count >= 3 ? Int(bytes[2]) << 8 | Int(low) : Int(low)
    }

    static func customName(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        return String(decoding: data.dropFirst().prefix { $0 != 0 }, as: UTF8.self)
    }

    static func string(_ data: Data) -> String { String(decoding: data.prefix { $0 != 0 }, as: UTF8.self) }

    static func psm(_ data: Data) -> UInt16? {
        let bytes = Array(data)
        guard let first = bytes.first else { return nil }
        if bytes.count == 1 { return (0x80...0xff).contains(first) ? UInt16(first) : nil }
        let little = UInt16(first) | UInt16(bytes[1]) << 8
        let big = UInt16(first) << 8 | UInt16(bytes[1])
        return (0x80...0xff).contains(little) ? little : ((0x80...0xff).contains(big) ? big : nil)
    }

    static func productName(id: UInt16) -> String? {
        [0x4082: "QuietComfort Ultra Headphones (2nd Gen)", 0x4066: "QuietComfort Ultra Headphones",
         0x4083: "QuietComfort Headphones (2nd Gen)", 0x4075: "QuietComfort Headphones",
         0x4039: "QuietComfort 45", 0x4024: "Noise Cancelling Headphones 700", 0x4062: "QuietComfort Ultra Earbuds (2nd Gen)",
         0x4072: "QuietComfort Ultra Earbuds", 0x4064: "QuietComfort Earbuds II", 0x402f: "QuietComfort Earbuds (2020)",
         0x4068: "Ultra Open Earbuds", 0x4089: "Ultra Open Earbuds (2nd Gen)", 0x400c: "QuietComfort 35",
         0x4020: "QuietComfort 35 II", 0x0023: "QuietComfort Earbuds (2024, different protocol)"][id]
    }
}
