import SwiftUI

struct DeviceControlsView: View {
    @EnvironmentObject var store: AppStore
    @State private var confirmLEAudio = false
    @State private var nextLEAudio = false
    @State private var confirmPower = false
    @State private var volumeDraft = 0.0

    var body: some View {
        Form {
            if store.saved.demo { Section { Label("All controls on this page are simulated.", systemImage: "sparkles").font(.footnote) } }
            Section("Headphone volume") {
                if store.deviceVolumeMaximum > 0 {
                    Slider(value: $volumeDraft, in: 0...Double(store.deviceVolumeMaximum), step: 1) { editing in
                        if !editing { store.setDeviceVolume(volumeDraft) }
                    }.disabled(!store.connected || !store.supports(5, 5)).accessibilityLabel("Headphone volume")
                    LabeledContent("Reported volume", value: "\(Int(store.deviceVolume)) / \(store.deviceVolumeMaximum)")
                } else { Text("Connect headphones that report their volume range.").foregroundStyle(.secondary) }
            }
            Section("Playback on the headphones") {
                LabeledContent("Status", value: store.playbackStatus)
                HStack {
                    playbackButton("Previous", icon: "backward.end.fill", action: 4)
                    playbackButton("Play", icon: "play.fill", action: 1)
                    playbackButton("Pause", icon: "pause.fill", action: 2)
                    playbackButton("Next", icon: "forward.end.fill", action: 3)
                }.buttonStyle(.bordered)
                Text("Requests go to the headphones’ active source. Firmware and the source app decide whether to act on them.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Connection and latency") {
                LabeledContent("Active source", value: store.audioSource)
                LabeledContent("Reported latency", value: store.deviceLatency)
                if let enabled = store.leAudio {
                    Toggle("LE Audio", isOn: Binding(get: { enabled }, set: { nextLEAudio = $0; confirmLEAudio = true }))
                        .disabled(!store.connected || !store.supports(1, 37))
                    Text("Changing LE Audio restarts the headphones and disconnects Earshot. Availability depends on the phone and firmware.").font(.caption).foregroundStyle(.secondary)
                } else { Text("LE Audio setting has not been reported.").foregroundStyle(.secondary) }
            }
            if let shortcut = store.buttonShortcut {
                Section("Shortcut button") {
                    Picker("Button action", selection: Binding(get: { Int(shortcut.action) }, set: { store.setButtonShortcut($0) })) {
                        ForEach(shortcut.supported.sorted(), id: \.self) { action in Text(BoseButtonShortcut.name(action)).tag(action) }
                    }.disabled(!store.connected || !store.supports(1, 9))
                    Text("Actions come from the device’s capability mask. A voice assistant or Spotify action can require setup in its own app.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Paired sources") {
                if store.pairedSources.isEmpty { Text("No paired-source list has been reported.").foregroundStyle(.secondary) }
                ForEach(store.pairedSources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(source.name); Spacer(); Text(source.connected ? "Connected" : "Paired").foregroundStyle(.secondary) }
                        Text(source.displayAddress).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Power off headphones", role: .destructive) { confirmPower = true }
                    .disabled(!store.connected || !store.supports(7, 4))
                Button("Refresh device reports") { store.refresh() }.disabled(!store.connected)
            }
        }
        .navigationTitle("Device controls").navigationBarTitleDisplayMode(.inline)
        .onAppear { volumeDraft = store.deviceVolume }
        .onChange(of: store.deviceVolume) { _, value in volumeDraft = value }
        .confirmationDialog("Restart headphones to change LE Audio?", isPresented: $confirmLEAudio, titleVisibility: .visible) {
            Button("Change LE Audio and restart") { store.setLEAudio(nextLEAudio) }
            Button("Cancel", role: .cancel) {}
        } message: { Text(store.saved.demo ? "This changes only the simulated setting." : "Audio and Earshot will disconnect. Reconnect after the headphones restart.") }
        .confirmationDialog("Power off your headphones?", isPresented: $confirmPower, titleVisibility: .visible) {
            Button("Power off", role: .destructive) { store.powerOffHeadphones() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Turn the headphones back on using their physical power control.") }
    }

    private func playbackButton(_ title: String, icon: String, action: Int) -> some View {
        Button { store.controlPlayback(action) } label: { Image(systemName: icon).frame(maxWidth: .infinity) }
            .accessibilityLabel(title).disabled(!store.connected || !store.playbackActions.contains(action))
    }
}
