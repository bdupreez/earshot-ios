import Foundation

// AI-assisted adaptation of HellzYeahh and contributors' MIT SoundcoreWrites and
// Sleep A30 mappings. No commands are sent by this module. A matching packet ACK
// alone is never evidence that a physical setting changed: compare a fresh state.
struct SoundcoreControlDefinition: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let options: [String]
    let value: Int?
    let enabled: Bool
    var note: String? = nil
}

extension SoundcoreState {
    var controls: [SoundcoreControlDefinition] {
        if let sleep {
            let flags: [(String, String, Int?, [String])] = [
                ("anc", "Noise cancelling", sleep.ancOn ? 1 : 0, ["Off", "On"]),
                ("listening_mode", "Listening mode", sleep.listeningLocal ? 1 : 0, ["Bluetooth", "Local sounds"]),
                ("default_listening_mode", "Start in", sleep.defaultListeningLocal ? 1 : 0, ["Bluetooth", "Local sounds"]),
                ("auto_switch_asleep", "Switch once asleep", sleep.autoSwitchAsleep ? 1 : 0, ["Off", "On"]),
                ("post_sleep_action", "Once asleep", sleep.postSleepAction, ["Pause", "Play local sounds"]),
                ("incoming_calls", "Incoming calls in Bluetooth mode", sleep.incomingCalls ? 1 : 0, ["Off", "On"]),
                ("prompt_low_battery", "Low battery prompt", sleep.lowBatteryPrompt ? 1 : 0, ["Off", "On"]),
                ("prompt_anc", "Noise cancelling prompt", sleep.ancPrompt ? 1 : 0, ["Off", "On"]),
                ("prompt_listening_mode", "Listening mode prompt", sleep.listeningModePrompt ? 1 : 0, ["Off", "On"]),
                ("prompt_auto_off", "Auto power-off prompt", sleep.autoOffPrompt ? 1 : 0, ["Off", "On"]),
                ("tap_controls", "Tap controls", sleep.tapControlsDisabled ? 0 : 1, ["Off", "On"])
            ]
            return flags.map { id, title, value, options in
                .init(id: id, title: title, options: options, value: value, enabled: writable && value != nil,
                      note: id == "post_sleep_action" ? "Playing local sounds turns noise cancelling off on the earbuds." : nil)
            }
        }
        var result: [SoundcoreControlDefinition] = []
        if let modes {
            result.append(.init(id: "ambient", title: "Listening mode", options: SoundcoreAmbient.allCases.map(\.title), value: ambient?.rawValue, enabled: writable))
            if !modes.codec.ncTypes.isEmpty {
                result.append(.init(id: "nc_type", title: "Noise-cancelling type", options: modes.codec.ncTypes, value: modes.ncType, enabled: writable && ambient == .noiseCancelling, note: "Change the type while noise cancelling is active."))
            }
            if let range = modes.codec.manualLevels {
                result.append(.init(id: "nc_level", title: "Manual noise-cancelling level", options: range.map { String($0) }, value: modes.manualLevel.map { $0 - range.lowerBound }, enabled: writable && ambient == .noiseCancelling && modes.ncType == 0, note: "Select Manual noise cancelling before changing the level."))
            }
            if !modes.codec.transparencyTypes.isEmpty {
                result.append(.init(id: "transparency_type", title: "Transparency type", options: modes.codec.transparencyTypes, value: modes.transparencyType, enabled: writable && ambient == .transparency))
            }
            if let wind = modes.windOn {
                result.append(.init(id: "wind", title: "Wind noise reduction", options: ["Off", "On"], value: wind ? 1 : 0, enabled: writable && ambient != .normal))
            }
        }
        if let layout = model.layout {
            result += layout.settings.map { setting in
                .init(id: setting.id, title: setting.title, options: setting.autoOff ? ["Off"] + layout.autoOffMinutes.map { "\($0) minutes" } : ["Off", "On"],
                      value: settings[setting.id], enabled: writable && settings[setting.id] != nil)
            }
        }
        return result
    }
}

