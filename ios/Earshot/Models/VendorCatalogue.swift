import Foundation

// AI-assisted native port of Earshot by HellzYeahh and contributors (MIT).
// Facts and demo fixtures: upstream 9e6c4912531ec6e159eded862d1b6ffa55094199,
// protocol/{sennheiser,sony,bragi,apple}, service/*StateMapping.kt, virtual/Virtual*.kt.
// Sennheiser references: momentum4-control (Ariazonaa), momentumctl (Galen Abell), MIT.
// Sony references: SonyHeadphonesClient (mos9527, Amr Satrio and contributors), MIT.
// This file contains no live transport, wire writer or claim of hardware compatibility.

enum HeadsetVendor: String, Codable, CaseIterable, Sendable {
    case bose, sennheiser, sony, skullcandy, apple, generic
}

enum VendorTransportAvailability: String, Codable, Sendable {
    case classicRFCOMMUnsupported, boseVerifiedL2CAP, batteryServiceReadOnly, systemAudioRouteOnly

    var explanation: String {
        switch self {
        case .classicRFCOMMUnsupported:
            return "The upstream driver uses Classic RFCOMM. This iOS app has no public transport for it. Controls below are simulated in demo only."
        case .boseVerifiedL2CAP:
            return "Physical control requires a discovered Bose LE channel and a verified BMAP response. A catalogue entry does not establish a connection."
        case .batteryServiceReadOnly:
            return "A selected BLE peripheral may expose the standard Battery Service. Reading its battery does not establish headphone control."
        case .systemAudioRouteOnly:
            return "The system may expose an audio route. Vendor controls and telemetry are unavailable unless a separately supported interface supplies them."
        }
    }
}

struct VendorChoice: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
}

enum VendorControlValue: Codable, Equatable, Sendable {
    case boolean(Bool), integer(Int), option(String)

    var boolValue: Bool? { if case .boolean(let value) = self { return value }; return nil }
    var integerValue: Int? { if case .integer(let value) = self { return value }; return nil }
    var optionValue: String? { if case .option(let value) = self { return value }; return nil }
}

enum VendorControlKind: Codable, Equatable, Sendable {
    case toggle, choice([VendorChoice]), integerRange(ClosedRange<Int>)
}

struct VendorControlDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: VendorControlKind
    let initialValue: VendorControlValue
    var notes: String = "Simulated setting. Physical support requires actual device evidence."
    var unit: String = ""

    func accepts(_ value: VendorControlValue) -> Bool {
        switch (kind, value) {
        case (.toggle, .boolean): return true
        case (.choice(let choices), .option(let id)): return choices.contains { $0.id == id }
        case (.integerRange(let range), .integer(let number)): return range.contains(number)
        default: return false
        }
    }
}

/// Documentation only. These records intentionally do not expose executable packet bytes.
struct VendorDocumentedRead: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let requirement: String
}

struct VendorLabGroup: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let reads: [VendorDocumentedRead]
}

enum VendorDemoEvidence: String, Codable, Sendable {
    case upstreamVirtualFixture, catalogueIllustration, noVendorControls
}

struct VendorBatteryFixture: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let percent: Int
    var charging: Bool = false
}

struct VendorModelDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let vendor: HeadsetVendor
    let transport: VendorTransportAvailability
    let earbuds: Bool
    let evidence: VendorDemoEvidence
    let sourcePaths: [String]
    let documentedCapabilities: [String]
    let controls: [VendorControlDefinition]
    let labGroups: [VendorLabGroup]
    var batteryFixture: [VendorBatteryFixture] = []
    var notes: String = "Catalogue and demo values do not prove physical support."

    func control(id: String) -> VendorControlDefinition? { controls.first { $0.id == id } }
    var documentedReadCount: Int { labGroups.reduce(0) { $0 + $1.reads.count } }
    var physicalControlAvailable: Bool { false } // A catalogue must never substitute for protocol verification.
}

/// Local demo state only; no Bluetooth objects or callbacks are retained here.
struct VendorDemoState: Codable, Equatable, Sendable {
    private(set) var modelID: String
    private(set) var values: [String: VendorControlValue]
    private var levelBeforeTransparency: Int?

