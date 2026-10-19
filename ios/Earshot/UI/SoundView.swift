import SwiftUI
import UniformTypeIdentifiers
import Charts
import AVKit

struct SoundView: View {
    @EnvironmentObject var store: AppStore
    @State private var page = 0
    @State private var importKind = 0
    @State private var importing = false
    @State private var editing: EQPreset?
    @State private var exporting = false
    @State private var exportDocument = PresetDocument(text: "")
    @State private var exportType = UTType.json
    @State private var exportName = "Earshot-preset.json"
    @State private var renaming = false
    @State private var renameText = ""
    @State private var deleting = false
    @State private var pasting = false
    @State private var presetActionTarget: EQPreset?
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
                    Toggle("Enable Pro EQ", isOn: $store.saved.proEnabled).font(.headline).onChange(of: store.saved.proEnabled) { _, enabled in if !enabled { store.audio.setBypassed(false) }; store.applyAudio() }
                    Picker("Preset", selection: Binding(get: { store.saved.presetID }, set: { store.choosePreset($0) })) { ForEach(store.presets) { preset in Text(preset.name).tag(preset.id) } }.accessibilityIdentifier("presetPicker")
                    EQChart(preset: store.preset)
                    if let description = store.preset.description { Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                    HStack { Label(String(format: "Preamp %.1f dB", store.effectiveAudioPreamp), systemImage: "waveform"); Spacer(); Label(store.saved.audioOptions.limiterEnabled ? "Limiter on" : "Limiter off", systemImage: store.saved.audioOptions.limiterEnabled ? "checkmark.shield" : "shield.slash") }.font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(store.preset.isBuiltIn ? "Edit a copy" : "Edit preset") { editing = store.preset }.buttonStyle(.bordered).accessibilityIdentifier("editPreset")
                        Spacer()
                        Menu("Manage preset") {
                            Button("Duplicate") { do { _ = try store.createUserPreset(store.preset) } catch { store.message = error.localizedDescription } }
                            if !store.preset.isBuiltIn {
                                Button("Rename") { presetActionTarget = store.preset; renameText = store.preset.name; renaming = true }
                                Button("Delete preset", role: .destructive) { presetActionTarget = store.preset; deleting = true }
                            }
                        }.accessibilityIdentifier("managePreset")
                    }
                    HStack { Button("Import preset") { importKind = 1; importing = true }; Spacer(); Button("Paste AutoEQ") { pasting = true } }
                    Menu("Export preset") {
                        Button("Earshot JSON") { prepareExport(autoEQ: false) }
                        Button("AutoEQ text") { prepareExport(autoEQ: true) }
                    }
                    if let recoveryURL = PresetRecovery.latestBackupURL {
                        ShareLink(item: recoveryURL) { Label("Export recovered preset data", systemImage: "square.and.arrow.up") }.font(.caption)
                    }
                }
                preampPanel
                Panel(title: "Local player") { LocalPlayerView(engine: store.audio) { importKind = 0; importing = true } }
                Panel(title: "Volume boost") {
                    HStack { Text("Added gain"); Spacer(); Text(String(format: "+%.0f dB", store.saved.boost)).monospacedDigit() }
                    Slider(value: $store.saved.boost, in: 0...Headroom.effectiveBoostCapDb(limiterEnabled: store.saved.audioOptions.limiterEnabled), step: 1).accessibilityLabel("Volume boost").onChange(of: store.saved.boost) { _, _ in store.applyAudio() }
                    Text("Start with low device volume. Boost increases loudness and the limiter reduces peaks. Pro EQ and boost apply only to Earshot’s local player.").font(.caption).foregroundStyle(.secondary)
                    if store.saved.boost > TuningSettings.boostWarningDb { Text("Above +6 dB, start with a low device volume to protect your hearing.").font(.caption).foregroundStyle(.orange) }
                }
            }
        }.navigationTitle("Sound")
            .fileImporter(isPresented: $importing, allowedContentTypes: importKind == 0 ? [.audio] : [.json, .plainText, .text]) { result in
                do {
                    let url = try result.get()
                    if importKind == 0 { try store.audio.load(url: url); store.applyAudio() }
                    else {
                        let text = try PresetCodec.readImportFile(url)
                        let summary = try store.importUserPresets(text: text, name: url.deletingPathExtension().lastPathComponent)
                        store.message = summary.message
                    }
                } catch { store.message = error.localizedDescription }
            }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: exportType, defaultFilename: exportName) { result in if case .failure(let error) = result { store.message = error.localizedDescription } }
            .sheet(item: $editing) { PresetEditor(preset: $0) }
            .sheet(isPresented: $pasting) { PresetPasteView() }
            .alert("Rename preset", isPresented: $renaming) {
                TextField("Preset name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    guard let id = presetActionTarget?.id else { return }
                    do { try store.renameUserPreset(id: id, name: renameText) } catch { store.message = error.localizedDescription }
                }.disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || renameText.trimmingCharacters(in: .whitespacesAndNewlines).count > 80)
            } message: { Text("Use a name containing 1–80 characters.") }
            .confirmationDialog("Delete \(presetActionTarget?.name ?? "preset")?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete preset", role: .destructive) { if let id = presetActionTarget?.id { store.deleteUserPreset(id: id) } }
            } message: { Text("Deleting an active preset returns playback to Flat. Built-in presets remain available.") }
    }

    private var preampPanel: some View {
        Panel(title: "Gain and protection") {
            Toggle("Automatic headroom", isOn: Binding(get: { store.saved.audioOptions.automaticHeadroom }, set: { store.saved.audioOptions.automaticHeadroom = $0; store.applyAudio() }))
            Text(String(format: "Applied preamp: %.1f dB", store.effectiveAudioPreamp)).font(.caption).foregroundStyle(.secondary)
            if !store.saved.audioOptions.automaticHeadroom {
                Slider(value: Binding(get: { store.saved.audioOptions.manualPreampDb }, set: { store.saved.audioOptions.manualPreampDb = $0; store.applyAudio() }), in: -30...0, step: 0.1).accessibilityLabel("Manual preamp")
                Button("Use preset preamp") { store.saved.audioOptions.manualPreampDb = store.preset.preampDb; store.applyAudio() }
            }
            Toggle("Peak protection", isOn: Binding(get: { store.saved.audioOptions.limiterEnabled }, set: { value in
                store.saved.audioOptions.limiterEnabled = value
                store.saved.boost = Headroom.clampBoost(store.saved.boost, limiterEnabled: value)
                store.applyAudio()
            }))
            Text(store.saved.audioOptions.limiterEnabled ? "Automatic headroom compensates overlapping boosts; peak protection controls loud passages." : "With protection off, boost is capped at +3 dB and playback reserves headroom to avoid clipping.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func prepareExport(autoEQ: Bool) {
        do {
            exportDocument = PresetDocument(text: autoEQ ? AutoEQParser.export(preset: store.preset) : try PresetCodec.encodePresets([store.preset]))
            exportType = autoEQ ? .plainText : .json
            exportName = autoEQ ? "Earshot-ParametricEQ.txt" : "Earshot-preset.json"
            exporting = true
        } catch { store.message = error.localizedDescription }
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
    @State private var seekPosition = 0.0
    @State private var scrubbing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(engine.fileName.isEmpty ? "Bring a track from Files" : engine.fileName).font(.headline)
            Text(engine.status).font(.caption).foregroundStyle(.secondary)
            if engine.hasFile {
                Slider(value: $seekPosition, in: 0...max(1, engine.duration), onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing { engine.seek(to: seekPosition) }
                }).accessibilityLabel("Playback position").accessibilityValue("\(time(scrubbing ? seekPosition : engine.position)) of \(time(engine.duration))")
                HStack { Text(time(scrubbing ? seekPosition : engine.position)); Spacer(); Text(time(engine.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack {
                Button { engine.skip(seconds: -15) } label: { Image(systemName: "gobackward.15") }.disabled(!engine.hasFile).accessibilityLabel("Back 15 seconds")
                Button { engine.playPause() } label: { Label(engine.isPlaying ? "Pause" : "Play", systemImage: engine.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.borderedProminent).disabled(!engine.hasFile).accessibilityIdentifier("playAudio")
                Button { engine.skip(seconds: 15) } label: { Image(systemName: "goforward.15") }.disabled(!engine.hasFile).accessibilityLabel("Forward 15 seconds")
                Button { engine.stop() } label: { Image(systemName: "stop.fill") }.disabled(!engine.hasFile).accessibilityLabel("Stop audio")
            }.buttonStyle(.bordered)
            HStack {
                Button("Open audio", action: importAudio).buttonStyle(.bordered)
                Spacer()
                AudioOutputPicker().frame(width: 44, height: 44)
            }
            Text(engine.routeName).font(.caption).foregroundStyle(.secondary)
            Toggle("A/B: hear original audio", isOn: Binding(get: { engine.isBypassed }, set: { engine.setBypassed($0) })).disabled(!store.saved.proEnabled).accessibilityIdentifier("compareOriginal")
            Text(!store.saved.proEnabled ? "Pro EQ is off: listening to the original audio." : engine.isBypassed ? "Original audio: filters, preamp, boost and protection are bypassed." : "Listening with your current Pro EQ settings.").font(.caption).foregroundStyle(.secondary)
            Button("Load listening sample") { do { try engine.loadDemo() } catch { store.message = error.localizedDescription } }.font(.footnote).accessibilityIdentifier("loadSample")
        }.onChange(of: engine.position) { _, value in if !scrubbing { seekPosition = value } }
    }

    private func time(_ seconds: Double) -> String { let value = max(0, Int(seconds)); return String(format: "%d:%02d", value / 60, value % 60) }
}

struct AudioOutputPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.accessibilityLabel = "Choose audio output"; return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct PresetEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var draft: PresetEditorDraft
    @State private var calculatePreamp: Bool
    @State private var confirmingGraphic = false
    @State private var previewing = false
    @State private var errorText: String?
    private let editingID: String?

    init(preset: EQPreset) {
        _draft = State(initialValue: PresetEditorDraft(preset: preset))
        _calculatePreamp = State(initialValue: preset.isBuiltIn)
        editingID = preset.isBuiltIn ? nil : preset.id
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    TextField("Name", text: $draft.preset.name)
                    Toggle("10-band graphic layout", isOn: Binding(get: { draft.graphic }, set: { value in
                        if value {
                            if GraphicEQ.isGraphic(draft.preset.bands) { draft.useGraphicLayout() }
                            else { confirmingGraphic = true }
                        } else { draft.useParametricLayout() }
                    }))
                    EQChart(preset: draft.preset)
                    if draft.parametricBackup != nil {
                        Button("Restore prior parametric filters") { draft.restoreParametricFilters() }
                        Text("Restoring replaces graphic edits with the exact filters saved before conversion.").font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Preview on local player", isOn: $previewing).disabled(!store.saved.proEnabled || !store.audio.hasFile)
                }
                Section("Filters") {
                    ForEach(Array(draft.preset.bands.enumerated()), id: \.offset) { index, band in
                        DisclosureGroup("\(frequencyLabel(band.frequencyHz)) Hz · \(String(format: "%+.1f", band.gainDb)) dB") {
                            Toggle("Enabled", isOn: bandBinding(index).enabled)
                            HStack { Text("Gain"); Slider(value: bandBinding(index).gainDb, in: -15...15, step: 0.5).accessibilityLabel("Filter \(index + 1) gain") }
                            if !draft.graphic {
                                HStack { Text("Frequency (Hz)"); TextField("Frequency", value: bandBinding(index).frequencyHz, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                                HStack { Text("Q"); Slider(value: bandBinding(index).q, in: 0.1...10, step: 0.1).accessibilityLabel("Filter \(index + 1) Q"); Text(String(format: "%.1f", band.q)) }
                                Picker("Type", selection: bandBinding(index).type) { ForEach(EQFilterType.allCases, id: \.self) { Text($0.label).tag($0) } }
                                HStack {
                                    Button { draft.moveFilter(from: index, to: index - 1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).accessibilityLabel("Move filter \(index + 1) up")
                                    Button { draft.moveFilter(from: index, to: index + 1) } label: { Image(systemName: "arrow.down") }.disabled(index == draft.preset.bands.count - 1).accessibilityLabel("Move filter \(index + 1) down")
                                    Spacer()
                                    Button("Remove filter", role: .destructive) { draft.removeFilters(at: IndexSet(integer: index)) }.disabled(draft.preset.bands.count <= 1)
                                }.buttonStyle(.borderless).frame(minHeight: 44)
                            }
                        }
                    }
                    if !draft.graphic && draft.preset.bands.count < PresetValidation.maximumBands {
                        Button("Add filter") { draft.preset.bands.append(EQBand(frequencyHz: min(16_000, (draft.preset.bands.map(\.frequencyHz).max() ?? 500) * 2), gainDb: 0)) }
                    }
                    Text("\(draft.preset.bands.count) of \(PresetValidation.maximumBands) filters").font(.caption).foregroundStyle(.secondary)
                }
                Section("Preset preamp") {
                    Toggle("Calculate headroom when saving", isOn: $calculatePreamp)
                    Text(String(format: "%.1f dB", calculatedPreamp)).monospacedDigit()
                    if !calculatePreamp { Slider(value: $draft.preset.preampDb, in: -30...0, step: 0.1).accessibilityLabel("Preset preamp") }
                    Text("Graphic conversion approximates the current response. Switching to parametric keeps every current graphic filter.").font(.caption).foregroundStyle(.secondary)
                    if editingID != nil { Button("Save a new copy") { save(asCopy: true) } }
                }
            }.navigationTitle(editingID == nil ? "Edit preset copy" : "Edit preset").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save(asCopy: false) }.disabled((try? PresetValidation.validated(draft.preset)) == nil) } }
                .confirmationDialog("Convert to graphic EQ?", isPresented: $confirmingGraphic, titleVisibility: .visible) {
                    Button("Approximate with ten bands") { draft.useGraphicLayout() }
                } message: { Text("The current curve will be sampled at ten frequencies. Shelves and narrow filters may sound different. Your exact parametric filters remain available to restore until you close this editor.") }
                .alert("Cannot save preset", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) { Button("OK") { errorText = nil } } message: { Text(errorText ?? "") }
                .onChange(of: draft.preset) { _, _ in updatePreview() }
                .onChange(of: calculatePreamp) { _, _ in updatePreview() }
                .onChange(of: previewing) { _, _ in if previewing { updatePreview() } else { store.applyAudio() } }
                .onDisappear { store.applyAudio() }
        }
    }

    private var calculatedPreamp: Double { calculatePreamp ? max(-30, Headroom.recommendedPreampDb(bands: draft.preset.bands)) : draft.preset.preampDb }

    private func bandBinding(_ index: Int) -> Binding<EQBand> {
        Binding(get: { draft.preset.bands.indices.contains(index) ? draft.preset.bands[index] : EQBand(frequencyHz: 1000, gainDb: 0) }, set: { value in if draft.preset.bands.indices.contains(index) { draft.preset.bands[index] = value } })
    }

    private func frequencyLabel(_ value: Double) -> String { value.isFinite ? String(format: "%.0f", value) : "Invalid" }

    private func save(asCopy: Bool) {
        do {
            var value = draft.preset
            value.preampDb = calculatedPreamp
            if !asCopy, let editingID { value.id = editingID; try store.updateUserPreset(value) }
            else { _ = try store.createUserPreset(value) }
            dismiss()
        } catch { errorText = error.localizedDescription }
    }

    private func updatePreview() {
        guard previewing, (try? PresetValidation.validated(draft.preset)) != nil else { return }
        store.audio.apply(preset: draft.preset, preamp: calculatedPreamp, enabled: store.saved.proEnabled, boost: store.saved.boost, limiterEnabled: store.saved.audioOptions.limiterEnabled)
    }
}

struct PresetPasteView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name = "Imported AutoEQ"
    @State private var text = ""
    @State private var errorText: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") { TextField("Name", text: $name) }
                Section("AutoEQ text or Earshot JSON") {
                    PasteButton(payloadType: String.self) { values in if let value = values.first { text = value } }
                    TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(minHeight: 260).autocorrectionDisabled().accessibilityIdentifier("presetImportText")
                    Text("\(text.utf8.count) bytes · maximum 2 MiB").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Link("Original Earshot by HellzYeahh", destination: URL(string: "https://github.com/HellzYeahh/earshot")!)
                    Link("AutoEq by Jaakko Pasanen · MIT", destination: URL(string: "https://github.com/jaakkopasanen/AutoEq")!)
                }
            }.navigationTitle("Import preset").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Import") {
                        do { let summary = try store.importUserPresets(text: text, name: name); dismiss(); store.message = summary.message }
                        catch { errorText = error.localizedDescription }
                    }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.utf8.count > PresetValidation.maximumFileBytes) }
                }
                .alert("Cannot import preset", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) { Button("OK") { errorText = nil } } message: { Text(errorText ?? "") }
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
