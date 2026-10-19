import SwiftUI
import AVKit

struct ToolsView: View {
    var body: some View {
        Page {
            Text("The useful little things.").font(.title2.weight(.bold))
            ToolLink(title: "Connection", detail: "Discover headphones and inspect your audio route", icon: "dot.radiowaves.left.and.right") { ConnectionView() }
            ToolLink(title: "Microphone check", detail: "Record, listen, and check the actual input", icon: "mic") { MicrophoneView() }
            ToolLink(title: "Protocol lab", detail: "Capability reads, experimental Print console and reports", icon: "flask") { LabView() }
            ToolLink(title: "iOS compatibility", detail: "What works here, and what needs hardware", icon: "checkmark.shield") { CompatibilityView() }
            InfoNote(text: "Earshot for iOS is an experimental AI-assisted port. Simulator success validates the app and virtual controls; physical headphone compatibility remains unverified.")
        }.navigationTitle("Tools")
    }
}

struct ConnectionView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Page {
            Panel(title: "Headphone control") {
                Text(store.saved.demo ? "Demo mode is active" : store.bluetooth.status).font(.subheadline)
                HStack {
                    Button("Scan for headphones") { if store.saved.demo { store.setDemo(false) }; store.bluetooth.scan() }.buttonStyle(.borderedProminent).accessibilityIdentifier("scanHeadphones")
                    if store.bluetooth.isConnected { Button("Disconnect") { store.bluetooth.disconnect() }.buttonStyle(.bordered) }
                }
                ForEach(store.bluetooth.devices) { device in
                    Button { store.bluetooth.connect(device) } label: { HStack { Label(device.name, systemImage: "headphones"); Spacer(); Image(systemName: "chevron.right") } }.padding(.vertical, 8)
                }
                Text("Discovery uses Bluetooth GATT and looks for the Bose L2CAP control service. An audio pairing alone does not establish an Earshot control connection.").font(.caption).foregroundStyle(.secondary)
            }
            AudioRoutePanel(routes: store.routes)
            ToolLink(title: "Device controls", detail: "Volume, transport, LE Audio, shortcuts and sources", icon: "headphones") { DeviceControlsView() }
            Panel(title: "Connect audio") {
                Text("Pair your headphones in iOS Settings, then choose them as the audio output here.").font(.subheadline).foregroundStyle(.secondary)
                RoutePicker().frame(width: 48, height: 44).accessibilityLabel("Choose audio output")
                Text("iOS manages Bluetooth codecs and LE Audio negotiation. This port cannot force AAC/SBC, read the negotiated codec, or alter phone-call volume.").font(.caption).foregroundStyle(.secondary)
            }
            InfoNote(text: "Classic RFCOMM sockets used by the Android app have no direct public iOS equivalent. A compatible BLE L2CAP service must be exposed by the headphones; this still needs a physical-device test.")
        }.navigationTitle("Connection").navigationBarTitleDisplayMode(.inline)
    }
}

