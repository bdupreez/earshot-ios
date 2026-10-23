import XCTest
@testable import Earshot

// Source-backed policy/integration regressions, not Bluetooth hardware validation.
final class AudioRouteConnectionTests: XCTestCase {
    private let a = CompanionAudioOutput(id: "a", name: "Headset A", kind: "BluetoothA2DPOutput", isHeadphones: true)
    private let b = CompanionAudioOutput(id: "b", name: "Headset B", kind: "BluetoothA2DPOutput", isHeadphones: true)
    private let speaker = CompanionAudioOutput(id: "speaker", name: "iPhone", kind: "Speaker", isHeadphones: false)

    func testForegroundExternalTransitionsDeduplicateAndRequireRouteEvidence() {
        var policy = AudioRouteConnectionPolicy()
        XCTAssertFalse(policy.observe(speaker, reason: .refresh, isAppActive: true))
        XCTAssertTrue(policy.observe(a, reason: .newDeviceAvailable, isAppActive: true))
        XCTAssertFalse(policy.observe(a, reason: .newDeviceAvailable, isAppActive: true))
        XCTAssertFalse(policy.observe(a, reason: .refresh, isAppActive: true))
        XCTAssertTrue(policy.observe(b, reason: .routeSelection, isAppActive: true))
        XCTAssertFalse(policy.observe(speaker, reason: .oldDeviceUnavailable, isAppActive: true))
        XCTAssertTrue(policy.observe(b, reason: .newDeviceAvailable, isAppActive: true))
    }

    func testCategoryAndOwnedMicrophoneChangesCannotLoopConnectionRules() {
        var policy = AudioRouteConnectionPolicy()
        XCTAssertTrue(policy.observe(a, reason: .newDeviceAvailable, isAppActive: true))
        let hfp = CompanionAudioOutput(id: "a-hfp", name: "Headset A", kind: "BluetoothHFP", isHeadphones: true)
        XCTAssertFalse(policy.observe(hfp, reason: .categoryChange, isAppActive: true))
        XCTAssertFalse(policy.observe(hfp, reason: .microphoneTransition, isAppActive: true))
        XCTAssertFalse(policy.observe(speaker, reason: .categoryChange, isAppActive: true))
        XCTAssertEqual(policy.lastExternalID, a.id)
        XCTAssertFalse(policy.observe(a, reason: .newDeviceAvailable, isAppActive: true))
    }

    func testInactiveAndInitialObservationsNeverReplayOnForegroundActivation() {
        var policy = AudioRouteConnectionPolicy()
        XCTAssertFalse(policy.observe(a, reason: .newDeviceAvailable, isAppActive: false))
        XCTAssertFalse(policy.observe(a, reason: .refresh, isAppActive: true))
        XCTAssertFalse(policy.observe(a, reason: .newDeviceAvailable, isAppActive: true))
        XCTAssertFalse(policy.observe(b, reason: .unknown, isAppActive: true))
        XCTAssertFalse(policy.observe(b, reason: .refresh, isAppActive: true))
        XCTAssertFalse(policy.observe(nil, reason: .oldDeviceUnavailable, isAppActive: false))
        XCTAssertTrue(policy.observe(a, reason: .newDeviceAvailable, isAppActive: true))
    }

    @MainActor func testRouteMemoryRestoresBeforeLocalRuleWithoutHardwareOrDuplicateControlLinkRun() throws {
        let suite = "AudioRouteConnectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults, arguments: [])
        store.appIsActive = true; store.saved.demo = false
        store.companion.preferences.spokenFeedback = false
        store.companion.preferences.outputEQ[a.id] = .preset(BuiltInPresets.flat.id)
        let local = AutomationRule(name: "Audio EQ", trigger: "On connection", actions: [.preset(BuiltInPresets.bassBoost.id)])
        let hardware = AutomationRule(name: "Hardware", trigger: "On connection", actions: [.mode(1), .preset(BuiltInPresets.vocalClarity.id)])
        XCTAssertTrue(store.upsertRule(local)); XCTAssertTrue(store.upsertRule(hardware))
        store.companion.acceptOutput(a, reason: .newDeviceAvailable)
        XCTAssertFalse(store.bluetooth.isConnected)
        XCTAssertEqual(store.saved.presetID, BuiltInPresets.bassBoost.id)
        XCTAssertEqual(store.ruleStatuses[local.id], "Local audio settings applied")
        XCTAssertNil(store.ruleStatuses[hardware.id])
        XCTAssertEqual(store.companion.preferences.outputEQ[a.id], .preset(BuiltInPresets.flat.id))
        let count = store.automationLog.count
        store.companion.acceptOutput(a, reason: .refresh)
        store.companion.acceptOutput(speaker, reason: .categoryChange)
        store.companion.acceptOutput(a, reason: .categoryChange)
        XCTAssertEqual(store.saved.presetID, BuiltInPresets.bassBoost.id, "Category changes cannot reapply remembered EQ over a temporary rule")
        store.connectionRulesPending = true
        store.processConnectionRules()
        XCTAssertEqual(store.automationLog.count, count)
    }

    @MainActor func testDemoInactiveDisabledAndManualRulesAreExcluded() throws {
        let suite = "AudioRouteConnectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(defaults: defaults, arguments: [])
        let local = AutomationRule(name: "Connection", trigger: "On connection", actions: [.preset(BuiltInPresets.bassBoost.id)])
        var disabled = local; disabled.id = UUID().uuidString; disabled.name = "Disabled"; disabled.enabled = false
        let manual = AutomationRule(name: "Manual", trigger: "Manual", actions: [.preset(BuiltInPresets.flat.id)])
        for rule in [local, disabled, manual] { XCTAssertTrue(store.upsertRule(rule)) }
        store.onAudioOutputChanged(a, reason: .newDeviceAvailable)
        XCTAssertTrue(store.ruleStatuses.isEmpty)
        store.appIsActive = true; store.saved.demo = true
        store.onAudioOutputChanged(b, reason: .newDeviceAvailable)
        XCTAssertTrue(store.ruleStatuses.isEmpty)
        store.saved.demo = false
        store.onAudioOutputChanged(a, reason: .newDeviceAvailable)
        XCTAssertEqual(store.ruleStatuses[local.id], "Local audio settings applied")
        XCTAssertNil(store.ruleStatuses[disabled.id]); XCTAssertNil(store.ruleStatuses[manual.id])
    }
}
