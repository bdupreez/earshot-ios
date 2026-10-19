// AI-assisted iOS port attempt of HellzYeahh/earshot. Original contributors retain credit.
// Upstream: https://github.com/HellzYeahh/earshot — MIT; see THIRD_PARTY_NOTICES.md.
// Calendar reminders: https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger
// Foreground actions: https://developer.apple.com/documentation/usernotifications/unnotificationaction
import Combine
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    nonisolated static let maximumScheduleRequests = 56
    nonisolated static let schedulePrefix = "earshot.rule."
    nonisolated static let scheduleCategory = "earshot.listening-rule"
    nonisolated static let runRuleAction = "earshot.run-rule"

    @Published private(set) var granted = false
    @Published private(set) var status = "Notifications have not been requested."
    @Published fileprivate(set) var scheduleStatus = "Schedule reminders have not been synchronized."
    private var alertedDevices: Set<String> = []
    private var desiredRules: [AutomationRule] = []
    private var scheduleRevision: UInt64 = 0
    private var scheduleTask: Task<Void, Never>?

    init() {
        let delegate = NotificationPresentationDelegate.shared
        delegate.manager = self
        UNUserNotificationCenter.current().delegate = delegate
        Task { await Self.registerCategory(in: .current()) }
    }

    func requestPermission() async {
        do {
            granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            status = granted ? "Notifications are allowed." : "Notifications are off. You can enable them in Settings."
        } catch { status = error.localizedDescription }
        syncRuleReminders(desiredRules)
    }

    /// Call only for real battery reports; demo devices should never produce system alerts.
    func reportBattery(deviceID: String, name: String, percent: Int, threshold: Int, isCharging: Bool) async {
        guard (0...100).contains(percent), (1...100).contains(threshold) else { return }
        if isCharging || percent > threshold + 5 { alertedDevices.remove(deviceID); return }
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

    /// Pure planning API: do not truncate an oversized plan. The caller can reject
    /// it before saving; synchronization also refuses it rather than silently losing reminders.
    nonisolated static func scheduleRequests(for rules: [AutomationRule]) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        var seen: Set<String> = []
        for rule in rules {
            guard rule.enabled, rule.notifyAtSchedule == true, rule.trigger == "Schedule (app open)",
                  rule.configurationError == nil, !rule.id.isEmpty, rule.id.utf8.count <= 256,
                  seen.insert(rule.id).inserted else { continue }
            let days: [Int?] = rule.effectiveWeekdays == Set(1...7) ? [nil] : rule.effectiveWeekdays.sorted().map(Optional.some)
            for day in days {
                var components = DateComponents()
                components.hour = rule.hour
                components.minute = rule.minute
                components.second = 0
                // Leave date, UTC offset and zone unset: this is a local wall-clock
                // reminder. The system calendar handles travel and DST, not a 24h interval.
                if let day { components.weekday = day % 7 + 1 }
                let content = UNMutableNotificationContent()
                content.title = "Listening reminder"
                content.body = "\(rule.name): open Earshot to run this rule."
                content.sound = .default
                content.categoryIdentifier = scheduleCategory
                content.userInfo = ["earshotRuleID": rule.id]
                let suffix = day.map { "weekday-\($0)" } ?? "daily"
                requests.append(UNNotificationRequest(identifier: "\(schedulePrefix)\(rule.id).\(suffix)", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
            }
        }
        return requests
    }

    nonisolated static func reminderCategory() -> UNNotificationCategory {
        let action = UNNotificationAction(identifier: runRuleAction, title: "Run rule", options: [.foreground, .authenticationRequired])
        return UNNotificationCategory(identifier: scheduleCategory, actions: [action], intentIdentifiers: [])
    }

    nonisolated static func reminderCommand(identifier: String, category: String, ruleID: String?, action: String) -> EarshotCommandPayload? {
        guard identifier.hasPrefix(schedulePrefix), category == scheduleCategory,
              action == UNNotificationDefaultActionIdentifier || action == runRuleAction,
              let id = ruleID, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.utf8.count <= 256 else { return nil }
        return .runRule(id: id)
    }

    /// Coalesce UI edits and serialize all center mutations. New revisions supersede
    /// an in-flight plan; the latest pass cleans any obsolete requests from that pass.
    /// This method queries authorization and never displays a permission prompt.
    func syncRuleReminders(_ rules: [AutomationRule]) {
        desiredRules = rules
        scheduleRevision &+= 1
        guard scheduleTask == nil else { return }
        scheduleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self else { return }
            while true {
                let revision = self.scheduleRevision
                let rules = self.desiredRules
                await self.applyReminderPlan(rules, revision: revision)
                if self.scheduleRevision == revision { self.scheduleTask = nil; return }
            }
        }
    }

    private static func registerCategory(in center: UNUserNotificationCenter) async {
        var categories = await center.notificationCategories()
        categories = Set(categories.filter { $0.identifier != scheduleCategory })
        categories.insert(reminderCategory())
        center.setNotificationCategories(categories)
    }

    private func applyReminderPlan(_ rules: [AutomationRule], revision: UInt64) async {
        let requests = Self.scheduleRequests(for: rules)
        guard requests.count <= Self.maximumScheduleRequests else {
            scheduleStatus = "Too many reminder times (\(requests.count)). Limit: \(Self.maximumScheduleRequests). Existing reminders were kept."
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        guard revision == scheduleRevision else { return }
        let managed = pending.filter { $0.identifier.hasPrefix(Self.schedulePrefix) }
        granted = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        guard granted else {
            center.removePendingNotificationRequests(withIdentifiers: managed.map(\.identifier))
            scheduleStatus = requests.isEmpty ? "No schedule reminders are enabled." : "Allow notifications to receive schedule reminders."
            return
        }
        await Self.registerCategory(in: center)
        guard revision == scheduleRevision else { return }
        let wanted = Set(requests.map(\.identifier))
        center.removePendingNotificationRequests(withIdentifiers: managed.filter { !wanted.contains($0.identifier) }.map(\.identifier))
        do {
            for request in requests {
                guard revision == scheduleRevision else { return }
                try await center.add(request)
            }
            guard revision == scheduleRevision else { return }
            scheduleStatus = requests.isEmpty ? "No schedule reminders are enabled." : "\(requests.count) reminder time\(requests.count == 1 ? "" : "s") scheduled. Tap a reminder to open Earshot and request the rule."
        } catch {
            // Do not claim a whole plan succeeded after a partial add failure.
            scheduleStatus = "Some reminders could not be scheduled; previous times may remain. \(error.localizedDescription). Reopen Earshot to retry."
        }
    }
}

@MainActor
private final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresentationDelegate()
    weak var manager: NotificationManager?

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.identifier.hasPrefix(NotificationManager.schedulePrefix), notification.request.content.categoryIdentifier == NotificationManager.scheduleCategory {
            return [] // The foreground rule timer owns execution; avoid a duplicate reminder banner.
        }
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        guard let command = NotificationManager.reminderCommand(identifier: request.identifier, category: request.content.categoryIdentifier, ruleID: request.content.userInfo["earshotRuleID"] as? String, action: response.actionIdentifier) else { return }
        // The action is foreground/authenticated. Even during launch this only queues
        // an expiring request; the app validates and executes it after becoming active.
        do { try EarshotShared.request(command) }
        catch { await MainActor.run { self.manager?.scheduleStatus = "Could not request this rule: \(error.localizedDescription)" } }
    }
}