enum SoundcoreWrites {
    private static func requireWritable(_ state: SoundcoreState) throws {
        guard state.writable else { throw SoundcoreFailure.refused(state.note ?? "This model has no confirmed writable layout.") }
    }
    private static func modes(_ state: SoundcoreState) throws -> SoundcoreModes {
        try requireWritable(state)
        guard let modes = state.modes else { throw SoundcoreFailure.refused("A complete sound-mode block has not been reported.") }
        return modes
    }
    private static func checked(_ state: SoundcoreState, _ packet: SoundcorePacket) throws -> SoundcorePacket {
        try SoundcoreWriteGuard.check(model: state.model, state: state, packet: packet); return packet
    }
    static func setAmbient(state: SoundcoreState, mode: SoundcoreAmbient) throws -> SoundcorePacket {
        if state.model == .sleepA30 {
            guard mode != .transparency else { throw SoundcoreFailure.refused("Sleep A30 has noise cancelling and off, without transparency.") }
            return try control(state: state, id: "anc", value: mode == .noiseCancelling ? 1 : 0)
        }
        let modes = try modes(state).changing { b in
            b[0] = UInt8(mode.rawValue)
            if state.modes?.codec.mirrorsAmbientAt2 == true { b[2] = UInt8(mode.rawValue) }
        }
        return try checked(state, SoundcorePacket(command: SoundcoreCommands.setSoundModes, body: modes.raw))
    }
    static func control(state: SoundcoreState, id: String, value: Int) throws -> SoundcorePacket {
        try requireWritable(state)
        if state.model == .sleepA30 { return try sleepControl(state: state, id: id, value: value) }
        if id == "ambient" {
            guard let mode = SoundcoreAmbient(rawValue: value) else { throw SoundcoreFailure.invalid("Unknown Soundcore listening mode.") }
            return try setAmbient(state: state, mode: mode)
        }
        if ["nc_type", "nc_level", "transparency_type", "wind"].contains(id) {
            let current = try modes(state)
            let changed: SoundcoreModes
            switch id {
            case "nc_type":
                guard current.codec.ncTypes.indices.contains(value), current.ambient == .noiseCancelling else { throw SoundcoreFailure.refused("Select noise cancelling, then choose a documented type.") }
                changed = current.changing { $0[3] = UInt8(value) }
            case "nc_level":
                guard let range = current.codec.manualLevels, (0..<range.count).contains(value), current.ambient == .noiseCancelling, current.ncType == 0 else { throw SoundcoreFailure.refused("Select Manual noise cancelling, then choose a documented level.") }
                changed = current.changing { $0[1] = UInt8((range.lowerBound + value) << 4) | ($0[1] & 15) }
            case "transparency_type":
                guard current.codec.transparencyTypes.indices.contains(value), current.ambient == .transparency else { throw SoundcoreFailure.refused("Select transparency, then choose a documented transparency type.") }
                changed = current.changing { $0[2] = UInt8(value) }
            default:
                guard (0...1).contains(value), current.codec.hasWind, current.ambient != .normal else { throw SoundcoreFailure.refused("Wind noise reduction requires noise cancelling or transparency.") }
                changed = current.changing { $0[4] = ($0[4] & 0xfe) | UInt8(value) }
            }
            return try checked(state, .init(command: SoundcoreCommands.setSoundModes, body: changed.raw))
        }
        guard let layout = state.model.layout, let setting = layout.settings.first(where: { $0.id == id }), state.settings[id] != nil else { throw SoundcoreFailure.refused("This setting has not been reported by the selected model.") }
        let bytes: [UInt8]
        if setting.autoOff {
            guard (0...layout.autoOffMinutes.count).contains(value) else { throw SoundcoreFailure.invalid("Choose one of the documented power-off times.") }
            if value == 0 {
                guard let previous = state.autoOffIndexes[id], layout.autoOffMinutes.indices.contains(previous) else { throw SoundcoreFailure.refused("The current power-off duration has not been reported.") }
                bytes = [0, UInt8(previous)]
            } else { bytes = [1, UInt8(value - 1)] }
        } else {
            guard (0...1).contains(value) else { throw SoundcoreFailure.invalid("This setting accepts off or on.") }
            bytes = [UInt8(value)]
        }
        return try checked(state, .init(command: setting.command, body: Data(bytes)))
    }
    static let sleepFlags: [(id: String, command: UInt16, offset: Int)] = [
        ("anc", 0x0687, 140), ("listening_mode", 0x01a9, 65), ("default_listening_mode", 0x1095, 66),
        ("auto_switch_asleep", 0x158f, 148), ("incoming_calls", 0x1075, 141), ("prompt_low_battery", 0x1082, 69),
        ("prompt_anc", 0x1077, 147), ("prompt_listening_mode", 0x109f, 138), ("prompt_auto_off", 0x109e, 137), ("tap_controls", 0x1094, 146)
    ]
    private static func sleepControl(state: SoundcoreState, id: String, value: Int) throws -> SoundcorePacket {
        guard state.sleep != nil, (0...1).contains(value) else { throw SoundcoreFailure.invalid("Sleep A30 controls accept one documented option.") }
        if id == "post_sleep_action" { return try checked(state, .init(command: 0x1585, body: Data([255, 255, 255, UInt8(value)]))) }
        guard let flag = sleepFlags.first(where: { $0.id == id }) else { throw SoundcoreFailure.refused("Sleep A30 has no such documented control.") }
        return try checked(state, .init(command: flag.command, body: Data([UInt8(id == "tap_controls" ? 1 - value : value)])))
    }
    static func confirms(before: SoundcoreState, after: SoundcoreState, packet: SoundcorePacket) -> Bool {
        guard before.model == after.model, after.writable, SoundcoreWriteGuard.allows(model: before.model, packet: packet) else { return false }
        if before.model == .sleepA30 {
            let id = packet.command == 0x1585 ? "post_sleep_action" : sleepFlags.first(where: { $0.command == packet.command })?.id
            guard let id, let control = after.controls.first(where: { $0.id == id }), let last = packet.body.last else { return false }
            return control.value == (id == "tap_controls" ? 1 - Int(last) : Int(last))
        }
        if packet.command == SoundcoreCommands.setSoundModes {
            guard let now = after.modes, let sent = SoundcoreModes(codec: now.codec, raw: packet.body), let was = before.modes else { return false }
            func matched<T: Equatable>(_ read: (SoundcoreModes) -> T) -> Bool { read(was) == read(sent) || read(now) == read(sent) }
            return matched { $0.ambient } && matched { $0.manualLevel } && matched { $0.ncType } && matched { $0.transparencyType } && matched { $0.windOn }
        }
        guard let setting = after.model.layout?.settings.first(where: { $0.command == packet.command }), let first = packet.body.first else { return false }
        let wanted = setting.autoOff && first != 0 ? Int(packet.body.last ?? 255) + 1 : Int(first)
        return after.settings[setting.id] == wanted
    }
}

extension SoundcoreWriteGuard {
    static func check(model: SoundcoreModel, state: SoundcoreState, packet: SoundcorePacket) throws {
        try check(model: model, packet: packet)
        if packet.isWrite {
            guard state.model == model, state.writable else { throw SoundcoreFailure.refused("The reported Soundcore state does not confirm a writable model layout.") }
        }
    }
}
