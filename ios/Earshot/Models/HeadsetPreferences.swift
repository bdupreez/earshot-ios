// AI-assisted adaptation of HellzYeahh/earshot HeadsetEqMemory and ShortcutAction (MIT).
import Foundation

enum CompanionAction: String, Codable, CaseIterable, Identifiable {
    case none, cycleEQ, voiceMemo
    var id: String { rawValue }
    var title: String {
        switch self { case .none: return "No Earshot action"; case .cycleEQ: return "Cycle local EQ"; case .voiceMemo: return "Start / stop voice memo" }
    }
}

struct HeadsetEQSelection: Codable, Equatable {
    var enabled: Bool
    var presetID: String?
    static let off = Self(enabled: false, presetID: nil)
    static func preset(_ id: String) -> Self { .init(enabled: true, presetID: id) }
}

struct HeadsetPreferences: Codable, Equatable {
    var rememberEQ = true
    var spokenFeedback = true
    var defaultAction = CompanionAction.none
    var outputEQ: [String: HeadsetEQSelection] = [:]
    var outputActions: [String: CompanionAction] = [:]
    static let maximumOutputs = 100
    init() {}
    private enum CodingKeys: String, CodingKey { case rememberEQ, spokenFeedback, defaultAction, outputEQ, outputActions }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rememberEQ = try values.decodeIfPresent(Bool.self, forKey: .rememberEQ) ?? true
        spokenFeedback = try values.decodeIfPresent(Bool.self, forKey: .spokenFeedback) ?? true
        defaultAction = (try? values.decode(CompanionAction.self, forKey: .defaultAction)) ?? .none
        if let eq = try? values.nestedContainer(keyedBy: OutputKey.self, forKey: .outputEQ) {
            for key in eq.allKeys.sorted(by: { $0.stringValue < $1.stringValue }).prefix(Self.maximumOutputs) {
                guard !key.stringValue.isEmpty, key.stringValue.utf8.count <= 512,
                      let selection = try? eq.decode(HeadsetEQSelection.self, forKey: key),
                      !selection.enabled || selection.presetID.map({ !$0.isEmpty && $0.utf8.count <= 256 }) == true else { continue }
                outputEQ[key.stringValue] = selection
            }
        }
        let rawActions = (try? values.decode([String: String].self, forKey: .outputActions)) ?? [:]
        outputActions = Dictionary(uniqueKeysWithValues: rawActions.sorted { $0.key < $1.key }.compactMap { key, value in
            guard !key.isEmpty, key.utf8.count <= 512, let action = CompanionAction(rawValue: value) else { return nil }
            return (key, action)
        }.prefix(Self.maximumOutputs))
    }
    private struct OutputKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    func action(for outputID: String?) -> CompanionAction { outputID.flatMap { outputActions[$0] } ?? defaultAction }
    @discardableResult mutating func remember(_ selection: HeadsetEQSelection, outputID: String) -> Bool {
        guard !outputID.isEmpty, outputID.utf8.count <= 512,
              outputEQ[outputID] != nil || outputEQ.count < Self.maximumOutputs else { return false }
        outputEQ[outputID] = selection
        return true
    }
    @discardableResult mutating func setAction(_ action: CompanionAction?, outputID: String) -> Bool {
        guard !outputID.isEmpty, outputID.utf8.count <= 512,
              action == nil || outputActions[outputID] != nil || outputActions.count < Self.maximumOutputs else { return false }
        outputActions[outputID] = action
        return true
    }
}

enum HeadsetEQRestoreDecision: Equatable {
    case unchanged, apply(String?), forgetMissing
    static func decide(selection: HeadsetEQSelection?, enabled: Bool, availableIDs: Set<String>) -> Self {
        guard enabled, let selection else { return .unchanged }
        guard selection.enabled else { return .apply(nil) }
        guard let id = selection.presetID, availableIDs.contains(id) else { return .forgetMissing }
        return .apply(id)
    }
}

enum CompanionEQCycle {
    static func next(presetIDs: [String], currentID: String?) -> String? {
        var seen = Set<String>()
        let ids = presetIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard let first = ids.first else { return nil }
        guard let currentID, let index = ids.firstIndex(of: currentID) else { return first }
        return ids[(index + 1) % ids.count]
    }
}
