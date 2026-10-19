// Regression tests for the AI-assisted iOS port of upstream Earshot (MIT).
import XCTest
@testable import Earshot

final class AutomationTests: XCTestCase {
    func testOldSavedStateRetainsPreferencesAndModeRuleWhileNewOptionsDefault() throws {
        let data = Data(#"{"demo":true,"profileID":"ultra1","eq":[3,-2,1],"theme":"Dark","rules":[{"id":"old","name":"Commute","enabled":true,"trigger":"On connection","modeIndex":1,"hour":9,"minute":30}]}"#.utf8)
        let state = try JSONDecoder().decode(SavedAppState.self, from: data)
        XCTAssertEqual(state.profileID, "ultra1")
        XCTAssertEqual(state.eq, [3, -2, 1])
        XCTAssertEqual(state.theme, "Dark")
        XCTAssertEqual(state.rules[0].effectiveActions, [.mode(1)])
        XCTAssertEqual(state.rules[0].effectiveWeekdays, Set(1...7))
        XCTAssertTrue(state.audioOptions.automaticHeadroom)
        XCTAssertTrue(state.audioOptions.limiterEnabled)
    }

    func testCorruptIndividualRecordsDoNotEraseOtherSavedSettings() throws {
        let data = Data(#"{"theme":"Dark","customPresets":[{"id":17}],"rules":[{"id":"good","name":"Office","enabled":true,"trigger":"Manual","modeIndex":1,"hour":9,"minute":0},{"name":12}]}"#.utf8)
        let state = try JSONDecoder().decode(SavedAppState.self, from: data)
        XCTAssertEqual(state.theme, "Dark")
        XCTAssertEqual(state.rules.map(\.id), ["good"])
        XCTAssertTrue(state.customPresets.isEmpty)
        XCTAssertEqual(state.recoveredItemCount, 2)
    }

    func testActionOrderIsCanonicalEvenForDecodedOutOfOrderRules() throws {
        let noise = NoiseState(level: 6)
        let rule = AutomationRule(name: "Combined", actions: [.preset("flat"), .noise(noise), .mode(1)])
        XCTAssertEqual(rule.effectiveActions, [.mode(1), .noise(noise), .preset("flat")])
        XCTAssertEqual(try JSONDecoder().decode(AutomationRule.self, from: JSONEncoder().encode(rule)).effectiveActions, rule.effectiveActions)
        XCTAssertNil(rule.configurationError)
        XCTAssertNotNil(AutomationRule(name: "Duplicate", actions: [.mode(0), .mode(1)]).configurationError)
        XCTAssertNotNil(AutomationRule(name: "Empty", actions: []).configurationError)
        XCTAssertNotNil(AutomationRule(name: "Invalid", actions: [.noise(NoiseState(level: .nan))]).configurationError)
    }

    func testNoiseFallbackMustBelongToDestinationMode() {
        let slots = NoiseWriteCapabilities(globalWrite: false, editableModeIDs: [4], currentMode: 4)
        XCTAssertTrue(slots.canWrite(afterSelecting: nil))
        XCTAssertFalse(slots.canWrite(afterSelecting: 0), "An editable CURRENT slot cannot authorize a write to the destination built-in mode.")
        XCTAssertTrue(slots.canWrite(afterSelecting: 4))
        XCTAssertTrue(NoiseWriteCapabilities(globalWrite: true, editableModeIDs: [], currentMode: 4).canWrite(afterSelecting: 0))
    }

    func testScheduleUsesISOWeekdaysAndStableWallClockOccurrence() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Australia/Melbourne"))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9, minute: 30)))
        let rule = AutomationRule(name: "Workdays", trigger: "Schedule (app open)", hour: 9, minute: 30, weekdays: [1, 2, 3, 4, 5])
        let key = try XCTUnwrap(rule.scheduleOccurrence(at: monday, calendar: calendar))
        XCTAssertEqual(key, rule.scheduleOccurrence(at: monday.addingTimeInterval(20), calendar: calendar))
        let saturday = try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: monday))
        XCTAssertNil(rule.scheduleOccurrence(at: saturday, calendar: calendar))
        XCTAssertNil(rule.scheduleOccurrence(at: monday.addingTimeInterval(60), calendar: calendar))
        var attempted = rule; attempted.lastFiredDay = key
        XCTAssertTrue(attempted.alreadyAttempted(key, date: monday, calendar: calendar))
    }

    func testFallBackRepeatedHourDoesNotRunTwice() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let formatter = ISO8601DateFormatter()
        let first = try XCTUnwrap(formatter.date(from: "2026-11-01T05:30:00Z"))
        let second = try XCTUnwrap(formatter.date(from: "2026-11-01T06:30:00Z"))
        let rule = AutomationRule(name: "Sunday", trigger: "Schedule (app open)", hour: 1, minute: 30, weekdays: [7])
        let key = try XCTUnwrap(rule.scheduleOccurrence(at: first, calendar: calendar))
        XCTAssertEqual(rule.scheduleOccurrence(at: second, calendar: calendar), key)
    }

    @MainActor func testCombinedDemoRuleAppliesAllActionsAndPreservesThemOnRelaunch() throws {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        f.store.finishWelcome(demo: true)
        let noise = NoiseState(level: 6, enabled: true, wind: true, spatial: 1)
        let rule = AutomationRule(name: "Commute", trigger: "Manual", actions: [.mode(1), .noise(noise), .preset("bass-boost")])
        // Use the real built-in ID instead of tying this test to a display label.
        var configured = rule; configured.actions = [.mode(1), .noise(noise), .preset(BuiltInPresets.bassBoost.id)]
        XCTAssertTrue(f.store.upsertRule(configured))
        XCTAssertTrue(f.store.runRule(configured))
        XCTAssertEqual(f.store.saved.currentMode, 1)
        XCTAssertEqual(f.store.saved.noise, noise)
        XCTAssertEqual(f.store.saved.presetID, BuiltInPresets.bassBoost.id)
        XCTAssertTrue(f.store.saved.proEnabled)
        XCTAssertEqual(f.store.ruleStatuses[rule.id], "Applied in demo")
        let restored = AppStore(defaults: f.defaults, arguments: [])
        XCTAssertEqual(restored.saved.rules.first?.effectiveActions, configured.effectiveActions)
        XCTAssertEqual(restored.saved.noise, noise)
    }

    @MainActor func testLocalPresetRuleWorksOfflineButMissingPresetRejectsWholeCombination() {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        let local = AutomationRule(name: "Local", trigger: "Manual", actions: [.preset(BuiltInPresets.bassBoost.id)])
        XCTAssertFalse(f.store.connected)
        XCTAssertTrue(f.store.runRule(local))
        XCTAssertTrue(f.store.saved.proEnabled)
        XCTAssertEqual(f.store.saved.presetID, BuiltInPresets.bassBoost.id)
        f.store.setDemo(true)
        f.store.selectMode(0)
        let invalid = AutomationRule(name: "Removed", actions: [.mode(1), .preset("missing")])
        XCTAssertFalse(f.store.runRule(invalid))
        XCTAssertEqual(f.store.saved.currentMode, 0, "Preflight must reject before applying the earlier valid action.")
        XCTAssertTrue(f.store.message?.contains("removed") == true)
    }

    @MainActor func testUnsupportedCombinationDoesNotConsumeScheduleOccurrence() throws {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        let now = Date.now
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let rule = AutomationRule(name: "Offline", trigger: "Schedule (app open)", hour: c.hour!, minute: c.minute!)
        XCTAssertTrue(f.store.upsertRule(rule))
        f.store.checkSchedules(now: now)
        XCTAssertNil(f.store.saved.rules.first?.lastFiredDay)
        XCTAssertTrue(f.store.automationLog.isEmpty)
        f.store.setDemo(true)
        f.store.checkSchedules(now: now)
        XCTAssertNotNil(f.store.saved.rules.first?.lastFiredDay)
        XCTAssertEqual(f.store.automationLog.count, 1)
    }

    @MainActor func testQuietAwareSemanticRequestsCannotSelectOpenEarbudSpatialModes() async throws {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        f.store.setDemo(true); f.store.appIsActive = true
        XCTAssertEqual(f.store.resolveListeningRole(.aware), 1)
        _ = try await f.store.executeSharedPayload(.listeningRole(.aware))
        XCTAssertEqual(f.store.saved.currentMode, 1)
        f.store.selectProfile("open")
        XCTAssertNil(f.store.resolveListeningRole(.aware))
        do { _ = try await f.store.executeSharedPayload(.listeningRole(.aware)); XCTFail("Open earbuds must not map Aware to Immersion by fixed index.") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Aware")) }
        XCTAssertEqual(f.store.saved.currentMode, 0)
    }

    @MainActor func testDeviceConfirmationRequiresFreshRelevantReport() {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        f.store.pendingDeviceOperation = .language(1)
        f.store.voicePromptsState = BoseVoicePromptsState(enabled: true, language: 1, installedLanguages: [1])
        f.store.checkDeviceOperationConfirmation(reportAddress: BmapAddress(2, 2))
        XCTAssertNotNil(f.store.pendingDeviceOperation)
        f.store.checkDeviceOperationConfirmation(reportAddress: BmapAddress(1, 3))
        XCTAssertNil(f.store.pendingDeviceOperation)
        XCTAssertEqual(f.store.deviceRequestStatus, "Confirmed by headphone reports.")
    }

    @MainActor private func fixture() -> (store: AppStore, defaults: UserDefaults, suite: String) {
        let suite = "EarshotAutomationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppStore(defaults: defaults, arguments: []), defaults, suite)
    }
}
