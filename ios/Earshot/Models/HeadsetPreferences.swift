// AI-assisted adaptation of HellzYeahh/earshot HeadsetEqMemory, ShortcutAction and
// CompanionRemote aliases (MIT). iOS nicknames are app-local, never system Bluetooth aliases.
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
    private(set) var outputNicknames: [String: String] = [:]
    static let maximumOutputs = 100
    static let maximumNicknameBytes = 80
    init() {}
    private enum CodingKeys: String, CodingKey { case rememberEQ, spokenFeedback, defaultAction, outputEQ, outputActions, outputNicknames }
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
        if let nicknames = try? values.nestedContainer(keyedBy: OutputKey.self, forKey: .outputNicknames) {
            for key in nicknames.allKeys.sorted(by: { $0.stringValue < $1.stringValue }) {
                guard let raw = try? nicknames.decode(String.self, forKey: key) else { continue }
                _ = setNickname(raw, outputID: key.stringValue)
                if outputNicknames.count == Self.maximumOutputs { break }
            }
        }
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
    static func validatedNickname(_ raw: String) -> String? {
        let forbidden = CharacterSet.controlCharacters.union(.newlines)
        guard !raw.unicodeScalars.contains(where: { forbidden.contains($0) }) else { return nil }
        let nickname = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty, nickname.utf8.count <= maximumNicknameBytes else { return nil }
        return nickname
    }
    func nickname(for outputID: String?) -> String? { outputID.flatMap { outputNicknames[$0] } }
    /// Each category admits 100 routes independently; the management list covers their full union.
    var savedOutputIDs: [String] {
        Array(Set(outputEQ.keys).union(outputActions.keys).union(outputNicknames.keys)).sorted()
            .prefix(Self.maximumOutputs * 3).map { $0 }
    }
    static func abbreviatedOutputID(_ outputID: String) -> String {
        let safe = outputID.components(separatedBy: CharacterSet.controlCharacters.union(.newlines)).joined()
        return safe.isEmpty ? "Unavailable route identifier" : "…\(safe.suffix(8))"
    }
    @discardableResult mutating func setNickname(_ nickname: String?, outputID: String) -> Bool {
        guard !outputID.isEmpty, outputID.utf8.count <= 512 else { return false }
        guard let nickname else { outputNicknames.removeValue(forKey: outputID); return true }
        guard let validated = Self.validatedNickname(nickname),
              outputNicknames[outputID] != nil || outputNicknames.count < Self.maximumOutputs else { return false }
        outputNicknames[outputID] = validated
        return true
    }
    mutating func forget(outputID: String) {
        outputEQ.removeValue(forKey: outputID)
        outputActions.removeValue(forKey: outputID)
        outputNicknames.removeValue(forKey: outputID)
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