    init(model: VendorModelDefinition) {
        modelID = model.id
        values = Dictionary(uniqueKeysWithValues: model.controls.map { ($0.id, $0.initialValue) })
    }

    subscript(_ id: String) -> VendorControlValue? { values[id] }

    /// Validate restored or edited data against the selected model, without inventing settings.
    mutating func reconcile(with model: VendorModelDefinition) {
        guard modelID == model.id else { self = Self(model: model); return }
        values = Dictionary(uniqueKeysWithValues: model.controls.map { control in
            let stored = values[control.id]
            return (control.id, stored.flatMap { control.accepts($0) ? $0 : nil } ?? control.initialValue)
        })
        if let levelBeforeTransparency, !(0...100).contains(levelBeforeTransparency) { self.levelBeforeTransparency = nil }
    }

    @discardableResult
    mutating func set(_ value: VendorControlValue, for id: String, model: VendorModelDefinition? = nil) -> Bool {
        guard let model = model ?? VendorCatalogue.model(id: modelID), model.id == modelID,
              let control = model.control(id: id), control.accepts(value) else { return false }
        let oldMode = values["mode"]?.optionValue
        let oldLevel = values["noiseLevel"]?.integerValue
        values[id] = value
        // Captured Momentum4 behavior: enabling transparency reaches100 and restores the old
        // slider on exit; enabling ANC or changing its mode table returns to full ANC.
        if model.vendor == .sennheiser, model.control(id: "noiseLevel") != nil {
            if id == "mode", case .option(let mode) = value {
                if mode == "transparency" {
                    if oldMode != "transparency" { levelBeforeTransparency = oldLevel }
                    values["noiseLevel"] = .integer(100)
                } else if mode == "anc" {
                    values["noiseLevel"] = .integer(0)
                } else if oldMode == "transparency", let previous = levelBeforeTransparency {
                    values["noiseLevel"] = .integer(previous)
                }
            } else if ["antiWind", "adaptive", "comfort"].contains(id) {
                values["mode"] = .option("anc"); values["noiseLevel"] = .integer(0)
            }
        }
        // Sony's fixture keeps user slots when editing bands; stock presets become Manual.
        if model.id == "sony.wh1000xm5" {
            if id.hasPrefix("eqBand"), let preset = values["eqPreset"]?.optionValue,
               !["a0", "a1", "a2"].contains(preset) { values["eqPreset"] = .option("a0") }
            if id == "eqPreset", case .option(let preset) = value,
               let bands = Self.sonyFixtureBands[preset] {
                for (index, band) in bands.enumerated() { values["eqBand\(index)"] = .integer(band) }
            }
        }
        return true
    }

    private static let sonyFixtureBands = [
        "00": [0, 0, 0, 0, 0, 0], "10": [0, -1, 0, 2, 4, 5],
        "16": [6, 4, 1, 0, 0, 0], "14": [0, -2, 2, 4, 2, 0]
    ]
}

enum VendorCatalogue {
    static let upstreamCommit = "9e6c4912531ec6e159eded862d1b6ffa55094199"
    static let models = sennheiserModels + sonyModels + methodModels + appleModels + genericModels
    static func model(id: String) -> VendorModelDefinition? { models.first { $0.id == id } }

    private static func toggle(_ id: String, _ title: String, _ initial: Bool, notes: String? = nil) -> VendorControlDefinition {
        .init(id: id, title: title, kind: .toggle, initialValue: .boolean(initial),
              notes: notes ?? "Simulated setting; physical support must come from device reports.")
    }
    private static func choice(_ id: String, _ title: String, _ options: [(String, String)], _ initial: String) -> VendorControlDefinition {
        .init(id: id, title: title, kind: .choice(options.map { .init(id: $0.0, title: $0.1) }), initialValue: .option(initial))
    }
    private static func range(_ id: String, _ title: String, _ bounds: ClosedRange<Int>, _ initial: Int, unit: String = "") -> VendorControlDefinition {
        .init(id: id, title: title, kind: .integerRange(bounds), initialValue: .integer(initial), unit: unit)
    }
    private static func group(_ id: String, _ title: String, _ reads: [(String, String)], requirement: String) -> VendorLabGroup {
        .init(id: id, title: title, reads: reads.map { .init(id: $0.0, title: $0.1, requirement: requirement) })
    }

