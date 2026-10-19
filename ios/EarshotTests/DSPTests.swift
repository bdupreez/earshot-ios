import AVFoundation
import XCTest
@testable import Earshot

final class DSPTests: XCTestCase {
    func testPeakingFiltersHitRequestedGain() {
        for gain in [-15.0, -6, -1, 1, 3, 6, 12, 15] {
            for frequency in [31.0, 100, 1000, 4000, 12_000] {
                let filter = Biquad(band: EQBand(frequencyHz: frequency, gainDb: gain))
                XCTAssertEqual(filter.magnitudeDb(frequencyHz: frequency), gain, accuracy: 0.001)
            }
        }
    }

    func testShelvesReachTheirPlateausAndHalfGainAtCorner() {
        for gain in [-9.0, -3, 4, 10] {
            let low = Biquad(band: EQBand(frequencyHz: 200, gainDb: gain, q: 0.707, type: .lowShelf))
            XCTAssertEqual(low.magnitudeDb(frequencyHz: 10), gain, accuracy: 0.2)
            XCTAssertEqual(low.magnitudeDb(frequencyHz: 200), gain / 2, accuracy: 0.001)
            XCTAssertEqual(low.magnitudeDb(frequencyHz: 10_000), 0, accuracy: 0.2)
            let high = Biquad(band: EQBand(frequencyHz: 2000, gainDb: gain, q: 0.707, type: .highShelf))
            XCTAssertEqual(high.magnitudeDb(frequencyHz: 20_000), gain, accuracy: 0.2)
            XCTAssertEqual(high.magnitudeDb(frequencyHz: 2000), gain / 2, accuracy: 0.001)
            XCTAssertEqual(high.magnitudeDb(frequencyHz: 40), 0, accuracy: 0.2)
        }
    }

    func testZeroGainIsUnityAndNyquistClampsSafely() {
        for type in EQFilterType.allCases {
            let filter = Biquad(band: EQBand(frequencyHz: 1000, gainDb: 0, type: type))
            for frequency in [20.0, 500, 1000, 5000, 20_000] {
                XCTAssertEqual(filter.magnitudeDb(frequencyHz: frequency), 0, accuracy: 1e-6)
            }
        }
        let filter = Biquad(band: EQBand(frequencyHz: 30_000, gainDb: 6), sampleRate: 44_100)
        XCTAssertTrue(filter.magnitudeDb(frequencyHz: 22_000).isFinite)
    }

    func testCombinedResponseSkipsDisabledBandsAndIncludesPreamp() {
        let bands = [EQBand(frequencyHz: 1000, gainDb: 6), EQBand(frequencyHz: 1000, gainDb: 12, enabled: false)]
        let response = EQResponse(bands: bands, preampDb: -2)
        XCTAssertEqual(response.bandCount, 1)
        XCTAssertEqual(response.magnitudeDb(frequencyHz: 1000), 4, accuracy: 0.001)
        let points = response.sample(nPoints: 256)
        XCTAssertEqual(points.count, 256)
        XCTAssertEqual(points.first!.frequencyHz, 20, accuracy: 1e-9)
        XCTAssertEqual(points.last!.frequencyHz, 20_000, accuracy: 1e-7)
        XCTAssertTrue(zip(points, points.dropFirst()).allSatisfy { $0.frequencyHz < $1.frequencyHz })
    }

    func testHeadroomAccountsForOverlappingBoosts() {
        XCTAssertEqual(Headroom.recommendedPreampDb(bands: GraphicEQ.flatBands), 0)
        XCTAssertEqual(Headroom.recommendedPreampDb(bands: [EQBand(frequencyHz: 1000, gainDb: -6)]), 0)
        XCTAssertEqual(Headroom.recommendedPreampDb(bands: [EQBand(frequencyHz: 1000, gainDb: 6)]), -6, accuracy: 0.1)
        let overlap = [EQBand(frequencyHz: 800, gainDb: 6, q: 0.7), EQBand(frequencyHz: 1250, gainDb: 6, q: 0.7)]
        XCTAssertLessThan(Headroom.recommendedPreampDb(bands: overlap), -8)
        XCTAssertEqual(Headroom.clampBoost(9, limiterEnabled: false), 3)
        XCTAssertEqual(Headroom.clampBoost(20, limiterEnabled: true), 12)
        XCTAssertEqual(Headroom.effectivePreampDb(0, bands: overlap, limiterEnabled: false), Headroom.recommendedPreampDb(bands: overlap))
    }

