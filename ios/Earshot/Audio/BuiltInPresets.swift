import Foundation

/*
 The QC Ultra correction below comes from AutoEq by Jaakko Pasanen.
 Copyright (c) 2018-2022 Jaakko Pasanen

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */
enum BuiltInPresets {
    static let qcUltraAutoEQURL = "https://github.com/jaakkopasanen/AutoEq/blob/master/results/Rtings/Bruel%20%26%20Kjaer%205128%20over-ear/Bose%20QuietComfort%20Ultra%20Headphones/Bose%20QuietComfort%20Ultra%20Headphones%20ParametricEQ.txt"

    static let flat = EQPreset(id: "flat", name: "Flat", bands: GraphicEQ.flatBands, isBuiltIn: true, description: "No change — the headphones' own sound.")

    static let bassBoost = withHeadroom(EQPreset(id: "bass", name: "Bass boost", bands: [
        EQBand(frequencyHz: 90, gainDb: 5, q: 0.7, type: .lowShelf),
        EQBand(frequencyHz: 60, gainDb: 1.5, q: 1),
        EQBand(frequencyHz: 250, gainDb: -1, q: 1.2)
    ], isBuiltIn: true, description: "Fuller low end without muddying the mids."))

    static let vocalClarity = withHeadroom(EQPreset(id: "vocal", name: "Vocal clarity", bands: [
        EQBand(frequencyHz: 120, gainDb: -2, q: 0.7, type: .lowShelf),
        EQBand(frequencyHz: 300, gainDb: -1.5, q: 1.2),
        EQBand(frequencyHz: 1200, gainDb: 1, q: 1),
        EQBand(frequencyHz: 2800, gainDb: 2.5, q: 1.1),
        EQBand(frequencyHz: 5500, gainDb: 1, q: 1.5)
    ], isBuiltIn: true, description: "Lifts presence around 3 kHz and trims the mud below it."))

    static let trebleSparkle = withHeadroom(EQPreset(id: "treble", name: "Treble sparkle", bands: [
        EQBand(frequencyHz: 6000, gainDb: 2, q: 1.2),
        EQBand(frequencyHz: 9000, gainDb: 3, q: 0.7, type: .highShelf),
        EQBand(frequencyHz: 3500, gainDb: -0.5, q: 1.5)
    ], isBuiltIn: true, description: "More air and detail in the top octaves."))

    static let podcast = withHeadroom(EQPreset(id: "podcast", name: "Podcast", bands: [
        EQBand(frequencyHz: 100, gainDb: -4, q: 0.7, type: .lowShelf),
        EQBand(frequencyHz: 200, gainDb: -1, q: 1),
        EQBand(frequencyHz: 1500, gainDb: 1.5, q: 1),
        EQBand(frequencyHz: 3000, gainDb: 2.5, q: 1.2),
        EQBand(frequencyHz: 8000, gainDb: -1.5, q: 0.7, type: .highShelf)
    ], isBuiltIn: true, description: "Intelligibility first: less rumble, clearer consonants."))

    static let loudness = withHeadroom(EQPreset(id: "loudness", name: "Loudness", bands: [
        EQBand(frequencyHz: 100, gainDb: 3.5, q: 0.7, type: .lowShelf),
        EQBand(frequencyHz: 700, gainDb: -1, q: 0.6),
        EQBand(frequencyHz: 8000, gainDb: 2.5, q: 0.7, type: .highShelf)
    ], isBuiltIn: true, description: "Soft smile curve for low-volume listening."))

    static let tunedForQCUltra = try! AutoEQParser.parse(text: """
    Preamp: -2.8 dB
    Filter 1: ON LSC Fc 105 Hz Gain -3.0 dB Q 0.70
    Filter 2: ON PK Fc 5032 Hz Gain 2.8 dB Q 3.69
    Filter 3: ON PK Fc 156 Hz Gain 1.5 dB Q 1.61
    Filter 4: ON PK Fc 94 Hz Gain -2.4 dB Q 2.32
    Filter 5: ON PK Fc 2373 Hz Gain -2.8 dB Q 5.58
    Filter 6: ON HSC Fc 10000 Hz Gain 2.7 dB Q 0.70
    Filter 7: ON PK Fc 1633 Hz Gain 2.6 dB Q 3.51
    Filter 8: ON PK Fc 491 Hz Gain -1.1 dB Q 2.50
    Filter 9: ON PK Fc 2194 Hz Gain -1.0 dB Q 3.76
    Filter 10: ON PK Fc 36 Hz Gain -0.5 dB Q 2.83
    """, id: "qc_ultra", name: "Tuned for QC Ultra", description: "Correction toward the Harman over-ear target for the Bose QuietComfort Ultra Headphones. AutoEq by Jaakko Pasanen (MIT license); Rtings measurement on the B&K 5128 rig. \(qcUltraAutoEQURL)", isBuiltIn: true)

    static let all: [EQPreset] = [flat, tunedForQCUltra, bassBoost, vocalClarity, trebleSparkle, podcast, loudness]

    static func byID(_ id: String?) -> EQPreset? { all.first { $0.id == id } }

    private static func withHeadroom(_ preset: EQPreset) -> EQPreset {
        var value = preset
        value.preampDb = Headroom.recommendedPreampDb(bands: value.bands)
        return value
    }
}
