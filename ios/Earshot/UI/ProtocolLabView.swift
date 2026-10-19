import SwiftUI

/// Foreground-only, read-only diagnostics for the AI-assisted HellzYeahh/earshot iOS port.
struct ProtocolLabView: View {
    @ObservedObject private var bluetooth: HeadphoneBluetooth
    @ObservedObject private var scanner: BmapProtocolScanner
    @Environment(\.scenePhase) private var scenePhase

    init(bluetooth: HeadphoneBluetooth) {
        self.bluetooth = bluetooth
        self.scanner = bluetooth.protocolScanner
    }

    var body: some View {
        List {
            Section {
                Text("Reads documented, non-sensitive BMAP settings and status. It sends GET requests only; no firmware or authentication functions are scanned.").font(.footnote)
                Button("Start read-only scan") { scanner.start { packet in try bluetooth.send(packet) } }
                    .disabled(!bluetooth.isConnected || scanner.isScanning)
                if scanner.isScanning {
                    ProgressView(value: Double(scanner.completed), total: Double(BmapProtocolScanner.addresses.count))
                    Button("Cancel scan", role: .cancel) { scanner.cancel() }
                }
                if !bluetooth.isConnected { Text("Connect to a verified headphone control channel first.").font(.caption).foregroundStyle(.secondary) }
                Text("\(scanner.completed) / \(BmapProtocolScanner.addresses.count) queries completed").font(.caption)
            }
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
        .navigationTitle("Protocol scan").navigationBarTitleDisplayMode(.inline)
        .onDisappear { scanner.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { scanner.cancel() } }
    }
}
