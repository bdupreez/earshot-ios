import Foundation

enum PresetCodec {
    static func encodePresets(_ presets: [EQPreset]) throws -> String { try encode(presets) }
    static func decodePresets(_ text: String) throws -> [EQPreset] {
        try checkTextSize(text)
        let values = try JSONDecoder().decode([EQPreset].self, from: Data(text.utf8))
        guard values.count <= PresetValidation.maximumPresets, values.allSatisfy({ $0.bands.count <= PresetValidation.maximumBands }) else {
            throw PresetImportError.tooManyBands
        }
        return values
    }
    static func encodeSettings(_ settings: TuningSettings) throws -> String { try encode(settings) }
    static func decodeSettings(_ text: String) throws -> TuningSettings {
        try JSONDecoder().decode(TuningSettings.self, from: Data(text.utf8))
    }
    static func encodeAppProfiles(_ profiles: [AppProfileRecord]) throws -> String { try encode(profiles) }
    static func decodeAppProfiles(_ text: String) throws -> [AppProfileRecord] {
        try JSONDecoder().decode([AppProfileRecord].self, from: Data(text.utf8))
    }

    /// Accepts an Android array export, a single JSON preset, or an AutoEQ text file.
    static func importPresets(text: String, name: String = "Imported preset") throws -> [EQPreset] {
        try checkTextSize(text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            let values = try decodePresets(trimmed).map(PresetValidation.validated)
            guard !values.isEmpty else { throw PresetImportError.noFilters }
            return values
        }
        if trimmed.hasPrefix("{") {
            let preset = try JSONDecoder().decode(EQPreset.self, from: Data(trimmed.utf8))
            return [try PresetValidation.validated(preset)]
        }
        return [try PresetValidation.validated(AutoEQParser.parse(text: trimmed, id: UUID().uuidString, name: name))]
    }

    static func readImportFile(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= PresetValidation.maximumFileBytes else { throw PresetImportError.fileTooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: PresetValidation.maximumFileBytes + 1) ?? Data()
        guard data.count <= PresetValidation.maximumFileBytes else { throw PresetImportError.fileTooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw PresetImportError.invalidEncoding }
        return text
    }

    static func checkTextSize(_ text: String) throws {
        guard text.utf8.count <= PresetValidation.maximumFileBytes else { throw PresetImportError.fileTooLarge }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

enum PresetImportError: LocalizedError {
    case noFilters
    case tooManyBands
    case fileTooLarge
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .noFilters: return "No supported AutoEQ filters found. Import an AutoEQ ParametricEQ text file or an Earshot JSON export."
        case .tooManyBands: return "This file exceeds the import limit of 128 filters per preset or 250 presets."
        case .fileTooLarge: return "Import a UTF-8 preset file smaller than 2 MiB."
        case .invalidEncoding: return "Preset files must contain UTF-8 JSON or AutoEQ text."
        }
    }
}

enum AutoEQParser {
    private static let preampRegex = try! NSRegularExpression(
        pattern: #"^\s*Preamp:\s*([-+]?\d+(?:\.\d+)?)\s*dB\s*$"#, options: .caseInsensitive)
    private static let filterRegex = try! NSRegularExpression(
        pattern: #"^\s*Filter\s*\d+\s*:\s*(ON|OFF)\s+(PK|LSC|HSC|LS|HS|PEQ)\s+Fc\s+([-+]?\d+(?:\.\d+)?)\s*Hz\s+Gain\s+([-+]?\d+(?:\.\d+)?)\s*dB(?:\s+Q\s+([-+]?\d+(?:\.\d+)?))?\s*$"#,
        options: .caseInsensitive)

    static func parse(text: String, id: String = UUID().uuidString, name: String = "Imported preset", description: String? = nil, isBuiltIn: Bool = false) throws -> EQPreset {
        try PresetCodec.checkTextSize(text)
        var preamp = 0.0
        var bands: [EQBand] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(line.startIndex..., in: line)
            if let match = preampRegex.firstMatch(in: line, range: range), let value = capture(1, match: match, text: line).flatMap(Double.init) {
                preamp = value.clamped(to: -30...0)
                continue
            }
            guard let match = filterRegex.firstMatch(in: line, range: range),
                  let frequency = capture(3, match: match, text: line).flatMap(Double.init), frequency.isFinite, frequency > 0,
                  let gain = capture(4, match: match, text: line).flatMap(Double.init), gain.isFinite else { continue }
            let filterType: EQFilterType
            switch capture(2, match: match, text: line)?.uppercased() {
            case "LS", "LSC": filterType = .lowShelf
            case "HS", "HSC": filterType = .highShelf
            default: filterType = .peak
            }
            let q = capture(5, match: match, text: line).flatMap(Double.init) ?? 0.707
            bands.append(EQBand(frequencyHz: frequency.clamped(to: 20...20_000), gainDb: gain.clamped(to: EQBand.gainRange), q: q.clamped(to: EQBand.qRange), type: filterType, enabled: capture(1, match: match, text: line)?.uppercased() == "ON"))
            guard bands.count <= 128 else { throw PresetImportError.tooManyBands }
        }
        guard !bands.isEmpty else { throw PresetImportError.noFilters }
        return EQPreset(id: id, name: name, bands: bands, preampDb: preamp, isBuiltIn: isBuiltIn, description: description)
    }

    static func export(preset: EQPreset) -> String {
        var lines = ["Preamp: \(format(preset.preampDb, places: 1)) dB"]
        for (index, band) in preset.bands.enumerated() {
            let type: String
            switch band.type {
            case .peak: type = "PK"
            case .lowShelf: type = "LSC"
            case .highShelf: type = "HSC"
            }
            let frequency = abs(band.frequencyHz - band.frequencyHz.rounded()) < 0.05 ? format(band.frequencyHz, places: 0) : format(band.frequencyHz, places: 1)
            lines.append("Filter \(index + 1): \(band.enabled ? "ON" : "OFF") \(type) Fc \(frequency) Hz Gain \(format(band.gainDb, places: 1)) dB Q \(format(band.q, places: 2))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func capture(_ index: Int, match: NSTextCheckingResult, text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    private static func format(_ value: Double, places: Int) -> String {
        String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    }
}
