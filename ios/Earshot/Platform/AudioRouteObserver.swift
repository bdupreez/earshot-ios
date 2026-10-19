// AI-assisted iOS port attempt of HellzYeahh/earshot. Original Earshot contributors retain credit.
// Upstream: https://github.com/HellzYeahh/earshot — MIT; see THIRD_PARTY_NOTICES.md.
import AVFoundation
import Combine
import Foundation

/// Reports facts from this app's audio session. A sample rate does not identify a Bluetooth codec.
@MainActor
final class AudioRouteObserver: ObservableObject {
    @Published private(set) var outputName = "No active output"
    @Published private(set) var inputName = "No active microphone"
    @Published private(set) var sampleRate: Double = 0
    @Published private(set) var outputVolume: Float = 0
    @Published private(set) var isBluetoothOutput = false
    private var routeObserver: NSObjectProtocol?
    private var volumeObserver: NSKeyValueObservation?

    init() {
        refresh()
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } }
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    func refresh() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        outputName = outputs.isEmpty ? "No active output" : outputs.map(\.portName).joined(separator: ", ")
        let inputs = session.currentRoute.inputs
        inputName = inputs.isEmpty ? "No active microphone" : inputs.map(\.portName).joined(separator: ", ")
        sampleRate = session.sampleRate
        outputVolume = session.outputVolume
        isBluetoothOutput = outputs.contains { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType) }
    }
}
