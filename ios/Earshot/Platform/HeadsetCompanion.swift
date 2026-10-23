// Original Earshot generic headset, EQ memory, shortcuts and voice memo design:
// HellzYeahh and contributors, MIT. This AI-assisted iOS adaptation uses public Apple APIs.
import AVFoundation
import Combine
import Foundation

struct CompanionAudioOutput: Equatable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let isHeadphones: Bool
    static func from(_ port: AVAudioSessionPortDescription) -> Self {
        let external: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .usbAudio, .lineOut, .airPlay]
        return .init(id: port.uid, name: port.portName, kind: port.portType.rawValue, isHeadphones: external.contains(port.portType))
    }
}

@MainActor
final class HeadsetCompanion: NSObject, ObservableObject {
    @Published private(set) var output: CompanionAudioOutput?
    @Published private(set) var outputVolume: Float = 0
    @Published private(set) var status = "Choose an audio output in the system route picker."
    @Published var preferences: HeadsetPreferences { didSet { persist() } }
    let memos: CompanionVoiceMemos
    var availablePresets: () -> [EQPreset] = { BuiltInPresets.all }
    var currentEQ: () -> (enabled: Bool, presetID: String?) = { (false, nil) }
    var applyEQ: (String?) -> Void = { _ in }
    var onOutputChanged: ((CompanionAudioOutput?, AudioRouteObservationReason) -> Void)?
    var canSpeakFeedback: () -> Bool = { true }
    var beforeRecording: (() throws -> Void)? {
        get { memos.beforeRecording }
        set { memos.beforeRecording = { [weak self] in self?.stopSpokenFeedback(); try newValue?() } }
    }
    var isAppActive = false {
        didSet {
            memos.isAppActive = isAppActive
            if !isAppActive { memos.stopRecording(); speech.stopSpeaking(at: .immediate) }
        }
    }
    private let defaults: UserDefaults
    private let speech = AVSpeechSynthesizer()
    private var routeObserver: NSObjectProtocol?
    private var volumeObserver: NSKeyValueObservation?
    private var lastOutputID: String?
    static let preferencesKey = "earshot.ios.headsetCompanion"

