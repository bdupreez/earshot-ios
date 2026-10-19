// AI-assisted iOS port attempt of HellzYeahh/earshot (MIT). Original contributors retain credit.
import XCTest
import UserNotifications
@testable import Earshot

final class ScheduleReminderTests: XCTestCase {
    private func rule(_ id: String = "commute", days: Set<Int>? = nil) -> AutomationRule {
        var value = AutomationRule(name: "Morning commute")
        value.id = id
        value.trigger = "Schedule (app open)"
        value.hour = 9
        value.minute = 30
        value.weekdays = days
        value.notifyAtSchedule = true
        return value
    }

    func testDailyPlanUsesOneRepeatingCalendarTriggerAndForegroundContent() throws {
        let request = try XCTUnwrap(NotificationManager.scheduleRequests(for: [rule()]).first)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 9)
        XCTAssertEqual(trigger.dateComponents.minute, 30)
        XCTAssertEqual(trigger.dateComponents.second, 0)
        XCTAssertNil(trigger.dateComponents.weekday)
        XCTAssertNil(trigger.dateComponents.day)
        XCTAssertNil(trigger.dateComponents.timeZone)
        XCTAssertNotNil(trigger.nextTriggerDate())
        XCTAssertEqual(request.identifier, "earshot.rule.commute.daily")
        XCTAssertEqual(request.content.categoryIdentifier, NotificationManager.scheduleCategory)
        XCTAssertEqual(request.content.userInfo["earshotRuleID"] as? String, "commute")
        XCTAssertTrue(request.content.body.contains("open Earshot"))
    }

    func testISOWeekdaysMapToNativeSundayBasedWeekdays() throws {
        let requests = NotificationManager.scheduleRequests(for: [rule(days: [1, 3, 7])])
        XCTAssertEqual(requests.map(\.identifier), ["earshot.rule.commute.weekday-1", "earshot.rule.commute.weekday-3", "earshot.rule.commute.weekday-7"])
        let triggers = try requests.map { try XCTUnwrap($0.trigger as? UNCalendarNotificationTrigger) }
        XCTAssertEqual(triggers.map { $0.dateComponents.weekday }, [2, 4, 1])
        XCTAssertTrue(triggers.allSatisfy(\.repeats))
        XCTAssertTrue(triggers.allSatisfy { $0.nextTriggerDate() != nil })
    }

    func testDisabledInvalidUnoptedAndNonScheduleRulesCreateNoRequests() {
        var disabled = rule("disabled"); disabled.enabled = false
        var unopted = rule("off"); unopted.notifyAtSchedule = false
        var legacy = rule("legacy"); legacy.notifyAtSchedule = nil
        var manual = rule("manual"); manual.trigger = "Manual"
        var connection = rule("connection"); connection.trigger = "On connection"
        var invalidTime = rule("bad-time"); invalidTime.hour = 24
        var invalidName = rule("bad-name"); invalidName.name = " "
        let values = [disabled, unopted, legacy, manual, connection, invalidTime, invalidName, rule("bad-days", days: [0]), rule("no-days", days: [])]
        XCTAssertTrue(NotificationManager.scheduleRequests(for: values).isEmpty)
    }

    func testIdentifiersSurviveRenamesAndDuplicateIDsCannotMultiplyReminders() {
        let original = rule(days: [1, 5])
        var renamed = original; renamed.name = "Renamed commute"
        let before = NotificationManager.scheduleRequests(for: [original])
        let after = NotificationManager.scheduleRequests(for: [renamed])
        XCTAssertEqual(before.map(\.identifier), after.map(\.identifier))
        XCTAssertNotEqual(before.first?.content.body, after.first?.content.body)
        XCTAssertEqual(NotificationManager.scheduleRequests(for: [original, renamed]).count, 2)
    }

    func testPlanReportsCapacityOverflowRatherThanTruncating() {
        XCTAssertEqual(NotificationManager.maximumScheduleRequests, 56)
        let atCapacity = (0..<56).map { rule("rule-\($0)") }
        XCTAssertEqual(NotificationManager.scheduleRequests(for: atCapacity).count, 56)
        let oversized = NotificationManager.scheduleRequests(for: atCapacity + [rule("extra")])
        XCTAssertEqual(oversized.count, 57)
        XCTAssertGreaterThan(oversized.count, NotificationManager.maximumScheduleRequests)
    }

    func testNativeCalendarComponentsKeepWallClockTimeAcrossDST() throws {
        let request = try XCTUnwrap(NotificationManager.scheduleRequests(for: [rule(days: [7])]).first)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        // nextTriggerDate has no injectable 'now'. Match the actual native trigger's
        // floating components using Foundation at known DST boundaries instead.
        for (month, day, expectedInterval) in [(3, 21, 7 * 86_400 - 3_600), (10, 17, 7 * 86_400 + 3_600)] {
            let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12)))
            let first = try XCTUnwrap(calendar.nextDate(after: start, matching: trigger.dateComponents, matchingPolicy: .nextTime))
            let second = try XCTUnwrap(calendar.nextDate(after: first.addingTimeInterval(1), matching: trigger.dateComponents, matchingPolicy: .nextTime))
            XCTAssertEqual(calendar.component(.hour, from: first), 9)
            XCTAssertEqual(calendar.component(.minute, from: first), 30)
            XCTAssertEqual(calendar.component(.hour, from: second), 9)
            XCTAssertEqual(calendar.component(.minute, from: second), 30)
            XCTAssertEqual(second.timeIntervalSince(first), TimeInterval(expectedInterval), accuracy: 1)
        }
    }

    func testOnlyForegroundRunAndDefaultTapCanRequestRule() throws {
        let category = NotificationManager.reminderCategory()
        let action = try XCTUnwrap(category.actions.first)
        XCTAssertTrue(action.options.contains(.foreground))
        XCTAssertTrue(action.options.contains(.authenticationRequired))
        for actionID in [NotificationManager.runRuleAction, UNNotificationDefaultActionIdentifier] {
            XCTAssertEqual(NotificationManager.reminderCommand(identifier: "earshot.rule.commute.daily", category: category.identifier, ruleID: "commute", action: actionID), .runRule(id: "commute"))
        }
        XCTAssertNil(NotificationManager.reminderCommand(identifier: "earshot.rule.commute.daily", category: category.identifier, ruleID: "commute", action: UNNotificationDismissActionIdentifier))
        XCTAssertNil(NotificationManager.reminderCommand(identifier: "earshot.low-battery.device", category: category.identifier, ruleID: "commute", action: action.identifier))
        XCTAssertNil(NotificationManager.reminderCommand(identifier: "earshot.rule.commute.daily", category: "unrelated", ruleID: "commute", action: action.identifier))
        XCTAssertNil(NotificationManager.reminderCommand(identifier: "earshot.rule.commute.daily", category: category.identifier, ruleID: nil, action: action.identifier))
    }
}
