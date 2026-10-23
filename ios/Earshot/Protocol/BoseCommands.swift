import Foundation

enum BoseCommands {
    static func get(_ address: BmapAddress) -> BmapPacket {
        BmapPacket(block: address.block, function: address.function, operation: .get)
    }

    static let liveness = get(BmapAddress(0, 1))
    static let subscribeNotifications = BmapPacket(block: 9, function: 2, operation: .setGet,
                                                  payload: Data([0x01, 0x80, 0x04, 0x22, 0xb7]))
    /// Query one at a time: unsupported functions are firmware capabilities, not fatal link errors.
    static let refresh: [BmapPacket] = [BmapAddress(0, 3), BmapAddress(0, 5), BmapAddress(0, 15),
        BmapAddress(1, 2), BmapAddress(2, 2), BmapAddress(2, 5), BmapAddress(1, 7),
        BmapAddress(31, 2), BmapAddress(31, 3), BmapAddress(31, 10), BmapAddress(31, 8),
        BmapAddress(1, 5), BmapAddress(1, 3), BmapAddress(1, 4), BmapAddress(1, 9),
        BmapAddress(1, 10), BmapAddress(1, 11), BmapAddress(1, 24), BmapAddress(1, 27),
        BmapAddress(1, 34), BmapAddress(1, 37), BmapAddress(4, 4), BmapAddress(5, 5),
        BmapAddress(5, 4), BmapAddress(2, 21), BmapAddress(0, 23), BmapAddress(5, 1),
        BmapAddress(5, 3), BmapAddress(5, 7), BmapAddress(7, 4), BmapAddress(0, 2),
        BmapAddress(4, 1), BmapAddress(4, 2), BmapAddress(4, 3), BmapAddress(4, 8),
        BmapAddress(4, 9), BmapAddress(4, 12), BmapAddress(4, 14), BmapAddress(4, 18), BmapAddress(2, 16)].map(get)

    static func setVolume(level: Int, maximum: Int) throws -> BmapPacket {
        guard (1...255).contains(maximum), (0...maximum).contains(level) else { throw BmapFailure.invalidPacket("Volume is outside the range reported by the headphones.") }
        return BmapPacket(block: 5, function: 5, operation: .setGet, payload: Data([UInt8(level)]))
    }

    static func playback(action: UInt8) throws -> BmapPacket {
        guard action <= 8 else { throw BmapFailure.invalidPacket("Unknown playback action.") }
        return BmapPacket(block: 5, function: 3, operation: .start, payload: Data([action]))
    }

    static let readModes = BmapPacket(block: 31, function: 6, operation: .start)

    static func setEQ(band: UInt8, value: Int) throws -> BmapPacket {
        guard band <= 2, (-10...10).contains(value) else { throw BmapFailure.invalidPacket("EQ must be a band 0…2 and a value −10…10.") }
        return BmapPacket(block: 1, function: 7, operation: .setGet, payload: Data([UInt8(bitPattern: Int8(value)), band]))
    }

    static func selectMode(index: UInt8) -> BmapPacket {
        BmapPacket(block: 31, function: 3, operation: .start, payload: Data([index, 0]))
    }

    static func setAudio(_ settings: BoseAudioSettings) throws -> BmapPacket {
        guard (0...10).contains(settings.cancellingLevel), settings.spatial <= 2 else { throw BmapFailure.invalidPacket("Invalid listening mode settings.") }
        // autoCnc must be zero; enabling it is rejected by known firmware.
        return BmapPacket(block: 31, function: 10, operation: .setGet,
                          payload: Data([UInt8(10 - settings.cancellingLevel), 0, settings.spatial,
                                         settings.windBlock ? 1 : 0, settings.ancEnabled ? 1 : 0]))
    }

    static func setToggle(function: UInt8, enabled: Bool) -> BmapPacket {
        BmapPacket(block: 1, function: function, operation: .setGet, payload: Data([enabled ? 1 : 0]))
    }

    static func setTouchControls(enabled: Bool) -> BmapPacket {
        // Upstream 99270636 verified bit 0 as touch ON (QC Ultra 2 fw 10.12).
        // The historical DisableCaptouch name is misleading. Ignore unrelated higher bits when reading.
        setToggle(function: 34, enabled: enabled)
    }