    init(defaults: UserDefaults = .standard, observeAudioRoute: Bool = true, memoDirectory: URL? = nil) {
        self.defaults = defaults
        preferences = defaults.data(forKey: Self.preferencesKey).flatMap { try? JSONDecoder().decode(HeadsetPreferences.self, from: $0) } ?? HeadsetPreferences()
        memos = CompanionVoiceMemos(directory: memoDirectory)
        super.init()
        speech.usesApplicationAudioSession = false
        if observeAudioRoute {
            // Root wires preset/application callbacks before the first explicit refresh.
            routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
                let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                let reason: AudioRouteObservationReason
                switch raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) {
                case .newDeviceAvailable: reason = .newDeviceAvailable
                case .oldDeviceUnavailable: reason = .oldDeviceUnavailable
                case .override, .routeConfigurationChange: reason = .routeSelection
                case .categoryChange, .noSuitableRouteForCategory: reason = .categoryChange
                case .wakeFromSleep: reason = .refresh
                default: reason = .unknown
                }
                Task { @MainActor [weak self] in self?.refreshRoute(reason: reason) }
            }
            volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.outputVolume = AVAudioSession.sharedInstance().outputVolume }
            }
        }
    }
    deinit { if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) } }
    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: Self.preferencesKey) }
    }
    func refreshRoute(reason: AudioRouteObservationReason = .refresh) {
        let session = AVAudioSession.sharedInstance()
        outputVolume = session.outputVolume
        let ports = session.currentRoute.outputs
        acceptOutput(ports.first(where: { CompanionAudioOutput.from($0).isHeadphones }).map(CompanionAudioOutput.from) ?? ports.first.map(CompanionAudioOutput.from), reason: reason)
    }
    /// Receives audio-session facts only; it never changes the BMAP control-link state.
    func acceptOutput(_ next: CompanionAudioOutput?, reason: AudioRouteObservationReason = .refresh) {
        output = next
        defer { onOutputChanged?(next, reason) } // Restore memory before a temporary connection rule.
        // Changing this app's category/input does not mean the user connected another
        // headset. It must not overwrite a temporary rule preset with remembered EQ.
        guard reason != .categoryChange, reason != .microphoneTransition, !memos.isRecording else { return }
        guard next?.id != lastOutputID else { return }
        lastOutputID = next?.id
        guard let next, next.isHeadphones else { status = "No external audio output is selected. This is separate from headphone control connectivity."; return }
        switch HeadsetEQRestoreDecision.decide(selection: preferences.outputEQ[next.id], enabled: preferences.rememberEQ, availableIDs: Set(availablePresets().map(\.id))) {
        case .unchanged: status = "Audio output: \(next.name). No saved local EQ change."
        case .apply(let id): applyEQ(id); status = "Restored \(id == nil ? "local EQ off" : "saved local EQ") for \(next.name)."
        case .forgetMissing: preferences.outputEQ.removeValue(forKey: next.id); status = "The saved local EQ preset for \(next.name) was removed. Choose another preset."
        }
    }
    /// Call only for a user's explicit preset/off selection, never automation or route restoration.
    func rememberExplicitPick(_ presetID: String?) {
        guard preferences.rememberEQ, let output, output.isHeadphones else { return }
        if let presetID, !availablePresets().contains(where: { $0.id == presetID }) { status = "That preset is unavailable."; return }
        guard preferences.remember(presetID.map(HeadsetEQSelection.preset) ?? .off, outputID: output.id) else {
            status = "Output memory is full. Forget an old output before adding another."; return
        }
        status = "Remembered \(presetID == nil ? "local EQ off" : "local EQ preset") for \(output.name)."
    }
    func forgetCurrentOutput() { if let id = output?.id { preferences.outputEQ.removeValue(forKey: id); preferences.outputActions.removeValue(forKey: id) } }
    @discardableResult func cycleEQ() -> String? {
        let presets = availablePresets()
        guard let next = CompanionEQCycle.next(presetIDs: presets.map(\.id), currentID: currentEQ().presetID) else { status = "No local EQ presets are available."; return nil }
        applyEQ(next)
        feedback(presets.first(where: { $0.id == next })?.name ?? "Local EQ changed")
        return next
    }
    func feedback(_ text: String) {
        status = String(text.prefix(300))
        guard preferences.spokenFeedback, isAppActive, !memos.isRecording, canSpeakFeedback() else { return }
        speech.stopSpeaking(at: .immediate)
        speech.speak(AVSpeechUtterance(string: status))
    }
    func stopSpokenFeedback() { speech.stopSpeaking(at: .immediate) }
    @discardableResult func perform(_ action: CompanionAction) async -> String {
        switch action {
        case .none: status = "Choose an Earshot action in Companion controls."
        case .cycleEQ: _ = cycleEQ()
        case .voiceMemo:
            speech.stopSpeaking(at: .immediate)
            if memos.isRecording { memos.stopRecording(); feedback(memos.status) }
            else { await memos.startRecording(); status = memos.status }
        }
        return status
    }
    @discardableResult func runConfiguredAction() async -> String { await perform(preferences.action(for: output?.id)) }
}

struct CompanionMemo: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let duration: TimeInterval
    let bytes: Int64
    let url: URL
    var title: String { "Earshot memo \(date.formatted(date: .abbreviated, time: .shortened))" }
}

enum CompanionMemoError: LocalizedError {
    case inactive, capacity, invalidRecording, missing, invalidName
    var errorDescription: String? {
        switch self {
        case .inactive: return "Open Earshot to start a voice memo."
        case .capacity: return "Voice memo storage is full (100 memos or 256 MiB). Share and delete a memo before recording."
        case .invalidRecording: return "No playable audio was captured."
        case .missing: return "This voice memo is no longer available."
        case .invalidName: return "This file is not an Earshot voice memo."
        }
    }
}

