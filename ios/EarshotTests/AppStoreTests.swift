import XCTest
@testable import Earshot

final class AppStoreTests: XCTestCase {
    @MainActor
    func testDemoHydratesModesAndEarbudCapabilities() {
        let fixture = makeStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        XCTAssertFalse(store.connected)
        XCTAssertTrue(store.welcome)
        store.finishWelcome(demo: true)
        XCTAssertTrue(store.connected)
        XCTAssertFalse(store.welcome)
        XCTAssertEqual(store.battery, 82)
        XCTAssertEqual(store.saved.modes.filter(\.builtIn).count, 4)
        XCTAssertTrue(store.supports(1, 7))
        store.selectProfile("budsII")
        XCTAssertTrue(store.profile.earbuds)
        XCTAssertFalse(store.profile.spatial)
        XCTAssertEqual(store.batteries["Case"], 64)
        XCTAssertEqual(store.saved.modes.count, 4)
        store.selectProfile("open")
        XCTAssertFalse(store.profile.noise)
        XCTAssertFalse(store.profile.wind)
        XCTAssertEqual(store.saved.modes.count, 2)
    }

    @MainActor
    func testDemoStateAndUserPresetPersistAcrossLaunches() {
        let fixture = makeStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        store.finishWelcome(demo: true)
        store.selectProfile("ultra1")
        store.selectMode(1)
        store.setEQ(0, value: 4)
        store.updateSidetone(3)
        store.updateAutoOff(60)
        store.saved.proEnabled = true
        var custom = BuiltInPresets.bassBoost
        custom.name = "My bass"
        store.savePreset(custom)
        let restored = AppStore(defaults: fixture.defaults, arguments: [])
        XCTAssertTrue(restored.saved.demo)
        XCTAssertFalse(restored.welcome)
        XCTAssertEqual(restored.profile.id, "ultra1")
        XCTAssertEqual(restored.saved.currentMode, 1)
        XCTAssertEqual(restored.saved.eq[0], 4)
        XCTAssertEqual(restored.saved.sidetone, 3)
        XCTAssertEqual(restored.saved.autoOff, 60)
        XCTAssertTrue(restored.saved.proEnabled)
        XCTAssertEqual(restored.preset.name, "My bass")
        XCTAssertFalse(restored.preset.isBuiltIn)
        XCTAssertNotEqual(restored.preset.id, BuiltInPresets.bassBoost.id)
        XCTAssertEqual(restored.preset.bands, BuiltInPresets.bassBoost.bands)
    }

    @MainActor
    func testUnconfiguredAndUnknownModesCannotBecomeActive() {
        let fixture = makeStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        store.setDemo(true)
        store.selectMode(1)
        let custom = store.saved.modes.first { !$0.configured }!
        store.selectMode(custom.id)
        XCTAssertEqual(store.saved.currentMode, 1)
        store.selectMode(255)
        XCTAssertEqual(store.saved.currentMode, 1)
        var configured = custom
        configured.name = "Office"
        configured.noise.level = 7
        store.saveMode(configured)
        store.selectMode(configured.id)
        XCTAssertEqual(store.saved.currentMode, configured.id)
        XCTAssertEqual(store.saved.noise.level, 7)
    }

    @MainActor
    func testModeNamesValidateUTF8ByteLength() {
        let fixture = makeStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        store.setDemo(true)
        var mode = store.saved.modes.first { !$0.builtIn }!
        let original = mode
        mode.name = "   "
        store.saveMode(mode)
        XCTAssertNotNil(store.message)
        XCTAssertEqual(store.saved.modes.first { $0.id == mode.id }, original)
        store.message = nil
        mode.name = String(repeating: "🎧", count: 8)
        store.saveMode(mode)
        XCTAssertNotNil(store.message)
        XCTAssertEqual(store.saved.modes.first { $0.id == mode.id }, original)
        store.message = nil
        mode.name = String(repeating: "a", count: 31)
        store.saveMode(mode)
        XCTAssertNil(store.message)
        XCTAssertEqual(store.saved.modes.first { $0.id == mode.id }?.name, mode.name)
    }

    @MainActor
    func testConnectionRuleRunsAndScheduleFiresOnlyOncePerDay() {
        let fixture = makeStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let store = fixture.store
        store.upsertRule(AutomationRule(name: "Aware when connected", modeIndex: 1))
        store.setDemo(true)
        XCTAssertEqual(store.saved.currentMode, 1)
        XCTAssertEqual(store.automationLog.count, 1)
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9, minute: 30))!
        let rule = AutomationRule(name: "Morning focus", trigger: "Schedule (app open)", modeIndex: 0, hour: 9, minute: 30)
        store.upsertRule(rule)
        store.checkSchedules(now: date)
        XCTAssertEqual(store.saved.currentMode, 0)
        XCTAssertEqual(store.automationLog.count, 2)
        store.checkSchedules(now: date.addingTimeInterval(20))
        XCTAssertEqual(store.automationLog.count, 2)
        store.checkSchedules(now: calendar.date(byAdding: .day, value: 1, to: date)!)
        XCTAssertEqual(store.automationLog.count, 3)
    }

    @MainActor
    func testDisconnectedRuleRequiresAConnectionAndProfileIDsAreUnique() {
        let fixture = makeStore()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.runRule(AutomationRule(name: "Focus"))
        XCTAssertNotNil(fixture.store.message)
        XCTAssertTrue(fixture.store.automationLog.isEmpty)
        XCTAssertEqual(DeviceProfile.all.count, 14)
        XCTAssertEqual(Set(DeviceProfile.all.map(\.id)).count, DeviceProfile.all.count)
        XCTAssertTrue(DeviceProfile.all.first { $0.id == "qc35" }!.unsupported)
        XCTAssertTrue(DeviceProfile.all.first { $0.id == "crusher" }!.crusher)
    }

    @MainActor
    private func makeStore() -> (store: AppStore, defaults: UserDefaults, suite: String) {
        let suite = "EarshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AppStore(defaults: defaults, arguments: []), defaults, suite)
    }
}
