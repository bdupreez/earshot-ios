import SwiftUI
import Combine

@MainActor final class AppStore: ObservableObject {
    @Published var saved: SavedAppState { didSet { persist() } }
    @Published var message: String?
    @Published var battery: Int?
    @Published var batteries: [String: Int] = [:]
    @Published var firmware = "Not read"
    @Published var batteryMinutes: Int?
    @Published var batteryReadings: [BoseBatteryReading] = []
    @Published var pairingMode: Bool?
    @Published var voicePromptsState: BoseVoicePromptsState?
    @Published var sourceCommandSupport: Set<BoseSourceAction> = []
    @Published var deviceRequestStatus = ""
    @Published var deviceStatus = BoseDeviceStatus()
    @Published private(set) var cncState: BoseCNCState?
    @Published var stateRecoveryURL: URL?
    var pendingDeviceOperation: PendingDeviceOperation?
    var deviceOperationTask: Task<Void, Never>?
    var modelFacts: BoseModelFacts?
    var reportedModeIDs: Set<Int> = []
    var appIsActive = false
    var lastSharedSnapshot: EarshotWidgetSnapshot?
    var lastIntentCatalog: EarshotIntentCatalog?
    var lastReminderRules: [AutomationRule]?
    @Published var shortcutStatus = ""
    @Published var shortcutLog: [String] = []
    var queuedAppRequests: [EarshotCommandEnvelope] = []
    var appRequestTask: Task<Void, Never>?
    @Published var liveFunctions = Set<String>()
    @Published var automationLog: [String] = []
    @Published var ruleStatuses: [String: String] = [:]
    @Published var activeRuleID: String?
    var automationTask: Task<Void, Never>?
    var commandFailureVersion = 0
    @Published var welcome: Bool
    @Published private(set) var liveDeviceName = "Bose headphones · identifying"
    @Published private(set) var liveProfile: DeviceProfile?
    @Published private(set) var deviceVolume: Double = 0
    @Published private(set) var deviceVolumeMaximum = 0
    @Published private(set) var playbackStatus = "Not reported"
    @Published private(set) var playbackActions: Set<Int> = []
    @Published private(set) var leAudio: Bool?
    @Published var deviceLatency = "Not reported"
    @Published var deviceLatencyRange: ClosedRange<Int>?
    @Published var deviceLatencyValue: Int?
    @Published var audioSource = "Not reported"
    @Published var pairedSources: [BosePairedSource] = []
    @Published private(set) var buttonShortcut: BoseButtonShortcut?
    let bluetooth = HeadphoneBluetooth()
    let audio = LocalAudioEngine()
    let mic = MicRecorder()
    let routes = AudioRouteObserver()
    let notifications = NotificationManager()
    let wifi = WiFiObserver()
    var lastWiFiActive: Bool?
    var observedWiFiSSID: String?
    var firedWiFiRuleIDs = Set<String>()
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private var lastConnected = false
    var liveModes: [Int: BoseMode] = [:]
    private var modesCapabilities: BoseModesCapabilities?
    private var favorites: Set<Int> = []
    private var favoriteTotal = 0
    private var voiceLanguage: UInt8?
    private var charging = false
    private var unavailableBlocks: Set<UInt8> = []
    private var refusedFunctions: Set<BmapAddress> = []
    private var pendingWrites: Set<BmapAddress> = []
    private var eqRanges: [UInt8: ClosedRange<Int>] = [:]
    private var subscribed = false
    private var lePreferenceRequested = false
    private var batteryPollTask: Task<Void, Never>?
    private var connectionRulesPending = false
    private var firedConnectionRuleIDs = Set<String>()

