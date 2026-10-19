import Foundation

/// Upstream Earshot Settings.kt CNC [1.5], by HellzYeahh and contributors (MIT).
struct BoseCNCState: Equatable, Sendable {
    let steps: Int
    let step: Int
    let flags: UInt8
    private init(steps: Int, step: Int, flags: UInt8) { self.steps = steps; self.step = step; self.flags = flags }
    var enabled: Bool { flags & 1 != 0 }
    var userCanToggle: Bool { flags & 2 == 0 }
    var maximumStep: Int { steps - 1 }
    /// Same integer rounding as upstream: UI 10 is wire step 0.
    var cancellingLevel: Int { ((maximumStep - step) * 10 + maximumStep / 2) / maximumStep }

    static func parse(_ payload: Data) -> BoseCNCState? {
        let bytes = Array(payload)
        guard bytes.count >= 3, bytes[0] >= 2, bytes[1] < bytes[0] else { return nil }
        return BoseCNCState(steps: Int(bytes[0]), step: Int(bytes[1]), flags: bytes[2])
    }

    func step(forLevel level: Int) throws -> Int {
        guard (0...10).contains(level), (2...255).contains(steps), (0..<steps).contains(step) else {
            throw BmapFailure.invalidPacket("Read a valid noise step range before changing the level.")
        }
        return maximumStep - (level * maximumStep + 5) / 10
    }

    /// A comparison target only. Actual state must still come from a valid device report.
    func expectedDirectReport(for requested: BoseAudioSettings) throws -> BoseAudioSettings {
        let targetStep = try step(forLevel: requested.cancellingLevel)
        let applied = BoseCNCState(steps: steps, step: targetStep, flags: flags)
        var expected = requested
        expected.cancellingLevel = applied.cancellingLevel
        expected.ancEnabled = userCanToggle ? requested.ancEnabled : enabled
        return expected
    }
}

extension BoseCommands {
    static func setDirectNoise(_ requested: BoseAudioSettings, state: BoseCNCState) throws -> BmapPacket {
        let wireStep = try state.step(forLevel: requested.cancellingLevel)
        let enabled = state.userCanToggle ? requested.ancEnabled : state.enabled
        return BmapPacket(block: 1, function: 5, operation: .setGet, payload: Data([UInt8(wireStep), enabled ? 1 : 0]))
    }
}
