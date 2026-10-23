import Foundation

// Native port of HellzYeahh/earshot's MIT state reader. The layout facts are
// inherited research; these parsers and simulated fixtures prove no iOS radio path.
struct SoundcoreSleepState: Equatable, Sendable {
    let budsLinked: Bool
    let listeningLocal: Bool
    let defaultListeningLocal: Bool
    let ancOn: Bool
    let tapControlsDisabled: Bool
    let lowBatteryPrompt: Bool
    let autoOffPrompt: Bool
    let listeningModePrompt: Bool
    let incomingCalls: Bool
    let postSleepAction: Int?
    let ancPrompt: Bool
    let autoSwitchAsleep: Bool
}

struct SoundcoreState: Equatable, Sendable {
    let model: SoundcoreModel
    let raw: Data
    var leftPercent: Int? = nil
    var rightPercent: Int? = nil
    var overallPercent: Int? = nil
    var casePercent: Int? = nil
    var charging: Bool? = nil
    var firmwareLeft: String? = nil
    var firmwareRight: String? = nil
    var caseFirmware: String? = nil
    var serial: String? = nil
    var ambient: SoundcoreAmbient? = nil
    var modes: SoundcoreModes? = nil
    var settings: [String: Int] = [:]
    var autoOffIndexes: [String: Int] = [:]
    var sleep: SoundcoreSleepState? = nil
    var writable = false
    var isSimulated = false
    var note: String? = nil
    var bodySize: Int { raw.count }
    var firmware: String? {
        let values = [firmwareLeft, firmwareRight].compactMap { $0 }
        let unique = values.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return unique.isEmpty ? nil : unique.joined(separator: " / ")
    }
    var headlinePercent: Int? { [leftPercent, rightPercent].compactMap { $0 }.min() ?? overallPercent }
}

struct SoundcoreBatteryPush: Equatable, Sendable {
    let left: Int?, right: Int?, casePercent: Int?, overall: Int?
}

