// AI-assisted iOS port attempt of HellzYeahh/earshot. Original Earshot contributors retain credit.
// Upstream: https://github.com/HellzYeahh/earshot — MIT; see THIRD_PARTY_NOTICES.md.
import AVFoundation
import Combine
import Foundation

/// A real, local microphone check. Headphone routing is requested, then the actual route is shown.
@MainActor
final class MicRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var level: Float = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackPosition: TimeInterval = 0
    @Published private(set) var hasRecording = false
    @Published private(set) var status = "Record a short clip to hear your microphone."
    @Published private(set) var routeDescription = "Microphone route appears when recording starts."
    @Published private(set) var usedHeadsetMic = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var interruption: NSObjectProtocol?
    private var requestingPermission = false
    private var recordingRequest = UUID()
    private let recordingURL: URL

    override init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        recordingURL = directory.appendingPathComponent("earshot-mic-check.m4a")
        super.init()
        if let existing = try? AVAudioPlayer(contentsOf: recordingURL) {
            hasRecording = true
            duration = existing.duration
            status = "Your last microphone check is ready to play."
        }
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording || self.isPlaying else { return }
                self.stopRecording()
                self.stopPlayback()
                self.status = "Microphone check stopped because audio was interrupted."
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
    }

    func startRecording(maxSeconds: TimeInterval = 8) async {
        guard !isRecording, !requestingPermission else { return }
        requestingPermission = true
        let request = UUID()
        recordingRequest = request
        defer { requestingPermission = false }
        let permitted = await AVAudioApplication.requestRecordPermission()
        // Navigating away while the system permission alert is open cancels this request.
        guard recordingRequest == request else { return }
        guard permitted else {
            status = "Microphone access is off. Enable Earshot in Settings → Privacy & Security → Microphone."
            return
        }
        stopPlayback()
        let session = AVAudioSession.sharedInstance()
        do {
            // HFP allows a Bluetooth headset microphone. A2DP alone is output-only.
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true)
            if let headset = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE }) {
                try session.setPreferredInput(headset)
            }
            let next = try AVAudioRecorder(url: recordingURL, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            next.delegate = self
            next.isMeteringEnabled = true
            guard next.prepareToRecord(), next.record(forDuration: min(max(maxSeconds, 1), 30)) else {
                throw RecorderError.couldNotStart
            }
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: recordingURL.path)
            recorder = next
            duration = 0
            playbackPosition = 0
            hasRecording = false
            isRecording = true
            updateRoute()
            status = "Recording locally. Your clip stays on this device."
            beginTimer()
        } catch {
            status = "Could not record: \(error.localizedDescription)"
            releaseSession()
        }
    }

    func stopRecording() {
        recordingRequest = UUID()
        guard isRecording else { return }
        duration = max(recorder?.currentTime ?? 0, duration)
        recorder?.stop()
        recorder = nil
        // The delegate may arrive after the recorder clock has advanced past its stop point.
        // The finalized file is authoritative (observed 7.96 s audio with an 8.8 s live clock).
        if let file = try? AVAudioFile(forReading: recordingURL), file.processingFormat.sampleRate > 0 {
            duration = Double(file.length) / file.processingFormat.sampleRate
        }
        isRecording = false
        level = 0
        timer?.invalidate()
        timer = nil
        hasRecording = duration > 0 && FileManager.default.fileExists(atPath: recordingURL.path)
        status = hasRecording ? "Recording ready. Play it back or delete it." : "No recording was captured."
        releaseSession()
    }

    func play() {
        guard hasRecording else { return }
        stopRecording()
        stopPlayback()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: recordingURL)
            next.delegate = self
            guard next.prepareToPlay(), next.play() else { throw RecorderError.couldNotPlay }
            player = next
            isPlaying = true
            playbackPosition = 0
            status = "Playing your microphone check."
            beginTimer()
        } catch {
            status = "Could not play: \(error.localizedDescription)"
            releaseSession()
        }
    }

    func stopPlayback() {
        guard isPlaying else { return }
        player?.stop()
        player = nil
        isPlaying = false
        playbackPosition = 0
        timer?.invalidate()
        timer = nil
        status = "Recording ready."
        releaseSession()
    }

    func deleteRecording() {
        stopRecording()
        stopPlayback()
        do {
            if FileManager.default.fileExists(atPath: recordingURL.path) {
                try FileManager.default.removeItem(at: recordingURL)
            }
            hasRecording = false
            duration = 0
            playbackPosition = 0
            status = "Recording deleted from this device."
        } catch {
            status = "Could not delete: \(error.localizedDescription)"
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            self.stopRecording()
            if !flag { self.status = "Recording stopped before it finished. Try again." }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
            if !flag { self?.status = "Playback stopped before it finished." }
        }
    }

    private func beginTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let recorder = self.recorder, self.isRecording {
                    recorder.updateMeters()
                    self.level = min(1, max(0, pow(10, recorder.peakPower(forChannel: 0) / 20)))
                    self.duration = max(self.duration, recorder.currentTime)
                    self.updateRoute()
                }
                if let player = self.player, self.isPlaying { self.playbackPosition = player.currentTime }
            }
        }
    }

    private func updateRoute() {
        let inputs = AVAudioSession.sharedInstance().currentRoute.inputs
        usedHeadsetMic = inputs.contains { $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE }
        routeDescription = inputs.map(\.portName).joined(separator: ", ")
        if routeDescription.isEmpty { routeDescription = "No microphone route available" }
    }

    private func releaseSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private enum RecorderError: LocalizedError {
        case couldNotStart, couldNotPlay
        var errorDescription: String? {
            switch self {
            case .couldNotStart: "The audio recorder could not start. Check the current audio route."
            case .couldNotPlay: "The audio player could not start."
            }
        }
    }
}
