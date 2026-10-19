import SwiftUI

@main struct EarshotApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .preferredColorScheme(store.saved.theme == "Dark" ? .dark : store.saved.theme == "Light" ? .light : nil)
                .tint(.earshot)
                .onOpenURL { url in store.requestFromURL(url) }
                .onChange(of: phase, initial: true) { _, phase in
                    store.appIsActive = phase == .active
                    if phase == .active {
                        // Permission may have changed in Settings. Reconcile the
                        // real notification plan even when saved rules are equal.
                        store.lastReminderRules = nil
                        store.checkSchedules()
                        store.processSharedRequests()
                    }
                    // Inactivity must stop SSID observation immediately. Waiting
                    // for an unrelated published change could retain a stale join.
                    store.syncPlatformIntegrations()
                }
                .onReceive(NotificationCenter.default.publisher(for: EarshotShared.intentNotification).receive(on: RunLoop.main)) { _ in
                    store.processSharedRequests()
                }
        }
    }
}