    private static let sennheiserModels: [VendorModelDefinition] = [
        ("momentum4", "MOMENTUM 4", "slider"), ("momentum5", "MOMENTUM 5", "slider"),
        ("accentumPlus", "ACCENTUM Plus", "slider"), ("accentum", "ACCENTUM", "toggles"),
        ("momentumTW3", "MOMENTUM True Wireless 3", "earbuds"), ("momentumTW4", "MOMENTUM True Wireless 4", "earbuds"),
        ("accentumTW", "ACCENTUM True Wireless", "earbuds"), ("momentumSport", "MOMENTUM Sport", "earbuds")
    ].map { slug, name, family in
        let earbuds = family == "earbuds"
        var controls = [choice("mode", "Listening mode", [("anc", "Noise cancelling"), ("transparency", "Transparency"), ("off", "Off")], "anc")]
        if family == "slider" {
            controls += [range("noiseLevel", "ANC to transparency", 0...100, 0),
                         toggle("adaptive", "Adaptive noise cancelling", false),
                         choice("antiWind", "Anti-wind", [("off", "Off"), ("max", "Max"), ("auto", "Auto")], "max"),
                         toggle("comfort", "Comfort mode", false, notes: "Simulated Sennheiser comfort setting; its exact physical effect is unconfirmed.")]
        } else if earbuds {
            controls += [toggle("antiWind", "Anti-wind", true),
                         choice("transparencyLevel", "Transparency level", [("1", "Low"), ("50", "Medium"), ("100", "High")], "100")]
        }
        controls += [toggle("pauseInTransparency", "Pause music in transparency", false)]
        if !earbuds { controls += [toggle("onHead", "On-head detection", true)] }
        if family != "toggles" { controls += [toggle("smartPause", "Smart pause", true)] }
        controls += [toggle("autoAnswer", "Auto-answer calls", false)]
        if !earbuds { controls += [toggle("comfortCall", "Comfort call", true)] }
        controls += [choice("sidetone", "Sidetone", [("off", "Off"), ("low", "Low"), ("high", "High")], "high"),
                     choice("autoOff", "Auto power off", [("0", "Never"), ("900", "15 min"), ("1800", "30 min"), ("3600", "1 h")], "900")]
        if ["momentum4", "momentum5"].contains(slug) {
            controls += [toggle("bassBoost", "Bass boost", false, notes: "Simulated generation-2 EQ. Physical EQ requires a compatible feature-version/configuration reply.")]
            for band in 0..<(slug == "momentum5" ? 8 : 5) { controls.append(range("eqBand\(band)", "EQ band \(band + 1)", -6...6, 0, unit: "dB")) }
        }
        return VendorModelDefinition(id: "sennheiser." + slug, name: "Sennheiser " + name, vendor: .sennheiser,
            transport: .classicRFCOMMUnsupported, earbuds: earbuds, evidence: slug == "momentum4" ? .upstreamVirtualFixture : .catalogueIllustration,
            sourcePaths: ["protocol/src/main/kotlin/dev/earshot/protocol/sennheiser/SennheiserModel.kt", "app/src/main/kotlin/dev/earshot/service/SennheiserStateMapping.kt", "app/src/main/kotlin/dev/earshot/virtual/VirtualSennheiser.kt"],
            documentedCapabilities: ["GAIA v3 model/feature-dependent controls", "Battery and firmware", "Generation-2 EQ only after compatible configuration reply"],
            controls: controls, labGroups: sennheiserLab(earbuds: earbuds, slider: family == "slider"),
            batteryFixture: [.init(id: earbuds ? "Left" : "Headphones", percent: 80)],
            notes: slug == "momentum4" ? "Simulated Momentum 4 fixture; firmware3.37.3 behavior from upstream MIT references. This is not a physical connection." : "Model-declared settings illustrated with simulated values. Actual hardware must announce its features; no iOS RFCOMM transport is available.")
    }

