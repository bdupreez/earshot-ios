// AI-assisted iOS port of HellzYeahh/earshot (MIT); original contributors retain credit.
// Exercises actual Simulator WidgetKit -> foreground App Intent -> demo state delivery.
// This does not establish physical headphones, signed iPhone provisioning or Siri delivery.
import XCTest

final class WidgetSystemUITests: XCTestCase {
    func testSmallWidgetCycleOpensAppAndAppliesDemoMode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let demo = app.buttons["tryDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        reveal(demo, in: app)
        demo.tap()
        XCTAssertTrue(app.navigationBars["earshot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo device"].exists)
        XCTAssertTrue(app.staticTexts["currentMode"].label.contains("Quiet"))

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let cycle = springboard.buttons["Cycle configured listening modes"]
        // Keep the test repeatable when its own widget is already installed.
        // Fresh simulators use the native size option observed in SpringBoard's
        // Earshot context menu; no unrelated Home Screen item is changed.
        if !cycle.waitForExistence(timeout: 5) {
            let icon = springboard.icons["Earshot"]
            XCTAssertTrue(icon.waitForExistence(timeout: 10), springboard.debugDescription)
            icon.press(forDuration: 1.2)
            let small = springboard.buttons["Small widget"]
            XCTAssertTrue(small.waitForExistence(timeout: 5), springboard.debugDescription)
            XCTAssertTrue(small.isEnabled)
            small.tap()
            let done = springboard.buttons["Done"]
            if done.exists, done.isHittable { done.tap() }
        }
        XCTAssertTrue(cycle.waitForExistence(timeout: 15), springboard.debugDescription)
        XCTAssertTrue(cycle.isHittable)
        capture(springboard, name: "Actual Simulator Earshot small widget before Cycle")
        cycle.tap()
        let foreground = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.state == .runningForeground
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [foreground], timeout: 10), .completed,
                       "The system widget must open Earshot; the test never activates it on the widget's behalf.")
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.staticTexts["currentMode"].label.contains("Aware")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [applied], timeout: 10), .completed, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Demo device"].exists)
        reveal(app.staticTexts["currentMode"], in: app)
        capture(app, name: "Actual widget Cycle opened Earshot and applied Aware in demo")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            let screen = app.frame
            var top = screen.minY + 20, bottom = screen.maxY - 24
            let nav = app.navigationBars.firstMatch
            if nav.exists, nav.isHittable { top = max(top, nav.frame.maxY + 8) }
            let tabs = app.tabBars.firstMatch
            if tabs.exists, tabs.isHittable, tabs.frame.minY > screen.midY { bottom = min(bottom, tabs.frame.minY - 12) }
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let middle = (top + bottom) / 2
            origin.withOffset(CGVector(dx: 8, dy: middle + 70))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 8, dy: middle - 70)),
                       withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTFail("Expected a visible widget-result control: \(element)\n\(app.debugDescription)")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
