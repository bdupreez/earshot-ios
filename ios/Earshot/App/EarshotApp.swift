import SwiftUI

@main struct EarshotApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(store.saved.theme == "Dark" ? .dark : store.saved.theme == "Light" ? .light : nil)
                .tint(.earshot)
                .onOpenURL { url in
                    guard url.scheme == "earshot", url.host == "mode", let index = Int(url.lastPathComponent) else { return }
                    store.selectMode(index)
                }
                .onChange(of: phase) { _, phase in
                    if phase == .active {
                        store.checkSchedules()
                        if let index = EarshotShared.defaults?.object(forKey: "pendingMode") as? Int {
                            EarshotShared.defaults?.removeObject(forKey: "pendingMode")
                            if store.connected { store.selectMode(index) } else { store.message = "Connect headphones or start demo mode to use this shortcut." }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: EarshotShared.intentNotification).receive(on: RunLoop.main)) { _ in
                    if let index = EarshotShared.defaults?.object(forKey: "pendingMode") as? Int {
                        EarshotShared.defaults?.removeObject(forKey: "pendingMode")
                        if store.connected { store.selectMode(index) } else { store.message = "Connect headphones or start demo mode to use this shortcut." }
                    }
                }
        }
    }
}