    static func setVoicePrompts(enabled: Bool, language: UInt8) throws -> BmapPacket {
        guard language < 32 else { throw BmapFailure.invalidPacket("Unknown voice-prompt language.") }
        return BmapPacket(block: 1, function: 3, operation: .setGet,
                          payload: Data([(enabled ? 0x20 : 0) | language]))
    }

    static func setSidetone(level: UInt8, persist: Bool = true) throws -> BmapPacket {
        guard level <= 3 else { throw BmapFailure.invalidPacket("Sidetone level must be 0…3.") }
        return BmapPacket(block: 1, function: 11, operation: .setGet, payload: Data([persist ? 1 : 0, level]))
    }

    static func setName(_ name: String) throws -> BmapPacket {
        let data = Data(name.utf8)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !data.contains(0), data.count <= 31 else {
            throw BmapFailure.invalidPacket("A name must contain 1…31 UTF-8 bytes without a NUL character.")
        }
        return BmapPacket(block: 1, function: 2, operation: .setGet, payload: data)
    }

    static func setStandby(minutes: Int) throws -> BmapPacket {
        guard (0...65_535).contains(minutes) else { throw BmapFailure.invalidPacket("Invalid standby time.") }
        let bytes: [UInt8] = minutes <= 255 ? [UInt8(minutes)] : [UInt8(minutes & 255), UInt8(minutes >> 8)]
        return BmapPacket(block: 1, function: 4, operation: .setGet, payload: Data(bytes))
    }

    static func setDirectNoise(level: Int, steps: Int, enabled: Bool = true) throws -> BmapPacket {
        guard (0...10).contains(level), (2...255).contains(steps) else { throw BmapFailure.invalidPacket("Invalid noise level or device step range.") }
        let maximum = steps - 1
        let wire = maximum - (level * maximum + 5) / 10
        return BmapPacket(block: 1, function: 5, operation: .setGet, payload: Data([UInt8(wire), enabled ? 1 : 0]))
    }

    static let readCurrentMode = get(BmapAddress(31, 3))

    static func writeMode(_ mode: BoseMode, name: String? = nil, settings: BoseAudioSettings? = nil) throws -> BmapPacket {
        guard mode.editable == true else { throw BmapFailure.invalidPacket("Only a mode reported editable by the headphones can be changed.") }
        let audio = settings ?? mode.settings
        guard (0...10).contains(audio.cancellingLevel), audio.spatial <= 2 else { throw BmapFailure.invalidPacket("Invalid mode settings.") }
        let string = name ?? mode.name
        let encodedName = Data(string.utf8)
        guard encodedName.count <= 31, !encodedName.contains(0) else { throw BmapFailure.invalidPacket("Mode names must fit 31 UTF-8 bytes.") }
        let length: Int
        switch mode.raw.count {
        case 48...: length = 40
        case 47, 45, 46: length = 39
        case 44: length = 37
        default: throw BmapFailure.invalidPacket("Read the complete mode configuration before editing it.")
        }
        var bytes = [UInt8](repeating: 0, count: length)
        bytes[0] = mode.index
        if name == nil { bytes[1] = mode.prompt.0; bytes[2] = mode.prompt.1 }
        bytes.replaceSubrange(3..<(3 + encodedName.count), with: encodedName)
        bytes[35] = UInt8(10 - audio.cancellingLevel)
        if length > 37 { bytes[37] = audio.spatial }
        if length > 38, mode.raw.count >= 47 { bytes[38] = audio.windBlock ? 1 : 0 }
        if length > 39 { bytes[39] = audio.ancEnabled ? 1 : 0 }
        return BmapPacket(block: 31, function: 6, operation: .setGet, payload: Data(bytes))
    }

    static func setFavorites(indices: Set<Int>, totalModes: Int) throws -> BmapPacket {
        guard (1...255).contains(totalModes), indices.allSatisfy({ (0..<totalModes).contains($0) }) else {
            throw BmapFailure.invalidPacket("Favourite indices must be within the device’s mode range.")
        }
        var bytes = [UInt8](repeating: 0, count: max(1, (totalModes + 7) / 8))
        for index in indices { bytes[bytes.count - 1 - index / 8] |= 1 << (index % 8) }
        return BmapPacket(block: 31, function: 8, operation: .setGet, payload: Data([UInt8(totalModes)] + bytes))
    }
}