    private static func sennheiserLab(earbuds: Bool, slider: Bool) -> [VendorLabGroup] {
        let requirement = "Documented GET only; requires reported GAIA feature/version and a supported transport. Metadata here sends nothing."
        var groups = [
            group("discovery", "Discovery", [("001d.0000", "Qualcomm API version"), ("001d.0001", "Qualcomm feature list"), ("0495.0001", "Sennheiser feature list")], requirement: requirement),
            group("device", "Device", [("0495.0402", "Wear state")] + (earbuds ? [] : [("0495.0401", "On-head detection")]), requirement: requirement),
            group("power", "Battery and power", [("0495.0601", "Auto power-off"), ("0495.0602", "Charging"), ("0495.0603", "Battery")], requirement: requirement),
            group("audio", "Generic audio", [("0495.0806", "Sidetone"), ("0495.080b", "Auto answer"), ("0495.080d", "Smart pause")] + (earbuds ? [] : [("0495.0815", "Comfort call")]), requirement: requirement),
            group("eq", "Generation-2 EQ", [("0495.1000", "EQ configuration"), ("0495.1003", "EQ gains"), ("0495.1009", "Bass boost")], requirement: requirement),
            group("versions", "Versions", [("0495.1201", "Firmware"), ("0495.1206", "Model and colour")], requirement: requirement),
            group("transparency", "Transparent hearing", [("0495.1801", "Pause music"), ("0495.1805", "Transparency")] + (earbuds ? [("0495.1803", "Transparency level")] : []), requirement: requirement)
        ]
        groups.append(group("anc", "Noise cancelling", [("0495.1a05", "ANC")] + (slider ? [("0495.1a01", "ANC mode table"), ("0495.1a03", "ANC level")] : []), requirement: requirement))
        return groups
    }

    private static let sonyModels: [VendorModelDefinition] = [
        ("wh1000xm5", "WH-1000XM5", false), ("wh1000xm6", "WH-1000XM6", false),
        ("wf1000xm4", "WF-1000XM4", true), ("wf1000xm5", "WF-1000XM5", true), ("wf1000xm6", "WF-1000XM6", true),
        ("linkbuds", "LinkBuds", true), ("linkbudsOpen", "LinkBuds Open", true), ("linkbudsS", "LinkBuds S", true), ("linkbudsClip", "LinkBuds Clip", true),
        ("ultWear", "ULT WEAR", false), ("whch720n", "WH-CH720N", false),
        ("wfc510", "WF-C510", true), ("wfc700n", "WF-C700N", true), ("wfc710n", "WF-C710N", true)
    ].map { slug, name, earbuds in
        let fixture = slug == "wh1000xm5"
        return VendorModelDefinition(id: "sony." + slug, name: "Sony " + name, vendor: .sony,
            transport: .classicRFCOMMUnsupported, earbuds: earbuds, evidence: fixture ? .upstreamVirtualFixture : .noVendorControls,
            sourcePaths: ["protocol/src/main/kotlin/dev/earshot/protocol/sony/SonyModel.kt", "app/src/main/kotlin/dev/earshot/virtual/VirtualSony.kt", "app/src/main/kotlin/dev/earshot/service/SonyStateMapping.kt"],
            documentedCapabilities: ["MDR v2; capabilities depend on actual support lists", "Model name alone does not authorize noise control, EQ or other settings"],
            controls: fixture ? sonyFixtureControls : [], labGroups: fixture ? sonyFixtureLab : [sonyFixtureLab[0]],
            batteryFixture: fixture ? [.init(id: "Headphones", percent: 70)] : [],
            notes: fixture ? "Simulated WH-1000XM5; upstream itself describes its exact capability list as a best guess, rather than a captured XM5. No hardware claim." : "Catalogue entry only. Use the explicit WH-1000XM5 demo fixture to explore source-backed example controls; other Sony models require their own capability replies.")
    }

