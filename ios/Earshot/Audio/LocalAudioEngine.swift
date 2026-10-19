import AVFoundation
import AudioToolbox
import Combine
import Foundation

/// Native playback only: iOS does not grant access to Spotify, calls, or other apps' audio streams.
@MainActor
final class LocalAudioEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var status = "Choose a local audio file to listen with EQ."
    @Published private(set) var fileName = ""
    @Published private(set) var routeName = "System audio output"
    @Published private(set) var duration = 0.0
    @Published private(set) var position = 0.0
    @Published private(set) var isBypassed = false

    var hasFile: Bool { audioFile != nil }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    // A single Apple N-band unit has a platform-dependent maximum. Keep each at 16 bands.
    private let equalizers = (0..<8).map { _ in AVAudioUnitEQ(numberOfBands: 16) }
    private let compressor = NativeAudioConfiguration.makeCompressor()
    private let limiter = NativeAudioConfiguration.makeLimiter()
    private var audioFile: AVAudioFile?
    private var ownedURL: URL?
    private var needsSchedule = true
    private var scheduleToken = UUID()
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var playbackMonitor: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var preset = BuiltInPresets.flat
    private var preamp: Double = 0
    private var enabled = false
    private var boost: Double = 0
    private var limiterEnabled = true

    init() {
        engine.attach(player)
        equalizers.forEach(engine.attach)
        engine.attach(compressor)
        engine.attach(limiter)
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let kind = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self, kind == AVAudioSession.InterruptionType.began.rawValue else { return }
                self.pause(status: "Playback paused by an audio interruption.")
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateRoute()
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                    self.pause(status: "Audio output disconnected. Press play to resume.")
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.audioFile != nil, !self.engine.isRunning else { return }
                // Hardware sample-rate changes can invalidate a player's scheduled buffers.
                self.stop()
                self.updateRoute()
                self.status = "Audio output changed. Press play to restart the track."
            }
        })
        updateRoute()
    }

    deinit {
        playbackMonitor?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func load(url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("EarshotAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            let file = try AVAudioFile(forReading: destination)
            guard file.length > 0, file.processingFormat.channelCount > 0 else { throw LocalAudioError.emptyFile }
            stop()
            engine.stop()
            engine.disconnectNodeOutput(player)
            equalizers.forEach(engine.disconnectNodeOutput)
            engine.disconnectNodeOutput(compressor)
            engine.disconnectNodeOutput(limiter)
            let chain: [AVAudioNode] = [player] + equalizers + [compressor, limiter, engine.mainMixerNode]
            for index in 0..<(chain.count - 1) {
                engine.connect(chain[index], to: chain[index + 1], format: file.processingFormat)
            }
            if let ownedURL { try? FileManager.default.removeItem(at: ownedURL) }
            ownedURL = destination
            audioFile = file
            fileName = url.lastPathComponent
            duration = Double(file.length) / file.processingFormat.sampleRate
            position = 0
            scheduledStartFrame = 0
            needsSchedule = true
            apply(preset: preset, preamp: preamp, enabled: enabled, boost: boost, limiterEnabled: limiterEnabled)
            status = "Ready · \(fileName)"
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func playPause() {
        guard let file = audioFile else { status = "Import an audio file first."; return }
        if isPlaying { pause(status: "Paused · \(fileName)"); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            if !engine.isRunning { engine.prepare(); try engine.start() }
            if needsSchedule {
                if position >= duration { position = 0; scheduledStartFrame = 0 }
                scheduleToken = UUID()
                let token = scheduleToken
                let remaining = file.length - scheduledStartFrame
                let frameCount = AVAudioFrameCount(min(remaining, AVAudioFramePosition(UInt32.max)))
                let endFrame = scheduledStartFrame + AVAudioFramePosition(frameCount)
                player.scheduleSegment(file, startingFrame: scheduledStartFrame, frameCount: frameCount, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.scheduleToken == token else { return }
                        if endFrame < file.length {
                            self.player.stop()
                            self.scheduledStartFrame = endFrame
                            self.position = Double(endFrame) / file.processingFormat.sampleRate
                            self.needsSchedule = true
                            self.isPlaying = false
                            self.playPause()
                            return
                        }
                        self.isPlaying = false
                        self.playbackMonitor?.cancel()
                        self.position = self.duration
                        self.needsSchedule = true
                        self.status = "Finished · \(self.fileName)"
                    }
                }
                needsSchedule = false
            }
            player.play()
            isPlaying = true
            beginProgressUpdates()
            updateRoute()
            status = "Playing · \(fileName)"
        } catch {
            isPlaying = false
            status = "Playback unavailable: \(error.localizedDescription)"
        }
    }

    func stop() {
        scheduleToken = UUID()
        player.stop()
        playbackMonitor?.cancel()
        isPlaying = false
        needsSchedule = true
        position = 0
        scheduledStartFrame = 0
        status = audioFile == nil ? "Choose a local audio file to listen with EQ." : "Stopped · \(fileName)"
    }

    func apply(preset: EQPreset, preamp: Double? = nil, enabled: Bool = true, boost: Double = 0, limiterEnabled: Bool = true) {
        self.preset = preset
        self.preamp = preamp ?? preset.preampDb
        self.enabled = enabled
        self.boost = boost
        self.limiterEnabled = limiterEnabled
        NativeAudioConfiguration.apply(equalizers: equalizers, compressor: compressor, limiter: limiter, preset: preset, preamp: self.preamp, enabled: enabled && !isBypassed, boost: boost, limiterEnabled: limiterEnabled, sampleRate: audioFile?.processingFormat.sampleRate ?? 48_000)
    }

    func setBypassed(_ bypassed: Bool) {
        isBypassed = bypassed
        apply(preset: preset, preamp: preamp, enabled: enabled, boost: boost, limiterEnabled: limiterEnabled)
    }

    func seek(to seconds: Double) {
        guard let file = audioFile, seconds.isFinite else { return }
        let resume = isPlaying
        scheduleToken = UUID()
        player.stop()
        playbackMonitor?.cancel()
        isPlaying = false
        position = seconds.clamped(to: 0...duration)
        scheduledStartFrame = min(file.length, AVAudioFramePosition((position * file.processingFormat.sampleRate).rounded(.down)))
        needsSchedule = true
        if resume, position < duration { playPause() }
        else { status = position >= duration ? "Finished · \(fileName)" : "Paused · \(fileName)" }
    }

    func skip(seconds: Double) { seek(to: position + seconds) }

    /// A quiet, app-generated source permits an actual playback smoke test without a file provider.
    func loadDemo() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Earshot listening sample.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let frameCount: AVAudioFrameCount = 48_000 * 12
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / 48_000
            let envelope = min(1, time * 4) * min(1, (12 - time) * 4)
            channel[frame] = Float(envelope * (0.025 * sin(2 * .pi * 220 * time) + 0.018 * sin(2 * .pi * 440 * time) + 0.012 * sin(2 * .pi * 880 * time)))
        }
        // Close the writer before the importer copies the file, so the WAV header is finalized.
        do {
            let output = try AVAudioFile(forWriting: url, settings: format.settings)
            try output.write(from: buffer)
        }
        try load(url: url)
    }

    private func pause(status: String) {
        updatePosition()
        player.pause()
        playbackMonitor?.cancel()
        isPlaying = false
        self.status = status
    }

    private func beginProgressUpdates() {
        playbackMonitor?.cancel()
        playbackMonitor = Task { [weak self] in
            while !Task.isCancelled {
                guard self?.isPlaying == true else { return }
                self?.updatePosition()
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }

    private func updatePosition() {
        guard let file = audioFile, let renderTime = player.lastRenderTime, let played = player.playerTime(forNodeTime: renderTime) else { return }
        position = (Double(scheduledStartFrame) / file.processingFormat.sampleRate + Double(played.sampleTime) / played.sampleRate).clamped(to: 0...duration)
    }

    private func updateRoute() {
        routeName = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: ", ")
        if routeName.isEmpty { routeName = "System audio output" }
    }
}