    func testAutoEQTypesDisabledBandsCRLFAndRoundTrip() throws {
        let text = "# comment\r\nPreamp: -6.4 dB\r\nFilter 1: ON PK Fc 105 Hz Gain -3.2 dB Q 0.70\r\nFilter 2: ON LSC Fc 105 Hz Gain -3.0 dB Q 0.70\r\nFilter 3: OFF HSC Fc 10000 Hz Gain 2.7 dB Q 0.70\r\n"
        let preset = try AutoEQParser.parse(text: text, id: "test", name: "Test")
        XCTAssertEqual(preset.preampDb, -6.4)
        XCTAssertEqual(preset.bands.map(\.type), [.peak, .lowShelf, .highShelf])
        XCTAssertFalse(preset.bands[2].enabled)
        XCTAssertEqual(preset.bands[0], EQBand(frequencyHz: 105, gainDb: -3.2, q: 0.7))
        let exported = AutoEQParser.export(preset: preset)
        XCTAssertTrue(exported.contains("Filter 1: ON PK Fc 105 Hz Gain -3.2 dB Q 0.70"))
        XCTAssertEqual(try AutoEQParser.parse(text: exported, id: "test", name: "Test"), preset)
    }

    func testAutoEQClampsValuesSupportsAliasesAndRejectsUnusableInput() throws {
        let preset = try AutoEQParser.parse(text: "Preamp: 5 dB\nFilter 1: ON LS Fc 50 Hz Gain -22 dB Q 15\nFilter 2: OFF HS Fc 10000 Hz Gain 3 dB\nFilter 3: ON PK Fc -100 Hz Gain 3 dB Q 1")
        XCTAssertEqual(preset.preampDb, 0)
        XCTAssertEqual(preset.bands.count, 2)
        XCTAssertEqual(preset.bands[0].gainDb, -15)
        XCTAssertEqual(preset.bands[0].q, 10)
        XCTAssertEqual(preset.bands[1].q, 0.707)
        XCTAssertThrowsError(try AutoEQParser.parse(text: "not a preset"))
        XCTAssertThrowsError(try AutoEQParser.parse(text: "Preamp: -3 dB"))
    }

