import Foundation

/// Robert Bristow-Johnson's Audio EQ Cookbook coefficients. Used for visualization and headroom.
struct Biquad: Sendable {
    private(set) var b0 = 1.0
    private(set) var b1 = 0.0
    private(set) var b2 = 0.0
    private(set) var a1 = 0.0
    private(set) var a2 = 0.0
    private var sampleRate: Double = 48_000
    static let defaultSampleRate = 48_000.0

    init() {}

    init(band: EQBand, sampleRate: Double = defaultSampleRate) {
        self.sampleRate = max(40, sampleRate)
        let fc = band.frequencyHz.clamped(to: 1...(self.sampleRate * 0.499))
        let q = max(0.001, band.q)
        let a = pow(10, band.gainDb / 40)
        let w = 2 * Double.pi * fc / self.sampleRate
        let c = cos(w)
        let alpha = sin(w) / (2 * q)
        let t = 2 * sqrt(a) * alpha
        let nb0, nb1, nb2, na0, na1, na2: Double
        switch band.type {
        case .peak:
            nb0 = 1 + alpha * a; nb1 = -2 * c; nb2 = 1 - alpha * a
            na0 = 1 + alpha / a; na1 = -2 * c; na2 = 1 - alpha / a
        case .lowShelf:
            nb0 = a * ((a + 1) - (a - 1) * c + t)
            nb1 = 2 * a * ((a - 1) - (a + 1) * c)
            nb2 = a * ((a + 1) - (a - 1) * c - t)
            na0 = (a + 1) + (a - 1) * c + t
            na1 = -2 * ((a - 1) + (a + 1) * c)
            na2 = (a + 1) + (a - 1) * c - t
        case .highShelf:
            nb0 = a * ((a + 1) + (a - 1) * c + t)
            nb1 = -2 * a * ((a - 1) + (a + 1) * c)
            nb2 = a * ((a + 1) + (a - 1) * c - t)
            na0 = (a + 1) - (a - 1) * c + t
            na1 = 2 * ((a - 1) - (a + 1) * c)
            na2 = (a + 1) - (a - 1) * c - t
        }
        b0 = nb0 / na0; b1 = nb1 / na0; b2 = nb2 / na0
        a1 = na1 / na0; a2 = na2 / na0
    }

    func magnitudeDb(frequencyHz: Double) -> Double {
        let w = 2 * Double.pi * frequencyHz / sampleRate
        let nr = b0 + b1 * cos(w) + b2 * cos(2 * w)
        let ni = -(b1 * sin(w) + b2 * sin(2 * w))
        let dr = 1 + a1 * cos(w) + a2 * cos(2 * w)
        let di = -(a1 * sin(w) + a2 * sin(2 * w))
        let numerator = nr * nr + ni * ni
        let denominator = dr * dr + di * di
        guard denominator > 0, numerator > 0 else { return numerator <= 0 ? -200 : 200 }
        return 10 * log10(numerator / denominator)
    }
}

struct ResponsePoint: Equatable, Sendable {
    var frequencyHz: Double
    var gainDb: Double
}

struct EQResponse: Sendable {
    let preampDb: Double
    let sampleRate: Double
    private let sections: [Biquad]
    var bandCount: Int { sections.count }

    init(bands: [EQBand], preampDb: Double = 0, sampleRate: Double = Biquad.defaultSampleRate) {
        self.preampDb = preampDb
        self.sampleRate = sampleRate
        sections = bands.filter(\.enabled).map { Biquad(band: $0, sampleRate: sampleRate) }
    }

    func magnitudeDb(frequencyHz: Double) -> Double { preampDb + bandsOnlyDb(frequencyHz: frequencyHz) }

    func bandsOnlyDb(frequencyHz: Double) -> Double {
        sections.reduce(0) { $0 + $1.magnitudeDb(frequencyHz: frequencyHz) }
    }

    func sample(nPoints: Int = 256, fMin: Double = 20, fMax: Double = 20_000) -> [ResponsePoint] {
        Self.logSpaced(n: nPoints, fMin: fMin, fMax: fMax).map {
            ResponsePoint(frequencyHz: $0, gainDb: magnitudeDb(frequencyHz: $0))
        }
    }

    func peakBandsOnlyDb(nPoints: Int = 512, fMin: Double = 20, fMax: Double = 20_000) -> Double {
        Self.logSpaced(n: nPoints, fMin: fMin, fMax: min(fMax, sampleRate * 0.499))
            .map { bandsOnlyDb(frequencyHz: $0) }.max() ?? 0
    }

    static func logSpaced(n: Int, fMin: Double, fMax: Double) -> [Double] {
        guard n > 0, fMin > 0, fMax > fMin else { return [] }
        if n == 1 { return [fMin] }
        let low = log(fMin)
        let step = (log(fMax) - low) / Double(n - 1)
        return (0..<n).map { exp(low + step * Double($0)) }
    }
}

enum Headroom {
    static let boostCapWithoutLimiterDb = 3.0

    static func recommendedPreampDb(bands: [EQBand], sampleRate: Double = Biquad.defaultSampleRate) -> Double {
        let peak = EQResponse(bands: bands, sampleRate: sampleRate).peakBandsOnlyDb()
        return peak > 0.000_001 ? -(ceil(peak * 10) / 10) : 0
    }

    static func effectiveBoostCapDb(limiterEnabled: Bool) -> Double {
        limiterEnabled ? TuningSettings.maxBoostDb : boostCapWithoutLimiterDb
    }

    static func clampBoost(_ boostDb: Double, limiterEnabled: Bool) -> Double {
        boostDb.clamped(to: 0...effectiveBoostCapDb(limiterEnabled: limiterEnabled))
    }

    static func effectivePreampDb(_ preampDb: Double, bands: [EQBand], limiterEnabled: Bool, sampleRate: Double = Biquad.defaultSampleRate) -> Double {
        limiterEnabled ? preampDb : min(preampDb, recommendedPreampDb(bands: bands, sampleRate: sampleRate))
    }

    static func worstCaseOvershootDb(bands: [EQBand], preampDb: Double, boostDb: Double) -> Double {
        max(0, EQResponse(bands: bands).peakBandsOnlyDb() + preampDb + boostDb)
    }
}