    private static var sonyFixtureControls: [VendorControlDefinition] {
        var controls = [choice("mode", "Listening mode", [("anc", "Noise cancelling"), ("ambient", "Ambient sound"), ("off", "Off")], "anc"),
                        range("ambientLevel", "Ambient sound level", 1...20, 15), toggle("focusOnVoice", "Focus on voice", false),
                        choice("eqPreset", "Equalizer", [("00", "Off"), ("10", "Bright"), ("11", "Excited"), ("12", "Mellow"), ("13", "Relaxed"), ("14", "Vocal"), ("15", "Treble boost"), ("16", "Bass boost"), ("17", "Speech"), ("a0", "Manual"), ("a1", "Custom 1"), ("a2", "Custom 2")], "00")]
        for (index, name) in ["Clear Bass", "400 Hz", "1 kHz", "2.5 kHz", "6.3 kHz", "16 kHz"].enumerated() {
            controls.append(range("eqBand\(index)", name, -10...10, 0, unit: "dB"))
        }
        controls += [choice("autoOff", "Auto power off", [("00", "5 min"), ("01", "30 min"), ("02", "1 hour"), ("03", "3 hours"), ("10", "When taken off"), ("11", "Off")], "10"),
                     toggle("speakToChat", "Speak-to-chat", false), toggle("pauseWhenTakenOff", "Pause when taken off", true),
                     toggle("dsee", "DSEE", true), choice("connectionPriority", "Bluetooth connection", [("quality", "Sound quality"), ("stable", "Stable connection")], "quality"),
                     toggle("voiceGuidance", "Voice guidance", true), toggle("multipoint", "Multipoint", true), toggle("touchControls", "Touch controls", true)]
        return controls
    }

    private static let sonyFixtureLab: [VendorLabGroup] = {
        let requirement = "Documented MDR v2 GET inquiry only, gated by reported support lists. Metadata sends nothing."
        return [
            group("connect", "Connect", [("t1.protocol", "Protocol info"), ("t1.capability", "Capability info"), ("t1.model", "Model name"), ("t1.firmware", "Firmware"), ("t1.series", "Series and colour"), ("t1.functions", "Support functions")], requirement: requirement),
            group("power", "Power and battery", [("t1.battery", "Battery"), ("t1.autoOffChoices", "Auto power-off choices"), ("t1.autoOff", "Auto power-off")], requirement: requirement),
            group("eq", "Equalizer", [("t1.eqCapability", "EQ capability"), ("t1.eqState", "EQ preset and bands")], requirement: requirement),
            group("noise", "Noise cancelling and ambient", [("t1.ncCapability", "Ambient range"), ("t1.ncState", "Noise control")], requirement: requirement),
            group("general", "General settings", [("t1.generalNames", "Reported setting names"), ("t1.generalValues", "Reported setting values")], requirement: requirement),
            group("audio", "Audio", [("t1.dseeType", "DSEE type"), ("t1.dsee", "DSEE"), ("t1.connection", "Connection priority")], requirement: requirement),
            group("system", "System", [("t1.wear", "Pause when taken off"), ("t1.talk", "Speak-to-chat")], requirement: requirement),
            group("voice", "Voice guidance", [("t2.functions", "Table-2 support functions"), ("t2.voice", "Voice guidance")], requirement: requirement)
        ]
    }()

    private static let methodModels: [VendorModelDefinition] = [("method360", "Method 360 ANC", 74), ("method540", "Method 540 ANC", 81)].map { slug, name, battery in
        VendorModelDefinition(id: "skullcandy." + slug, name: "Skullcandy " + name, vendor: .skullcandy,
            transport: .classicRFCOMMUnsupported, earbuds: true, evidence: .upstreamVirtualFixture,
            sourcePaths: ["protocol/src/main/kotlin/dev/earshot/protocol/bragi/BragiModel.kt", "protocol/src/main/kotlin/dev/earshot/protocol/bragi/BragiReads.kt", "app/src/main/kotlin/dev/earshot/virtual/VirtualCrusher.kt"],
            documentedCapabilities: ["Quiet / Aware / Off", "Noise gain", "Sidetone", "Battery", "No Crusher bass or spatial-audio service"],
            controls: [choice("mode", "Listening mode", [("quiet", "Quiet"), ("aware", "Aware"), ("off", "Off")], "quiet"), range("quietGain", "Quiet level", 0...10, 7), range("awareGain", "Aware level", 0...10, 5), toggle("sidetoneEnabled", "Sidetone", true), range("sidetoneVolume", "Sidetone level", 0...5, 3)],
            labGroups: [group("device", "Device", [("2.1", "Device info"), ("2.2", "System info"), ("2.3", "Battery"), ("2.4", "Device mode info"), ("2.5", "Time")], requirement: "Documented read-only BOS-RPC metadata; no transport or authentication action."),
                        group("hearing", "Hearing", [("4.1", "Hearing mode"), ("4.3", "Hearing mode info"), ("4.4", "PEQ state"), ("4.5", "PEQ configuration"), ("4.6", "PEQ info"), ("4.10", "Sidetone"), ("4.12", "Sidetone info")], requirement: "Documented reads only; no configure/set/subscription/pairing calls.")],
            batteryFixture: [.init(id: "Earbuds", percent: battery)], notes: "Simulated upstream Method fixture. Gain and sidetone ranges are fixture values; real devices would have to report their own ranges. No Crusher-only controls or live iOS Bragi transport.")
    }

