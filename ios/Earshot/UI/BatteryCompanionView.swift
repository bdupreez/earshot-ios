import SwiftUI

/// Explicit read-only tool for the AI-assisted native port of HellzYeahh/earshot (MIT).
struct BatteryCompanionView: View {
    @StateObject private var companion = BatteryCompanion()
    @State private var includeNearbyApple = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section("Read-only Bluetooth battery") {
                Text("Discover peripherals that advertise the standard Battery Service, then select the exact source to read. This tool never sends headphone controls or changes Earshot's connected device.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Include nearby Apple adverts", isOn: $includeNearbyApple)
                    .accessibilityIdentifier("batteryNearbyApple")
                    .disabled(companion.isScanning || companion.isReading)
                Text("Public iOS may not provide AirPods/Beats telemetry. Nearby adverts have unverified identities and are never assigned to your current audio route.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(companion.isScanning ? "Stop discovery" : "Discover battery sources") {
                    if companion.isScanning { companion.cancelByUser() }
                    else { companion.discover(includeNearbyApple: includeNearbyApple) }
                }
                .accessibilityIdentifier("discoverBatterySources")
                .disabled(companion.isReading)
                if companion.isReading {
                    Button("Cancel battery read", role: .cancel) { companion.cancelByUser() }
                }
                Text(companion.status).accessibilityIdentifier("batteryCompanionStatus")
            }
            if let reading = companion.reading {
                Section("Selected source reading") {
                    LabeledContent(reading.sourceName, value: "\(reading.percent)%")
                    Text(reading.receivedAt, style: .time).font(.caption)
                    Text("Last reported by the source you selected. This does not verify a headphone control connection.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Discovered standard battery sources") {
                if companion.devices.isEmpty { Text("No source selected or discovered yet.").foregroundStyle(.secondary) }
                ForEach(companion.devices) { device in
                    Button { companion.read(device) } label: {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("Standard Battery Service · \(device.rssi) dBm · Tap to read")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(companion.isReading)
                }
            }
            if !companion.nearbyApple.isEmpty {
                Section("Nearby Apple adverts · identity unverified") {
                    ForEach(companion.nearbyApple) { observation in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(observation.advert.modelName)
                            Text(batteryDescription(observation.advert)).font(.caption)
                            Text("Unverified nearby advert · \(observation.rssi) dBm")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(observation.receivedAt, style: .time).font(.caption)
                        }
                    }
                    Text("These may belong to someone else. Discovery never establishes ownership, pairs a device or controls it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Battery companion")
        .onDisappear { companion.stopForInactivity() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { companion.stopForInactivity() } }
    }

    private func batteryDescription(_ advert: AppleContinuityAdvert) -> String {
        func value(_ percent: Int?, charging: Bool) -> String {
            (percent.map { "\($0)%" } ?? "Unknown") + (charging ? " charging" : "")
        }
        if advert.isHeadphones { return "Headphones: " + value(advert.headlinePercent, charging: advert.leftCharging || advert.rightCharging) }
        return "Left: " + value(advert.leftPercent, charging: advert.leftCharging) +
            " · Right: " + value(advert.rightPercent, charging: advert.rightCharging) +
            " · Case: " + value(advert.casePercent, charging: advert.caseCharging)
    }
}