enum LocalAudioError: LocalizedError {
    case emptyFile, renderFailed
    var errorDescription: String? {
        switch self {
        case .emptyFile: return "This file has no playable audio."
        case .renderFailed: return "The native audio processor could not render this buffer."
        }
    }
}

enum NativeAudioConfiguration {
    static func makeCompressor() -> AVAudioUnitEffect {
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        let unit = AVAudioUnitEffect(audioComponentDescription: description)
        AudioUnitSetParameter(unit.audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, -3, 0)
        AudioUnitSetParameter(unit.audioUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 0.1, 0)
        AudioUnitSetParameter(unit.audioUnit, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1, 0)
        AudioUnitSetParameter(unit.audioUnit, kDynamicsProcessorParam_ExpansionThreshold, kAudioUnitScope_Global, 0, -80, 0)
        AudioUnitSetParameter(unit.audioUnit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.0001, 0)
        AudioUnitSetParameter(unit.audioUnit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.060, 0)
        AudioUnitSetParameter(unit.audioUnit, kDynamicsProcessorParam_OverallGain, kAudioUnitScope_Global, 0, 0, 0)
        return unit
    }

    static func makeLimiter() -> AVAudioUnitEffect {
        let description = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        let limiter = AVAudioUnitEffect(audioComponentDescription: description)
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.060, 0)
        return limiter
    }

    static func bandwidthOctaves(q: Double) -> Double {
        (2 * asinh(1 / (2 * q.clamped(to: EQBand.qRange))) / log(2)).clamped(to: 0.05...5)
    }

    static func apply(equalizers: [AVAudioUnitEQ], compressor: AVAudioUnitEffect, limiter: AVAudioUnitEffect, preset: EQPreset, preamp: Double, enabled: Bool, boost: Double, limiterEnabled: Bool, sampleRate: Double) {
        for (index, parameters) in equalizers.flatMap(\.bands).enumerated() {
            guard index < preset.bands.count else { parameters.bypass = true; continue }
            let band = preset.bands[index]
            parameters.bypass = !enabled || !band.enabled
            parameters.frequency = Float(band.frequencyHz.clamped(to: 20...max(20, sampleRate * 0.499)))
            parameters.gain = Float(band.gainDb.clamped(to: EQBand.gainRange))
            parameters.bandwidth = Float(bandwidthOctaves(q: band.q))
            switch band.type {
            case .peak: parameters.filterType = .parametric
            case .lowShelf: parameters.filterType = .resonantLowShelf
            case .highShelf: parameters.filterType = .resonantHighShelf
            }
        }
        let effectiveBoost = Headroom.clampBoost(boost, limiterEnabled: limiterEnabled)
        // Automatic headroom can require more attenuation than the manual preamp control.
        let userPreamp = preamp.clamped(to: -96...0)
        let recommendation = Headroom.recommendedPreampDb(bands: preset.bands, sampleRate: sampleRate)
        // The dynamics unit handles sustained overload; the final limiter catches transients.
        let safePreamp = limiterEnabled ? userPreamp : min(userPreamp, recommendation - effectiveBoost - 1)
        for (index, unit) in equalizers.enumerated() {
            let gain = safePreamp + effectiveBoost
            unit.globalGain = enabled && index == 0 ? Float(gain.clamped(to: -96...24)) : 0
        }
        compressor.bypass = !enabled || !limiterEnabled
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 0, 0)
        limiter.bypass = !enabled || !limiterEnabled
    }
}

