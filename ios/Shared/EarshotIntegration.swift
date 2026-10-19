// AI-assisted iOS port attempt of HellzYeahh/earshot (MIT). Original contributors retain credit.
// Shared by the app and extensions; no Bluetooth work runs in a widget process.
import Foundation
import Darwin

enum EarshotListeningRole: String, Codable, Sendable { case quiet, aware }

enum EarshotCommandPayload: Codable, Equatable, Sendable {
    case listeningMode(index: Int)
    case listeningRole(EarshotListeningRole)
    case cycleModes
    case noiseLevel(Double)
    case hardwareEQ(bass: Double, mid: Double, treble: Double)
    case localPreset(id: String)
    case runRule(id: String)

    func validate() throws {
        switch self {
        case .listeningMode(let index):
            guard (0...254).contains(index) else { throw EarshotIntegrationError.invalidCommand }
        case .listeningRole, .cycleModes: break
        case .noiseLevel(let level):
            guard level.isFinite, (0...10).contains(level) else { throw EarshotIntegrationError.invalidCommand }
        case .hardwareEQ(let bass, let mid, let treble):
            guard [bass, mid, treble].allSatisfy({ $0.isFinite && (-10...10).contains($0) }) else { throw EarshotIntegrationError.invalidCommand }
        case .localPreset(let id), .runRule(let id):
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.utf8.count <= 256 else { throw EarshotIntegrationError.invalidCommand }
        }
    }

    fileprivate var replacementKey: String? {
        switch self {
        case .listeningMode, .listeningRole: return "mode"
        case .noiseLevel: return "noise"
        case .hardwareEQ: return "hardwareEQ"
        case .localPreset: return "localPreset"
        case .runRule: return nil // Separate rule invocations retain their order.
        case .cycleModes: return nil // Each tap advances once after the previous live report.
        }
    }

    fileprivate var coalescesRepeatedValues: Bool { if case .cycleModes = self { return false }; return true }
}

struct EarshotCommandEnvelope: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    let expiresAt: Date
    let payload: EarshotCommandPayload
}

struct EarshotCommandDrain: Sendable {
    let commands: [EarshotCommandEnvelope]
    let expiredCount: Int
    let discardedCount: Int
}

enum EarshotIntegrationError: LocalizedError {
    case storageUnavailable, invalidCommand, unsupportedData, queueFull
    var errorDescription: String? {
        switch self {
        case .storageUnavailable: return "Earshot’s shared storage is unavailable. Open the signed app and try again."
        case .invalidCommand: return "This Earshot request has invalid parameters."
        case .unsupportedData: return "Earshot’s pending requests could not be read. Open the app before trying again."
        case .queueFull: return "Earshot has too many pending requests. Open the app to process them first."
        }
    }
}

/// Cross-process, bounded, at-most-once delivery. Consumption is atomic; the app must
/// validate capabilities and report execution errors rather than interpreting enqueue as success.
struct EarshotCommandQueue: Sendable {
    static let maximumCount = 32
    static let lifetime: TimeInterval = 120
    let directory: URL

    private struct State: Codable {
        var version = 1
        var pending: [EarshotCommandEnvelope] = []
        var consumed: [UUID] = []
        var expiredCount = 0
        var discardedCount = 0
    }

    @discardableResult
    func enqueue(_ payload: EarshotCommandPayload, id: UUID = UUID(), now: Date = .now) throws -> EarshotCommandEnvelope? {
        try payload.validate()
        return try transaction { state in
            prune(&state, now: now)
            if state.consumed.contains(id) { return nil }
            if let existing = state.pending.first(where: { $0.id == id || (payload.coalescesRepeatedValues && $0.payload == payload && now.timeIntervalSince($0.createdAt) < 2) }) { return existing }
            if let key = payload.replacementKey { state.pending.removeAll { $0.payload.replacementKey == key } }
            guard state.pending.count < Self.maximumCount else { throw EarshotIntegrationError.queueFull }
            let envelope = EarshotCommandEnvelope(id: id, createdAt: now, expiresAt: now.addingTimeInterval(Self.lifetime), payload: payload)
            state.pending.append(envelope)
            return envelope
        }
    }

    func consumePending(now: Date = .now) throws -> EarshotCommandDrain {
        try transaction { state in
            prune(&state, now: now)
            let result = EarshotCommandDrain(commands: state.pending, expiredCount: state.expiredCount, discardedCount: state.discardedCount)
            state.consumed.append(contentsOf: state.pending.map(\.id))
            state.consumed = Array(state.consumed.suffix(128))
            state.pending.removeAll()
            state.expiredCount = 0
            state.discardedCount = 0
            return result
        }
    }

    private func prune(_ state: inout State, now: Date) {
        var kept: [EarshotCommandEnvelope] = []
        var seen = Set(state.consumed)
        for command in state.pending {
            if command.expiresAt <= now { state.expiredCount += 1; continue }
            if command.createdAt > now.addingTimeInterval(60) || command.expiresAt <= command.createdAt || command.expiresAt.timeIntervalSince(command.createdAt) > Self.lifetime + 1 || (try? command.payload.validate()) == nil || !seen.insert(command.id).inserted {
                state.discardedCount += 1
                continue
            }
            kept.append(command)
        }
        state.pending = kept
    }