    init(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.defaults = defaults
        if arguments.contains("--uitesting") { defaults.removeObject(forKey: "earshot.ios.state") ; defaults.removeObject(forKey: "earshot.welcomed") }
        welcome = !defaults.bool(forKey: "earshot.welcomed")
        let originalData = defaults.data(forKey: "earshot.ios.state")
        let decoded = originalData.flatMap { try? JSONDecoder().decode(SavedAppState.self, from: $0) }
        saved = decoded ?? SavedAppState()
        audio.mayReleaseAudioSession = { [weak self] in
            guard let self else { return true }
            return !self.mic.isRecording && !self.mic.isPlaying
        }
        if let originalData, decoded == nil || saved.recoveredItemCount > 0 {
            do {
                let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Earshot-Recovery", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("state-\(UUID().uuidString).json")
                try originalData.write(to: url, options: [.atomic, .completeFileProtection])
                stateRecoveryURL = url
                message = "Saved data contained unreadable records. Other settings were retained; export the original data from App preferences for recovery."
            } catch {
                defaults.set(originalData, forKey: "earshot.ios.state.recovery")
                message = "Some saved records could not be read. The original bytes were preserved in local recovery storage."
            }
        }
        if stateRecoveryURL == nil {
            // Repairing saved JSON must not hide the original recovery export on
            // the next clean launch. Retain access to the newest preserved file.
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Earshot-Recovery", isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
            stateRecoveryURL = files.filter { $0.pathExtension == "json" }.max {
                let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return a < b
            }
        }
        if saved.eq.count != 3 || saved.eq.contains(where: { !$0.isFinite || !(-10...10).contains($0) }) { saved.eq = [0, 0, 0] }
        bluetooth.onPacket = { [weak self] packet in self?.receive(packet) }
        wifi.onSSIDChange = { [weak self] ssid in self?.observedWiFiJoin(ssid) }
        wifi.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        notifications.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        bluetooth.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        bluetooth.$isConnected.removeDuplicates().sink { [weak self] connected in
            // @Published emits before its storage changes; defer guards until the new value is visible.
            Task { @MainActor [weak self] in
                guard let self, self.bluetooth.isConnected == connected else { return }
                if connected {
                    self.connectionRulesPending = true
                    self.firedWiFiRuleIDs = []
                    self.firedConnectionRuleIDs = []
                    self.refresh(); self.startBatteryFallback(); self.processConnectionRules(); self.processWiFiRules()
                } else if !self.saved.demo {
                    self.refreshTask?.cancel(); self.batteryPollTask?.cancel(); self.clearLiveState()
                }
                self.lastConnected = connected
            }
        }.store(in: &cancellables)
        if saved.demo { hydrateDemo() }
        else if !welcome { bluetooth.start() }
        if let warning = normalizePresetLibrary() { message = warning }
        applyAudio()
    }
    var profile: DeviceProfile {
        if saved.demo { return DeviceProfile.all.first { $0.id == saved.profileID } ?? DeviceProfile.all[0] }
        var result = liveProfile ?? DeviceProfile(id: "unknown", name: liveDeviceName, spatial: false, noise: false, wind: false, presets: [], customCount: 0)
        if let capabilities = modesCapabilities {
            result.noise = capabilities.cnc || capabilities.ancToggle
            result.spatial = capabilities.spatial; result.wind = capabilities.wind; result.customCount = capabilities.custom
        }
        return result
    }
    var connected: Bool { saved.demo || bluetooth.isConnected }
    var modeName: String { if saved.currentMode == 255 { return "Unsaved listening settings" }; return saved.modes.first { $0.id == saved.currentMode }?.name ?? "No mode selected" }
    var presets: [EQPreset] { BuiltInPresets.all + saved.customPresets }
    var preset: EQPreset { presets.first { $0.id == saved.presetID } ?? BuiltInPresets.flat }
    func supports(_ block: Int, _ function: Int) -> Bool { saved.demo || liveFunctions.contains("\(block).\(function)") }
    var canEditFavorites: Bool { saved.demo || connected && supports(31, 8) && favoriteTotal > 0 && !profile.unsupported }
    var canControlNoise: Bool { saved.demo || connected && !profile.unsupported && (supports(31, 10) || usesDirectNoise() || canEditMode(saved.currentMode)) }
    func canEditMode(_ id: Int) -> Bool {
        saved.demo || connected && !profile.unsupported && liveModes[id]?.editable == true &&
            [44, 45, 47, 48].contains(liveModes[id]?.raw.count ?? 0)
    }
    func usesDirectNoise(for modeID: Int? = nil) -> Bool {
        !supports(31, 10) && supports(1, 5) && cncState != nil &&
            (modelFacts?.directNoise == true || !canEditMode(modeID ?? saved.currentMode))
    }
    func canToggleANC(for modeID: Int? = nil) -> Bool {
        if saved.demo { return !profile.legacy }
        if supports(31, 10) { return modesCapabilities?.ancToggle == true }
        if usesDirectNoise(for: modeID) { return cncState?.userCanToggle == true }
        return liveModes[modeID ?? saved.currentMode]?.raw.count == 48 && modesCapabilities?.ancToggle != false
    }
    func noiseProfile(for modeID: Int? = nil) -> DeviceProfile {
        var value = profile
        if !saved.demo, usesDirectNoise(for: modeID) {
            // CNC [1.5] can only change level/ANC. Model catalogue defaults must
            // not imply that this write path can also change Wind or Spatial.
            value.wind = false; value.spatial = false
        }
        return value
    }
    func expectedNoiseReport(_ requested: NoiseState) throws -> NoiseState {
        let settings = audioSettings(requested)
        if usesDirectNoise(), let cncState { return noiseState(try cncState.expectedDirectReport(for: settings)) }
        return noiseState(settings.expectedModeReport(for: supports(31, 10) ? nil : liveModes[saved.currentMode]))
    }

