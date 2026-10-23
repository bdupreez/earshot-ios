import Foundation

// AI-assisted port of HellzYeahh/earshot (MIT). Offsets and model distinctions
// follow upstream's researched facts, not a claim of physical iOS compatibility.
enum SoundcoreAmbient: Int, CaseIterable, Codable, Sendable {
    case noiseCancelling = 0, transparency = 1, normal = 2
    var title: String { switch self { case .noiseCancelling: return "Noise cancelling"; case .transparency: return "Transparency"; case .normal: return "Normal" } }
}

struct SoundcoreModeCodec: Equatable, Sendable {
    let name: String
    let size: Int
    var manualLevels: ClosedRange<Int>? = nil
    var ncTypes: [String] = []
    var transparencyTypes: [String] = []
    var mirrorsAmbientAt2 = false
    var hasWind = true
    static let transparent = ["Fully transparent", "Vocal mode"]
    static let scene = ["Manual", "Adaptive", "Multi-scene"]
    static let transport = Self(name: "v2-7 transport", size: 7, manualLevels: 1...5, ncTypes: ["Manual", "Adaptive", "Transportation"], transparencyTypes: transparent)
    static let scenes = Self(name: "v2-7 scene", size: 7, manualLevels: 1...5, ncTypes: scene, transparencyTypes: transparent)
    static let mirror = Self(name: "v2-7 mirror", size: 7, manualLevels: 1...5, ncTypes: scene, mirrorsAmbientAt2: true)
    static let eight = Self(name: "v2-8", size: 8, manualLevels: 1...5, ncTypes: scene, transparencyTypes: transparent)
    static let tws = Self(name: "v2-6 tws", size: 6, manualLevels: 1...3, ncTypes: ["Manual", "Adaptive"], transparencyTypes: transparent)
    static let liberty4 = Self(name: "v2-6 liberty 4", size: 6, manualLevels: 1...6, ncTypes: ["Manual", "Adaptive"], transparencyTypes: transparent)
    static let space = Self(name: "v2-6 space one", size: 6, manualLevels: 1...5, ncTypes: ["Manual", "Adaptive"], mirrorsAmbientAt2: true)
    static let spacePro = Self(name: "v2-6 space one pro", size: 6, manualLevels: 1...5, ncTypes: ["Manual", "Adaptive"])
    static let q45 = Self(name: "v2-6 q45", size: 6, manualLevels: 1...5, ncTypes: ["Manual", "Adaptive"])
    static let space2 = Self(name: "space 2", size: 6, manualLevels: 1...5, hasWind: false)
    static let slider = Self(name: "slider (polarity unresolved)", size: 4, hasWind: false)
}

struct SoundcoreModes: Equatable, Sendable {
    let codec: SoundcoreModeCodec
    private(set) var raw: Data
    init?(codec: SoundcoreModeCodec, raw: Data) {
        guard raw.count == codec.size else { return nil }
        self.codec = codec; self.raw = raw
    }
    private var bytes: [UInt8] { Array(raw) }
    var ambient: SoundcoreAmbient? { SoundcoreAmbient(rawValue: Int(bytes[0])) }
    var manualLevel: Int? { let level = Int(bytes[1] >> 4); return codec.manualLevels?.contains(level) == true ? level : nil }
    var adaptiveLevel: Int? { codec.manualLevels == nil ? nil : Int(bytes[1] & 15) }
    var ncType: Int? { codec.ncTypes.indices.contains(Int(bytes[3])) ? Int(bytes[3]) : nil }
    var transparencyType: Int? { codec.transparencyTypes.indices.contains(Int(bytes[2])) ? Int(bytes[2]) : nil }
    var windOn: Bool? { codec.hasWind ? bytes[4] & 1 != 0 : nil }
    func changing(_ edit: (inout [UInt8]) -> Void) -> Self {
        var b = bytes; edit(&b)
        // Never let an accidental internal edit invalidate later indexed reads.
        guard b.count == codec.size else { return self }
        var copy = self; copy.raw = Data(b); return copy
    }
}

struct SoundcoreSetting: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let command: UInt16
    let offset: Int
    var autoOff = false
}

struct SoundcoreLayout: Equatable, Sendable {
    let stateSize: Int?
    let modeOffset: Int
    let codec: SoundcoreModeCodec
    var lengthByteOffset: Int? = nil
    var caseBatteryOffset: Int? = nil
    var caseFirmwareOffset: Int? = nil
    var settings: [SoundcoreSetting] = []
    var autoOffMinutes: [Int] = []
    var writable = false
    var sessionInit = false
    func allows(command: UInt16, body: Data) -> Bool {
        guard writable else { return false }
        if command == SoundcoreCommands.setSoundModes { return body.count == codec.size }
        if command == SoundcoreCommands.sessionInit { return sessionInit && body.isEmpty }
        guard let setting = settings.first(where: { $0.command == command }) else { return false }
        let b = Array(body)
        if setting.autoOff { return b.count == 2 && b[0] <= 1 && autoOffMinutes.indices.contains(Int(b[1])) }
        return b.count == 1 && b[0] <= 1
    }
}

