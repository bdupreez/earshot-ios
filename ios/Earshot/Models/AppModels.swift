import Foundation

struct DeviceProfile: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    var earbuds = false
    var spatial = true
    var noise = true
    var wind = true
    var legacy = false
    var unsupported = false
    var crusher = false
    var presets = ["Quiet", "Aware", "Immersion", "Cinema"]
    var customCount = 7

    static let all: [DeviceProfile] = [
        .init(id: "ultra2", name: "QC Ultra Headphones · 2nd Gen"),
        .init(id: "ultra1", name: "QC Ultra Headphones · 1st Gen", presets: ["Quiet", "Aware", "Immersion"]),
        .init(id: "qc2", name: "QC Headphones · 2nd Gen"),
        .init(id: "qc", name: "QC Headphones / QC SC", spatial: false, legacy: true, presets: ["Quiet", "Aware"]),
        .init(id: "qc45", name: "QC45 / QC SE", spatial: false, legacy: true, presets: ["Quiet", "Aware"]),
        .init(id: "buds2", name: "QC Ultra Earbuds · 2nd Gen", earbuds: true),
        .init(id: "buds1", name: "QC Ultra Earbuds · 1st Gen", earbuds: true, presets: ["Quiet", "Aware", "Immersion"]),
        .init(id: "budsII", name: "QC Earbuds II", earbuds: true, spatial: false, legacy: true, presets: ["Quiet", "Aware"], customCount: 2),
        .init(id: "buds2020", name: "QC Earbuds · 2020", earbuds: true, spatial: false, legacy: true, presets: ["Quiet", "Aware"], customCount: 0),
        .init(id: "open", name: "Ultra Open Earbuds · 1st Gen", earbuds: true, noise: false, wind: false, presets: ["Stereo", "Immersion"], customCount: 0),
        .init(id: "open2", name: "Ultra Open Earbuds · 2nd Gen", earbuds: true, noise: false, wind: false, presets: ["Stereo", "Immersion", "Cinema"], customCount: 0),
        .init(id: "nc700", name: "Noise Cancelling Headphones 700", spatial: false, wind: false, legacy: true, presets: [], customCount: 0),
        .init(id: "qc35", name: "QC35 / QC35 II", spatial: false, wind: false, unsupported: true, presets: [], customCount: 0),
        .init(id: "crusher", name: "Skullcandy Crusher 1080 ANC", wind: false, crusher: true, presets: ["Quiet", "Aware", "Off"], customCount: 0)
    ]
}

struct NoiseState: Codable, Equatable {
    var level: Double = 10
    var enabled = true
    var wind = false
    var spatial = 0
}

struct ListeningMode: Identifiable, Codable, Equatable {
    var id: Int
    var name: String
    var builtIn: Bool
    var favorite = false
    var configured = true
    var noise = NoiseState()
}

struct AutomationRule: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var enabled = true
    var trigger: String = "On connection"
    var modeIndex = 0
    var hour = 9
    var minute = 0
    var lastFiredDay: String?
}

struct SavedAppState: Codable {
    var demo = false
    var profileID = "ultra2"
    var modes: [ListeningMode] = []
    var currentMode = 0
    var noise = NoiseState()
    var eq: [Double] = [0, 0, 0]
    var sidetone = 2
    var autoPause = true
    var autoAnswer = false
    var multipoint = true
    var voicePrompts = true
    var touchControls = true
    var autoOff = 20
    var theme = "System"
    var proEnabled = false
    var presetID = "flat"
    var customPresets: [EQPreset] = []
    var boost = 0.0
    var batteryAlert = 20
    var rules: [AutomationRule] = []
}
