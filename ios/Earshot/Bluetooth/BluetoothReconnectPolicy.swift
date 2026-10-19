import Foundation

/// Native iOS lifecycle policy for the AI-assisted port of HellzYeahh/earshot (MIT).
/// Mirrors upstream's explicit user-stop rule, with a finite retry budget suitable for iOS.
struct BluetoothReconnectPolicy: Equatable {
    static let delays: [TimeInterval] = [1, 2, 4, 8, 16, 30]
    var enabled: Bool
    var rememberedID: UUID?
    var userStopped: Bool
    var suspended = false
    private(set) var attempts = 0

    var eligible: Bool { enabled && rememberedID != nil && !userStopped && !suspended }
    var exhausted: Bool { attempts >= Self.delays.count }

    mutating func nextDelay() -> TimeInterval? {
        guard eligible, !exhausted else { return nil }
        let delay = Self.delays[attempts]
        attempts += 1
        return delay
    }

    mutating func enable(_ value: Bool) {
        enabled = value; attempts = 0
        if value { userStopped = false }
    }
    mutating func manualConnection() { userStopped = false; suspended = false; attempts = 0 }
    mutating func manualDisconnect() { userStopped = true; attempts = 0 }
    mutating func verified(_ identifier: UUID) { rememberedID = identifier; userStopped = false; attempts = 0 }
    mutating func resume() { suspended = false }
    mutating func rearm() { attempts = 0 }
}

struct BluetoothLivenessMonitor {
    enum Action: Equatable { case none, sendProbe, disconnect }
    var lastResponse: Date
    private(set) var probeSentAt: Date?
    private var unansweredRequests: [Date] = []
    init(lastResponse: Date) { self.lastResponse = lastResponse }

    mutating func sentRequest(at now: Date) {
        unansweredRequests.append(now)
        if unansweredRequests.count > 256 { unansweredRequests.removeFirst() }
    }
    mutating func received(at now: Date) { lastResponse = now; probeSentAt = nil; unansweredRequests.removeAll() }
    mutating func tick(at now: Date) -> Action {
        if let probeSentAt { return now.timeIntervalSince(probeSentAt) >= 3 ? .disconnect : .none }
        // Upstream tolerates absent/silent functions, probing only after three unanswered
        // requests. An idle notification subscription must not become periodic BMAP polling.
        guard unansweredRequests.filter({ now.timeIntervalSince($0) >= 1.5 }).count >= 3 else { return .none }
        probeSentAt = now
        return .sendProbe
    }
}
