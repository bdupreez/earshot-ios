// Earshot by HellzYeahh and contributors (MIT), AI-assisted native iOS adaptation.
import SwiftUI

extension DeviceProfile {
    static var all: [Self] {
        boseProfiles + SoundcoreModel.allCases.map {
            Self(id: "soundcore.\($0.rawValue)", name: $0.displayName, earbuds: $0.earbuds,
                 spatial: false, noise: false, wind: false, unsupported: true, presets: [], customCount: 0)
        } + VendorCatalogue.models.map {
            Self(id: $0.id, name: $0.name, earbuds: $0.earbuds, spatial: false, noise: false,
                 wind: false, unsupported: true, presets: [], customCount: 0)
        }
    }
    var soundcoreModel: SoundcoreModel? {
        guard id.hasPrefix("soundcore.") else { return nil }
        return SoundcoreModel(rawValue: String(id.dropFirst("soundcore.".count)))
    }
    var vendorDefinition: VendorModelDefinition? { VendorCatalogue.model(id: id) }
    var isVendorCatalogue: Bool { soundcoreModel != nil || vendorDefinition != nil }
}

/// A local virtual fixture, deliberately incapable of issuing a Bluetooth request.
struct VendorDemoView: View {
    let model: VendorModelDefinition
    @State private var state: VendorDemoState
    init(model: VendorModelDefinition) { self.model = model; _state = State(initialValue: VendorDemoState(model: model)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InfoNote(text: model.transport.explanation)
            Panel(title: model.name, subtitle: evidenceLabel) {
                Text(model.notes).font(.footnote).foregroundStyle(.secondary)
                ForEach(model.batteryFixture) { reading in
                    LabeledContent("\(reading.id) battery · simulated", value: "\(reading.percent)%")
                }
                ForEach(model.controls) { control in
                    controlView(control)
                    if !control.notes.isEmpty && !control.notes.hasPrefix("Simulated setting") { Text(control.notes).font(.caption).foregroundStyle(.secondary) }
                }
                if model.controls.isEmpty { Text("This catalogue entry has no documented virtual controls. Use the headset companion for local EQ, audio routing and voice memos.").font(.footnote) }
                Button("Reset this virtual device") { state = VendorDemoState(model: model) }
            }
            VendorLabCatalogue(model: model)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("vendorDemo.\(model.id)")
    }
    private var evidenceLabel: String {
        switch model.evidence {
        case .upstreamVirtualFixture: return "SIMULATED · upstream virtual fixture"
        case .catalogueIllustration: return "SIMULATED · catalogue illustration"
        case .noVendorControls: return "SIMULATED · no vendor controls"
        }
    }
    @ViewBuilder private func controlView(_ control: VendorControlDefinition) -> some View {
        switch control.kind {
        case .toggle:
            Toggle(control.title, isOn: Binding(get: { state[control.id]?.boolValue ?? false }, set: { _ = state.set(.boolean($0), for: control.id) }))
                .accessibilityIdentifier("vendorControl.\(control.id)")
        case .choice(let choices):
            VStack(alignment: .leading, spacing: 4) {
                Text(control.title).font(.subheadline.weight(.medium))
                Picker(control.title, selection: Binding(get: { state[control.id]?.optionValue ?? "" }, set: { _ = state.set(.option($0), for: control.id) })) {
                    ForEach(choices) { Text($0.title).tag($0.id) }
                }.labelsHidden().accessibilityLabel(control.title)
                    .accessibilityValue(choices.first { $0.id == state[control.id]?.optionValue }?.title ?? "Not reported")
                    .accessibilityIdentifier("vendorControl.\(control.id)")
            }
        case .integerRange(let range):
            VStack(alignment: .leading) {
                LabeledContent(control.title, value: "\(state[control.id]?.integerValue ?? range.lowerBound)\(control.unit)")
                Slider(value: Binding(get: { Double(state[control.id]?.integerValue ?? range.lowerBound) }, set: { _ = state.set(.integer(Int($0.rounded())), for: control.id) }), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .accessibilityLabel(control.title).accessibilityIdentifier("vendorControl.\(control.id)")
            }
        }
    }
}

struct VendorLabCatalogue: View {
    let model: VendorModelDefinition
    var body: some View {
        Panel(title: "Protocol research · read-only catalogue") {
            Text("These documented upstream queries are reference material. This screen sends no packets and makes no physical support claim.").font(.footnote).foregroundStyle(.secondary)
            ForEach(model.labGroups) { group in
                Text(group.title).font(.headline)
                ForEach(group.reads) { read in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(read.id) · \(read.title)").font(.subheadline)
                        Text(read.requirement).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(model.sourcePaths, id: \.self) { path in
                if let url = URL(string: "https://github.com/HellzYeahh/earshot/blob/\(VendorCatalogue.upstreamCommit)/\(path)") {
                    Link("Original research: \(path)", destination: url).font(.caption)
                }
            }
            Text("Original Earshot: HellzYeahh and contributors · MIT. See About for full research credits.").font(.caption)
        }
    }
}

struct VendorCatalogueView: View {
    var body: some View {
        List {
            Section {
                Text("Model awareness and local demos do not establish a control connection. iOS cannot use the Classic RFCOMM drivers shipped by upstream. Battery reads, when available, are a separate read-only feature.").font(.footnote)
            }
            Section("Soundcore · 35 documented models") {
                ForEach(SoundcoreModel.allCases) { model in
                    NavigationLink(model.displayName) { Page { SoundcoreDemoView(model: model) }.navigationTitle(model.displayName).navigationBarTitleDisplayMode(.inline) }
                }
            }
            ForEach([HeadsetVendor.sennheiser, .sony, .skullcandy, .apple, .generic], id: \.self) { vendor in
                Section(vendor.rawValue.capitalized) {
                    ForEach(VendorCatalogue.models.filter { $0.vendor == vendor }) { model in
                        NavigationLink(model.name) { Page { VendorDemoView(model: model) }.navigationTitle(model.name).navigationBarTitleDisplayMode(.inline) }
                    }
                }
            }
        }.navigationTitle("Vendor catalogue").navigationBarTitleDisplayMode(.inline)
    }
}
