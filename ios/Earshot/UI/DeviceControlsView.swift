import SwiftUI

struct DeviceControlsView: View {
    @EnvironmentObject var store: AppStore
    @State private var confirmLEAudio = false
    @State private var nextLEAudio = false
    @State private var confirmPower = false
    @State private var volumeDraft = 0.0
    @State private var nameDraft = ""
    @State private var nextPairing = false
    @State private var confirmPairing = false
    @State private var sourceAction: BoseSourceAction?
    @State private var sourceTarget: BosePairedSource?
    @State private var confirmSource = false
    @State private var confirmForgetRemembered = false

    private var nameByteCount: Int { nameDraft.utf8.count }
    private var invalidName: Bool { nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || nameByteCount > 31 }

    var body: some View {
        Form {
            if store.saved.demo { Section { Label("All controls on this page are simulated.", systemImage: "sparkles").font(.footnote) } }
            reconnectSection
            nameSection
            volumeSection
            playbackSection
            connectionSection
            shortcutSection
            voiceSection
            pairedSection
            if !store.saved.demo { Section("Diagnostics") { NavigationLink("Read-only protocol scan") { ProtocolLabView(bluetooth: store.bluetooth) } } }
            if !store.deviceRequestStatus.isEmpty { Section("Latest device request") { Text(store.deviceRequestStatus).font(.footnote).accessibilityIdentifier("deviceRequestStatus") } }
            powerSection
        }
        .navigationTitle("Device controls").navigationBarTitleDisplayMode(.inline)
        .onAppear { volumeDraft = store.deviceVolume; nameDraft = store.displayDeviceName }
        .onChange(of: store.deviceVolume) { _, value in volumeDraft = value }
        .onChange(of: store.displayDeviceName) { _, value in nameDraft = value }
        .alert(sourceAction?.title ?? "Manage source", isPresented: $confirmSource) {
            if let action = sourceAction, let source = sourceTarget {
                Button(action.title, role: action == .remove || action == .disconnect ? .destructive : nil) { store.manageSource(source, action: action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text(sourceConfirmationMessage) }
    }

    @ViewBuilder private var reconnectSection: some View {
        if !store.saved.demo {
            Section("Remembered headphones") {
                Toggle("Reconnect automatically", isOn: Binding(get: { store.bluetooth.reconnectEnabled }, set: { store.bluetooth.setReconnectEnabled($0) }))
                if let name = store.bluetooth.rememberedDeviceName {
                    LabeledContent("Remembered device", value: name)
                    Button("Reconnect once") { store.bluetooth.reconnectRememberedDevice() }.disabled(store.bluetooth.isConnected)
                    if store.bluetooth.isReconnecting { Button("Cancel reconnect", role: .cancel) { store.bluetooth.disconnect() } }
                    Button("Forget remembered headphones", role: .destructive) { confirmForgetRemembered = true }
                        .confirmationDialog("Forget remembered headphones?", isPresented: $confirmForgetRemembered, titleVisibility: .visible) {
                            Button("Forget and disconnect", role: .destructive) { store.bluetooth.forgetRememberedDevice() }
                        } message: { Text("Earshot will stop reconnecting until you scan and connect again.") }
                } else { Text("Connect a verified control link once to remember your headphones.").font(.caption).foregroundStyle(.secondary) }
                Text("Retries are limited. iOS may pause background work. Disconnecting manually stops retries until you explicitly connect again.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var nameSection: some View {
        if store.supports(1, 2) {
            Section("Headphone name") {
                TextField("Name", text: $nameDraft).textInputAutocapitalization(.words)
                HStack {
                    Text("\(nameByteCount)/31 UTF-8 bytes").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save name") { store.renameHeadphones(nameDraft) }.disabled(!store.connected || store.profile.unsupported || invalidName)
                }
            }
        }
    }

    private var volumeSection: some View {
        Section("Headphone volume") {
            if store.deviceVolumeMaximum > 0 {
                Slider(value: $volumeDraft, in: 0...Double(store.deviceVolumeMaximum), step: 1) { editing in
                    if !editing { store.setDeviceVolume(volumeDraft) }
                }.disabled(!store.connected || !store.supports(5, 5)).accessibilityLabel("Headphone volume")
                LabeledContent("Reported volume", value: "\(Int(store.deviceVolume)) / \(store.deviceVolumeMaximum)")
            } else { Text("Connect headphones that report their volume range.").foregroundStyle(.secondary) }
        }
    }

    private var playbackSection: some View {
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
    }

    private var connectionSection: some View {
        Section("Connection and latency") {
            LabeledContent("Active source", value: store.audioSource)
            LabeledContent("Reported latency", value: store.deviceLatency)
            if let enabled = store.leAudio {
                Toggle("LE Audio", isOn: Binding(get: { enabled }, set: { nextLEAudio = $0; confirmLEAudio = true }))
                    .disabled(!store.connected || !store.supports(1, 37))
                    .confirmationDialog("Restart headphones to change LE Audio?", isPresented: $confirmLEAudio, titleVisibility: .visible) {
                        Button("Change LE Audio and restart") { store.setLEAudio(nextLEAudio) }
                        Button("Cancel", role: .cancel) {}
                    } message: { Text(store.saved.demo ? "This changes only the simulated setting." : "Audio and Earshot will disconnect. Reconnect after the headphones restart.") }
                Text("Changing LE Audio restarts the headphones and disconnects Earshot. Availability depends on the phone and firmware.").font(.caption).foregroundStyle(.secondary)
            } else { Text("LE Audio setting has not been reported.").foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var shortcutSection: some View {
        if let shortcut = store.buttonShortcut {
            Section("Shortcut button") {
                Picker("Button action", selection: Binding(get: { Int(shortcut.action) }, set: { store.setButtonShortcut($0) })) {
                    ForEach(shortcut.supported.sorted(), id: \.self) { action in Text(BoseButtonShortcut.name(action)).tag(action) }
                }.disabled(!store.connected || !store.supports(1, 9))
                Text("Actions come from the device’s capability mask. A voice assistant or Spotify action can require setup in its own app.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var voiceSection: some View {
        if let voice = store.voicePromptsState {
            Section("Voice-prompt language") {
                Picker("Language", selection: Binding(get: { Int(voice.language) }, set: { store.setVoiceLanguage(UInt8($0)) })) {
                    ForEach(languageCodes(voice), id: \.self) { code in Text(BoseVoicePromptsState.languages[UInt8(code)] ?? "Language \(code)").tag(code) }
                }.disabled(!store.connected || !store.supports(1, 3) || voice.installedLanguages?.isEmpty != false || store.profile.unsupported)
                Text("Only languages reported installed by the headphones are offered. Prompt enablement is preserved.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func languageCodes(_ voice: BoseVoicePromptsState) -> [Int] {
        Array((voice.installedLanguages ?? []).union([Int(voice.language)])).filter { (0..<32).contains($0) }.sorted()
    }

    private var pairedSection: some View {
        Section("Paired sources") {
            if let pairing = store.pairingMode {
                Toggle("Pairing mode", isOn: Binding(get: { pairing }, set: { nextPairing = $0; confirmPairing = true }))
                    .disabled(!store.connected || !store.supports(4, 8) || store.profile.unsupported)
                    .confirmationDialog(nextPairing ? "Enter headphone pairing mode?" : "Leave pairing mode?", isPresented: $confirmPairing, titleVisibility: .visible) {
                        Button(nextPairing ? "Enter pairing mode" : "Leave pairing mode") { store.setPairingMode(nextPairing) }
                    } message: { Text("The headphones may disconnect while changing pairing mode. Use Bluetooth settings to pair a new source.") }
            }
            if store.pairedSources.isEmpty { Text("No paired-source list has been reported.").foregroundStyle(.secondary) }
            ForEach(store.pairedSources) { source in sourceRow(source) }
            Text("Each source function needs device support evidence. The firmware may still reject an operation; a request is complete only when the headphones report its result.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func availableActions(_ source: BosePairedSource) -> [BoseSourceAction] {
        BoseSourceAction.allCases.filter { action in
            store.sourceCommandSupport.contains(action) && (action != .connect || !source.connected)
                && (![.disconnect, .route].contains(action) || source.connected)
        }
    }

    private func sourceRow(_ source: BosePairedSource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(source.name)
                Spacer()
                Text(source.isLocal ? "This phone" : source.connected ? "Connected" : "Paired").foregroundStyle(.secondary)
                if !store.profile.unsupported {
                    Menu {
                        ForEach(availableActions(source)) { action in
                            Button(action.title, role: action == .remove || action == .disconnect ? .destructive : nil) {
                                sourceAction = action; sourceTarget = source; confirmSource = true
                            }
                        }
                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("Manage \(source.name)") }
                    .disabled(!store.connected || availableActions(source).isEmpty)
                }
            }
            Text(source.displayAddress).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private var sourceConfirmationMessage: String {
        guard let action = sourceAction, let source = sourceTarget else { return "" }
        switch action {
        case .remove: return "The headphones will forget \(source.name). Pair it again in Bluetooth settings to use it later." + (source.isLocal ? " This phone’s control link may disconnect." : "")
        case .disconnect: return "Disconnect \(source.name) from the headphones?" + (source.isLocal ? " This is the control phone; automatic reconnect will pause." : "")
        case .route: return "Start playback on \(source.name) first. The headphones’ routing table may be unavailable until that source is streaming."
        case .connect: return "Ask the headphones to connect to \(source.name)? The source must be nearby and available."
        }
    }

    private var powerSection: some View {
        Section {
            Button("Power off headphones", role: .destructive) { confirmPower = true }
                .disabled(!store.connected || !store.supports(7, 4))
                .confirmationDialog("Power off your headphones?", isPresented: $confirmPower, titleVisibility: .visible) {
                    Button("Power off", role: .destructive) { store.powerOffHeadphones() }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Turn the headphones back on using their physical power control.") }
            Button("Refresh device reports") { store.refresh() }.disabled(!store.connected)
        }
    }

    private func playbackButton(_ title: String, icon: String, action: Int) -> some View {
        Button { store.controlPlayback(action) } label: { Image(systemName: icon).frame(maxWidth: .infinity) }
            .accessibilityLabel(title).disabled(!store.connected || !store.playbackActions.contains(action))
    }
}
