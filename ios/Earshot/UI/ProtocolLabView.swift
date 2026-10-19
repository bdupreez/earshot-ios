import SwiftUI

/// Foreground diagnostics for the AI-assisted HellzYeahh/earshot iOS port.
/// The scan is read-only. The separate Print console requires explicit experimental consent.
struct ProtocolLabView: View {
    @ObservedObject private var bluetooth: HeadphoneBluetooth
    @ObservedObject private var scanner: BmapProtocolScanner
    @ObservedObject private var console: BosePrintConsole
    @Environment(\.scenePhase) private var scenePhase
    @State private var command = "output"
    @State private var experimentalEnabled = false
    @State private var confirmExperimental = false
    @State private var validation: String?

    init(bluetooth: HeadphoneBluetooth) {
        self.bluetooth = bluetooth
        self.scanner = bluetooth.protocolScanner
        self.console = bluetooth.printConsole
    }

    var body: some View {
        List {
            Section {
                Text("Reads documented, non-sensitive BMAP settings and status. It sends GET requests only; no firmware or authentication functions are scanned.").font(.footnote)
                Button("Start read-only scan") { scanner.start { packet in try bluetooth.send(packet) } }
                    .disabled(!bluetooth.isConnected || scanner.isScanning || console.isRunning)
                if scanner.isScanning {
                    ProgressView(value: Double(scanner.completed), total: Double(BmapProtocolScanner.addresses.count))
                    Button("Cancel scan", role: .cancel) { scanner.cancel() }
                }
                if !bluetooth.isConnected { Text("Connect to a verified headphone control channel first.").font(.caption).foregroundStyle(.secondary) }
                Text("\(scanner.completed) / \(BmapProtocolScanner.addresses.count) queries completed").font(.caption)
            }
            consoleSection
            Section("Device responses") {
                ForEach(scanner.results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.address.description).font(.headline.monospaced())
                        Text(result.response).font(.caption.monospaced()).foregroundStyle(result.succeeded ? .primary : .secondary).textSelection(.enabled)
                    }
                }
            }
            if !scanner.results.isEmpty {
                Section {
                    ShareLink(item: "Earshot — AI-assisted iOS port of HellzYeahh/earshot\nRead-only protocol scan; physical device responses only\n" + scanner.results.map { "\($0.address): \($0.response)" }.joined(separator: "\n")) {
                        Label("Share redacted scan results", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("Protocol diagnostics").navigationBarTitleDisplayMode(.inline)
        .onDisappear { stopDiagnostics() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopDiagnostics() } }
        .onChange(of: bluetooth.isConnected) { _, connected in if !connected { experimentalEnabled = false; console.cancel() } }
        .onChange(of: command) { _, _ in validation = nil }
    }

    private var consoleSection: some View {
        Section("Experimental Print console") {
            Text("Sends only bind, unbind, verbosity or output commands to the firmware’s Print block. Accepted arguments are unknown and untested on iOS hardware. These commands can change firmware logging; no command runs merely by opening this page.")
                .font(.footnote)
            TextField("Print command", text: $command)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.body.monospaced()).accessibilityIdentifier("printCommand")
            Button("Validate command locally") { validateCommand() }
                .accessibilityIdentifier("validatePrintCommand")
            if let validation { Text(validation).font(.caption).accessibilityIdentifier("printValidation") }
            Toggle("Enable experimental Print commands", isOn: Binding(get: { experimentalEnabled }, set: { enabled in
                if enabled { confirmExperimental = true }
                else { experimentalEnabled = false; console.cancel() }
            }))
            .accessibilityIdentifier("enablePrintCommands")
            .alert("Enable experimental firmware commands?", isPresented: $confirmExperimental) {
                Button("Enable experimental commands", role: .destructive) { experimentalEnabled = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only the four upstream Print verbs are available. The firmware may reject arguments or continue logging after collection stops. Replies can contain private device information. No firmware update, authentication, factory-reset or arbitrary BMAP commands are offered.")
            }
            Button("Send Print command") {
                console.submit(command, experimentalEnabled: experimentalEnabled, isConnected: bluetooth.isConnected) { packet in try bluetooth.send(packet) }
            }
            .disabled(!canSendConsole).accessibilityIdentifier("sendPrintCommand")
            if console.isRunning { Button("Stop collecting", role: .cancel) { console.cancel() }.accessibilityIdentifier("cancelPrintConsole") }
            Text(console.status).font(.caption).accessibilityIdentifier("printConsoleStatus")
            if !bluetooth.isConnected {
                Text("Sending needs a verified physical headphone control channel. Demo and Simulator provide no console replies. Local validation sends nothing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Collection stops after a quiet gap, 5 seconds or 64 frames. Stopping collection does not undo queued commands or disable firmware logging. Logs stay in memory unless you explicitly share them.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(console.entries) { entry in
                Text(entry.kind == .command ? "> \(entry.text)" : entry.text)
                    .font(.caption.monospaced()).textSelection(.enabled)
                    .foregroundStyle(entry.kind == .error ? .red : .primary)
            }
            if !console.entries.isEmpty {
                Button("Clear console transcript") { console.clear() }.accessibilityIdentifier("clearPrintConsole")
                ShareLink(item: "Earshot experimental Print console — physical responses; may contain private device information\n" + console.transcript) { Label("Share console transcript", systemImage: "square.and.arrow.up") }
            }
        }
    }

    private var canSendConsole: Bool {
        bluetooth.isConnected && experimentalEnabled && !scanner.isScanning && !console.isRunning && (try? BosePrintCodec.parse(command)) != nil
    }

    private func validateCommand() {
        do {
            let packet = try BosePrintCodec.parse(command)
            validation = "Valid Print command: \(packet.address) \(packet.operation), \(packet.payload.count) payload bytes. Nothing sent."
        } catch { validation = error.localizedDescription + " Nothing sent." }
    }

    private func stopDiagnostics() {
        scanner.cancel(); console.cancel(); experimentalEnabled = false
    }
}
