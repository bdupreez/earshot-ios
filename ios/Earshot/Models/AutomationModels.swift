// AI-assisted native port of HellzYeahh/earshot's multi-action rules (MIT).
// Upstream: app/.../core/AutomationRepository.kt; see THIRD_PARTY_NOTICES.md.
import Foundation

enum AutomationAction: Codable, Equatable {
    case mode(Int)
    case noise(NoiseState)
    /// nil means bypass the local player EQ. This never changes another app's audio.
    case preset(String?)

    var kind: String {
        switch self { case .mode: return "mode"; case .noise: return "noise"; case .preset: return "preset" }
    }
    var needsHeadphones: Bool {
        switch self { case .mode, .noise: return true; case .preset: return false }
    }
}

extension AutomationRule {
    /// v0.1 rules stored just modeIndex. Retain that action when decoding old state,
    /// rather than resetting the user's rules when multi-action support is added.
    var effectiveActions: [AutomationAction] {
        let order = ["mode", "noise", "preset"]
        return (actions ?? [.mode(modeIndex)]).sorted { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }
    }
    /// ISO weekdays match upstream: Monday=1 ... Sunday=7, independent of locale.
    var effectiveWeekdays: Set<Int> { weekdays ?? Set(1...7) }

    var configurationError: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100 else { return "Give the rule a name of 1–100 characters." }
        guard ["On connection", "Schedule (app open)", "Manual"].contains(trigger) else { return "Choose a supported rule trigger." }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return "Choose a valid schedule time." }
        if trigger == "Schedule (app open)" {
            guard !effectiveWeekdays.isEmpty, effectiveWeekdays.isSubset(of: Set(1...7)) else { return "Choose at least one weekday." }
        }
        guard !effectiveActions.isEmpty, effectiveActions.count <= 3,
              Set(effectiveActions.map(\.kind)).count == effectiveActions.count else { return "Choose one or more different actions." }
        for action in effectiveActions {
            switch action {
            case .mode(let index):
                guard (0...254).contains(index) else { return "Choose a valid listening mode." }
            case .noise(let noise):
                guard noise.level.isFinite, (0...10).contains(noise.level), (0...2).contains(noise.spatial) else { return "Noise settings are outside the supported range." }
            case .preset(let id):
                if let id, id.isEmpty || id.count > 128 { return "Choose a valid local EQ preset." }
            }
        }
        return nil
    }

    static func weekdayName(_ isoDay: Int, short: Bool = false, calendar: Calendar = .current) -> String {
        guard (1...7).contains(isoDay) else { return "Unknown day" }
        return (short ? calendar.shortWeekdaySymbols : calendar.weekdaySymbols)[isoDay % 7]
    }
    var weekdayDescription: String {
        effectiveWeekdays == Set(1...7) ? "Every day" : effectiveWeekdays.sorted().map { Self.weekdayName($0, short: true) }.joined(separator: ", ")
    }
    var scheduleDescription: String {
        trigger == "Schedule (app open)" ? String(format: "%02d:%02d · ", hour, minute) + weekdayDescription + " · app open" : trigger
    }

    func scheduleOccurrence(at date: Date, calendar: Calendar = .current) -> String? {
        guard enabled, trigger == "Schedule (app open)", configurationError == nil else { return nil }
        let c = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        guard c.hour == hour, c.minute == minute, let weekday = c.weekday,
              effectiveWeekdays.contains((weekday + 5) % 7 + 1) else { return nil }
        // Wall-clock keys deliberately coalesce the repeated hour at daylight-saving
        // fall-back. A zone change or an edited time represents a new occurrence.
        return "\(calendar.timeZone.identifier)|\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)|\(hour):\(minute)"
    }

    func alreadyAttempted(_ occurrence: String, date: Date, calendar: Calendar = .current) -> Bool {
        lastFiredDay == occurrence || lastFiredDay == calendar.startOfDay(for: date).description
    }
}

enum RuleRunSource: Equatable { case manual, connection, schedule, shortcut }

enum RuleExecutionError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let text) = self { return text }; return nil }
}

/// A destination slot matters when firmware has only editable-slot noise writes.
struct NoiseWriteCapabilities {
    let globalWrite: Bool
    let editableModeIDs: Set<Int>
    let currentMode: Int
    func canWrite(afterSelecting target: Int?) -> Bool { globalWrite || editableModeIDs.contains(target ?? currentMode) }
}
