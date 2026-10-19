import SwiftUI
import UniformTypeIdentifiers
import Charts

struct SoundView: View {
    @EnvironmentObject var store: AppStore
    @State private var page = 0
    @State private var importKind = 0
    @State private var importing = false
    @State private var editing: EQPreset?
    @State private var exporting = false
    @State private var exportDocument = PresetDocument(text: "")
    var body: some View {
        Page {
            Text("Find your frequency.").font(.title2.weight(.bold))
            Picker("Equalizer", selection: $page) { Text("Headphone EQ").tag(0); Text("Pro EQ").tag(1) }.pickerStyle(.segmented)
            if page == 0 {
                Panel(title: "A little more you", subtitle: "Saved on your headphones. Applies to every audio source.") {
                    ForEach(0..<3) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(["Bass", "Mid", "Treble"][index]).font(.headline); Spacer(); Text(String(format: "%+.0f dB", store.saved.eq[index])).monospacedDigit().foregroundStyle(Color.earshot) }
                            Slider(value: Binding(get: { store.saved.eq[index] }, set: { store.setEQ(index, value: $0) }), in: -10...10, step: 1).accessibilityLabel(["Bass", "Mid", "Treble"][index])
                        }
                    }.disabled(!store.connected || !store.supports(1, 7) || store.profile.unsupported)
                    Button("Reset headphone EQ") { for index in 0..<3 { store.setEQ(index, value: 0) } }.disabled(!store.connected || !store.supports(1, 7))
                }
            } else {
                InfoNote(text: "Pro EQ processes audio played inside Earshot. iOS does not let this app equalize Spotify, Apple Music, calls, or other apps.")
                Panel {
                    Toggle("Enable Pro EQ", isOn: $store.saved.proEnabled).font(.headline).onChange(of: store.saved.proEnabled) { _, _ in store.applyAudio() }
                    Picker("Preset", selection: Binding(get: { store.saved.presetID }, set: { store.choosePreset($0) })) { ForEach(store.presets) { preset in Text(preset.name).tag(preset.id) } }.accessibilityIdentifier("presetPicker")
                    EQChart(preset: store.preset)
                    if let description = store.preset.description { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                    HStack { Label(String(format: "Preamp %.1f dB", store.preset.preampDb), systemImage: "waveform"); Spacer(); Label("Limiter on", systemImage: "checkmark.shield") }.font(.caption).foregroundStyle(.secondary)
                    Button("Edit a copy") { editing = store.preset }.buttonStyle(.bordered).accessibilityIdentifier("editPreset")
                    HStack { Button("Import preset") { importKind = 1; importing = true }; Spacer(); Button("Export preset") { do { exportDocument = PresetDocument(text: try PresetCodec.encodePresets([store.preset])); exporting = true } catch { store.message = error.localizedDescription } } }
                }
                Panel(title: "Local player") { LocalPlayerView(engine: store.audio) { importKind = 0; importing = true } }
                Panel(title: "Volume boost") {
                    HStack { Text("Added gain"); Spacer(); Text(String(format: "+%.0f dB", store.saved.boost)).monospacedDigit() }
                    Slider(value: $store.saved.boost, in: 0...12, step: 1).onChange(of: store.saved.boost) { _, _ in store.applyAudio() }
                    Text("Start with low device volume. Boost increases loudness and the limiter reduces peaks. Pro EQ and boost apply only to Earshot’s local player.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Sound")
            .fileImporter(isPresented: $importing, allowedContentTypes: importKind == 0 ? [.audio] : [.json, .plainText, .text]) { result in
                do {
                    let url = try result.get()
                    if importKind == 0 { try store.audio.load(url: url); store.applyAudio() }
                    else {
                        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let text = try String(contentsOf: url, encoding: .utf8)
                        let presets = try PresetCodec.importPresets(text: text, name: url.deletingPathExtension().lastPathComponent)
                        for preset in presets { store.savePreset(preset) }
                    }
                } catch { store.message = error.localizedDescription }
            }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "Earshot-preset.json") { result in if case .failure(let error) = result { store.message = error.localizedDescription } }
            .sheet(item: $editing) { PresetEditor(preset: $0) }
    }
}

