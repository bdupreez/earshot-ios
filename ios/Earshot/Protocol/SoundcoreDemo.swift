import Foundation

// Explicit simulation for the AI-assisted port of HellzYeahh/earshot (MIT).
// These synthetic state records exercise upstream's documented layouts. They
// are not captures and must never be passed off as physical headphone reports.
enum SoundcoreDemo {
    static func state(for model: SoundcoreModel) throws -> SoundcoreState {
        let body = fixtureBody(for: model)
        guard var state = SoundcoreStateReader.parse(model: model, body: body) else { throw SoundcoreFailure.invalid("The simulated Soundcore fixture could not be decoded.") }
        state.isSimulated = true
        return state
    }
    static func fixtureBody(for model: SoundcoreModel) -> Data {
        let serial = model.serialPrefix + "DEMO00000000"
        if model.header == .tlv {
            var bytes: [UInt8] = []
            func tag(_ tag: UInt8, _ value: [UInt8]) { bytes += [tag, UInt8(value.count)] + value }
            tag(1, [0]); tag(2, [1]); tag(3, [0, 80]); tag(4, [0, 65]); tag(5, Array("01.02".utf8)); tag(6, Array("01.02".utf8))
            tag(7, Array(serial.utf8) + [0]); tag(8, [0, 90]); tag(9, Array("01.01".utf8)); tag(36, [0, 0, 0])
            return Data(bytes)
        }
        let layout = model.layout
        let header: SoundcoreHeader = model.header == .unknown ? .g2t : model.header
        let minimum = header == .sleep ? 30 : header == .g2h ? 23 : 32
        let size = model == .sleepA30 ? 150 : layout?.stateSize ?? (model == .liberty4 ? 150 : minimum)
        var bytes = [UInt8](repeating: 0, count: size)
        func put(_ text: String, _ at: Int) { let value = Array(text.utf8); bytes.replaceSubrange(at..<(at + value.count), with: value) }
        switch header {
        case .g2h: bytes[0] = 4; put("02.45", 2); put(serial, 7)
        case .sleep: bytes[1] = 1; bytes[2] = 7; bytes[3] = 8; put("01.91", 4); put("01.91", 9); put(serial, 14)
        default: bytes[1] = 1; bytes[2] = model.batteryScale == .percent ? 80 : 4; bytes[3] = model.batteryScale == .percent ? 65 : 5; put("01.23", 6); put("01.23", 11); put(serial, 16)
        }
        if let layout {
            if let at = layout.lengthByteOffset { bytes[at] = UInt8(layout.modeOffset - at) }
            var block = [UInt8](repeating: 0, count: layout.codec.size)
            block[1] = UInt8((layout.codec.manualLevels?.lowerBound ?? 0) << 4) | 1
            if layout.codec == .spacePro { block[2] = 1 }
            if layout.codec == .space2 { block[1] = 0x3f; block[2] = 2; block[5] = 1 }
            bytes.replaceSubrange(layout.modeOffset..<(layout.modeOffset + block.count), with: block)
            if let at = layout.caseBatteryOffset { bytes[at] = model.batteryScale == .percent ? 90 : 3 }
            if let at = layout.caseFirmwareOffset { put("03.04", at) }
        }
        if model == .sleepA30 { put("01.68", 36); bytes[140] = 1 }
        return Data(bytes)
    }
    static func applying(_ packet: SoundcorePacket, to state: SoundcoreState) throws -> SoundcoreState {
        guard state.isSimulated else { throw SoundcoreFailure.refused("Simulation cannot change a physical report.") }
        try SoundcoreWriteGuard.check(model: state.model, state: state, packet: packet)
        guard packet.isWrite else { throw SoundcoreFailure.refused("A read does not change simulated state.") }
        var bytes = Array(state.raw)
        if state.model == .sleepA30 {
            if packet.command == SoundcoreCommands.setSleepTimer { bytes[144] = Array(packet.body)[3] }
            else if let flag = SoundcoreWrites.sleepFlags.first(where: { $0.command == packet.command }), let value = packet.body.first { bytes[flag.offset] = value }
            else { throw SoundcoreFailure.refused("This session operation has no simulated setting effect.") }
        } else if let layout = state.model.layout {
            if packet.command == SoundcoreCommands.setSoundModes {
                bytes.replaceSubrange(layout.modeOffset..<(layout.modeOffset + layout.codec.size), with: packet.body)
            } else if let setting = layout.settings.first(where: { $0.command == packet.command }) {
                bytes.replaceSubrange(setting.offset..<(setting.offset + packet.body.count), with: packet.body)
            } else { throw SoundcoreFailure.refused("This session operation has no simulated setting effect.") }
        }
        guard var result = SoundcoreStateReader.parse(model: state.model, body: Data(bytes)) else { throw SoundcoreFailure.invalid("The simulated write did not produce a valid state.") }
        result.isSimulated = true
        return result
    }
}