    private func transaction<T>(_ body: (inout State) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lock = directory.appendingPathComponent("commands.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw EarshotIntegrationError.storageUnavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw EarshotIntegrationError.storageUnavailable }
        defer { flock(descriptor, LOCK_UN) }
        let file = directory.appendingPathComponent("commands.json")
        var state = State()
        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            if data.count <= 128_000, let decoded = try? JSONDecoder().decode(State.self, from: data), decoded.version == 1,
               decoded.pending.count <= Self.maximumCount, decoded.consumed.count <= 128,
               (0...1_000_000).contains(decoded.expiredCount), (0...1_000_000).contains(decoded.discardedCount) {
                state = decoded
            } else {
                // Do not execute malformed/future-version requests or permanently poison
                // the queue. Preserve one bounded diagnostic copy and report the discard.
                let quarantine = directory.appendingPathComponent("commands-unreadable.json")
                if FileManager.default.fileExists(atPath: quarantine.path) { try FileManager.default.removeItem(at: quarantine) }
                try FileManager.default.moveItem(at: file, to: quarantine)
                state.discardedCount = 1
            }
        }
        let result = try body(&state)
        try JSONEncoder().encode(state).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return result
    }
}

struct EarshotCatalogItem: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
}

/// Pure ordering from upstream Earshot TileCycle.kt by HellzYeahh and contributors (MIT).
/// The foreground executor additionally requires current configured device reports.
struct EarshotCycleMode: Equatable, Sendable {
    let id: Int
    let configured: Bool
    let favorite: Bool
}

enum EarshotModeCycle {
    static func canonical(_ indices: [Int]) -> [Int] { Set(indices.filter { (0...254).contains($0) }).sorted() }

    static func order(preferred: [Int], modes: [EarshotCycleMode]) -> [Int] {
        let usable = Set(modes.filter { $0.configured && (0...254).contains($0.id) }.map(\.id))
        var seen = Set<Int>()
        let selected = preferred.filter { (0...254).contains($0) && seen.insert($0).inserted && (modes.isEmpty || usable.contains($0)) }
        if !selected.isEmpty { return selected }
        let favorites = canonical(modes.filter { $0.configured && $0.favorite }.map(\.id))
        if !favorites.isEmpty { return favorites }
        let presets = [0, 1, 2].filter { modes.isEmpty || usable.contains($0) }
        return presets.isEmpty ? usable.sorted() : presets
    }

    static func next(current: Int?, order: [Int]) -> Int? {
        guard !order.isEmpty else { return nil }
        guard let current, let index = order.firstIndex(of: current) else { return order.first }
        return order[(index + 1) % order.count]
    }
}

struct EarshotIntentCatalog: Codable, Equatable, Sendable {
    var modes: [EarshotCatalogItem] = []
    var presets: [EarshotCatalogItem] = []
    var rules: [EarshotCatalogItem] = []
}

struct EarshotWidgetBattery: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let percent: Int?
    var remainingMinutes: Int? = nil
    var validPercent: Int? { percent.flatMap { (0...100).contains($0) ? $0 : nil } }
    var remainingDescription: String? {
        guard let value = remainingMinutes, value >= 0, value < 65_535 else { return nil }
        return value >= 60 ? "\(value / 60)h \(value % 60)m" : "\(value)m"
    }
}

struct EarshotWidgetSnapshot: Codable, Equatable, Sendable {
    var updatedAt: Date = .now
    let connected: Bool
    let demo: Bool
    let profileName: String
    let modeName: String
    var batteries: [EarshotWidgetBattery] = []
    // Optional additions decode older snapshots without inventing a configured cycle.
    var cycleNextModeName: String?
    var cycleStatus: String?

    func isStale(at date: Date) -> Bool { date.timeIntervalSince(updatedAt) >= 300 || updatedAt > date.addingTimeInterval(60) }
    var visibleBatteries: [EarshotWidgetBattery] { Array(batteries.prefix(4)) }
}

enum EarshotShared {
    static let group = "group.dev.earshot.ios"
    static let defaults = UserDefaults(suiteName: group)
    static let intentNotification = Notification.Name("EarshotModeIntentRequested")
    private static let snapshotKey = "earshot.widget.snapshot.v2"
    private static let catalogKey = "earshot.intent.catalog.v1"

    static func commandQueue() throws -> EarshotCommandQueue {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw EarshotIntegrationError.storageUnavailable }
        return EarshotCommandQueue(directory: root.appendingPathComponent("EarshotRequests", isDirectory: true))
    }

    static func save(snapshot: EarshotWidgetSnapshot, catalog: EarshotIntentCatalog, defaults target: UserDefaults? = defaults) {
        if let data = try? JSONEncoder().encode(snapshot) { target?.set(data, forKey: snapshotKey) }
        if let data = try? JSONEncoder().encode(catalog) { target?.set(data, forKey: catalogKey) }
    }

    static func snapshot(defaults target: UserDefaults? = defaults) -> EarshotWidgetSnapshot? {
        guard let data = target?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(EarshotWidgetSnapshot.self, from: data)
    }

    static func catalog(defaults target: UserDefaults? = defaults) -> EarshotIntentCatalog {
        guard let data = target?.data(forKey: catalogKey), let value = try? JSONDecoder().decode(EarshotIntentCatalog.self, from: data) else { return .init() }
        return value
    }

    @discardableResult
    static func request(_ payload: EarshotCommandPayload) throws -> EarshotCommandEnvelope? {
        let command = try commandQueue().enqueue(payload)
        NotificationCenter.default.post(name: intentNotification, object: nil)
        return command
    }
}
