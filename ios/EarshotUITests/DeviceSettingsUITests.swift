// Original settings behavior: HellzYeahh/earshot (MIT). This journey uses demo state only.
import XCTest

final class DeviceSettingsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    func testSelfVoicePersistencePreservesLevelAndFiftyPercentThresholdSurvivesRelaunch() {
        app.launch()
        let demo = app.buttons["tryDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10)); tap(demo)
        if app.buttons["dismissReleaseNotes"].waitForExistence(timeout: 2) { app.buttons["dismissReleaseNotes"].tap() }
        selectTab("Settings")
        let persistence = app.switches["sidetonePersistence"]
        assertSwitch(persistence, isOn: true)
        setSwitch(persistence, isOn: false)
        let voice = picker("Self Voice")
        tap(voice)
        let high = app.buttons["High"]
        XCTAssertTrue(high.waitForExistence(timeout: 5)); high.tap()
        assertPicker(voice, equals: "High")
        assertSwitch(persistence, isOn: false)
        setSwitch(persistence, isOn: true)
        assertPicker(voice, equals: "High")
        capture("Demo Self Voice High retains its independently selected remember flag")

        openPreferences()
        let threshold = picker("Alert at")
        tap(threshold)
        let fifty = app.buttons["50%"]
        XCTAssertTrue(fifty.waitForExistence(timeout: 5)); reveal(fifty); fifty.tap()
        assertPicker(threshold, equals: "50%")
        assertNoPermissionPrompt()
        capture("Demo battery alert threshold is exactly 50 percent without requesting notifications")

        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertFalse(app.buttons["tryDemo"].exists)
        selectTab("Settings")
        assertPicker(picker("Self Voice"), equals: "High")
        openPreferences()
        assertPicker(picker("Alert at"), equals: "50%")
        assertNoPermissionPrompt()
        capture("50 percent battery threshold and High Self Voice persisted after relaunch")
    }

    private func openPreferences() {
        tap(picker("App preferences"))
        XCTAssertTrue(app.navigationBars["App preferences"].waitForExistence(timeout: 5))
    }

    private func picker(_ title: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch }

    private func assertPicker(_ element: XCUIElement, equals expected: String) {
        reveal(element)
        let exact = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            if let value = element.value as? String, !value.isEmpty { return value == expected }
            return element.label.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines) == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exact], timeout: 5), .completed, "Expected exact native picker value \(expected): \(element)")
    }

    private func assertSwitch(_ element: XCUIElement, isOn: Bool) {
        reveal(element)
        let exact = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", isOn ? "1" : "0"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [exact], timeout: 5), .completed)
    }

    private func setSwitch(_ element: XCUIElement, isOn: Bool) {
        reveal(element)
        guard (element.value as? String == "1") != isOn else { return }
        let frame = element.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.maxX - min(25, frame.width / 2), dy: frame.midY)).tap()
        assertSwitch(element, isOn: isOn)
    }

    private func selectTab(_ name: String) {
        let compact = app.tabBars.buttons[name]
        let target = compact.exists ? compact : app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap()
    }

    private func tap(_ element: XCUIElement) { reveal(element); element.tap() }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<20 {
            let screen = app.frame
            var top = screen.minY + 20, bottom = screen.maxY - 20
            if let nav = app.navigationBars.allElementsBoundByIndex.last(where: { $0.isHittable && !$0.frame.isEmpty }) { top = max(top, nav.frame.maxY + 6) }
            let bar = app.tabBars.firstMatch
            if bar.exists, bar.isHittable {
                if bar.frame.minY > screen.midY { bottom = min(bottom, bar.frame.minY - 12) }
                else { top = max(top, bar.frame.maxY + 6) }
            }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 8) }
            if element.exists, element.isHittable, !element.frame.isEmpty, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            let downward = !element.exists || element.frame.maxY > bottom
            let travel = min(140, (bottom - top) * 0.4), middle = (top + bottom) / 2
            let start = middle + (downward ? travel / 2 : -travel / 2), end = middle - (downward ? travel / 2 : -travel / 2)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: screen.minX + 8, dy: start)).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: screen.minX + 8, dy: end)), withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTFail("Could not fully reveal \(element)")
    }

    private func assertNoPermissionPrompt() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: alert)
        absent.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 1.5), .completed, "Changing a demo threshold must not request notification permission")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    private func capture(_ title: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = title; attachment.lifetime = .keepAlways; add(attachment)
    }
}
