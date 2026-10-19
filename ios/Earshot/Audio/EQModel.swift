import Foundation

/// Names match the original Android preset format, so existing exports remain portable.
enum EQFilterType: String, Codable, CaseIterable, Sendable {
    case peak = "PEAK"
    case lowShelf = "LOW_SHELF"
    case highShelf = "HIGH_SHELF"

    var label: String {
        switch self {
        case .peak: return "Peak"
        case .lowShelf: return "Low shelf"
        case .highShelf: return "High shelf"
        }
    }
}

struct EQBand: Codable, Equatable, Hashable, Sendable {
    var frequencyHz: Double
    var gainDb: Double
    var q: Double = 1.41
    var type: EQFilterType = .peak
    var enabled: Bool = true

    static let gainRange = -15.0...15.0
    static let qRange = 0.1...10.0

    init(frequencyHz: Double, gainDb: Double, q: Double = 1.41, type: EQFilterType = .peak, enabled: Bool = true) {
        self.frequencyHz = frequencyHz
        self.gainDb = gainDb
        self.q = q
        self.type = type
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey { case frequencyHz, gainDb, q, type, enabled }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        frequencyHz = try values.decode(Double.self, forKey: .frequencyHz)
        gainDb = try values.decode(Double.self, forKey: .gainDb)
        q = try values.decodeIfPresent(Double.self, forKey: .q) ?? 1.41
        type = try values.decodeIfPresent(EQFilterType.self, forKey: .type) ?? .peak
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        guard frequencyHz.isFinite, frequencyHz > 0, gainDb.isFinite, q.isFinite else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "An EQ band contains invalid numbers."))
        }
        gainDb = gainDb.clamped(to: Self.gainRange)
        q = q.clamped(to: Self.qRange)
    }
}

struct EQPreset: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var bands: [EQBand]
    var preampDb: Double = 0
    var isBuiltIn: Bool = false
    var description: String?

    init(id: String, name: String, bands: [EQBand], preampDb: Double = 0, isBuiltIn: Bool = false, description: String? = nil) {
        self.id = id
        self.name = name
        self.bands = bands
        self.preampDb = preampDb
        self.isBuiltIn = isBuiltIn
        self.description = description
    }

    private enum CodingKeys: String, CodingKey { case id, name, bands, preampDb, isBuiltIn, description }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        bands = try values.decode([EQBand].self, forKey: .bands)
        preampDb = try values.decodeIfPresent(Double.self, forKey: .preampDb) ?? 0
        isBuiltIn = try values.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        description = try values.decodeIfPresent(String.self, forKey: .description)
        guard preampDb.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .preampDb, in: values, debugDescription: "Invalid preamp gain.")
        }
        preampDb = preampDb.clamped(to: -30...0)
    }
}

enum GraphicEQ {
    static let frequenciesHz: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let bandCount = frequenciesHz.count
    static let defaultQ = 1.41

    static func bandsFromGains(_ gains: [Double]) -> [EQBand] {
        precondition(gains.count == bandCount, "Expected ten graphic equalizer gains")
        return zip(frequenciesHz, gains).map { EQBand(frequencyHz: $0, gainDb: $1) }
    }

    static var flatBands: [EQBand] { bandsFromGains(Array(repeating: 0, count: bandCount)) }
}

struct TuningSettings: Codable, Equatable, Sendable {
    var enabled = false
    var activePresetId: String?
    var bands = GraphicEQ.flatBands
    var preampDb: Double = 0
    var boostDb: Double = 0
    var limiterEnabled = true

    static let maxBoostDb = 12.0
    static let boostWarningDb = 6.0

    init() {}

    private enum CodingKeys: String, CodingKey { case enabled, activePresetId, bands, preampDb, boostDb, limiterEnabled }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        activePresetId = try values.decodeIfPresent(String.self, forKey: .activePresetId)
        bands = try values.decodeIfPresent([EQBand].self, forKey: .bands) ?? GraphicEQ.flatBands
        preampDb = (try values.decodeIfPresent(Double.self, forKey: .preampDb) ?? 0).clamped(to: -30...0)
        limiterEnabled = try values.decodeIfPresent(Bool.self, forKey: .limiterEnabled) ?? true
        boostDb = Headroom.clampBoost(try values.decodeIfPresent(Double.self, forKey: .boostDb) ?? 0, limiterEnabled: limiterEnabled)
    }
}

struct AppProfileRecord: Codable, Equatable, Sendable {
    var packageName: String
    var appLabel: String
    var presetId: String
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        guard isFinite else { return range.lowerBound }
        return min(range.upperBound, max(range.lowerBound, self))
    }
}