    func finishWelcome(demo: Bool) {
        defaults.set(true, forKey: "earshot.welcomed"); welcome = false
        if demo { setDemo(true) } else { bluetooth.scan() }
    }
    func setDemo(_ enabled: Bool) {
        refreshTask?.cancel(); batteryPollTask?.cancel()
        bluetooth.suspend(); clearLiveState(); saved.demo = enabled
        if enabled { hydrateDemo(); runConnectionRules() }
        else { battery = nil; batteries = [:]; saved.modes = []; firmware = "Not read"; bluetooth.start() }
    }
    func selectProfile(_ id: String) {
        guard saved.demo else { return }
        saved.profileID = id; saved.modes = []; saved.currentMode = 0; saved.noise = .init()
        if saved.demo { hydrateDemo() }
    }
    private func hydrateDemo() {
        if saved.modes.isEmpty {
            saved.modes = profile.presets.enumerated().map { ListeningMode(id: $0.offset, name: $0.element, builtIn: true, favorite: true, noise: .init(level: $0.offset == 1 ? 0 : 10, spatial: $0.offset >= 2 ? 1 : 0)) }
            saved.modes += (0..<profile.customCount).map { ListeningMode(id: profile.presets.count + $0, name: "Custom \($0 + 1)", builtIn: false, configured: false) }
        }
        deviceStatus = BoseDeviceStatus(microphoneMuted: false, operationMode: .normal, leAudioSupported: !profile.legacy)
        batteryMinutes = profile.earbuds ? 240 : 720
        batteryReadings = [BoseBatteryReading(component: 0, percent: 82, remainingMinutes: batteryMinutes)]
        pairingMode = false
        voicePromptsState = BoseVoicePromptsState(enabled: saved.voicePrompts, language: saved.demoVoiceLanguage, installedLanguages: Set(BoseVoicePromptsState.languages.keys.map(Int.init)))
        sourceCommandSupport = Set(BoseSourceAction.allCases)
        battery = 82; batteries = profile.earbuds ? ["Left": 82, "Right": 78, "Case": 64] : [:]; firmware = "10.12.12 · simulated"
        deviceVolumeMaximum = 31; deviceVolume = 18; playbackStatus = "Paused · simulated"
        playbackActions = [0, 1, 2, 3, 4]; leAudio = !profile.legacy
        deviceLatencyRange = 100...400; deviceLatencyValue = 210
        deviceLatency = "210 (reported units; simulated)"; audioSource = "Bluetooth · simulated"
        if profile.earbuds {
            battery = 78
            batteryReadings = [BoseBatteryReading(component: 1, percent: 78, remainingMinutes: 240), BoseBatteryReading(component: 2, percent: 82, remainingMinutes: 260), BoseBatteryReading(component: 3, percent: 64, remainingMinutes: nil)]
        }
        pairedSources = [BosePairedSource(address: Data([0x10, 0, 0, 0, 0, 1]), name: "Demo iPhone", connected: true, isLocal: true), BosePairedSource(address: Data([0x10, 0, 0, 0, 0, 2]), name: "Demo laptop", connected: false)]
        buttonShortcut = BoseButtonShortcut(button: 0x80, event: 9, action: 19, supported: [1, 14, 16, 19])
    }
    func selectMode(_ index: Int) {
        guard connected, (0...254).contains(index), let mode = saved.modes.first(where: { $0.id == index && $0.configured }) else { return }
        if saved.demo { saved.currentMode = index; saved.noise = mode.noise }
        else if supports(31, 3), !profile.unsupported { send(BoseCommands.selectMode(index: UInt8(index))) }
    }
    func changeNoise(_ noise: NoiseState) {
        guard connected, noise.level.isFinite, (0...10).contains(noise.level), (0...2).contains(noise.spatial) else { return }
        if saved.demo { saved.noise = noise }
        else {
            guard canControlNoise else { return }
            do {
                if noise.enabled != saved.noise.enabled, !canToggleANC() {
                    message = "These headphones have not reported support for switching noise cancellation on or off."
                    return
                }
                if supports(31, 10) { send(try BoseCommands.setAudio(audioSettings(noise))); send(BoseCommands.readCurrentMode) }
                else if usesDirectNoise(), let cncState { send(try BoseCommands.setDirectNoise(audioSettings(noise), state: cncState)) }
                else if let mode = liveModes[saved.currentMode], canEditMode(saved.currentMode) { send(try BoseCommands.writeMode(mode, settings: audioSettings(noise))) }
            } catch { message = error.localizedDescription }
        }
    }
    func setEQ(_ index: Int, value: Double) {
        guard connected, saved.eq.indices.contains(index), value.isFinite, (-10...10).contains(value) else { return }
        if saved.demo { saved.eq[index] = value }
        else if supports(1, 7), !profile.unsupported {
            let range = eqRanges[UInt8(index)] ?? -10...10
            do { send(try BoseCommands.setEQ(band: UInt8(index), value: min(range.upperBound, max(range.lowerBound, Int(value))))) } catch { message = error.localizedDescription }
        }
    }
    func setSetting(_ key: String, value: Bool, function: UInt8) {
        if saved.demo {
            switch key { case "autoPause": saved.autoPause = value; case "autoAnswer": saved.autoAnswer = value; case "multipoint": saved.multipoint = value; case "voicePrompts": saved.voicePrompts = value; if let voice = voicePromptsState { voicePromptsState = BoseVoicePromptsState(enabled: value, language: voice.language, installedLanguages: voice.installedLanguages) }; case "touchControls": saved.touchControls = value; default: break }
        } else {
            guard connected, supports(1, Int(function)), !profile.unsupported else { return }
            do {
                if function == 34 { send(BoseCommands.setTouchControls(enabled: value)) }
                else if function == 3 {
                    guard let voiceLanguage else { return }
                    send(try BoseCommands.setVoicePrompts(enabled: value, language: voiceLanguage))
                } else if [10, 24, 27].contains(function) { send(BoseCommands.setToggle(function: function, enabled: value)) }
            } catch { message = error.localizedDescription }
        }
    }
    func updateSidetone(_ value: Int) {
        guard (0...3).contains(value) else { return }
        if saved.demo { saved.sidetone = value }
        else if supports(1, 11), !profile.unsupported { do { send(try BoseCommands.setSidetone(level: UInt8(value))) } catch { message = error.localizedDescription } }
    }
    func updateAutoOff(_ value: Int) {
        if saved.demo { saved.autoOff = value }
        else if supports(1, 4), !profile.unsupported { do { send(try BoseCommands.setStandby(minutes: value)) } catch { message = error.localizedDescription } }
    }
    func saveMode(_ mode: ListeningMode) {
        guard !mode.name.trimmingCharacters(in: .whitespaces).isEmpty, mode.name.utf8.count <= 31 else { message = "Use a name of 1–31 UTF-8 bytes."; return }
        guard mode.noise.level.isFinite, (0...10).contains(mode.noise.level), (0...2).contains(mode.noise.spatial) else { message = "The listening settings are outside the supported range."; return }
        if saved.demo {
            if let i = saved.modes.firstIndex(where: { $0.id == mode.id }) { saved.modes[i] = mode; saved.modes[i].configured = true }
        } else if canEditMode(mode.id), let raw = liveModes[mode.id] {
            do { send(try BoseCommands.writeMode(raw, name: raw.name == mode.name ? nil : mode.name, settings: audioSettings(mode.noise))) }
            catch { message = error.localizedDescription }
        }
    }
    func resetMode(_ id: Int) {
        guard canEditMode(id), let index = saved.modes.firstIndex(where: { $0.id == id }), !saved.modes[index].builtIn else { return }
        if saved.demo {
            saved.modes[index].name = "Custom \(id - profile.presets.count + 1)"
            saved.modes[index].configured = false; saved.modes[index].favorite = false; saved.modes[index].noise = .init()
        } else if (0...254).contains(id) {
            send(BmapPacket(block: 31, function: 9, operation: .start, payload: Data([UInt8(id)])))
            send(BmapPacket(block: 31, function: 6, operation: .get, payload: Data([UInt8(id)])))
        }
    }
    func toggleFavorite(_ id: Int) {
        guard canEditFavorites, let i = saved.modes.firstIndex(where: { $0.id == id }) else { return }
        if saved.demo { saved.modes[i].favorite.toggle() }
        else {
            var next = favorites
            if next.contains(id) { next.remove(id) } else { next.insert(id) }
            guard next.count >= (modesCapabilities?.minimumFavorites ?? 0) else { message = "The headphones require at least \(modesCapabilities?.minimumFavorites ?? 0) favourite modes."; return }
            do { send(try BoseCommands.setFavorites(indices: next, totalModes: favoriteTotal)) } catch { message = error.localizedDescription }
        }
    }
    func choosePreset(_ id: String) { saved.presetID = id; applyAudio() }
    func applyAudio() { audio.apply(preset: preset, preamp: effectiveAudioPreamp, enabled: saved.proEnabled, boost: saved.boost, limiterEnabled: saved.audioOptions.limiterEnabled) }
    func savePreset(_ newPreset: EQPreset) {
        do { _ = try createUserPreset(newPreset) } catch { message = error.localizedDescription }
    }
    func refresh() {
        guard !saved.demo else { hydrateDemo(); return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            self?.send(BoseCommands.subscribeNotifications)
            for packet in BoseCommands.refresh {
                guard !Task.isCancelled, let self, self.bluetooth.isConnected else { return }
                if self.unavailableBlocks.contains(packet.block) || self.refusedFunctions.contains(packet.address) { continue }
                if self.modelFacts?.knownAbsent.contains(packet.address) == true, !self.supports(Int(packet.block), Int(packet.function)) { continue }
                if self.profile.unsupported && ![0, 2].contains(packet.block) { continue }
                self.send(packet)
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard let self, !Task.isCancelled, self.bluetooth.isConnected else { return }
            if self.supports(31, 2) || self.supports(31, 3), !self.unavailableBlocks.contains(31) { self.send(self.modelFacts?.modeDumpCommand ?? BoseCommands.readModes) }
        }
    }
    func send(_ packet: BmapPacket) {
        do {
            try bluetooth.send(packet)
            if packet.operation == .setGet && packet.address != BmapAddress(9, 2)
                || packet.operation == .start && !(packet.address == BmapAddress(31, 6) && packet.payload.isEmpty) {
                pendingWrites.insert(packet.address)
            }
        } catch { commandFailureVersion += 1; message = error.localizedDescription }
    }
    func receive(_ p: BmapPacket) {
        guard !saved.demo else { return }
        let key = "\(p.block).\(p.function)"
        if let capability = BoseParsers.sourceCapability(p) {
            if capability.supported { sourceCommandSupport.insert(capability.action) }
            else { sourceCommandSupport.remove(capability.action) }
        }
        if p.operation == .error {
            if pendingDeviceOperation?.address == p.address {
                deviceRequestStatus = BmapFailure.device(p.address, p.errorCode ?? 0).localizedDescription
                deviceOperationTask?.cancel(); pendingDeviceOperation = nil
            }
            liveFunctions.remove(key)
            if [4, 5].contains(p.errorCode ?? 0) { refusedFunctions.insert(p.address) }
            if p.address == BmapAddress(31, 1), [4, 5].contains(p.errorCode ?? 0) { send(BoseCommands.readModes) }
            if p.errorCode == 3 {
                unavailableBlocks.insert(p.block)
                liveFunctions = liveFunctions.filter { !$0.hasPrefix("\(p.block).") }
            }
            if pendingWrites.remove(p.address) != nil {
                commandFailureVersion += 1
                message = BmapFailure.device(p.address, p.errorCode ?? 0).localizedDescription
            }
            return
        }
        guard p.operation == .status || p.operation == .result else { return }
        let data = Array(p.payload)
        let wasWrite = pendingWrites.remove(p.address) != nil
        var valid = deviceStatus.receive(p)
        switch (p.block, p.function) {
        case (0, 1): valid = !data.isEmpty
        case (0, 3):
            if data.count >= 2 {
                let id = UInt16(data[0]) << 8 | UInt16(data[1])
                applyProductIdentity(id)
                valid = true
            }
        case (0, 5):
            if let string = String(data: p.payload, encoding: .utf8), !string.isEmpty { firmware = string.trimmingCharacters(in: .controlCharacters); valid = true }
        case (0, 15):
            if let string = String(data: p.payload, encoding: .utf8), !string.isEmpty { liveDeviceName = string.trimmingCharacters(in: .controlCharacters); applyNameIdentityFallback(); valid = true }
        case (1, 2):
            if let name = BoseParsers.customName(p.payload), !name.isEmpty { liveDeviceName = name; applyNameIdentityFallback(); valid = true }
        case (2, 2):
            let parsed = BoseBattery.parse(p.payload)
            if !parsed.readings.isEmpty {
                battery = parsed.percent; batteryMinutes = parsed.remainingMinutes; batteryReadings = parsed.readings
                batteries = Dictionary(parsed.readings.filter { [1, 2, 3].contains($0.component) }.compactMap { reading in
                    reading.percent.map { (reading.label, $0) }
                }, uniquingKeysWith: { _, newest in newest })
                valid = true; notifyBattery()
            }
        case (2, 5):
            if let flag = data.first, flag <= 1 { charging = flag != 0; valid = true; notifyBattery() }
        case (1, 7):
            let bands = BoseEQBand.parse(p.payload)
            if data.count.isMultiple(of: 4), !bands.isEmpty, bands.allSatisfy({ $0.id < 3 && (-10...10).contains($0.min) && (-10...10).contains($0.max) && $0.min <= $0.max && ($0.min...$0.max).contains($0.value) }) {
                for band in bands { saved.eq[Int(band.id)] = Double(band.value); eqRanges[band.id] = band.min...band.max }
                valid = true
            }
        case (31, 2):
            if let caps = BoseModesCapabilities.parse(p.payload), (1...255).contains(caps.totalModes) {
                modesCapabilities = caps; syncBuiltInModes(); valid = true
            }
        case (31, 10):
            if data.count >= 5, data[0] <= 10, data[2] <= 2, data[3] <= 1, data[4] <= 1, let n = BoseAudioSettings.parse(p.payload) {
                saved.noise = noiseState(n); valid = true
            }
        case (1, 5):
            if let state = BoseCNCState.parse(p.payload) {
                cncState = state; valid = true
                if !supports(31, 10) {
                    saved.noise.level = Double(state.cancellingLevel)
                    saved.noise.enabled = state.enabled
                }
            }
        case (31, 3):
            if let index = data.first, index == 255 || Int(index) < (modesCapabilities?.totalModes ?? 255) {
                saved.currentMode = Int(index); valid = true
                if !supports(31, 10), let mode = liveModes[Int(index)] { saved.noise = noiseState(mode.settings) }
            } else if wasWrite { send(BoseCommands.get(BmapAddress(31, 3))) }
        case (31, 6):
            if let mode = BoseMode.parse(p.payload), Int(mode.index) < (modesCapabilities?.totalModes ?? 255), mode.settings.spatial <= 2 {
                let id = Int(mode.index)
                reportedModeIDs.insert(id)
                if mode.raw.count >= 44 { liveModes[id] = mode }
                let editable = mode.editable ?? liveModes[id]?.editable ?? false
                let display = ListeningMode(id: id, name: mode.displayName, builtIn: !editable,
                    favorite: favorites.contains(id), configured: !mode.isEmpty, noise: noiseState(mode.settings))
                saved.modes.removeAll { $0.id == id }; saved.modes.append(display); saved.modes.sort { $0.id < $1.id }
                if id == saved.currentMode, !supports(31, 10) { saved.noise = display.noise }
                if mode.raw.count < 44 { send(BmapPacket(block: 31, function: 6, operation: .get, payload: Data([mode.index]))) }
                valid = true
            }
        case (31, 8):
            if let parsed = BoseParsers.favorites(p.payload), parsed.total > 0,
               data.count == 1 + max(1, (parsed.total + 7) / 8) {
                favoriteTotal = parsed.total; favorites = parsed.indices
                for index in saved.modes.indices { saved.modes[index].favorite = favorites.contains(saved.modes[index].id) }
                valid = true
            }
        case (1, 3):
            if let state = BoseVoicePromptsState.parse(p.payload) { saved.voicePrompts = state.enabled; voiceLanguage = state.language; voicePromptsState = state; valid = true }
        case (1, 4):
            if let minutes = BoseParsers.standbyMinutes(p.payload) { saved.autoOff = minutes; valid = true }
        case (1, 10):
            if let value = BoseParsers.multipoint(p.payload) { saved.multipoint = value; valid = true }
        case (1, 11):
            if data.count >= 2, data[1] <= 3 { saved.sidetone = Int(data[1]); valid = true }
        case (1, 24): if let flag = data.first, flag <= 1 { saved.autoPause = flag != 0; valid = true }
        case (1, 27): if let flag = data.first, flag <= 1 { saved.autoAnswer = flag != 0; valid = true }
        case (1, 34): if let state = BoseParsers.touchControls(p.payload) { saved.touchControls = state; valid = true }
        case (1, 37): if let flag = data.first, flag <= 1 { leAudio = flag != 0; valid = true }
        case (0, 23): valid = data.first.map { $0 <= 1 } ?? false
        case (5, 5):
            if data.count >= 2, data[0] > 0, data[1] <= data[0] {
                deviceVolumeMaximum = Int(data[0]); deviceVolume = Double(data[1]); valid = true
            }
        case (5, 3):
            if wasWrite { send(BoseCommands.get(BmapAddress(5, 4))) }
            else if !data.isEmpty { playbackActions = BoseParsers.bitset(p.payload).filter { $0 <= 8 }; valid = true }
        case (5, 4):
            if let code = data.first, code <= 4 {
                playbackStatus = ["Stopped", "Playing", "Paused", "Fast forwarding", "Rewinding"][Int(code)]; valid = true
            }
        case (5, 7):
            if let latency = BoseLatency.parse(p.payload) {
                deviceLatencyRange = latency.range; deviceLatencyValue = latency.current
                deviceLatency = "\(latency.current) (range \(latency.range.lowerBound)…\(latency.range.upperBound); device units)"; valid = true
            } else if wasWrite { send(BoseCommands.get(BmapAddress(5, 7))) }
        case (5, 1):
            if data.count >= 3, data[2] <= 5 {
                audioSource = ["None", "Bluetooth", "Auxiliary", "USB", "LE Audio unicast", "LE Audio broadcast"][Int(data[2])]; valid = true
            }
        case (4, 4):
            if let sources = BosePairedSource.parseList(p.payload) {
                pairedSources = sources; valid = true
                let addresses = Set(sources.map { $0.address.hexString })
                deviceStatus.extendedProfiles = deviceStatus.extendedProfiles.filter { addresses.contains($0.key) }
                for source in sources.prefix(8) {
                    send(BmapPacket(block: 4, function: 5, operation: .get, payload: source.address))
                    if let extended = try? BoseCommands.queryDeviceExtendedInfo(source.address) { send(extended) }
                }
            }
        case (4, 5):
            if let info = BoseDeviceInfo.parse(p.payload), let index = pairedSources.firstIndex(where: { $0.address == info.address }) {
                if let name = info.name { pairedSources[index].name = name }
                pairedSources[index].connected = info.connected; pairedSources[index].isLocal = info.isLocal; valid = true
            }
        case (4, 8):
            if let flag = data.first, flag <= 1 { pairingMode = flag != 0; valid = true }
        case (4, 1), (4, 2), (4, 3):
            if wasWrite { send(BoseCommands.get(BmapAddress(4, 4))) }
            valid = BoseParsers.sourceCapability(p)?.supported == true
        case (4, 12):
            if BoseParsers.routedSource(p) != nil { valid = true }
        case (1, 9):
            if let shortcut = BoseButtonShortcut.parse(p.payload) { buttonShortcut = shortcut; valid = true }
        case (7, 4): valid = data.first.map { $0 <= 1 } ?? false
        case (9, 2):
            if !data.isEmpty { subscribed = BoseParsers.bitset(data.count == 5 ? Data(data.dropFirst()) : p.payload).contains(2); valid = true }
        default: break
        }
        if valid { liveFunctions.insert(key); refusedFunctions.remove(p.address) }
        if p.address == BmapAddress(0, 23), deviceStatus.leAudioSupported == true, !lePreferenceRequested {
            lePreferenceRequested = true
            send(BoseCommands.checkLEAudioPreference)
        }
        if valid { checkDeviceOperationConfirmation(reportAddress: p.address, routedAddress: BoseParsers.routedSource(p)) }
        processConnectionRules(); processWiFiRules()
    }
    private func applyProductIdentity(_ id: UInt16) {
        let mapping: [UInt16: String] = [0x4082: "ultra2", 0x4066: "ultra1", 0x4083: "qc2", 0x4075: "qc",
            0x4039: "qc45", 0x4024: "nc700", 0x4062: "buds2", 0x4072: "buds1", 0x4064: "budsII",
            0x402f: "buds2020", 0x4068: "open", 0x4089: "open2", 0x400c: "qc35", 0x4020: "qc35"]
        liveProfile = mapping[id].flatMap { profileID in DeviceProfile.all.first { $0.id == profileID } }
        modelFacts = BoseModelFacts.lookup(id)
        if var model = liveProfile, let facts = modelFacts {
            model.presets = facts.presetNames; model.customCount = facts.customCount
            liveProfile = model
        }
        if id == 0x0023 {
            liveProfile = DeviceProfile(id: "brussels", name: "QC Earbuds 2024 · different protocol", spatial: false, noise: false, wind: false, unsupported: true, presets: [], customCount: 0)
        }
    }
    private func applyNameIdentityFallback() {
        // Product IDs are authoritative. Upstream name rules are only a fallback
        // while identification is unavailable; a later ID reply replaces the guess.
        guard !supports(0, 3), modelFacts == nil, let facts = BoseModelFacts.fromName(liveDeviceName) else { return }
        applyProductIdentity(facts.productID)
    }
    func audioSettings(_ noise: NoiseState) -> BoseAudioSettings {
        BoseAudioSettings(cancellingLevel: Int(noise.level), spatial: UInt8(clamping: noise.spatial), windBlock: noise.wind, ancEnabled: noise.enabled)
    }
    func noiseState(_ audio: BoseAudioSettings) -> NoiseState {
        NoiseState(level: Double(audio.cancellingLevel), enabled: audio.ancEnabled, wind: audio.windBlock, spatial: Int(audio.spatial))
    }
    private func clearLiveState() {
        cancelRuleExecution(reason: "Cancelled — headphone link changed")
        deviceOperationTask?.cancel(); deviceOperationTask = nil; pendingDeviceOperation = nil
        deviceRequestStatus = ""; pairingMode = nil; voicePromptsState = nil; sourceCommandSupport = []
        deviceStatus = BoseDeviceStatus(); cncState = nil
        batteryMinutes = nil; batteryReadings = []; modelFacts = nil; reportedModeIDs = []
        liveFunctions = []; liveModes = [:]; modesCapabilities = nil; liveProfile = nil; voiceLanguage = nil
        liveDeviceName = "Bose headphones · identifying"; unavailableBlocks = []; refusedFunctions = []; pendingWrites = []
        eqRanges = [:]; favorites = []; favoriteTotal = 0; subscribed = false; lePreferenceRequested = false; connectionRulesPending = false
        charging = false; firedConnectionRuleIDs = []
        deviceVolume = 0; deviceVolumeMaximum = 0; playbackStatus = "Not reported"; playbackActions = []
        leAudio = nil; deviceLatency = "Not reported"; deviceLatencyValue = nil; deviceLatencyRange = nil; audioSource = "Not reported"; pairedSources = []; buttonShortcut = nil
        if !saved.demo { battery = nil; batteries = [:]; saved.modes = []; firmware = "Not read" }
    }
    private func notifyBattery() {
        guard !saved.demo, let battery, saved.batteryAlert > 0 else { return }
        let identity = bluetooth.connectedDeviceID?.uuidString ?? "current-headphones"
        Task { await notifications.reportBattery(deviceID: identity, name: liveDeviceName, percent: battery, threshold: saved.batteryAlert, isCharging: charging) }
    }
    private func startBatteryFallback() {
        batteryPollTask?.cancel()
        batteryPollTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                guard let self, self.bluetooth.isConnected else { return }
                if !self.subscribed { self.send(BoseCommands.get(BmapAddress(2, 2))) }
            }
        }
    }
    func hardwareEQRequestError(_ values: [Double]) -> String? {
        guard connected, supports(1, 7), !profile.unsupported else { return "The current headphones have not reported hardware EQ support." }
        guard values.count == 3 else { return "Provide all three hardware EQ bands." }
        for (index, value) in values.enumerated() {
            let range = eqRanges[UInt8(index)] ?? -10...10
            if !value.isFinite || !(-10...10).contains(value) || !range.contains(Int(value.rounded())) { return "An EQ band is outside the range reported by the headphones." }
        }
        return nil
    }
    func setDeviceVolume(_ level: Double) {
        guard level.isFinite, level >= 0, level <= Double(deviceVolumeMaximum) else { return }
        if saved.demo { deviceVolume = level }
        else if supports(5, 5), !profile.unsupported {
            do { send(try BoseCommands.setVolume(level: Int(level.rounded()), maximum: deviceVolumeMaximum)) } catch { message = error.localizedDescription }
        }
    }
    func controlPlayback(_ action: Int) {
        guard playbackActions.contains(action), connected else { return }
        if saved.demo { playbackStatus = action == 1 ? "Playing · simulated" : action == 2 ? "Paused · simulated" : "Action \(action) · simulated" }
        else if supports(5, 3), !profile.unsupported { do { send(try BoseCommands.playback(action: UInt8(action))) } catch { message = error.localizedDescription } }
    }
    /// The view must confirm the documented device restart before calling this method.
    func setLEAudio(_ enabled: Bool) {
        if saved.demo { leAudio = enabled }
        else if supports(1, 37), !profile.unsupported { send(BoseCommands.setToggle(function: 37, enabled: enabled)) }
    }
    func setButtonShortcut(_ action: Int) {
        guard connected, let shortcut = buttonShortcut, shortcut.supported.contains(action), (0...255).contains(action) else { return }
        if saved.demo { buttonShortcut = BoseButtonShortcut(button: shortcut.button, event: shortcut.event, action: UInt8(action), supported: shortcut.supported) }
        else if supports(1, 9), !profile.unsupported {
            send(BmapPacket(block: 1, function: 9, operation: .setGet, payload: Data([shortcut.button, shortcut.event, UInt8(action)])))
        }
    }
    func powerOffHeadphones() {
        if saved.demo { message = "Simulated power off. Demo mode is still available." }
        else if connected, supports(7, 4), !profile.unsupported { bluetooth.preventReconnectUntilUserAction(); send(BmapPacket(block: 7, function: 4, operation: .start, payload: Data([0]))) }
    }
    private func syncBuiltInModes() {
        guard let caps = modesCapabilities else { return }
        let labels = modelFacts?.builtInLabels(reportedCount: caps.builtIn) ?? (0..<caps.builtIn).map { "Mode \($0 + 1)" }
        // A reported built-in count establishes selectable slots. A full mode record
        // remains authoritative for names/settings/editability; catalogue labels only
        // fill slots whose records have not arrived yet.
        for (index, label) in labels.enumerated() where !reportedModeIDs.contains(index) {
            saved.modes.removeAll { $0.id == index }
            saved.modes.append(ListeningMode(id: index, name: label, builtIn: true, favorite: favorites.contains(index)))
        }
        saved.modes.sort { $0.id < $1.id }
    }
    func processConnectionRules() {
        guard connectionRulesPending else { return }
        let rules = saved.rules.filter { $0.enabled && $0.trigger == "On connection" }
        for rule in rules where !firedConnectionRuleIDs.contains(rule.id) && ruleAvailabilityError(rule) == nil {
            if runRule(rule, source: .connection) { firedConnectionRuleIDs.insert(rule.id) }
        }
        connectionRulesPending = rules.contains { !firedConnectionRuleIDs.contains($0.id) }
    }
    private func runConnectionRules() {
        for rule in saved.rules where rule.enabled && rule.trigger == "On connection" { runRule(rule, source: .connection) }
    }
    var report: String { "Earshot iOS — AI-assisted port attempt\nOriginal: https://github.com/HellzYeahh/earshot\nDemo: \(saved.demo)\nProfile: \(profile.name)\nBluetooth: \(bluetooth.status)\nFirmware: \(firmware)\nAudio route: \(routes.outputName)\n\n" + bluetooth.log.joined(separator: "\n") }
    private func persist() { if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "earshot.ios.state") } }
}
