// AI-assisted iOS port attempt of HellzYeahh/earshot. Original Earshot contributors retain credit.
// Upstream: https://github.com/HellzYeahh/earshot — MIT; see THIRD_PARTY_NOTICES.md.
import Combine
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    @Published private(set) var granted = false
    @Published private(set) var status = "Notifications have not been requested."
    private var alertedDevices: Set<String> = []

    init() {
        // Keep one delegate alive even when a preferences screen creates its own helper.
        UNUserNotificationCenter.current().delegate = NotificationPresentationDelegate.shared
    }

    func requestPermission() async {
        do {
            granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            status = granted ? "Low battery notifications are allowed." : "Notifications are off. You can enable them in Settings."
        } catch { status = error.localizedDescription }
    }

    /// Call only for real battery reports; demo devices should never produce system alerts.
    func reportBattery(deviceID: String, name: String, percent: Int, threshold: Int, isCharging: Bool) async {
        guard (0...100).contains(percent), (1...100).contains(threshold) else { return }
        if isCharging || percent > threshold + 5 {
            alertedDevices.remove(deviceID)
            return
        }
        guard percent <= threshold, !alertedDevices.contains(deviceID) else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        granted = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        guard granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "Headphone battery is low"
        content.body = "\(name) has \(percent)% battery remaining."
        content.sound = .default
        do {
            let request = UNNotificationRequest(identifier: "earshot.low-battery.\(deviceID)", content: content, trigger: nil)
            try await UNUserNotificationCenter.current().add(request)
            alertedDevices.insert(deviceID)
        } catch { status = "Could not show battery alert: \(error.localizedDescription)" }
    }
}

@MainActor
private final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresentationDelegate()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
