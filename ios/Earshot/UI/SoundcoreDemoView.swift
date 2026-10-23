import SwiftUI

// Native simulation UI for the AI-assisted port of HellzYeahh/earshot (MIT).
// This view owns no Bluetooth manager and cannot send a physical command.
struct SoundcoreDemoView: View {
    let model: SoundcoreModel
    @State private var state: SoundcoreState?
    @State private var result = ""
    @State private var packetPreview = "No request has been simulated."
    @State private var diagnosticsExpanded = false

    init(model: SoundcoreModel) {
        self.model = model
        _state = State(initialValue: try? SoundcoreDemo.state(for: model))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Panel {
                Label("SIMULATED · no headphone connection", systemImage: "testtube.2")
                    .font(.headline).foregroundStyle(Color.earshot).accessibilityIdentifier("soundcoreSimulationBanner")
                Text(model.displayName).font(.title3.bold())
                Text("These controls change synthetic state using the documented model layout. No radio command is sent and no device setting changes.")
            }
            if let state { stateSections(state) }
            else { Panel { Text("The synthetic model fixture could not be read.").foregroundStyle(.secondary) } }
            Panel(title: "Physical transport") {
                Text(SoundcoreModel.transportLimitation).font(.footnote)
                    .accessibilityIdentifier("soundcoreTransportLimitation")
                Text("The vendor service UUIDs identify Classic Bluetooth services. They are not verified BLE services or characteristic write targets.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Panel(title: "Original work") {
                Text("Original Earshot: HellzYeahh and contributors, MIT. This native screen is an experimental AI-assisted port. Soundcore protocol research includes soundcorebridge (MIT) and restated OpenSCQ30/Gadgetbridge facts; their GPL/AGPL code is not copied.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("Original Earshot", destination: URL(string: "https://github.com/HellzYeahh/earshot")!)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("soundcoreDemo.\(model.rawValue)")
        .onChange(of: model) { _, _ in resetSimulation() }
    }

    @ViewBuilder private func stateSections(_ state: SoundcoreState) -> some View {
        Panel(title: "Synthetic state") {
            batteryRow("Battery", state.headlinePercent)
            if model.earbuds {
                batteryRow("Left", state.leftPercent)
                batteryRow("Right", state.rightPercent)
            }
            if let percent = state.casePercent { batteryRow("Case", percent) }
            LabeledContent("Firmware fixture", value: state.firmware ?? "Not reported")
            if let firmware = state.caseFirmware { LabeledContent("Case firmware fixture", value: firmware) }
            if let ambient = state.ambient { LabeledContent("Listening mode", value: ambient.title).accessibilityIdentifier("soundcoreReportedMode") }
            LabeledContent("Body size", value: "\(state.bodySize) bytes")
            Text(state.writable ? "Documented layout available for simulation." : state.note ?? "This layout is read-only.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if !state.controls.isEmpty {
            Panel(title: "Model controls · simulation only") {
                ForEach(state.controls) { control in controlRow(control) }
            }
        } else {
            Panel(title: "Read-only model") {
                Text("Upstream has not established safe setting writes for this model. The available battery, firmware and mode facts can be explored here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        if !result.isEmpty {
            Panel(title: "Simulation result") { Text(result).accessibilityIdentifier("soundcoreSimulationResult") }
        }
        Panel(title: "Protocol lab · offline") {
            DisclosureGroup("Documented read requests", isExpanded: $diagnosticsExpanded) {
                ForEach(SoundcoreWriteGuard.documentedReads(for: model), id: \.command) { packet in
                    Button(readTitle(packet.command)) { previewRead(packet) }
                        .accessibilityIdentifier("soundcoreRead.\(packet.command)")
                }
                Text("Only model-allowlisted empty-body reads are available. This lab encodes requests locally. It does not scan a device or guess unknown commands.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("Last simulated request · complete frame").font(.caption).foregroundStyle(.secondary)
            Text(packetPreview).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                .accessibilityIdentifier("soundcorePacketPreview")
            Button("Reset this simulation") { resetSimulation() }.accessibilityIdentifier("soundcoreResetSimulation")
        }
    }

    private func batteryRow(_ label: String, _ percent: Int?) -> some View {
        LabeledContent(label, value: percent.map { "\($0)% · simulated" } ?? "Not reported")
    }
    private func controlRow(_ control: SoundcoreControlDefinition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(control.title).font(.subheadline.weight(.medium))
            Picker(control.title, selection: Binding(get: { control.value ?? -1 }, set: { applyControl(control.id, value: $0) })) {
                if control.value == nil { Text("Not reported").tag(-1) }
                ForEach(control.options.indices, id: \.self) { index in Text(control.options[index]).tag(index) }
            }
            .labelsHidden().accessibilityLabel(control.title)
            .accessibilityValue(control.value.flatMap { control.options.indices.contains($0) ? control.options[$0] : nil } ?? "Not reported")
            .disabled(!control.enabled)
            .accessibilityIdentifier("soundcoreControl.\(control.id)")
            if let note = control.note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func applyControl(_ id: String, value: Int) {
        guard let before = state else { return }
        do {
            let packet = try SoundcoreWrites.control(state: before, id: id, value: value)
            let encoded = try packet.encode()
            var buffer = SoundcoreFrameBuffer()
            guard let decoded = buffer.feed(encoded).first, decoded == packet else { throw SoundcoreFailure.invalid("The simulated request failed framing verification.") }
            let after = try SoundcoreDemo.applying(decoded, to: before)
            guard SoundcoreWrites.confirms(before: before, after: after, packet: decoded) else { throw SoundcoreFailure.invalid("The simulated readback did not confirm the setting.") }
            state = after
            packetPreview = encoded.hexString
            result = "Simulated setting confirmed by reparsing the synthetic state. No physical command was sent."
        } catch { result = error.localizedDescription }
    }
    private func previewRead(_ packet: SoundcorePacket) {
        do {
            try SoundcoreWriteGuard.check(model: model, packet: packet)
            packetPreview = try packet.encode().hexString
            if packet.command == SoundcoreCommands.requestState, let state {
                let response = try SoundcorePacket(command: packet.command, body: state.raw, inbound: true).encode()
                var buffer = SoundcoreFrameBuffer()
                guard let parsed = buffer.feed(response).first, parsed.inbound,
                      SoundcoreStateReader.parse(model: model, body: parsed.body) != nil else { throw SoundcoreFailure.invalid("The synthetic state reply could not be decoded.") }
                result = "Simulated state request and inbound frame decoded locally. No device was contacted."
            } else { result = "The documented request was encoded locally. No captured reply is simulated for this read." }
        } catch { result = error.localizedDescription }
    }
    private func resetSimulation() {
        do { state = try SoundcoreDemo.state(for: model); result = "Simulation reset. No device was contacted."; packetPreview = "No request has been simulated." }
        catch { state = nil; result = error.localizedDescription }
    }
    private func readTitle(_ command: UInt16) -> String {
        switch command {
        case SoundcoreCommands.requestState: return "Encode state read"
        case SoundcoreCommands.requestInfo: return "Encode device info read"
        case SoundcoreCommands.sessionInfo: return "Encode session-info read"
        case SoundcoreCommands.alarms: return "Encode alarms read"
        case SoundcoreCommands.sleepSettings: return "Encode sleep-settings read"
        default: return "Documented read"
        }
    }
}
