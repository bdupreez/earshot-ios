// AI-assisted iOS adaptation of Earshot by HellzYeahh and contributors (MIT).
import AVKit
import MediaPlayer
import SwiftUI

struct CompanionControlsView: View {
    @EnvironmentObject private var companion: HeadsetCompanion
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Page {
            InfoNote(text: "Headset companion features adapted from the original Earshot by HellzYeahh and contributors. This experimental AI-assisted iOS port uses public iOS audio APIs.")
            Panel(title: "Audio output") {
                LabeledContent("Selected output", value: companion.output?.name ?? "No active output")
                if let output = companion.output { Text(output.isHeadphones ? "External audio route selected" : "Built-in or system audio output").font(.caption).foregroundStyle(.secondary) }
                Text("An audio route is separate from a verified headphone control connection. It does not prove battery, ANC, hardware EQ or button support.").font(.footnote).foregroundStyle(.secondary)
                HStack { Text("Choose audio output"); Spacer(); CompanionRoutePicker().frame(width: 48, height: 44) }
                CompanionSystemVolume().frame(height: 44).accessibilityLabel("System output volume")
                Text("iOS manages system output volume and the routes available in its picker.").font(.caption).foregroundStyle(.secondary)
                Button("Refresh audio route") { companion.refreshRoute() }
            }
            Panel(title: "Local EQ for this output") {
                Toggle("Remember local EQ by output", isOn: $companion.preferences.rememberEQ)
                if let output = companion.output, output.isHeadphones {
                    Picker("Saved local EQ", selection: Binding(get: {
                        guard let saved = companion.preferences.outputEQ[output.id] else { return "__unset" }
                        return saved.enabled ? saved.presetID ?? "__unset" : "__off"
                    }, set: { selection in
                        if selection == "__unset" { companion.preferences.outputEQ.removeValue(forKey: output.id) }
                        else {
                            let id: String? = selection == "__off" ? nil : selection
                            companion.applyEQ(id)
                            companion.rememberExplicitPick(id)
                        }
                    })) {
                        Text("No saved choice").tag("__unset")
                        Text("Local EQ off").tag("__off")
                        ForEach(companion.availablePresets()) { preset in Text(preset.name).tag(preset.id) }
                    }.disabled(!companion.preferences.rememberEQ).accessibilityIdentifier("companionRememberedEQ")
                    Button("Forget this output’s preferences", role: .destructive) { companion.forgetCurrentOutput() }
                } else { Text("Select an external audio output to remember its preset or local EQ off.").font(.footnote).foregroundStyle(.secondary) }
                Text("Only explicit preset or off choices are remembered. Rules and temporary EQ changes do not replace them. EQ affects audio played inside Earshot.").font(.footnote).foregroundStyle(.secondary)
                Button("Cycle local EQ") { _ = companion.cycleEQ() }.accessibilityIdentifier("companionCycleEQ")
                Toggle("Spoken confirmation", isOn: $companion.preferences.spokenFeedback)
                Text(companion.status).font(.caption).accessibilityIdentifier("companionStatus")
            }
            Panel(title: "Foreground actions") {
                Text("Default Earshot action").font(.subheadline)
                Picker("Default Earshot action", selection: $companion.preferences.defaultAction) {
                    ForEach(CompanionAction.allCases) { Text($0.title).tag($0) }
                }
                if let output = companion.output, output.isHeadphones {
                    Text("Action for this output").font(.subheadline)
                    Picker("Action for this output", selection: Binding(get: { companion.preferences.outputActions[output.id]?.rawValue ?? "__default" }, set: { value in
                        _ = companion.preferences.setAction(CompanionAction(rawValue: value), outputID: output.id)
                    })) {
                        Text("Use default").tag("__default")
                        ForEach(CompanionAction.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                Button("Run selected Earshot action") { Task { await companion.runConfiguredAction() } }.accessibilityIdentifier("companionRunAction")
                Text("Run these actions here or through Earshot’s explicit Shortcuts actions. iOS does not let Earshot become the global assistant, intercept arbitrary headset presses, or remap another app’s controls. A supported Bose button report is a separate, verified control feature.").font(.footnote).foregroundStyle(.secondary)
            }
            CompanionMemoControls(memos: companion.memos)
        }
        .navigationTitle("Headset companion").navigationBarTitleDisplayMode(.inline)
        // Permission sheets temporarily make a foreground scene inactive. Only
        // backgrounding ends the explicit recording request; audio interruptions
        // are handled independently by AVAudioSession notifications.
        .onChange(of: phase, initial: true) { _, phase in companion.isAppActive = phase != .background }
    }
}

private struct CompanionMemoControls: View {
    @ObservedObject var memos: CompanionVoiceMemos
    @State private var deleting: CompanionMemo?
    var body: some View {
        Panel(title: "Voice memos", subtitle: "Persistent, on-device recordings") {
            Text(memos.status).font(.footnote).accessibilityIdentifier("companionMemoStatus")
            if memos.isRecording {
                LabeledContent("Recording", value: time(memos.elapsed))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("companionMemoElapsed")
                    .accessibilityValue("\(Int(memos.elapsed)) seconds")
                Text("Input: \(memos.microphoneRoute)").font(.caption)
            }
            Button(memos.isRecording ? "Stop and save memo" : "Record voice memo") {
                if memos.isRecording { memos.stopRecording() }
                else { Task { await memos.startRecording() } }
            }.earshotProminentButton().accessibilityIdentifier("companionRecordMemo")
            Text("Recording requires microphone permission and stops when Earshot leaves the foreground, audio is interrupted, the input disappears, or 30 minutes elapse. iOS chooses the actual microphone; the route is shown while recording.").font(.caption).foregroundStyle(.secondary)
            Text("Up to 100 memos and 256 MiB. Share and delete saved memos to make space. Saved files are never automatically evicted.").font(.caption).foregroundStyle(.secondary)
            if memos.recordings.isEmpty { Text("No saved voice memos.").foregroundStyle(.secondary) }
            ForEach(memos.recordings) { memo in
                VStack(alignment: .leading, spacing: 8) {
                    Text(memo.title).font(.headline)
                    Text("\(time(memo.duration)) · \(ByteCountFormatter.string(fromByteCount: memo.bytes, countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                    if memos.playingID == memo.id {
                        ProgressView(value: memos.playbackPosition, total: max(0.001, memo.duration))
                            .accessibilityLabel("Voice memo playback")
                            .accessibilityValue("\(time(memos.playbackPosition)) of \(time(memo.duration))")
                    }
                    HStack {
                        Button(memos.playingID == memo.id ? "Stop playback" : "Play memo") {
                            if memos.playingID == memo.id { memos.stopPlayback() } else { memos.play(memo.id) }
                        }.accessibilityIdentifier("companionPlayMemo.\(memo.id)")
                        ShareLink(item: memo.url) { Label("Share", systemImage: "square.and.arrow.up") }
                        Spacer()
                        Button("Delete", role: .destructive) { deleting = memo }
                    }.disabled(memos.isRecording)
                }.padding(.vertical, 8)
            }
        }
        .alert("Delete voice memo?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete memo", role: .destructive) { if let deleting { memos.delete(deleting.id) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This permanently deletes the selected memo from this device. Share it first if you want to keep a copy.") }
        .onDisappear { memos.stopPlayback() }
    }
    private func time(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct CompanionRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { AVRoutePickerView() }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
private struct CompanionSystemVolume: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView { let view = MPVolumeView(); view.showsRouteButton = false; return view }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