enum SoundcoreStateReader {
    private struct Text { let value: String?; let valid: Bool }
    private struct Header {
        let kind: SoundcoreHeader
        let left: Int?, right: Int?, overall: Int?, charging: Bool?
        let firmwareLeft: Text, firmwareRight: Text, serial: Text
        func plausible(strict: Bool) -> Bool {
            let pattern = strict ? #"^\d{2}\.\d{2}$"# : #"^[0-9A-Za-z._-]{3,5}$"#
            let firmwareOK = [firmwareLeft, firmwareRight].allSatisfy { $0.valid && ($0.value == nil || $0.value?.range(of: pattern, options: .regularExpression) != nil) }
            return firmwareOK && serial.valid && (serial.value == nil || serial.value?.range(of: #"^\d{4}[0-9A-Za-z]{12}$"#, options: .regularExpression) != nil)
        }
    }
    private static func text(_ b: [UInt8], _ start: Int, _ length: Int) -> Text {
        guard start >= 0, start + length <= b.count else { return .init(value: nil, valid: false) }
        var part = Array(b[start..<(start + length)])
        if part.allSatisfy({ $0 == 0 }) || part.allSatisfy({ $0 == 255 }) { return .init(value: nil, valid: true) }
        while part.last == 0 { part.removeLast() }
        guard part.allSatisfy({ (32...126).contains($0) }) else { return .init(value: nil, valid: false) }
        let value = String(decoding: part, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return .init(value: value.isEmpty ? nil : value, valid: true)
    }
    private static func flag(_ value: UInt8?) -> Bool? { value == 0 ? false : value == 1 ? true : nil }
    private static func combined(_ values: [Bool?]) -> Bool? { let known = values.compactMap { $0 }; return known.isEmpty ? nil : known.contains(true) }
    private static func header(_ kind: SoundcoreHeader, model: SoundcoreModel, bytes b: [UInt8]) -> Header? {
        func p(_ i: Int) -> Int? { model.batteryScale.percent(b[i]) }
        switch kind {
        case .g2t:
            guard b.count >= 32 else { return nil }
            return .init(kind: kind, left: p(2), right: p(3), overall: nil, charging: combined([flag(b[4]), flag(b[5])]), firmwareLeft: text(b, 6, 5), firmwareRight: text(b, 11, 5), serial: text(b, 16, 16))
        case .sleep:
            guard b.count >= 30 else { return nil }
            return .init(kind: kind, left: p(2), right: p(3), overall: nil, charging: nil, firmwareLeft: text(b, 4, 5), firmwareRight: text(b, 9, 5), serial: text(b, 14, 16))
        case .g2h:
            guard b.count >= 23 else { return nil }
            return .init(kind: kind, left: nil, right: nil, overall: p(0), charging: flag(b[1]), firmwareLeft: text(b, 2, 5), firmwareRight: .init(value: nil, valid: true), serial: text(b, 7, 16))
        default: return nil
        }
    }
    static func parse(model: SoundcoreModel, body: Data) -> SoundcoreState? {
        guard body.count <= SoundcoreFrameBuffer.maximumFrame - SoundcorePacket.overhead else { return nil }
        let b = Array(body)
        if model.header == .tlv { return parseTLV(model: model, bytes: b) }
        var order: [SoundcoreHeader] = []
        for kind in [model.header, .g2t, .sleep, .g2h] where kind != .unknown && kind != .tlv && !order.contains(kind) { order.append(kind) }
        let strict = order.compactMap { header($0, model: model, bytes: b) }.first { $0.plausible(strict: true) }
        let relaxed = order.first.flatMap { header($0, model: model, bytes: b) }.flatMap { $0.plausible(strict: false) ? $0 : nil }
        guard let h = strict ?? relaxed else { return nil }
        var state = SoundcoreState(model: model, raw: body)
        state.leftPercent = h.left; state.rightPercent = h.right; state.overallPercent = h.overall; state.charging = h.charging
        state.firmwareLeft = h.firmwareLeft.value; state.firmwareRight = h.firmwareRight.value; state.serial = h.serial.value
        if model == .sleepA30 { return parseSleep(state: state, header: h, bytes: b) }
        guard let layout = model.layout else {
            state.note = "Battery and firmware only: this model's settings layout is not documented."; return state
        }
        let sameHeader = h.kind == model.header
        let sameSize = layout.stateSize == b.count
        let lengthOK = layout.lengthByteOffset.map { $0 < b.count && $0 + Int(b[$0]) == layout.modeOffset }
        if sameHeader && sameSize {
            if let at = layout.caseBatteryOffset, b.indices.contains(at) { state.casePercent = model.batteryScale.percent(b[at]) }
            if let at = layout.caseFirmwareOffset, let value = text(b, at, 5).value, value.range(of: #"^\d{2}\.\d{2}$"#, options: .regularExpression) != nil { state.caseFirmware = value }
            for setting in layout.settings where b.indices.contains(setting.offset) {
                let first = Int(b[setting.offset])
                if setting.autoOff {
                    guard b.indices.contains(setting.offset + 1) else { continue }
                    let index = Int(b[setting.offset + 1])
                    if layout.autoOffMinutes.indices.contains(index) { state.autoOffIndexes[setting.id] = index }
                    if first == 0 { state.settings[setting.id] = 0 }
                    else if first == 1 && layout.autoOffMinutes.indices.contains(index) { state.settings[setting.id] = index + 1 }
                } else if first <= 1 { state.settings[setting.id] = first }
            }
        }
        if sameHeader && b.count >= layout.modeOffset + layout.codec.size && (sameSize || lengthOK == true) {
            state.modes = .init(codec: layout.codec, raw: Data(b[layout.modeOffset..<(layout.modeOffset + layout.codec.size)]))
            state.ambient = state.modes?.ambient
        }
        state.writable = layout.writable && state.modes != nil && sameSize && lengthOK != false && h.serial.value?.hasPrefix(model.serialPrefix) == true
        if !state.writable {
            state.note = layout.writable ? "State size, model identity or layout does not match the documented firmware; settings are read-only." : "This model's control layout or handshake is unresolved; settings are read-only."
        }
        return state
    }
    private static func parseSleep(state original: SoundcoreState, header h: Header, bytes b: [UInt8]) -> SoundcoreState {
        var state = original
        guard b.count >= 149, h.kind == .sleep else { state.note = "A complete Sleep A30 state has not been reported."; return state }
        state.caseFirmware = text(b, 36, 5).value
        state.sleep = SoundcoreSleepState(budsLinked: b[1] != 0, listeningLocal: b[65] == 1, defaultListeningLocal: b[66] == 1,
            ancOn: b[140] != 0, tapControlsDisabled: b[146] != 0, lowBatteryPrompt: b[69] != 0, autoOffPrompt: b[137] != 0,
            listeningModePrompt: b[138] != 0, incomingCalls: b[141] != 0, postSleepAction: b[144] <= 1 ? Int(b[144]) : nil,
            ancPrompt: b[147] != 0, autoSwitchAsleep: b[148] != 0)
        state.ambient = b[140] == 0 ? .normal : .noiseCancelling
        let flags = [65, 66, 69, 137, 138, 140, 141, 144, 146, 147, 148]
        state.writable = b.count == 150 && b[0] <= 1 && b[1] <= 1 && flags.allSatisfy { b[$0] <= 1 } && h.serial.value?.hasPrefix("1301") == true
        if !state.writable { state.note = "Sleep A30 model identity, state size or flags are unconfirmed; controls are read-only." }
        return state
    }
    private static func parseTLV(model: SoundcoreModel, bytes b: [UInt8]) -> SoundcoreState? {
        var tags: [UInt8: [UInt8]] = [:]
        var i = 0
        while i < b.count {
            guard i + 2 <= b.count else { return nil }
            let length = Int(b[i + 1])
            guard i + 2 + length <= b.count, tags[b[i]] == nil else { return nil }
            tags[b[i]] = Array(b[(i + 2)..<(i + 2 + length)]); i += 2 + length
        }
        guard tags[3]?.count == 2 || tags[4]?.count == 2 || tags[7] != nil else { return nil }
        func percent(_ tag: UInt8) -> Int? { guard let bytes = tags[tag], bytes.count == 2 else { return nil }; return model.batteryScale.percent(bytes[1]) }
        func charging(_ tag: UInt8) -> Bool? { guard let bytes = tags[tag], bytes.count == 2 else { return nil }; return flag(bytes[0]) }
        func firmware(_ tag: UInt8) -> String? { guard let bytes = tags[tag], bytes.count == 5 else { return nil }; return text(bytes, 0, 5).value }
        var state = SoundcoreState(model: model, raw: Data(b))
        state.leftPercent = percent(3); state.rightPercent = percent(4); state.casePercent = percent(8)
        state.charging = combined([charging(3), charging(4)]); state.firmwareLeft = firmware(5); state.firmwareRight = firmware(6); state.caseFirmware = firmware(9)
        if let serial = tags[7], serial.count >= 16 { state.serial = text(serial, 0, 16).value }
        if let mode = tags[36]?.first { state.ambient = mode == 3 ? .noiseCancelling : SoundcoreAmbient(rawValue: Int(mode)) }
        state.note = "Battery, firmware and sound mode are read-only; this generation's write commands are undocumented."
        return state
    }
    static func batteryPush(model: SoundcoreModel, body: Data) -> SoundcoreBatteryPush? {
        let b = Array(body)
        guard model.header != .tlv, model.header != .unknown, !b.isEmpty else { return nil }
        if model.header == .g2h { return .init(left: nil, right: nil, casePercent: nil, overall: model.batteryScale.percent(b[0])) }
        guard b.count >= 2 else { return nil }
        return .init(left: model.batteryScale.percent(b[0]), right: model.batteryScale.percent(b[1]), casePercent: b.count > 2 ? model.batteryScale.percent(b[2]) : nil, overall: nil)
    }
    static func chargingPush(_ body: Data) -> Bool? { combined(Array(body.prefix(2)).map { flag($0) }) }
}
