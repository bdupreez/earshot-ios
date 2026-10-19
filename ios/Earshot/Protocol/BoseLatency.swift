import Foundation

/// Exact signed-16-bit wire layout from HellzYeahh's upstream Earshot AudioManagement.kt (MIT).
/// The Bose app contains this setter but does not call it; units/effect are unverified.
struct BoseLatency: Equatable {
    let range: ClosedRange<Int>
    let current: Int

    static func parse(_ payload: Data) -> BoseLatency? {
        let bytes = Array(payload)
        guard bytes.count >= 6 else { return nil }
        func signed(_ index: Int) -> Int { Int(Int16(bitPattern: UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1]))) }
        let low = signed(0), high = signed(2), current = signed(4)
        guard low <= high, (low...high).contains(current) else { return nil }
        return BoseLatency(range: low...high, current: current)
    }
}

extension BoseCommands {
    static func setLatency(_ value: Int, reportedRange: ClosedRange<Int>) throws -> BmapPacket {
        guard reportedRange.lowerBound >= Int(Int16.min), reportedRange.upperBound <= Int(Int16.max),
              reportedRange.contains(value), let signed = Int16(exactly: value) else {
            throw BmapFailure.invalidPacket("Experimental latency must stay within the signed range reported by the headphones.")
        }
        let bits = UInt16(bitPattern: signed)
        return BmapPacket(block: 5, function: 7, operation: .setGet, payload: Data([UInt8(bits >> 8), UInt8(bits & 0xff)]))
    }
}