struct EQChart: View {
    let preset: EQPreset
    var body: some View {
        let points = EQResponse(bands: preset.bands, preampDb: 0).sample(nPoints: 160)
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            AreaMark(x: .value("Frequency", point.frequencyHz), yStart: .value("Zero", 0), yEnd: .value("Gain", point.gainDb)).foregroundStyle(LinearGradient(colors: [.earshot.opacity(0.2), .earshot.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Frequency", point.frequencyHz), y: .value("Gain", point.gainDb)).foregroundStyle(Color.earshot).lineStyle(StrokeStyle(lineWidth: 2.5))
        }.chartXScale(domain: 20.0...20000.0, type: .log).chartYScale(domain: -15.0...15.0)
            .chartXAxis { AxisMarks(values: [20.0, 100, 1000, 10000]) { value in AxisGridLine(); AxisValueLabel { if let f = value.as(Double.self) { Text(f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))") } } } }
            .chartYAxis { AxisMarks(values: [-12.0, 0, 12]) }
            .frame(height: 170).accessibilityLabel("Equalizer frequency response, \(preset.name)")
    }
}

struct LocalPlayerView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var engine: LocalAudioEngine
    let importAudio: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(engine.fileName.isEmpty ? "Bring a track from Files" : engine.fileName).font(.headline)
            Text(engine.status).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { engine.playPause() } label: { Label(engine.isPlaying ? "Pause" : "Play", systemImage: engine.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.borderedProminent).disabled(!engine.hasFile).accessibilityIdentifier("playAudio")
                Button("Open audio", action: importAudio).buttonStyle(.bordered)
            }
            Button("Load listening sample") { do { try engine.loadDemo() } catch { store.message = error.localizedDescription } }.font(.footnote).accessibilityIdentifier("loadSample")
        }
    }
}

struct PresetEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var preset: EQPreset
    @State private var graphic = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") { TextField("Name", text: $preset.name); Toggle("10-band graphic layout", isOn: $graphic).onChange(of: graphic) { _, value in if value { preset.bands = GraphicEQ.flatBands } }; EQChart(preset: preset) }
                Section("Filters") {
                    ForEach(preset.bands.indices, id: \.self) { index in
                        DisclosureGroup("\(Int(preset.bands[index].frequencyHz)) Hz · \(String(format: "%+.1f", preset.bands[index].gainDb)) dB") {
                            Toggle("Enabled", isOn: $preset.bands[index].enabled)
                            HStack { Text("Gain"); Slider(value: $preset.bands[index].gainDb, in: -15...15, step: 0.5) }
                            if !graphic {
                                HStack { Text("Frequency (Hz)"); TextField("Frequency", value: $preset.bands[index].frequencyHz, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                                HStack { Text("Q"); Slider(value: $preset.bands[index].q, in: 0.1...10, step: 0.1); Text(String(format: "%.1f", preset.bands[index].q)) }
                                Picker("Type", selection: $preset.bands[index].type) { ForEach(EQFilterType.allCases, id: \.self) { Text($0.label).tag($0) } }
                            }
                        }
                    }
                    if !graphic && preset.bands.count < 10 { Button("Add filter") { preset.bands.append(EQBand(frequencyHz: 1000, gainDb: 0)) } }
                }
                Section { Text("Saving calculates headroom automatically. Graphic layout starts from ten flat bands.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Edit preset").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { preset.preampDb = Headroom.recommendedPreampDb(bands: preset.bands); store.savePreset(preset); dismiss() }.disabled(preset.name.trimmingCharacters(in: .whitespaces).isEmpty || preset.bands.contains { !$0.frequencyHz.isFinite || !(20...20000).contains($0.frequencyHz) }) } }
        }
    }
}

struct PresetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}
