import Foundation

// Model catalogue adapted from HellzYeahh and contributors' MIT Earshot sources.
// OpenSCQ30/Gadgetbridge supply protocol facts only, not copied implementation.
// Classic vendor UUIDs are SDP/RFCOMM identifiers, NEVER a GATT write allow-list.
enum SoundcoreHeader: String, Sendable { case sleep, g2t, g2h, tlv, unknown }
enum SoundcoreBatteryScale: String, Sendable {
    case five, nine, ten, percent
    func percent(_ raw: UInt8) -> Int? {
        switch self {
        case .five: return raw <= 5 ? Int(raw) * 20 : nil
        case .nine: return raw <= 9 ? (Int(raw) + 1) * 10 : nil
        case .ten: return raw <= 10 ? Int(raw) * 10 : nil
        case .percent: return raw <= 100 ? Int(raw) : nil
        }
    }
}

enum SoundcoreModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case sleepA30 = "D1301"
    case sleepA20 = "A6611"
    case spaceOne = "A3035"
    case spaceOnePro = "A3062"
    case spaceQ45 = "A3040"
    case space2 = "D1402"
    case liberty4NC = "A3947"
    case liberty5 = "A3957"
    case p40i = "A3955"
    case r50iNC = "A3959"
    case a30i = "A3958"
    case p31i = "D1202"
    case r60iNC = "D1202C"
    case spaceA40 = "A3936"
    case liberty3Pro = "A3952"
    case liberty4 = "A3953"
    case liberty4Pro = "A3954"
    case sportX20 = "A3968"
    case lifeNote3 = "A3933"
    case lifeNote3S = "A3945"
    case lifeP3 = "A3939"
    case lifeP2Mini = "A3944"
    case a20i = "A3948"
    case p20i = "A3949"
    case c30i = "A3330"
    case aeroClip = "A3388"
    case v20i = "A3876"
    case aeroFit2 = "A3874"
    case c50i = "D1101"
    case liberty5Pro = "D1203"
    case liberty5ProMax = "D1204"
    case libertyBuds2 = "D1206"
    case p42i = "D1205"
    case aeroFit2Pro = "A3875"
    case v40i = "A3878"
    var id: String { rawValue }
    var code: String { rawValue }
    var displayName: String { metadata.name }
    var header: SoundcoreHeader { metadata.header }
    var batteryScale: SoundcoreBatteryScale { metadata.battery }
    var earbuds: Bool { metadata.earbuds }
    var serialPrefix: String { String(rawValue.dropFirst().prefix(4)) }
    var layout: SoundcoreLayout? { SoundcoreLayouts.layout(for: self) }
    var hasDocumentedWrites: Bool { self == .sleepA30 || layout?.writable == true }
    static let classicServicePrefix = "0cf12d31-fac3-4553-bd80-d6832e7"
    static let liveControlAvailable = false
    static let transportLimitation = "The documented Soundcore control transport is Classic Bluetooth RFCOMM. Public iOS APIs cannot open it directly. A verified manufacturer BLE/MFi control endpoint is required; generic write/notify characteristics are not safe evidence."
    var classicVendorServiceUUIDs: [String] {
        let number = (UInt32(rawValue.prefix(5), radix: 16) ?? 0) | 0x10000
        return ([String(format: "%05x", number)] + metadata.extraSuffixes).map { Self.classicServicePrefix + $0 }
    }
    static func fromName(_ name: String?) -> Self? {
        guard let name, name.range(of: #"\bjbl\b|harman"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        return allCases.first { name.range(of: $0.metadata.pattern, options: [.regularExpression, .caseInsensitive]) != nil }
    }
    static func fromClassicServiceUUID(_ uuid: String) -> Self? {
        allCases.first { $0.classicVendorServiceUUIDs.contains(uuid.lowercased()) }
    }
    static func fromSerial(_ serial: String?) -> Self? {
        guard let serial, serial.count >= 4 else { return nil }
        return allCases.first { serial.hasPrefix($0.serialPrefix) }
    }
    static func identifyClassic(uuids: [String], name: String?) -> Self? {
        if let name, name.range(of: #"\bjbl\b|harman"#, options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        return uuids.compactMap(fromClassicServiceUUID).first
    }
    private struct Metadata {
        let name: String
        let pattern: String
        let header: SoundcoreHeader
        let battery: SoundcoreBatteryScale
        let earbuds: Bool
        let extraSuffixes: [String]
    }
    private var metadata: Metadata {
        switch self {
        case .sleepA30: return Metadata(name: "Soundcore Sleep A30", pattern: "sleep\\s*a30", header: .sleep, battery: .nine, earbuds: true, extraSuffixes: [])
        case .sleepA20: return Metadata(name: "Soundcore Sleep A20", pattern: "soundcore[\\s_-]*sleep\\s*a20", header: .sleep, battery: .nine, earbuds: true, extraSuffixes: [])
        case .spaceOne: return Metadata(name: "Soundcore Space One", pattern: "soundcore[\\s_-]*space\\s*one(?![\\s_-]*pro)", header: .g2h, battery: .five, earbuds: false, extraSuffixes: [])
        case .spaceOnePro: return Metadata(name: "Soundcore Space One Pro", pattern: "soundcore[\\s_-]*space\\s*one[\\s_-]*pro", header: .g2h, battery: .nine, earbuds: false, extraSuffixes: [])
        case .spaceQ45: return Metadata(name: "Soundcore Space Q45", pattern: "soundcore[\\s_-]*space\\s*q\\s*45", header: .g2h, battery: .five, earbuds: false, extraSuffixes: [])
        case .space2: return Metadata(name: "Soundcore Space 2", pattern: "soundcore[\\s_-]*space\\s*2\\b", header: .g2h, battery: .nine, earbuds: false, extraSuffixes: [])
        case .liberty4NC: return Metadata(name: "Soundcore Liberty 4 NC", pattern: "soundcore[\\s_-]*liberty\\s*4[\\s_-]*nc", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .liberty5: return Metadata(name: "Soundcore Liberty 5", pattern: "soundcore[\\s_-]*liberty\\s*5(?![\\s_-]*pro)", header: .g2t, battery: .nine, earbuds: true, extraSuffixes: [])
        case .p40i: return Metadata(name: "Soundcore P40i", pattern: "soundcore[\\s_-]*p40i", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .r50iNC: return Metadata(name: "Soundcore R50i NC", pattern: "soundcore[\\s_-]*(?:r50i[\\s_-]*nc|p30i)", header: .g2t, battery: .ten, earbuds: true, extraSuffixes: ["b395b"])
        case .a30i: return Metadata(name: "Soundcore A30i", pattern: "soundcore[\\s_-]*a30i", header: .g2t, battery: .nine, earbuds: true, extraSuffixes: [])
        case .p31i: return Metadata(name: "Soundcore P31i", pattern: "soundcore[\\s_-]*p31i", header: .g2t, battery: .nine, earbuds: true, extraSuffixes: [])
        case .r60iNC: return Metadata(name: "Soundcore R60i NC", pattern: "soundcore[\\s_-]*r60i", header: .g2t, battery: .nine, earbuds: true, extraSuffixes: ["1202c"])
        case .spaceA40: return Metadata(name: "Soundcore Space A40", pattern: "soundcore[\\s_-]*space\\s*a40", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .liberty3Pro: return Metadata(name: "Soundcore Liberty 3 Pro", pattern: "soundcore[\\s_-]*liberty\\s*3[\\s_-]*pro", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .liberty4: return Metadata(name: "Soundcore Liberty 4", pattern: "soundcore[\\s_-]*liberty\\s*4(?![\\s_-]*(?:nc|pro))", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .liberty4Pro: return Metadata(name: "Soundcore Liberty 4 Pro", pattern: "soundcore[\\s_-]*liberty\\s*4[\\s_-]*pro", header: .g2t, battery: .percent, earbuds: true, extraSuffixes: [])
        case .sportX20: return Metadata(name: "Soundcore Sport X20", pattern: "soundcore[\\s_-]*sport\\s*x20", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .lifeNote3: return Metadata(name: "Soundcore Life Note 3", pattern: "soundcore[\\s_-]*life\\s*note\\s*3(?![\\s_-]*s\\b)", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .lifeNote3S: return Metadata(name: "Soundcore Life Note 3S", pattern: "soundcore[\\s_-]*life\\s*note\\s*3[\\s_-]*s\\b", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .lifeP3: return Metadata(name: "Soundcore Life P3", pattern: "soundcore[\\s_-]*life\\s*p3", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .lifeP2Mini: return Metadata(name: "Soundcore Life P2 Mini", pattern: "soundcore[\\s_-]*life\\s*p2", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .a20i: return Metadata(name: "Soundcore A20i", pattern: "soundcore[\\s_-]*a20i", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .p20i: return Metadata(name: "Soundcore P20i / R50i", pattern: "soundcore[\\s_-]*(?:p20i|p25i|r50i(?![\\s_-]*nc))", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .c30i: return Metadata(name: "Soundcore C30i", pattern: "soundcore[\\s_-]*c30i", header: .g2t, battery: .five, earbuds: true, extraSuffixes: [])
        case .aeroClip: return Metadata(name: "Soundcore AeroClip", pattern: "soundcore[\\s_-]*aeroclip", header: .g2t, battery: .nine, earbuds: true, extraSuffixes: [])
        case .v20i: return Metadata(name: "Soundcore V20i", pattern: "soundcore[\\s_-]*v20i", header: .g2t, battery: .nine, earbuds: true, extraSuffixes: [])
        case .aeroFit2: return Metadata(name: "Soundcore AeroFit 2", pattern: "soundcore[\\s_-]*aerofit\\s*2(?![\\s_-]*pro)", header: .g2t, battery: .nine, earbuds: true, extraSuffixes: [])
        case .c50i: return Metadata(name: "Soundcore C50i", pattern: "soundcore[\\s_-]*c50i", header: .g2t, battery: .nine, earbuds: true, extraSuffixes: [])
        case .liberty5Pro: return Metadata(name: "Soundcore Liberty 5 Pro", pattern: "soundcore[\\s_-]*liberty\\s*5[\\s_-]*pro(?![\\s_-]*max)", header: .tlv, battery: .percent, earbuds: true, extraSuffixes: [])
        case .liberty5ProMax: return Metadata(name: "Soundcore Liberty 5 Pro Max", pattern: "soundcore[\\s_-]*liberty\\s*5[\\s_-]*pro[\\s_-]*max", header: .tlv, battery: .percent, earbuds: true, extraSuffixes: [])
        case .libertyBuds2: return Metadata(name: "Soundcore Liberty Buds 2", pattern: "soundcore[\\s_-]*liberty\\s*buds\\s*2", header: .tlv, battery: .percent, earbuds: true, extraSuffixes: [])
        case .p42i: return Metadata(name: "Soundcore P42i", pattern: "soundcore[\\s_-]*p42i", header: .unknown, battery: .nine, earbuds: true, extraSuffixes: [])
        case .aeroFit2Pro: return Metadata(name: "Soundcore AeroFit 2 Pro", pattern: "soundcore[\\s_-]*aerofit\\s*2[\\s_-]*pro", header: .unknown, battery: .nine, earbuds: true, extraSuffixes: [])
        case .v40i: return Metadata(name: "Soundcore V40i", pattern: "soundcore[\\s_-]*v40i", header: .unknown, battery: .nine, earbuds: true, extraSuffixes: [])
        }
    }
}
