import Foundation

struct AudioPlaybackOptions: Codable, Equatable, Sendable {
    var automaticHeadroom = true
    var manualPreampDb = 0.0
    var limiterEnabled = true

    init() {}
    private enum CodingKeys: String, CodingKey { case automaticHeadroom, manualPreampDb, limiterEnabled }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        automaticHeadroom = try values.decodeIfPresent(Bool.self, forKey: .automaticHeadroom) ?? true
        manualPreampDb = (try values.decodeIfPresent(Double.self, forKey: .manualPreampDb) ?? 0).clamped(to: -30...0)
        limiterEnabled = try values.decodeIfPresent(Bool.self, forKey: .limiterEnabled) ?? true
    }
}

enum PresetValidationError: LocalizedError {
    case invalidName, invalidFilters, invalidGain, protectedPreset, missingPreset, libraryFull, excessiveGain

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Use a preset name containing 1–80 characters."
        case .invalidFilters: return "Use 1–128 filters with frequencies from 20 to 20,000 Hz, gains from −15 to +15 dB, and Q from 0.1 to 10."
        case .invalidGain: return "Preamp must be a finite value from −30 to 0 dB."
        case .protectedPreset: return "Built-in presets are protected. Save an editable copy instead."
        case .missingPreset: return "This user preset no longer exists. Save a new copy instead."
        case .libraryFull: return "The library holds up to 250 user presets. Delete a preset before adding more."
        case .excessiveGain: return "These overlapping filters exceed the safe processing range. Reduce their combined boost."
        }
    }
}

enum PresetValidation {
    static let maximumFileBytes = 2 * 1024 * 1024
    static let maximumPresets = 250
    static let maximumBands = 128

    static func validated(_ preset: EQPreset) throws -> EQPreset {
        var value = preset
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty, value.name.count <= 80 else { throw PresetValidationError.invalidName }
        guard !value.bands.isEmpty, value.bands.count <= maximumBands,
              value.bands.allSatisfy({ $0.frequencyHz.isFinite && (20...20_000).contains($0.frequencyHz) && $0.gainDb.isFinite && EQBand.gainRange.contains($0.gainDb) && $0.q.isFinite && EQBand.qRange.contains($0.q) }) else {
            throw PresetValidationError.invalidFilters
        }
        guard value.preampDb.isFinite, (-30...0).contains(value.preampDb) else { throw PresetValidationError.invalidGain }
        // Bound intermediate floating-point gain as well as the final combined response.
        let positiveGain = value.bands.filter(\.enabled).reduce(0) { $0 + max(0, $1.gainDb) }
        guard positiveGain <= 120, EQResponse(bands: value.bands).peakBandsOnlyDb() <= 60 else { throw PresetValidationError.excessiveGain }
        if let description = value.description, description.count > 8192 { value.description = String(description.prefix(8192)) }
        return value
    }

    static func uniqueName(_ name: String, existing: [EQPreset], excludingID: String? = nil) -> String {
        let names = Set(existing.filter { $0.id != excludingID }.map { $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) })
        func taken(_ value: String) -> Bool { names.contains(value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))) }
        if !taken(name) { return name }
        var suffix = 2
        while taken("\(String(name.prefix(74))) \(suffix)") { suffix += 1 }
        return "\(String(name.prefix(74))) \(suffix)"
    }
}

/// Keeps an exact recovery point when a parametric curve is approximated by ten graphic bands.
struct PresetEditorDraft: Equatable {
    var preset: EQPreset
    private(set) var graphic: Bool
    private(set) var parametricBackup: [EQBand]?

    init(preset: EQPreset) {
        self.preset = preset
        graphic = GraphicEQ.isGraphic(preset.bands)
    }

    mutating func useGraphicLayout() {
        guard !graphic else { return }
        parametricBackup = preset.bands
        preset.bands = GraphicEQ.approximateBands(from: preset.bands)
        graphic = true
    }

    mutating func useParametricLayout() { graphic = false }

    mutating func restoreParametricFilters() {
        guard let parametricBackup else { return }
        preset.bands = parametricBackup
        self.parametricBackup = nil
        graphic = false
    }

    mutating func removeFilters(at offsets: IndexSet) {
        let valid = offsets.filter { preset.bands.indices.contains($0) }
        guard preset.bands.count > valid.count else { return }
        for index in valid.sorted(by: >) { preset.bands.remove(at: index) }
        graphic = false
    }

    mutating func moveFilter(from source: Int, to destination: Int) {
        guard preset.bands.indices.contains(source), preset.bands.indices.contains(destination), source != destination else { return }
        let band = preset.bands.remove(at: source)
        preset.bands.insert(band, at: destination)
        graphic = false
    }
}

extension GraphicEQ {
    static func isGraphic(_ bands: [EQBand]) -> Bool {
        bands.count == bandCount && zip(bands, frequenciesHz).allSatisfy { $0.type == .peak && abs($0.frequencyHz - $1) < 0.001 && abs($0.q - defaultQ) < 0.001 }
    }

    static func approximateBands(from bands: [EQBand]) -> [EQBand] {
        if isGraphic(bands) { return bands }
        let response = EQResponse(bands: bands)
        return bandsFromGains(frequenciesHz.map { response.bandsOnlyDb(frequencyHz: $0).clamped(to: EQBand.gainRange) })
    }
}

struct PresetImportSummary: Equatable {
    var imported: Int
    var skippedDuplicates: Int
    var message: String { "Imported \(imported) preset\(imported == 1 ? "" : "s")." + (skippedDuplicates > 0 ? " Skipped \(skippedDuplicates) existing duplicate\(skippedDuplicates == 1 ? "" : "s")." : "") }
}

enum PresetRecovery {
    private static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Earshot Preset Recovery", isDirectory: true)
    }

    static var latestBackupURL: URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension == "json" }.max { left, right in
            let a = (try? left.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? right.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a < b
        }
    }

    static func save(_ presets: [EQPreset]) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Earshot-presets-\(UUID().uuidString).json")
        try Data(PresetCodec.encodePresets(presets).utf8).write(to: url, options: .atomic)
        return url
    }
}
