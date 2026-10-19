import Foundation

extension BoseAudioSettings {
    /// Expected comparison target, never a substitute for an actual headphone response.
    /// HellzYeahh's Earshot AudioModes.kt documents the 47-byte COMPACT/QC45 quirk:
    /// writing Wind Block makes firmware report CNC wire 0 (UI level 10), regardless
    /// of the transmitted CNC. The write bytes remain exactly as the user requested.
    func expectedModeReport(for mode: BoseMode?) -> BoseAudioSettings {
        guard mode?.raw.count == 47, windBlock else { return self }
        var expected = self
        expected.cancellingLevel = 10
        return expected
    }
}