enum SoundcoreLayouts {
    private static let tens = [10, 20, 30, 60], halves = [30, 60, 90, 120]
    private static func flag(_ id: String, _ title: String, _ command: UInt16, _ at: Int) -> SoundcoreSetting { .init(id: id, title: title, command: command, offset: at) }
    private static func tone(_ at: Int) -> SoundcoreSetting { flag("touch_tone", "Touch tone", 0x0183, at) }
    private static func multi(_ at: Int) -> SoundcoreSetting { flag("multipoint", "Multipoint", 0x0b84, at) }
    private static func auto(_ at: Int) -> SoundcoreSetting { .init(id: "auto_off", title: "Auto power-off", command: 0x0186, offset: at, autoOff: true) }
    private static func low(_ at: Int) -> SoundcoreSetting { flag("low_battery_prompt", "Low battery prompt", 0x1082, at) }
    private static func game(_ at: Int, _ command: UInt16) -> SoundcoreSetting { flag("gaming_mode", "Gaming mode", command, at) }
    static func layout(for model: SoundcoreModel) -> SoundcoreLayout? {
        switch model {
        case .liberty4NC:
            return .init(stateSize: 159, modeOffset: 126, codec: .transport, lengthByteOffset: 108, caseBatteryOffset: 139,
                settings: [tone(144), game(143, 0x1085), flag("leak_compensation", "Sound leak compensation", 0x1086, 141), multi(147), low(157), auto(154)], autoOffMinutes: tens, writable: true)
        case .liberty5:
            return .init(stateSize: 154, modeOffset: 119, codec: .transport, lengthByteOffset: 109, caseBatteryOffset: 37, caseFirmwareOffset: 32,
                settings: [flag("wearing_tone", "Wearing tone", 0x018c, 127), multi(130), auto(131), flag("wear_detection", "Wear detection", 0x0181, 144), tone(145), game(146, 0x1085)], autoOffMinutes: tens, writable: true, sessionInit: true)
        case .p40i:
            return .init(stateSize: 152, modeOffset: 119, codec: .scenes, lengthByteOffset: 109, caseBatteryOffset: 37, caseFirmwareOffset: 32,
                settings: [tone(133), multi(134), auto(138), low(141)], autoOffMinutes: tens, writable: true, sessionInit: true)
        case .r50iNC:
            return .init(stateSize: 91, modeOffset: 64, codec: .mirror, lengthByteOffset: 54, settings: [tone(72), multi(73), auto(75), game(78, 0x0187)], autoOffMinutes: tens, writable: true)
        case .a30i:
            return .init(stateSize: 91, modeOffset: 64, codec: .mirror, lengthByteOffset: 54, settings: [tone(72), flag("surround", "3D surround", 0x0286, 74), auto(75)], autoOffMinutes: tens, writable: true)
        case .p31i, .r60iNC:
            return .init(stateSize: 152, modeOffset: 119, codec: .eight, lengthByteOffset: 109, caseBatteryOffset: 37, caseFirmwareOffset: 32,
                settings: [tone(128), low(129), multi(131), auto(132)], autoOffMinutes: tens, writable: true, sessionInit: true)
        case .spaceA40:
            return .init(stateSize: 143, modeOffset: 117, codec: .tws, lengthByteOffset: 103, caseBatteryOffset: 124,
                settings: [tone(123), multi(127), auto(128), game(130, 0x0187)], autoOffMinutes: halves, writable: true)
        case .liberty3Pro:
            return .init(stateSize: 153, modeOffset: 121, codec: .tws, lengthByteOffset: 103, caseBatteryOffset: 130,
                settings: [tone(127), flag("wear_detection", "Wear detection", 0x0181, 128), flag("wearing_tone", "Wearing tone", 0x018c, 136), auto(138)], autoOffMinutes: halves, writable: true)
        case .liberty4: return .init(stateSize: nil, modeOffset: 121, codec: .liberty4, lengthByteOffset: 103)
        case .liberty4Pro: return .init(stateSize: 165, modeOffset: 125, codec: .slider, lengthByteOffset: 115, caseBatteryOffset: 37, caseFirmwareOffset: 32)
        case .spaceOne: return .init(stateSize: 95, modeOffset: 69, codec: .space, settings: [multi(82), auto(85)], autoOffMinutes: halves, writable: true)
        case .spaceOnePro: return .init(stateSize: 95, modeOffset: 69, codec: .spacePro, settings: [multi(79), auto(80)], autoOffMinutes: halves, writable: true)
        case .spaceQ45: return .init(stateSize: 142, modeOffset: 49, codec: .q45, settings: [multi(62), auto(65)], autoOffMinutes: halves, writable: true)
        case .space2: return .init(stateSize: 103, modeOffset: 71, codec: .space2)
        default: return nil
        }
    }
}
