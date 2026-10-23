import Foundation

// AI-assisted adaptation of HellzYeahh/earshot AudioLinkMonitor/AutomationEngine (MIT).
// These are this app's public audio-route observations, not global Bluetooth monitoring.
enum AudioRouteObservationReason: Equatable, Sendable {
    case refresh, newDeviceAvailable, oldDeviceUnavailable, routeSelection
    case categoryChange, microphoneTransition, unknown
    var canIndicateConnection: Bool {
        switch self {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeSelection: return true
        default: return false
        }
    }
}

struct AudioRouteConnectionPolicy {
    private(set) var lastExternalID: String?

    /// Inactive events update the baseline without replay on activation. App-owned
    /// category/HFP changes preserve it, preventing microphone-driven reconnect loops.
    mutating func observe(_ output: CompanionAudioOutput?, reason: AudioRouteObservationReason,
                          isAppActive: Bool) -> Bool {
        if reason == .categoryChange || reason == .microphoneTransition { return false }
        let externalID = output.flatMap { $0.isHeadphones && !$0.id.isEmpty ? $0.id : nil }
        let changed = externalID != lastExternalID
        lastExternalID = externalID
        return changed && externalID != nil && isAppActive && reason.canIndicateConnection
    }
}