    private static let appleModels: [VendorModelDefinition] = [
        ("airpods", "AirPods", true), ("airpods2", "AirPods (2nd generation)", true), ("airpods3", "AirPods (3rd generation)", true),
        ("airpodsPro", "AirPods Pro", true), ("airpodsPro2", "AirPods Pro (2nd generation)", true), ("airpodsPro2USB", "AirPods Pro (2nd generation, USB-C)", true),
        ("airpodsMax", "AirPods Max", false), ("powerbeats3", "Powerbeats3", true), ("powerbeatsPro", "Powerbeats Pro", true), ("powerbeats4", "Powerbeats4", true),
        ("beatsX", "BeatsX", true), ("solo3", "Beats Solo3", false), ("studio3", "Beats Studio3", false), ("soloPro", "Beats Solo Pro", false),
        ("flex", "Beats Flex", true), ("studioBuds", "Beats Studio Buds", true), ("fitPro", "Beats Fit Pro", true), ("studioBudsPlus", "Beats Studio Buds+", true), ("studioPro", "Beats Studio Pro", false)
    ].map { slug, name, earbuds in
        VendorModelDefinition(id: "apple." + slug, name: name, vendor: .apple, transport: .systemAudioRouteOnly,
            earbuds: earbuds, evidence: slug == "airpodsPro" ? .upstreamVirtualFixture : .noVendorControls,
            sourcePaths: ["protocol/src/main/kotlin/dev/earshot/protocol/apple/ContinuityAdvert.kt", "app/src/main/kotlin/dev/earshot/virtual/DemoMode.kt"],
            documentedCapabilities: ["Upstream manufacturer-advert battery parser only", "No noise modes or vendor controls", "Public iOS advertisement delivery and ownership association unverified"],
            controls: [], labGroups: [], batteryFixture: slug == "airpodsPro" ? [.init(id: "Left", percent: 90), .init(id: "Right", percent: 80), .init(id: "Case", percent: 60, charging: true)] : [],
            notes: "No Apple private API is used. Nearby advertisements do not prove which audio route owns a battery reading; shown fixture values are simulated.")
    }

    private static let genericModels: [VendorModelDefinition] = [
        ("headset", "Other headset", "No upstream vendor driver; current audio route and Earshot's local player are separate from vendor control."),
        ("sonyWH1000XM4", "Sony WH-1000XM4 (MDR v1)", "Upstream deliberately leaves MDR v1 generic; no MDR v2 settings are assumed."),
        ("boseQCE2024", "Bose QuietComfort Earbuds (2024)", "Upstream issue#1 identifies this as a different protocol; do not probe it as Bose BMAP."),
        ("sennheiserCXPlus", "Sennheiser CX Plus True Wireless", "Upstream BLE-only model has no GAIA v3 driver; no vendor characteristic is guessed."),
        ("sennheiserCX500", "Sennheiser CX 500BT", "Upstream BLE-only model has no GAIA v3 driver; generic until a separately documented interface exists.")
    ].map { slug, name, note in
        VendorModelDefinition(id: "generic." + slug, name: name, vendor: .generic, transport: .systemAudioRouteOnly,
            earbuds: slug != "sonyWH1000XM4" && slug != "headset", evidence: .noVendorControls,
            sourcePaths: ["docs/supported-headsets.md", "app/src/main/kotlin/dev/earshot/bt/DeviceFamily.kt"],
            documentedCapabilities: ["Current system audio route", "Earshot local audio playback and local Pro EQ", "Optional standard BAS read only when actually discovered"], controls: [], labGroups: [], notes: note)
    }
}