    func testOriginalAndroidJSONAndFutureFieldsAreCompatible() throws {
        let json = #"[{"id":"mine","name":"My preset","bands":[{"frequencyHz":440,"gainDb":2.5,"type":"HIGH_SHELF","enabled":false}],"futureField":42}]"#
        let presets = try PresetCodec.decodePresets(json)
        XCTAssertEqual(presets[0].bands[0].q, 1.41)
        XCTAssertEqual(presets[0].preampDb, 0)
        XCTAssertFalse(presets[0].isBuiltIn)
        XCTAssertEqual(try PresetCodec.decodePresets(PresetCodec.encodePresets(presets)), presets)
        let settings = try PresetCodec.decodeSettings(#"{"enabled":true,"futureField":42}"#)
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.bands, GraphicEQ.flatBands)
        XCTAssertEqual(try PresetCodec.decodeSettings(PresetCodec.encodeSettings(settings)), settings)
        XCTAssertThrowsError(try PresetCodec.decodePresets("not JSON"))
        XCTAssertThrowsError(try PresetCodec.decodePresets(#"[{"id":"bad","name":"Bad","bands":[{"frequencyHz":-5,"gainDb":2}]}]"#))
    }

    func testAllBuiltInPresetsAndQCAttributionMatchAndroid() throws {
        let presets = BuiltInPresets.all
        XCTAssertEqual(presets.count, 7)
        XCTAssertEqual(Set(presets.map(\.id)).count, presets.count)
        for preset in presets {
            XCTAssertTrue(preset.isBuiltIn)
            XCTAssertFalse(preset.bands.isEmpty)
            XCTAssertLessThanOrEqual(preset.bands.count, 10)
            XCTAssertTrue((-15.0...0).contains(preset.preampDb))
            XCTAssertNotNil(preset.description)
            XCTAssertLessThanOrEqual(Headroom.worstCaseOvershootDb(bands: preset.bands, preampDb: preset.preampDb, boostDb: 0), preset.id == "qc_ultra" ? 1 : 0.05)
        }
        let qc = BuiltInPresets.tunedForQCUltra
        XCTAssertEqual(qc.bands.count, 10)
        XCTAssertEqual(qc.preampDb, -2.8)
        XCTAssertEqual(qc.bands[0], EQBand(frequencyHz: 105, gainDb: -3, q: 0.7, type: .lowShelf))
        XCTAssertEqual(qc.bands[9].frequencyHz, 36)
        XCTAssertTrue(qc.description!.contains("MIT"))
        XCTAssertTrue(qc.description!.contains(BuiltInPresets.qcUltraAutoEQURL))
        XCTAssertEqual(try PresetCodec.decodePresets(PresetCodec.encodePresets(presets)), presets)
    }

    func testNativeAudioEQReallyChangesRenderedSamples() throws {
        let samples = tone(amplitude: 0.1)
        let flat = try NativeEQRenderer.render(samples: samples, preset: BuiltInPresets.flat, limiterEnabled: false)
        let cut = EQPreset(id: "cut", name: "Cut", bands: [EQBand(frequencyHz: 1000, gainDb: -12, q: 1)])
        let filtered = try NativeEQRenderer.render(samples: samples, preset: cut, limiterEnabled: false)
        XCTAssertEqual(flat.count, samples.count)
        XCTAssertEqual(filtered.count, samples.count)
        XCTAssertTrue(filtered.allSatisfy(\.isFinite))
        XCTAssertLessThan(rms(filtered), rms(flat) * 0.4, "The real AVAudioUnitEQ must attenuate a 1kHz tone")
    }

    func testNativeLimiterContainsBoostedFullScaleTone() throws {
        for (gain, boost) in [(0.0, 0.0), (6.0, 0.0), (15.0, 0.0), (15.0, 12.0)] {
            let hot = EQPreset(id: "hot", name: "Hot", bands: [EQBand(frequencyHz: 1000, gainDb: gain, q: 1)])
            let rendered = try NativeEQRenderer.render(samples: tone(amplitude: 0.95, frameCount: 144_000), preset: hot, preamp: 0, boost: boost, limiterEnabled: true)
            XCTAssertTrue(rendered.allSatisfy(\.isFinite))
            XCTAssertGreaterThan(rms(rendered), 0.3, "Sustained gain \(gain) + boost \(boost) must remain audible")
            XCTAssertLessThanOrEqual(rendered.map { abs($0) }.max() ?? 100, 1.01)
            XCTAssertGreaterThan(rms(Array(rendered.suffix(24_000))), 0.3, "The protection chain must not fade toward silence")
        }
    }

    func testNativeBoostActuallyAmplifiesAQuietSource() throws {
        let samples = tone(amplitude: 0.01)
        let normal = try NativeEQRenderer.render(samples: samples, preset: BuiltInPresets.flat)
        let boosted = try NativeEQRenderer.render(samples: samples, preset: BuiltInPresets.flat, boost: 12)
        XCTAssertEqual(rms(boosted) / rms(normal), pow(10, 12.0 / 20), accuracy: 0.1)
    }

    func testDisablingProEQRestoresUnprocessedPlaybackAtEveryLevel() throws {
        for amplitude in [0.1, 0.95] {
            let samples = tone(amplitude: amplitude)
            let rendered = try NativeEQRenderer.render(samples: samples, preset: BuiltInPresets.tunedForQCUltra, preamp: -20, enabled: false, boost: 12, limiterEnabled: true)
            XCTAssertEqual(rendered.count, samples.count)
            XCTAssertEqual(rms(rendered), rms(samples), accuracy: 0.001, "The master toggle must bypass filters, preamp, boost and dynamics")
        }
    }

    @MainActor
    func testDemoAudioLoadsPlaysPausesAndStops() throws {
        let audio = LocalAudioEngine()
        XCTAssertFalse(audio.hasFile)
        try audio.loadDemo()
        XCTAssertTrue(audio.hasFile)
        audio.apply(preset: BuiltInPresets.bassBoost)
        audio.playPause()
        XCTAssertTrue(audio.isPlaying, audio.status)
        audio.playPause()
        XCTAssertFalse(audio.isPlaying)
        audio.stop()
        XCTAssertTrue(audio.status.hasPrefix("Stopped"))
    }

    private func tone(amplitude: Double, frameCount: Int = 24_000) -> [Float] {
        (0..<frameCount).map { Float(amplitude * sin(2 * .pi * 1000 * Double($0) / 48_000)) }
    }

    private func rms(_ values: [Float]) -> Double {
        let settled = values.dropFirst(4096)
        return sqrt(settled.reduce(0) { $0 + Double($1 * $1) } / Double(settled.count))
    }
}
