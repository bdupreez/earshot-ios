import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
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
                Text(store.saved.demo ? store.profile.name : store.liveDeviceName).font(.title2.weight(.bold)).frame(maxWidth: .infinity)
                Text(store.saved.demo ? "A virtual device. Changes stay in the demo." : store.bluetooth.status).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                if !store.batteries.isEmpty { HStack { ForEach(store.batteries.keys.sorted(), id: \.self) { key in VStack(spacing: 4) { Text("\(store.batteries[key]!)%").font(.headline); Text(key).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) } } }
                if !store.connected { NavigationLink("Find headphones") { ConnectionView() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity) }
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
                        NoiseControls(noise: Binding(get: { store.saved.noise }, set: { store.changeNoise($0) }), profile: store.profile)
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
    }
}
