import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var switchingHeadphones = false
    var body: some View {
        Page {
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text("MAKE ROOM FOR SOUND").font(.caption2.weight(.bold)).tracking(2).foregroundStyle(.secondary); Text("Your listening space").font(.title2.weight(.bold)) }
                Spacer()
                NavigationLink { ConnectionView() } label: { Image(systemName: "dot.radiowaves.left.and.right").font(.title3).padding(12).background(.quaternary, in: Circle()) }.accessibilityLabel("Headphone connection")
            }
            Panel {
                HStack {
                    Label(store.saved.demo ? "Demo device" : store.bluetooth.isConnected ? "Connected" : "Not connected", systemImage: store.saved.demo ? "sparkles" : "circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.earshot)
                    Spacer()
                    if let battery = store.battery { Label("\(battery)%", systemImage: "battery.75percent").font(.subheadline.weight(.medium)).monospacedDigit() }
                }
                HeadphoneArtwork(earbuds: store.profile.earbuds)
                Button { switchingHeadphones = true } label: {
                    HStack(spacing: 8) {
                        Text(store.displayDeviceName).font(.title2.weight(.bold))
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("headphoneSwitcher")
                    .accessibilityHint("Choose another headphone or demo profile.")
                Text(store.saved.demo ? "A virtual device. Changes stay in the demo." : store.bluetooth.status).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                if let time = store.remainingTimeDescription { Text("Reported listening time: \(time)\(store.saved.demo ? " · simulated" : "")").font(.caption).foregroundStyle(.secondary) }
                if !store.batteries.isEmpty { HStack { ForEach(store.batteries.keys.sorted(), id: \.self) { key in VStack(spacing: 4) { Text("\(store.batteries[key]!)%").font(.headline); Text(key).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) } } }
                if !store.connected { NavigationLink("Find headphones") { ConnectionView() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity) }
            }
            if store.deviceStatus.operationMode == .firmwareUpdateOnly {
                InfoNote(text: "The headphones report firmware-update-only mode. Normal controls may be unavailable. This port does not perform firmware updates.")
            }
            if store.connected && !store.profile.unsupported {
                if !store.saved.modes.filter({ $0.configured }).isEmpty {
                    Panel(title: "Listening mode") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(store.saved.modes.filter { $0.configured }) { mode in
                                    Button { store.selectMode(mode.id) } label: {
                                        VStack(spacing: 10) { Image(systemName: mode.id == 0 ? "moon" : mode.id == 1 ? "sun.max" : "waveform").font(.title3); Text(mode.name).font(.subheadline.weight(.medium)) }
                                            .frame(minWidth: 80).padding(.vertical, 18).padding(.horizontal, 12)
                                            .foregroundStyle(store.saved.currentMode == mode.id ? .white : .primary)
                                            .background(store.saved.currentMode == mode.id ? Color.earshot : Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                                    }.buttonStyle(.plain).accessibilityIdentifier("mode.\(mode.id)").accessibilityValue(store.saved.currentMode == mode.id ? "Selected" : "Not selected").accessibilityAddTraits(store.saved.currentMode == mode.id ? .isSelected : [])
                                }
                            }
                        }
                        Text("Current mode: \(store.modeName)").font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("currentMode")
                    }
                }
                if store.profile.noise || store.profile.spatial {
                    Panel(title: "Let the world in. Or out.") {
                        NoiseControls(noise: Binding(get: { store.saved.noise }, set: { store.changeNoise($0) }), profile: store.noiseProfile(), ancToggle: store.canToggleANC())
                            // A drag belongs to one device and listening mode. Discard its
                            // uncommitted value if either changes before finger-up.
                            .id("\(store.saved.demo)-\(store.profile.id)-\(store.saved.currentMode)-\(store.bluetooth.connectedDeviceID?.uuidString ?? "none")")
                            .disabled(!store.canControlNoise)
                        if !store.canControlNoise { Text("Noise control becomes available when the headphones report support. Older models may need a custom mode selected.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if store.profile.crusher { InfoNote(text: "Crusher is a UI demonstration only. Its encrypted Bragi transport has not been ported or tested on iOS.") }
            }
            Panel {
                HStack { Image(systemName: "music.note").font(.title2).foregroundStyle(Color.earshot); VStack(alignment: .leading, spacing: 4) { Text("Make it sound like you").font(.headline); Text("Explore local audio with Pro EQ").font(.subheadline).foregroundStyle(.secondary) }; Spacer() }
            }
            Text("Built on the original Earshot · AI-assisted iOS port").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 10)
        }.navigationTitle("earshot").navigationBarTitleDisplayMode(.inline)
            .toolbar { if store.saved.demo { Text("DEMO").font(.caption2.weight(.bold)).foregroundStyle(Color.earshot) } }
            .refreshable { store.refresh() }
            .sheet(isPresented: $switchingHeadphones) { HomeHeadphoneSwitcher().environmentObject(store) }
    }
}

/// AI-assisted native counterpart of HellzYeahh/earshot's Home quick switcher (MIT).
/// Real devices retain the existing verified discovery/connection flow; demo profiles stay local.
private struct HomeHeadphoneSwitcher: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.saved.demo { demoProfiles }
                else { ConnectionView() }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var demoProfiles: some View {
        List {
            Section {
                ForEach(DeviceProfile.all) { profile in
                    Button {
                        if store.saved.profileID != profile.id { store.selectProfile(profile.id) }
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: profile.earbuds ? "earbuds" : "headphones").foregroundStyle(Color.earshot)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.saved.demoDeviceNames[profile.id] ?? profile.name).foregroundStyle(Color.primary)
                                Text("Simulated demo profile").font(.caption).foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            if store.saved.profileID == profile.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.earshot).accessibilityHidden(true)
                            }
                        }.frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("switchDemo.\(profile.id)")
                    .accessibilityValue(store.saved.profileID == profile.id ? "Selected" : "Not selected")
                }
            } header: { Text("Demo profiles") } footer: {
                Text("These are virtual headphones. Switching profiles changes only the demo and never starts Bluetooth discovery.")
            }
        }
        .navigationTitle("Switch headphones").navigationBarTitleDisplayMode(.inline)
    }
}
