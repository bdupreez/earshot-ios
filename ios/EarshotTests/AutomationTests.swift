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

    func testWiFiRuleUsesUpstreamMatchingWithoutUnknownNetworkFallback() {
        XCTAssertTrue(WiFiSSID.matches(" \"Office\" ", "office"))
        XCTAssertFalse(WiFiSSID.matches("Office", nil))
        XCTAssertFalse(WiFiSSID.matches("Office", "<unknown ssid>"))
        XCTAssertFalse(WiFiSSID.matches("Office", "0x"))
        XCTAssertNil(AutomationRule(name: "Office", trigger: "Wi-Fi (app open)", wifiSSID: "Office").configurationError)
        XCTAssertNotNil(AutomationRule(name: "Missing", trigger: "Wi-Fi (app open)").configurationError)
    }

    @MainActor func testLatencyDemoStillUsesReportedRangeAndNeverSendsBluetooth() {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        f.store.setDemo(true)
        f.store.updateLatency(225)
        XCTAssertEqual(f.store.deviceLatencyValue, 225)
        XCTAssertTrue(f.store.deviceRequestStatus.contains("demo only"))
        f.store.updateLatency(401)
        XCTAssertEqual(f.store.deviceLatencyValue, 225)
        XCTAssertNotNil(f.store.message)
        XCTAssertFalse(f.store.bluetooth.isConnected)
    }

    @MainActor func testRememberedSSIDCannotRunRulesAfterObservationIsDisabled() {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        f.store.appIsActive = true
        let rule = AutomationRule(name: "Office EQ", trigger: "Wi-Fi (app open)",
                                  actions: [.preset(BuiltInPresets.bassBoost.id)], wifiSSID: "Office")
        XCTAssertTrue(f.store.upsertRule(rule))
        // A prior observation is not fresh evidence after opt-out/permission loss.
        f.store.observedWiFiSSID = "Office"
        f.store.wifi.disable()
        f.store.processWiFiRules()
        XCTAssertFalse(f.store.saved.proEnabled)
        XCTAssertTrue(f.store.automationLog.isEmpty)
        XCTAssertTrue(f.store.firedWiFiRuleIDs.isEmpty)
    }

    @MainActor func testReportedProductIdentityOverridesNameFallbackAndLaterRename() {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        f.store.receive(BmapPacket(block: 0, function: 15, operation: .status, payload: Data("Bose QC45".utf8)))
        XCTAssertEqual(f.store.profile.id, "qc45")
        XCTAssertEqual(f.store.profile.customCount, 2)
        f.store.receive(BmapPacket(block: 0, function: 3, operation: .status, payload: Data([0x40, 0x82])))
        XCTAssertEqual(f.store.profile.id, "ultra2")
        f.store.receive(BmapPacket(block: 0, function: 15, operation: .status, payload: Data("Bose QC45".utf8)))
        XCTAssertEqual(f.store.profile.id, "ultra2", "A renamed device must retain its reported product identity.")
    }

    @MainActor func testReportedCapabilitiesOverrideCatalogueDefaults() {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        f.store.receive(BmapPacket(block: 0, function: 3, operation: .status, payload: Data([0x40, 0x39])))
        f.store.receive(BmapPacket(block: 31, function: 2, operation: .status, payload: Data([3, 4, 0, 0, 0, 0b0010_1101])))
        XCTAssertEqual(f.store.profile.customCount, 4)
        XCTAssertTrue(f.store.profile.spatial)
        XCTAssertTrue(f.store.profile.wind)
        XCTAssertEqual(f.store.saved.modes.filter(\.builtIn).count, 3)
    }

    @MainActor func testRecoveryExportSurvivesRepairAndCleanRelaunch() throws {
        let suite = "EarshotRecoveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = Data("{unreadable original settings}".utf8)
        defaults.set(original, forKey: "earshot.ios.state")
        let store = AppStore(defaults: defaults, arguments: [])
        let recovery = try XCTUnwrap(store.stateRecoveryURL)
        defer { try? FileManager.default.removeItem(at: recovery) }
        store.saved.theme = "Dark" // Persist the successfully recovered/default state.
        let restored = AppStore(defaults: defaults, arguments: [])
        XCTAssertEqual(restored.saved.theme, "Dark")
        XCTAssertEqual(restored.stateRecoveryURL, recovery)
        XCTAssertEqual(try Data(contentsOf: recovery), original)
    }

    @MainActor func testDirectNoiseUsesReportedQuantizationAndTogglePermission() throws {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        f.store.receive(BmapPacket(block: 0, function: 3, operation: .status, payload: Data([0x40, 0x24])))
        f.store.receive(BmapPacket(block: 1, function: 5, operation: .status, payload: Data([3, 1, 3])))
        XCTAssertTrue(f.store.usesDirectNoise())
        XCTAssertFalse(f.store.canToggleANC())
        XCTAssertFalse(f.store.noiseProfile().spatial)
        XCTAssertFalse(f.store.noiseProfile().wind)
        XCTAssertEqual(f.store.saved.noise.level, 5)
        let expected = try f.store.expectedNoiseReport(NoiseState(level: 3, enabled: false))
        XCTAssertEqual(expected.level, 5, "A rule must wait for the representable reported level, not an impossible value.")
        XCTAssertTrue(expected.enabled, "The device's no-toggle flag must preserve its actual ANC state.")
    }

    @MainActor func testInformationalStartRefusalDoesNotFailAnUnrelatedHardwareMutation() {
        let f = fixture(); defer { f.defaults.removePersistentDomain(forName: f.suite) }
        f.store.trackSentRequest(BoseCommands.checkLEAudioPreference)
        f.store.receive(BmapPacket(block: 4, function: 19, operation: .error, payload: Data([5])))
        XCTAssertEqual(f.store.commandFailureVersion, 0)
        XCTAssertNil(f.store.message)
        f.store.trackSentRequest(BoseCommands.selectMode(index: 1))
        f.store.receive(BmapPacket(block: 31, function: 3, operation: .error, payload: Data([5])))
        XCTAssertEqual(f.store.commandFailureVersion, 1, "A real mutation refusal must still fail its waiting rule.")
        XCTAssertNotNil(f.store.message)
    }

    @MainActor private func fixture() -> (store: AppStore, defaults: UserDefaults, suite: String) {
        let suite = "EarshotAutomationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (AppStore(defaults: defaults, arguments: []), defaults, suite)
    }
}
