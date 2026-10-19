import Combine
import Foundation

/// Exact Print.kt packet shapes from HellzYeahh's upstream Earshot (MIT).
/// Arguments accepted by the firmware are unknown. This is experimental, not a shell.
enum BosePrintCodec {
    static func parse(_ line: String) throws -> BmapPacket {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 265 else {
            throw BmapFailure.invalidPacket("Enter one Print command; arguments must fit 255 UTF-8 bytes.")
        }
        guard !trimmed.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) }) else {
            throw BmapFailure.invalidPacket("Print commands must be one line without control characters.")
        }
        let split = trimmed.firstIndex(of: " ")
        let verb = (split.map { String(trimmed[..<$0]) } ?? trimmed).lowercased()
        let argument = split.map { String(trimmed[trimmed.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
        let payload = Data(argument.utf8)
        guard payload.count <= 255 else { throw BmapFailure.invalidPacket("Print arguments must fit 255 UTF-8 bytes.") }
        switch verb {
        case "bind": return BmapPacket(block: 22, function: 3, operation: .setGet, payload: payload)
        case "unbind": return BmapPacket(block: 22, function: 4, operation: .setGet, payload: payload)
        case "verbosity": return BmapPacket(block: 22, function: 5, operation: .setGet, payload: payload)
        case "output":
            // Upstream treats absent/non-integer/overflowing arguments as the empty form.
            let number = Int32(argument)
            let bytes = number.map { Data([UInt8(clamping: $0)]) } ?? Data()
            return BmapPacket(block: 22, function: 2, operation: .start, payload: bytes)
        default: throw BmapFailure.invalidPacket("Unknown Print command. Use bind, unbind, verbosity or output.")
        }
    }

    static func render(_ payload: Data) -> String {
        guard var text = String(data: payload, encoding: .utf8) else { return payload.hexString }
        while text.last == "\0" { text.removeLast() }
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { scalar in
            scalar.value == 0xfffd || (scalar.value < 32 && ![9, 10, 13].contains(scalar.value)) || (127...159).contains(scalar.value)
        }) else { return payload.hexString }
        return text
    }
}

struct BosePrintEntry: Identifiable, Equatable {
    enum Kind { case command, response, notice, error }
    let id = UUID()
    let kind: Kind
    let text: String
}

/// Bounded foreground collection. A packet being queued is never treated as command success.
/// This model does not persist logs, change logging configuration automatically, or collect idle pushes.
@MainActor
final class BosePrintConsole: ObservableObject {
    @Published private(set) var entries: [BosePrintEntry] = []
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Console is idle. No Print commands have been sent."
    var transcript: String { entries.map { $0.kind == .command ? "> \($0.text)" : $0.text }.joined(separator: "\n") }

    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var expectedAddress: BmapAddress?
    private var lastResponse: ContinuousClock.Instant?
    private var responseCount = 0
    private var matchingReply = false
    private var sawError = false
    private let responseTimeout: Duration
    private let quietPeriod: Duration
    private let maximumCollection: Duration
    private let pollInterval: Duration
    private let responseLimit: Int

    init(responseTimeout: Duration = .seconds(3), quietPeriod: Duration = .milliseconds(500),
         maximumCollection: Duration = .seconds(5), pollInterval: Duration = .milliseconds(25), responseLimit: Int = 64) {
        self.responseTimeout = max(.milliseconds(1), responseTimeout)
        self.quietPeriod = max(.milliseconds(1), quietPeriod)
        self.maximumCollection = max(self.responseTimeout, maximumCollection)
        self.pollInterval = max(.milliseconds(1), pollInterval)
        self.responseLimit = min(64, max(1, responseLimit))
    }

    deinit { task?.cancel() }

    @discardableResult
    func submit(_ line: String, experimentalEnabled: Bool, isConnected: Bool,
                send: @escaping @MainActor (BmapPacket) throws -> Void) -> Bool {
        guard !isRunning else { return false }
        do {
            let packet = try BosePrintCodec.parse(line)
            guard experimentalEnabled else { throw BmapFailure.unavailable("Explicitly enable experimental Print commands first.") }
            guard isConnected else { throw BmapFailure.unavailable("Connect a verified physical headphone control channel. Demo and Simulator do not supply console replies.") }
            try BmapWriteGuard.check(packet)
            let token = UUID(); generation = token
            expectedAddress = packet.address; responseCount = 0; lastResponse = nil; matchingReply = false; sawError = false
            isRunning = true; status = "Request queued. Waiting for actual Print responses."
            append(.command, line.trimmingCharacters(in: .whitespacesAndNewlines))
            // Set collection state first so an injected/synchronous response is not lost.
            try send(packet)
            guard isRunning, generation == token else { return true }
            let clock = ContinuousClock(), started = clock.now
            task = Task { @MainActor [weak self] in
                while let self, self.isRunning, self.generation == token {
                    do { try await Task.sleep(for: self.pollInterval) } catch { return }
                    guard !Task.isCancelled, self.generation == token else { return }
                    let now = clock.now
                    if started.duration(to: now) >= self.maximumCollection {
                        self.finish("Collection time limit reached. Firmware output may continue.")
                    } else if let last = self.lastResponse, last.duration(to: now) >= self.quietPeriod {
                        let outcome = self.sawError ? "The headphones returned an error."
                            : self.matchingReply ? "Print responses collected; inspect the reported output."
                            : "Print output collected without a direct reply to this command."
                        self.finish(outcome)
                    } else if self.responseCount == 0, started.duration(to: now) >= self.responseTimeout {
                        self.finish("No Print response before timeout. The command may have been ignored.")
                    }
                }
            }
            return true
        } catch {
            stopTask()
            status = error.localizedDescription
            append(.error, "! \(status)")
            return false
        }
    }

    /// Only active block22 collection is accepted. Late/idle packets cannot grow the transcript.
    func receive(_ packet: BmapPacket) {
        guard isRunning, packet.block == 22, (2...7).contains(packet.function),
              [.status, .result, .error, .processing].contains(packet.operation) else { return }
        responseCount += 1; lastResponse = ContinuousClock().now
        if packet.address == expectedAddress, packet.operation != .processing { matchingReply = true }
        let body: String
        if let code = packet.errorCode { body = BmapFailure.device(packet.address, code).localizedDescription; sawError = true }
        else { let rendered = BosePrintCodec.render(packet.payload); body = rendered.isEmpty ? "(empty payload)" : rendered }
        append(packet.operation == .error ? .error : .response, "\(packet.address) \(packet.operation): \(body)")
        if responseCount >= responseLimit { finish("Response limit reached. Stopped collecting; firmware output may continue.") }
    }

    func cancel(reason: String = "Stopped collecting. Commands already queued or delivered are not undone.") {
        let wasRunning = isRunning
        stopTask()
        if wasRunning { status = reason; append(.notice, "! \(reason)") }
    }

    func clear() {
        stopTask(); entries = []
        status = "Transcript cleared. Commands already sent are not undone."
    }

    private func finish(_ message: String) {
        stopTask(); status = message; append(.notice, "! \(message)")
    }

    private func stopTask() {
        generation = UUID(); task?.cancel(); task = nil; isRunning = false; expectedAddress = nil
    }

    private func append(_ kind: BosePrintEntry.Kind, _ value: String) {
        entries.append(BosePrintEntry(kind: kind, text: String(value.prefix(1_024))))
        // Both entry count and aggregate characters are bounded, including unsolicited output.
        while entries.count > 100 || entries.reduce(0, { $0 + $1.text.count }) > 24_000 { entries.removeFirst() }
    }
}