/// Persistent app-owned files. Saved memos are never silently evicted; only expired
/// unfinished recordings are cleaned. No arbitrary user path is accepted for deletion.
enum CompanionMemoStorage {
    static let maximumCount = 100
    static let maximumBytes: Int64 = 256 * 1024 * 1024
    static let maximumSeconds: TimeInterval = 30 * 60
    static func url(id: UUID, directory: URL, pending: Bool = false) -> URL {
        directory.appendingPathComponent("\(id.uuidString)\(pending ? ".pending" : "").m4a")
    }
    static func identifier(for url: URL) -> UUID? { UUID(uuidString: url.deletingPathExtension().lastPathComponent) }
    static func mayRecord(count: Int, bytes: Int64) -> Bool { count < maximumCount && bytes < maximumBytes - 1024 * 1024 }
    static func cleanExpiredPartials(in directory: URL, now: Date = .now) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
        for file in files where file.lastPathComponent.hasSuffix(".pending.m4a") {
            let info = try file.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true, let modified = info.contentModificationDate, now.timeIntervalSince(modified) > 24 * 60 * 60,
                  UUID(uuidString: file.deletingPathExtension().deletingPathExtension().lastPathComponent) != nil else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }
}

@MainActor
final class CompanionVoiceMemos: NSObject, ObservableObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    @Published private(set) var recordings: [CompanionMemo] = []
    @Published private(set) var isRecording = false
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var playbackPosition: TimeInterval = 0
    @Published private(set) var playingID: UUID?
    @Published private(set) var status = "Voice memos stay on this device until you explicitly share or delete them."
    @Published private(set) var microphoneRoute = "Microphone route appears while recording."
    var beforeRecording: (() throws -> Void)?
    var mayReleaseAudioSession: () -> Bool = { true }
    var isAppActive = false {
        didSet { if !isAppActive { stopRecording(); stopPlayback() } }
    }
    let directory: URL
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var activeID: UUID?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var permissionRequest: UUID?
    private var ownsSession = false

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Earshot Voice Memos", isDirectory: true)
        super.init()
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            try CompanionMemoStorage.cleanExpiredPartials(in: self.directory)
            reload()
        } catch { status = "Voice memo storage unavailable: \(error.localizedDescription)" }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopRecording(); self?.stopPlayback() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor [weak self] in self?.stopRecording(); self?.stopPlayback() }
            }
        })
    }
    deinit { timer?.invalidate(); observers.forEach(NotificationCenter.default.removeObserver) }
    func reload() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey, .isSymbolicLinkKey])
            recordings = files.compactMap { file -> CompanionMemo? in
                guard file.pathExtension == "m4a", let id = CompanionMemoStorage.identifier(for: file),
                      let values = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey, .isSymbolicLinkKey]), values.isSymbolicLink != true,
                      let audio = try? AVAudioFile(forReading: file), audio.processingFormat.sampleRate > 0, audio.length > 0 else { return nil }
                return .init(id: id, date: values.creationDate ?? .distantPast, duration: Double(audio.length) / audio.processingFormat.sampleRate, bytes: Int64(values.fileSize ?? 0), url: file)
            }.sorted { $0.date > $1.date }
        } catch { status = "Could not list voice memos: \(error.localizedDescription)" }
    }
    func startRecording() async {
        guard !isRecording, permissionRequest == nil else { return }
        guard isAppActive else { status = CompanionMemoError.inactive.localizedDescription; return }
        reload()
        guard CompanionMemoStorage.mayRecord(count: recordings.count, bytes: recordings.reduce(0) { $0 + $1.bytes }) else { status = CompanionMemoError.capacity.localizedDescription; return }
        let request = UUID(); permissionRequest = request
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard permissionRequest == request else { return }
        permissionRequest = nil
        guard allowed else { status = "Allow Microphone access in iOS Settings to record a memo."; return }
        guard isAppActive else { status = CompanionMemoError.inactive.localizedDescription; return }
        stopPlayback()
        let id = UUID(), target = CompanionMemoStorage.url(id: id, directory: directory, pending: true)
        do {
            try beforeRecording?()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker])
            try session.setActive(true); ownsSession = true
            if let input = session.availableInputs?.first(where: { [.bluetoothHFP, .bluetoothLE].contains($0.portType) }) { try session.setPreferredInput(input) }
            let next = try AVAudioRecorder(url: target, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000])
            next.delegate = self
            guard next.prepareToRecord(), next.record(forDuration: CompanionMemoStorage.maximumSeconds) else { throw CompanionMemoError.invalidRecording }
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
            recorder = next; activeID = id; elapsed = 0; isRecording = true
            microphoneRoute = session.currentRoute.inputs.map(\.portName).joined(separator: ", ")
            status = "Recording a voice memo · 30 minute maximum"
            beginTimer()
        } catch {
            try? FileManager.default.removeItem(at: target)
            releaseSession(); status = "Could not record: \(error.localizedDescription)"
        }
    }
    func stopRecording() {
        permissionRequest = nil
        guard isRecording, let id = activeID else { return }
        recorder?.stop(); recorder = nil; isRecording = false; activeID = nil; timer?.invalidate(); timer = nil
        let pending = CompanionMemoStorage.url(id: id, directory: directory, pending: true)
        do {
            let audio = try AVAudioFile(forReading: pending)
            guard audio.length > 0 else { throw CompanionMemoError.invalidRecording }
            let size = Int64((try pending.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
            guard recordings.reduce(0, { $0 + $1.bytes }) + size <= CompanionMemoStorage.maximumBytes else { throw CompanionMemoError.capacity }
            elapsed = Double(audio.length) / audio.processingFormat.sampleRate
            try FileManager.default.moveItem(at: pending, to: CompanionMemoStorage.url(id: id, directory: directory))
            status = "Voice memo saved on this device."
        } catch { try? FileManager.default.removeItem(at: pending); status = "Memo could not be saved: \(error.localizedDescription)" }
        releaseSession(); reload()
    }
    func play(_ id: UUID) {
        guard isAppActive else { status = "Open Earshot to play a voice memo."; return }
        guard !isRecording, let memo = recordings.first(where: { $0.id == id }) else { return }
        stopPlayback()
        do {
            try beforeRecording?() // The same exclusivity hook stops other app-owned audio.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback); try session.setActive(true); ownsSession = true
            let next = try AVAudioPlayer(contentsOf: memo.url)
            next.delegate = self
            guard next.prepareToPlay(), next.play() else { throw CompanionMemoError.invalidRecording }
            player = next; playingID = id; isPlaying = true; playbackPosition = 0; status = "Playing \(memo.title)"; beginTimer()
        } catch { releaseSession(); status = "Could not play memo: \(error.localizedDescription)" }
    }
    func stopPlayback() {
        guard isPlaying else { return }
        player?.stop(); player = nil; isPlaying = false; playingID = nil; playbackPosition = 0; timer?.invalidate(); timer = nil; releaseSession(); status = "Voice memo ready."
    }
    func delete(_ id: UUID) {
        guard !isRecording, let memo = recordings.first(where: { $0.id == id }), memo.url == CompanionMemoStorage.url(id: id, directory: directory) else { return }
        if playingID == id { stopPlayback() }
        do { try FileManager.default.removeItem(at: memo.url); reload(); status = "Voice memo deleted." }
        catch { status = "Could not delete memo: \(error.localizedDescription)" }
    }
    private func beginTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let recorder = self.recorder, self.isRecording {
                    self.elapsed = recorder.currentTime
                    if self.recordings.reduce(0, { $0 + $1.bytes }) + Int64(self.elapsed * 10_000) >= CompanionMemoStorage.maximumBytes { self.stopRecording() }
                }
                if let player = self.player, self.isPlaying { self.playbackPosition = player.currentTime }
            }
        }
    }
    private func releaseSession() {
        guard ownsSession else { return }; ownsSession = false
        if mayReleaseAudioSession() { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in if self?.recorder === recorder { self?.stopRecording() } }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in if self?.player === player { self?.stopPlayback() } }
    }
}