/// Exercises Apple's actual AVAudioUnitEQ and peak limiter using AVAudioEngine offline rendering.
enum NativeEQRenderer {
    static func render(samples: [Float], sampleRate: Double = 48_000, preset: EQPreset, preamp: Double? = nil, enabled: Bool = true, boost: Double = 0, limiterEnabled: Bool = true) throws -> [Float] {
        guard !samples.isEmpty else { return [] }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let equalizers = (0..<max(1, (preset.bands.count + 15) / 16)).map { _ in AVAudioUnitEQ(numberOfBands: 16) }
        let compressor = NativeAudioConfiguration.makeCompressor()
        let limiter = NativeAudioConfiguration.makeLimiter()
        engine.attach(player)
        equalizers.forEach(engine.attach)
        engine.attach(compressor)
        engine.attach(limiter)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let chain: [AVAudioNode] = [player] + equalizers + [compressor, limiter, engine.mainMixerNode]
        for index in 0..<(chain.count - 1) { engine.connect(chain[index], to: chain[index + 1], format: format) }
        NativeAudioConfiguration.apply(equalizers: equalizers, compressor: compressor, limiter: limiter, preset: preset, preamp: preamp ?? preset.preampDb, enabled: enabled, boost: boost, limiterEnabled: limiterEnabled, sampleRate: sampleRate)
        let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        source.frameLength = source.frameCapacity
        samples.withUnsafeBufferPointer { source.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        player.scheduleBuffer(source)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        try engine.start()
        player.play()
        defer { player.stop(); engine.stop(); engine.disableManualRenderingMode() }
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        var result: [Float] = []
        var retries = 0
        while result.count < samples.count {
            let count = AVAudioFrameCount(min(1024, samples.count - result.count))
            switch try engine.renderOffline(count, to: output) {
            case .success:
                result.append(contentsOf: UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
                retries = 0
            case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
                retries += 1
                guard retries < 20 else { throw LocalAudioError.renderFailed }
            case .error: throw LocalAudioError.renderFailed
            @unknown default: throw LocalAudioError.renderFailed
            }
        }
        return result
    }
}
