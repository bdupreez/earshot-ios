// AI-assisted iOS port attempt of https://github.com/HellzYeahh/earshot (MIT).
import AppIntents
import Foundation

enum EarshotShared {
    static let group = "group.dev.earshot.ios"
    static let defaults = UserDefaults(suiteName: group)
    static let intentNotification = Notification.Name("EarshotModeIntentRequested")
}

struct QuietModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Use Quiet mode in Earshot"
    static var description = IntentDescription("Open Earshot and request Quiet mode on the current connected or demo device.")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        EarshotShared.defaults?.set(0, forKey: "pendingMode")
        NotificationCenter.default.post(name: EarshotShared.intentNotification, object: nil)
        return .result()
    }
}

struct AwareModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Use Aware mode in Earshot"
    static var description = IntentDescription("Open Earshot and request Aware mode on the current connected or demo device.")
    static var openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        EarshotShared.defaults?.set(1, forKey: "pendingMode")
        NotificationCenter.default.post(name: EarshotShared.intentNotification, object: nil)
        return .result()
    }
}

struct EarshotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: QuietModeIntent(), phrases: ["Use Quiet mode in \(.applicationName)"], shortTitle: "Quiet mode", systemImageName: "moon")
        AppShortcut(intent: AwareModeIntent(), phrases: ["Use Aware mode in \(.applicationName)"], shortTitle: "Aware mode", systemImageName: "sun.max")
    }
}
