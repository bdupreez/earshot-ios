import Foundation

/// First guesses from upstream Earshot's BoseModel.kt (HellzYeahh and contributors, MIT).
/// These are catalogue facts, not iPhone verification. Device capabilities/status always win.
struct BoseModelFacts: Equatable {
    let productID: UInt16
    let presetNames: [String]
    let customCount: Int
    let knownAbsent: Set<BmapAddress>
    let directNoise: Bool
    let unsupported: Bool
    var prefersModesGetAll: Bool { [0x4075, 0x4039, 0x4064, 0x402f, 0x4068, 0x4089].contains(productID) }
    var windExcludesNoiseLevel: Bool { [0x4075, 0x4039].contains(productID) }
    var modeDumpCommand: BmapPacket { BmapPacket(block: 31, function: prefersModesGetAll ? 1 : 6, operation: .start) }

    static func lookup(_ productID: UInt16) -> BoseModelFacts? {
        let legacy: Set<BmapAddress> = [BmapAddress(31, 10), BmapAddress(0, 23), BmapAddress(1, 37), BmapAddress(4, 19), BmapAddress(5, 7), BmapAddress(1, 34)]
        let earbudLegacy = legacy.subtracting([BmapAddress(1, 34)])
        let quiet = ["Quiet", "Aware"]
        let ultra = quiet + ["Immersion", "Cinema"]
        let open = ["Stereo", "Immersion", "Cinema"]
        let presets: [String], customs: Int, absent: Set<BmapAddress>, direct: Bool, unsupported: Bool
        switch productID {
        case 0x4082, 0x4083, 0x4062: (presets, customs, absent, direct, unsupported) = (ultra, 7, [], false, false)
        case 0x4066, 0x4072: (presets, customs, absent, direct, unsupported) = (Array(ultra.prefix(3)), 7, [], false, false)
        case 0x4075: (presets, customs, absent, direct, unsupported) = (quiet, 2, legacy, false, false)
        case 0x4039: (presets, customs, absent, direct, unsupported) = (quiet, 2, legacy.union([BmapAddress(1, 24), BmapAddress(1, 27)]), false, false)
        case 0x4064: (presets, customs, absent, direct, unsupported) = (quiet, 2, earbudLegacy, false, false)
        case 0x402f: (presets, customs, absent, direct, unsupported) = (quiet, 2, legacy.union([BmapAddress(1, 24), BmapAddress(1, 27)]), true, false)
        case 0x4024: (presets, customs, absent, direct, unsupported) = ([], 0, legacy, true, false)
        case 0x4068, 0x4089:
            (presets, customs, absent, direct, unsupported) = (productID == 0x4068 ? Array(open.prefix(2)) : open, 0,
                [BmapAddress(1, 5), BmapAddress(31, 10), BmapAddress(1, 37), BmapAddress(5, 7)], false, false)
        case 0x400c, 0x4020, 0x0023: (presets, customs, absent, direct, unsupported) = ([], 0, [], false, true)
        default: return nil
        }
        return BoseModelFacts(productID: productID, presetNames: presets, customCount: customs, knownAbsent: absent, directNoise: direct, unsupported: unsupported)
    }

    func builtInLabels(reportedCount: Int) -> [String] {
        guard reportedCount > 0 else { return [] }
        return (0..<min(255, reportedCount)).map { presetNames.indices.contains($0) ? presetNames[$0] : "Mode \($0 + 1)" }
    }

    /// Exact upstream name rules are a fallback only; a known ProductIdVariants reply wins.
    static func fromName(_ name: String) -> BoseModelFacts? {
        var n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if n.hasPrefix("le-") { n.removeFirst(3) }
        n = n.replacingOccurrences(of: "quietcomfort", with: "qc").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        func matches(_ pattern: String) -> Bool { n.range(of: pattern, options: .regularExpression) != nil }
        let gen2 = matches("\\b(2nd|gen ?2)\\b")
        let id: UInt16
        if (n.contains("ultra open") || n.contains("open earbuds")) && !n.contains("sport") {
            id = gen2 || matches("\\bopen (2|ii)\\b") ? 0x4089 : 0x4068
        } else if n.contains("qc ultra") && n.contains("earbud") {
            id = gen2 || matches("\\b(earbuds?|ultra) (2|ii)\\b") ? 0x4062 : 0x4072
        } else if n.contains("qc ultra") { id = gen2 || matches("\\bultra (2|ii)\\b") ? 0x4082 : 0x4066
        } else if matches("qc ?45") || matches("qc ?se\\b") { id = 0x4039
        } else if matches("qc ?35 ?(ii|2)\\b") { id = 0x4020
        } else if matches("qc ?35\\b") { id = 0x400c
        } else if matches("qc ?sc\\b") { id = 0x4075
        } else if matches("\\bqc (2|ii) hp\\b") { id = 0x4083
        } else if n.contains("qc headphones") { id = gen2 || matches("\\bheadphones (2|ii)\\b") ? 0x4083 : 0x4075
        } else if matches("\\bnc ?700\\b") || n.contains("noise cancelling headphones 700") { id = 0x4024
        } else if n.contains("qc earbuds") { id = gen2 || matches("\\bearbuds (2|ii)\\b") ? 0x4064 : 0x402f
        } else { return nil }
        return lookup(id)
    }
}
