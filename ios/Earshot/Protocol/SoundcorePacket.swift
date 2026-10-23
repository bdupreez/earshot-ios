import Foundation

// AI-assisted native adaptation of HellzYeahh/earshot's MIT Soundcore implementation.
// soundcorebridge (MIT) and upstream's restated OpenSCQ30/Gadgetbridge protocol
// facts inform this codec; no GPL/AGPL implementation is copied. These frames
// describe Classic RFCOMM control. They do NOT establish any iOS GATT endpoint.
enum SoundcoreFailure: LocalizedError, Equatable {
    case invalid(String), refused(String)
    var errorDescription: String? { switch self { case .invalid(let text), .refused(let text): return text } }
}

struct SoundcorePacket: Equatable, Sendable {
    static let outboundPrefix: [UInt8] = [0x08, 0xee, 0, 0, 0]
    static let inboundPrefix: [UInt8] = [0x09, 0xff, 0, 0, 1]
    static let overhead = 10
    let command: UInt16
    var body: Data = Data()
    var inbound = false
    var category: UInt8 { UInt8(command >> 8) }
    var code: UInt8 { UInt8(command & 0xff) }
    // Sleep A30's incoming-call and ANC-prompt setters (10 75, 10 77) are
    // documented exceptions to the high-bit convention. Treat both as mutations
    // at every state/allow-list/simulation boundary, never as harmless reads.
    var isWrite: Bool { code >= 0x80 || SoundcoreCommands.lowCodeMutations.contains(command) }

    func encode() throws -> Data {
        let count = body.count + Self.overhead
        guard count <= SoundcoreFrameBuffer.maximumFrame else { throw SoundcoreFailure.invalid("Soundcore frame exceeds the documented frame limit.") }
        var bytes = inbound ? Self.inboundPrefix : Self.outboundPrefix
        bytes += [category, code, UInt8(count & 0xff), UInt8(count >> 8)]
        bytes += body
        bytes.append(Self.checksum(bytes))
        return Data(bytes)
    }
    static func checksum(_ bytes: [UInt8]) -> UInt8 { bytes.reduce(0) { $0 &+ $1 } }
}

struct SoundcoreFrameBuffer {
    static let maximumFrame = 2048
    private(set) var pending = Data()
    private(set) var droppedBytes = 0
    mutating func reset() { pending.removeAll(); droppedBytes = 0 }
    mutating func feed(_ chunk: Data) -> [SoundcorePacket] {
        var result: [SoundcorePacket] = []
        // Process bounded slices rather than retaining an unbounded notification.
        for start in stride(from: 0, to: chunk.count, by: Self.maximumFrame) {
            pending.append(contentsOf: chunk.dropFirst(start).prefix(Self.maximumFrame))
            drain(into: &result)
        }
        return result
    }
    private mutating func drain(into result: inout [SoundcorePacket]) {
        while true {
            let bytes = Array(pending)
            let start = bytes.count >= 5 ? (0...(bytes.count - 5)).first {
                Array(bytes[$0..<($0 + 5)]) == SoundcorePacket.inboundPrefix || Array(bytes[$0..<($0 + 5)]) == SoundcorePacket.outboundPrefix
            } : nil
            guard let start else {
                let keep = min(4, bytes.count)
                droppedBytes += bytes.count - keep
                pending = Data(bytes.suffix(keep)); return
            }
            if start > 0 { pending.removeFirst(start); droppedBytes += start; continue }
            guard bytes.count >= 9 else { return }
            let total = Int(bytes[7]) | Int(bytes[8]) << 8
            guard (SoundcorePacket.overhead...Self.maximumFrame).contains(total) else {
                pending.removeFirst(); droppedBytes += 1; continue
            }
            guard bytes.count >= total else { return }
            let frame = Array(bytes.prefix(total))
            pending.removeFirst(total)
            guard SoundcorePacket.checksum(Array(frame.dropLast())) == frame.last else { droppedBytes += total; continue }
            result.append(SoundcorePacket(command: UInt16(frame[5]) << 8 | UInt16(frame[6]),
                body: Data(frame[9..<(total - 1)]), inbound: Array(frame.prefix(5)) == SoundcorePacket.inboundPrefix))
        }
    }
}

