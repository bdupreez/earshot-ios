import SwiftUI
import WidgetKit

struct RootView: View {
    @EnvironmentObject var store: AppStore
    let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "house") }
            NavigationStack { SoundView() }.tabItem { Label("Sound", systemImage: "slider.horizontal.3") }
            NavigationStack { ModesView() }.tabItem { Label("Modes", systemImage: "waveform") }
            NavigationStack { ToolsView() }.tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: $store.welcome) { WelcomeView().environmentObject(store) }
        .alert("Earshot", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("OK") { store.message = nil } } message: { Text(store.message ?? "") }
        .onReceive(timer) { _ in store.checkSchedules() }
        .onReceive(store.$saved.debounce(for: .milliseconds(200), scheduler: RunLoop.main)) { _ in updateWidget() }
        .onChange(of: store.battery) { _, _ in updateWidget() }
    }
    private func updateWidget() {
        let shared = EarshotShared.defaults
        shared?.set(store.connected ? store.modeName : "Disconnected", forKey: "widgetMode")
        shared?.set(store.battery, forKey: "widgetBattery")
        shared?.set(store.saved.demo, forKey: "widgetDemo")
        shared?.set(Date.now, forKey: "widgetUpdated")
        WidgetCenter.shared.reloadTimelines(ofKind: "EarshotListeningWidget")
    }
}

struct WelcomeView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { Image(systemName: "waveform.circle.fill").font(.largeTitle); Text("earshot").font(.system(size: 30, weight: .bold, design: .rounded)) }.foregroundStyle(Color.earshot)
                HeadphoneArtwork().frame(maxWidth: .infinity).padding(.vertical, 10)
                Text("Your sound.\nA little closer.").font(.system(size: 42, weight: .bold, design: .rounded)).tracking(-1.5)
                Text("A native iOS companion for your headphones. Listening modes, thoughtful sound tuning, and useful little tools.").font(.title3).foregroundStyle(.secondary)
                InfoNote(text: "An AI-assisted port attempt of the original Earshot by HellzYeahh and contributors. Independent, open source, and still experimental.")
                VStack(spacing: 12) {
                    Button { store.finishWelcome(demo: false) } label: { Label("Find my headphones", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).accessibilityIdentifier("connectHeadphones")
                    Button { store.finishWelcome(demo: true) } label: { Text("Try demo mode").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.bordered).accessibilityIdentifier("tryDemo")
                }
                Text("No account. No analytics. Your settings stay on this device.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }.padding(28).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.background(Color(uiColor: .systemGroupedBackground)).interactiveDismissDisabled()
    }
}
