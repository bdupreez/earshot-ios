// AI-assisted native port of upstream Earshot's safe device management (MIT).
import Foundation

enum PendingDeviceOperation: Equatable {
    case name(String), pairing(Bool), language(UInt8), latency(Int), source(Data, BoseSourceAction), diagnostic(BmapAddress)
    var address: BmapAddress {
        switch self {
        case .name: return BmapAddress(1, 2)
        case .pairing: return BmapAddress(4, 8)
        case .language: return BmapAddress(1, 3)
        case .latency: return BmapAddress(5, 7)
        case .source(_, let action): return BmapAddress(4, action.rawValue)
        case .diagnostic(let address): return address
        }
    }
}

@MainActor extension AppStore {
    var displayDeviceName: String { saved.demo ? saved.demoDeviceNames[saved.profileID] ?? profile.name : liveDeviceName }
    var remainingTimeDescription: String? { EarshotWidgetBattery(id: "main", name: "Headphones", percent: battery, remainingMinutes: batteryMinutes).remainingDescription }

    func queryLEAudioPreference() {
        if saved.demo {
            deviceStatus.lePreference = BoseLEPreference(flags: 3)
            deviceRequestStatus = "LE preference reported in demo only."
            return
        }
        guard connected, !saved.demo, !profile.unsupported else { message = "Connect real compatible headphones to query their LE preference."; return }
        beginDeviceOperation(.diagnostic(BmapAddress(4, 19)))
        send(BoseCommands.checkLEAudioPreference)
    }

    func refreshRoutingSupport() {
        if saved.demo {
            sourceCommandSupport.insert(.route)
            deviceRequestStatus = "Routing support reported in demo only."
            return
        }
        guard connected, !saved.demo, !profile.unsupported else { message = "Connect real compatible headphones to read routing support."; return }
        // An empty routing table can return error 4, then change when a source
        // starts streaming. An explicit refresh must retry that informational GET.
        beginDeviceOperation(.diagnostic(BmapAddress(4, 12)))
        send(BoseCommands.readRoutingSupport)
    }

    func renameHeadphones(_ name: String) {
        guard connected, supports(1, 2), !profile.unsupported else { message = "Headphone renaming has not been reported as available."; return }
        do {
            let packet = try BoseCommands.setName(name)
            if saved.demo { saved.demoDeviceNames[saved.profileID] = name; deviceRequestStatus = "Name changed in demo only." }
            else { beginDeviceOperation(.name(name)); send(packet); send(BoseCommands.get(BmapAddress(1, 2))) }
        } catch { message = error.localizedDescription }
    }

    func setPairingMode(_ enabled: Bool) {
        guard connected, supports(4, 8), !profile.unsupported, pairingMode != nil else { message = "Pairing mode has not been reported as available."; return }
        if saved.demo { pairingMode = enabled; deviceRequestStatus = "Pairing mode changed in demo only." }
        else {
            beginDeviceOperation(.pairing(enabled)); send(BoseCommands.pairingMode(enabled: enabled))
            send(BoseCommands.get(BmapAddress(4, 8)))
        }
    }

    func setVoiceLanguage(_ language: UInt8) {
        guard connected, supports(1, 3), !profile.unsupported, let voice = voicePromptsState,
              voice.installedLanguages?.contains(Int(language)) == true else { message = "Choose a language reported installed by the headphones."; return }
        if saved.demo {
            saved.demoVoiceLanguage = language
            voicePromptsState = BoseVoicePromptsState(enabled: voice.enabled, language: language, installedLanguages: voice.installedLanguages)
            deviceRequestStatus = "Voice language changed in demo only."
        } else {
            do { beginDeviceOperation(.language(language)); send(try BoseCommands.setVoicePrompts(enabled: voice.enabled, language: language)) }
            catch { message = error.localizedDescription }
        }
    }

    /// The view confirms source removal/disconnection/routing before this call.
    func manageSource(_ source: BosePairedSource, action: BoseSourceAction) {
        guard connected, !profile.unsupported, sourceCommandSupport.contains(action), pairedSources.contains(where: { $0.address == source.address }) else { message = "This source operation has not been reported as available."; return }
        do {
            let packet = try BoseCommands.source(action: action, address: source.address)
            if saved.demo {
                if let i = pairedSources.firstIndex(where: { $0.address == source.address }) {
                    switch action {
                    case .connect: pairedSources[i].connected = true
                    case .disconnect: pairedSources[i].connected = false
                    case .remove: pairedSources.remove(at: i)
                    case .route: audioSource = "\(source.name) · simulated"
                    }
                }
                deviceRequestStatus = "\(action.title) completed in demo only."
            } else {
                if source.isLocal && (action == .disconnect || action == .remove) { bluetooth.preventReconnectUntilUserAction() }
                beginDeviceOperation(.source(source.address, action)); send(packet)
                send(BoseCommands.get(BmapAddress(4, 4)))
            }
        } catch { message = error.localizedDescription }
    }

    /// Called only after the dedicated experimental-write confirmation.
    func updateLatency(_ value: Int) {
        guard connected, supports(5, 7), !profile.unsupported, let range = deviceLatencyRange else { message = "No supported latency range has been reported."; return }
        do {
            let packet = try BoseCommands.setLatency(value, reportedRange: range)
            if saved.demo {
                deviceLatencyValue = value
                deviceLatency = "\(value) (range \(range.lowerBound)…\(range.upperBound); simulated device units)"
                deviceRequestStatus = "Experimental value changed in demo only."
            } else { beginDeviceOperation(.latency(value)); send(packet) }
        } catch { message = error.localizedDescription }
    }

    func beginDeviceOperation(_ operation: PendingDeviceOperation) {
        deviceOperationTask?.cancel()
        pendingDeviceOperation = operation
        deviceRequestStatus = "Request sent. Waiting for the headphones to report the new state."
        deviceOperationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.pendingDeviceOperation == operation else { return }
            self.pendingDeviceOperation = nil
            self.deviceRequestStatus = "The headphones did not confirm this request. The displayed values remain device-reported."
        }
    }

    func checkDeviceOperationConfirmation(reportAddress: BmapAddress, routedAddress: Data? = nil) {
        guard let operation = pendingDeviceOperation else { return }
        let relevant: Set<BmapAddress>
        if case .source(_, let action) = operation { relevant = action == .route ? [BmapAddress(4, 12)] : [BmapAddress(4, 4), BmapAddress(4, 5)] }
        else { relevant = [operation.address] }
        guard relevant.contains(reportAddress) else { return }
        let confirmed: Bool
        switch operation {
        case .name(let name): confirmed = liveDeviceName == name
        case .pairing(let enabled): confirmed = pairingMode == enabled
        case .latency(let value): confirmed = deviceLatencyValue == value
        case .language(let language): confirmed = voicePromptsState?.language == language
        case .diagnostic: confirmed = true // Caller requires a fresh, valid report at the relevant address.
        case .source(let address, let action):
            switch action {
            case .connect: confirmed = pairedSources.first(where: { $0.address == address })?.connected == true
            case .disconnect: confirmed = pairedSources.first(where: { $0.address == address })?.connected == false
            case .remove: confirmed = !pairedSources.contains(where: { $0.address == address })
            case .route: confirmed = routedAddress == address
            }
        }
        if confirmed {
            deviceOperationTask?.cancel(); deviceOperationTask = nil; pendingDeviceOperation = nil
            deviceRequestStatus = "Confirmed by headphone reports."
        }
    }
}