enum SoundcoreCommands {
    static let requestState: UInt16 = 0x0101, requestInfo: UInt16 = 0x0105
    static let pushTWS: UInt16 = 0x0102, pushBattery: UInt16 = 0x0103, pushCharging: UInt16 = 0x0104
    static let pushSoundModes: UInt16 = 0x0601, setSoundModes: UInt16 = 0x0681
    static let setANC: UInt16 = 0x0687, setTapDisabled: UInt16 = 0x1094, setListeningMode: UInt16 = 0x01a9
    static let setDefaultListeningMode: UInt16 = 0x1095, setLowBatteryPrompt: UInt16 = 0x1082
    static let setAutoOffPrompt: UInt16 = 0x109e, setListeningModePrompt: UInt16 = 0x109f, setANCPrompt: UInt16 = 0x1077
    static let setIncomingCalls: UInt16 = 0x1075, setAutoSwitchAsleep: UInt16 = 0x158f, setSleepTimer: UInt16 = 0x1585
    static let sleepSettings: UInt16 = 0x1503, alarms: UInt16 = 0x1401, sessionInfo: UInt16 = 0x0501, sessionInit: UInt16 = 0x0581
    static let lowCodeMutations: Set<UInt16> = [setIncomingCalls, setANCPrompt]
}

enum SoundcoreWriteGuard {
    static let never: Set<UInt16> = [0x0b81, 0x0b82, 0x0b83, 0x0b85, 0x0185, 0x0189, 0x1089, 0x0482, 0x1482, 0x0901]
    static let sleepFlags: Set<UInt16> = [0x0687, 0x1094, 0x01a9, 0x1095, 0x1082, 0x109e, 0x109f, 0x1077, 0x1075, 0x158f]

    static func allows(model: SoundcoreModel?, packet: SoundcorePacket) -> Bool {
        guard !packet.inbound, !never.contains(packet.command) else { return false }
        if [SoundcoreCommands.requestState, SoundcoreCommands.requestInfo].contains(packet.command) { return packet.body.isEmpty }
        guard let model else { return false } // Unknown family never inherits Sleep A30's writes.
        if model == .sleepA30 {
            if [SoundcoreCommands.sleepSettings, SoundcoreCommands.alarms, SoundcoreCommands.sessionInfo, SoundcoreCommands.sessionInit].contains(packet.command) { return packet.body.isEmpty }
            if sleepFlags.contains(packet.command) { return packet.body.count == 1 && packet.body.first.map { $0 <= 1 } == true }
            if packet.command == SoundcoreCommands.setSleepTimer {
                let b = Array(packet.body)
                guard b.count == 4 else { return false }
                // Upstream's exposed control writes only the post-sleep action,
                // leaving all three timer bytes unchanged. No guessed timer write.
                return Array(b.prefix(3)) == [255, 255, 255] && b[3] <= 1
            }
            return false
        }
        guard let layout = model.layout, layout.writable else { return false }
        if packet.command == SoundcoreCommands.sessionInfo { return layout.sessionInit && packet.body.isEmpty }
        return layout.allows(command: packet.command, body: packet.body)
    }
    static func check(model: SoundcoreModel?, packet: SoundcorePacket) throws {
        guard allows(model: model, packet: packet) else { throw SoundcoreFailure.refused("This Soundcore command or payload is not on this model's safe allow-list.") }
    }
    static func documentedReads(for model: SoundcoreModel?) -> [SoundcorePacket] {
        [SoundcoreCommands.requestState, SoundcoreCommands.requestInfo, SoundcoreCommands.sessionInfo, SoundcoreCommands.alarms, SoundcoreCommands.sleepSettings]
            .map { SoundcorePacket(command: $0) }.filter { allows(model: model, packet: $0) }
    }
}