struct AudioRoutePanel: View {
    @ObservedObject var routes: AudioRouteObserver
    var body: some View {
        Panel(title: "This app’s audio route") {
            LabeledContent("Output", value: routes.outputName)
            LabeledContent("Input", value: routes.inputName)
            LabeledContent("Session sample rate", value: "\(Int(routes.sampleRate)) Hz")
            Text("Sample rate is an audio-session measurement, not a Bluetooth codec identifier.").font(.caption).foregroundStyle(.secondary)
            Button("Refresh route") { routes.refresh() }
        }
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.tintColor = UIColor(Color.earshot); return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct MicrophoneView: View {
    @EnvironmentObject var store: AppStore
    var body: some View { MicrophoneControls(mic: store.mic, audio: store.audio).navigationTitle("Microphone check").navigationBarTitleDisplayMode(.inline) }
}

struct MicrophoneControls: View {
    @ObservedObject var mic: MicRecorder
    let audio: LocalAudioEngine
    var body: some View {
        Page {
            Panel {
                Image(systemName: mic.isRecording ? "waveform" : "mic.circle").font(.system(size: 64, weight: .light)).foregroundStyle(Color.earshot).frame(maxWidth: .infinity).padding(.vertical, 16)
                Text(mic.status).font(.headline)
                ProgressView(value: Double(mic.level)).tint(.earshot).accessibilityLabel("Microphone input level")
                HStack { Text("\(String(format: "%.1f", mic.duration)) seconds").monospacedDigit(); Spacer(); Text("8 second maximum").foregroundStyle(.secondary) }.font(.caption)
                if mic.hasRecording && !mic.isRecording {
                    VStack(spacing: 6) {
                        ProgressView(value: mic.playbackPosition, total: max(mic.duration, 0.001))
                            .tint(.earshot)
                            .accessibilityIdentifier("micPlaybackProgress")
                            .accessibilityLabel("Recording playback progress")
                            .accessibilityValue(String(format: "%.1f of %.1f seconds", mic.playbackPosition, mic.duration))
                        HStack {
                            Text(playbackTime(mic.playbackPosition))
                            Spacer()
                            Text(playbackTime(mic.duration))
                        }.font(.caption.monospacedDigit()).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }
                Button { if mic.isRecording { mic.stopRecording() } else { audio.stop(); Task { await mic.startRecording() } } } label: { Label(mic.isRecording ? "Stop recording" : "Record microphone", systemImage: mic.isRecording ? "stop.fill" : "record.circle").frame(maxWidth: .infinity).padding(6) }.buttonStyle(.borderedProminent).accessibilityIdentifier("recordMic")
                HStack { Button(mic.isPlaying ? "Stop playback" : "Play recording") { if mic.isPlaying { mic.stopPlayback() } else { audio.stop(); mic.play() } }.disabled(!mic.hasRecording || mic.isRecording); Spacer(); Button("Delete", role: .destructive) { mic.deleteRecording() }.disabled(!mic.hasRecording || mic.isRecording) }
            }
            InfoNote(text: mic.routeDescription, icon: "ear")
            Text("The app requests a Bluetooth headset microphone when available, then shows the actual route. Recordings stay in the local app cache until deleted. iOS does not allow this app to process cellular or other apps’ call audio.").font(.footnote).foregroundStyle(.secondary)
        }.onDisappear { mic.stopRecording(); mic.stopPlayback() }
    }

    private func playbackTime(_ seconds: TimeInterval) -> String {
        let wholeSeconds = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }
}

struct LabView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = 0
    let queries: [(String, UInt8, UInt8)] = [("Protocol version [0.1]",0,1), ("Product [0.3]",0,3), ("Battery [2.2]",2,2), ("EQ [1.7]",1,7), ("Mode capabilities [31.2]",31,2), ("Current mode [31.3]",31,3)]
    var body: some View {
        Page {
            InfoNote(text: "The queries below are read-only. The separate Print console requires explicit experimental consent. Firmware update, authentication, reset, factory defaults and destructive commands are blocked in the transport.")
            Panel(title: "Query headphones") {
                Picker("Function", selection: $query) { ForEach(queries.indices, id: \.self) { Text(queries[$0].0).tag($0) } }
                Button("Send GET") { let q = queries[query]; store.send(BmapPacket(block: q.1, function: q.2, operation: .get)) }.buttonStyle(.borderedProminent).disabled(!store.bluetooth.isConnected || store.saved.demo)
                if store.saved.demo { Text("Demo mode does not send Bluetooth packets.").font(.caption).foregroundStyle(.secondary) }
            }
            NavigationLink("Capability scan and console") { ProtocolLabView(bluetooth: store.bluetooth) }
            Panel(title: "Connection report") {
                ShareLink(item: store.report) { Label("Share connection report", systemImage: "square.and.arrow.up") }
                Text(store.report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
        }.navigationTitle("Protocol lab").navigationBarTitleDisplayMode(.inline)
    }
}

struct CompatibilityView: View {
    var body: some View {
        Page {
            Panel(title: "Built natively for iOS") { Text("SwiftUI navigation and controls, persistent demo profiles, mode editing, EQ math and presets, local audio playback with EQ and limiter, microphone recording, Bluetooth discovery, diagnostics, and foreground automation rules.") }
            Panel(title: "Needs real headphones") { Text("The Bose BLE L2CAP path must be verified for each device and firmware. Live battery, EQ, mode and settings controls depend on a verified BMAP link and supported device replies. A simulator cannot test Bluetooth interoperability.") }
            Panel(title: "Platform differences") { Text("iOS has no public equivalent for arbitrary Android RFCOMM sockets, Shizuku codec controls, global third-party audio EQ, call-volume boosting, or monitoring other apps. Background execution is constrained; scheduled rules run while Earshot is open.") }
            Panel(title: "Still incomplete") { Text("Physical validation of the implemented reconnect/restoration, model adaptation, source routing and custom-mode controls remains pending. Crusher’s Classic Bragi transport has no supported public iOS control path. BMAP device controls, custom-mode writes, favorites and shortcut remapping need real-device verification. Use the original vendor app for firmware updates.") }
            InfoNote(text: "This is an AI-assisted attempt to port HellzYeahh’s Earshot. It is not an official Bose or Skullcandy app. Original contributors and research projects are credited in About.")
        }.navigationTitle("iOS compatibility").navigationBarTitleDisplayMode(.inline)
    }
}
