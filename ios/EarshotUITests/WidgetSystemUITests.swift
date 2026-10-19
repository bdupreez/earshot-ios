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
        if !cycle.waitForExistence(timeout: 5) || springboard.buttons["Quiet"].exists || springboard.buttons["Aware"].exists {
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
        // Capture only Earshot's native widget element for shareable evidence;
        // unrelated installed apps need not appear in the exported attachment.
        guard let tile = springboard.icons.matching(identifier: "Earshot").allElementsBoundByIndex.first(where: {
            ($0.value as? String) == "Widget" && !$0.frame.isEmpty
        }) else { XCTFail("Expected Earshot’s own native small widget element: \(springboard.debugDescription)"); return }
        let attachment = XCTAttachment(screenshot: tile.screenshot())
        attachment.name = "Actual Earshot small widget before Cycle"
        attachment.lifetime = .keepAlways
        add(attachment)
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

    // The medium journey also verifies three-part battery layout and unclipped controls.
    // The name intentionally sorts after the existing small-widget acceptance case.
    func testWidgetMediumAwareOpensAppAndAppliesDemoMode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let demo = app.buttons["tryDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        reveal(demo, in: app); demo.tap()
        XCTAssertTrue(app.navigationBars["earshot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo device"].exists)
        XCTAssertTrue(app.staticTexts["currentMode"].label.contains("Quiet"))

        let switcher = app.buttons["headphoneSwitcher"]
        reveal(switcher, in: app); switcher.tap()
        XCTAssertTrue(app.navigationBars["Switch headphones"].waitForExistence(timeout: 5))
        let earbuds = app.buttons["switchDemo.budsII"]
        reveal(earbuds, in: app); earbuds.tap()
        XCTAssertTrue(app.navigationBars["Switch headphones"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["headphoneSwitcher"].label.contains("QC Earbuds II"))
        XCTAssertTrue(app.staticTexts["currentMode"].label.contains("Quiet"))

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let quiet = springboard.buttons["Quiet"]
        let aware = springboard.buttons["Aware"]
        let cycle = springboard.buttons["Cycle configured listening modes"]
        // The medium size exposes semantic Quiet/Aware controls in addition to Cycle.
        // Reuse an installed medium widget, or choose the actual observed native size item.
        if !quiet.waitForExistence(timeout: 5) || !aware.exists {
            let icon = springboard.icons.matching(identifier: "Earshot").firstMatch
            XCTAssertTrue(icon.waitForExistence(timeout: 10), springboard.debugDescription)
            icon.press(forDuration: 1.2)
            let medium = springboard.buttons["Medium-sized widget"]
            XCTAssertTrue(medium.waitForExistence(timeout: 5), springboard.debugDescription)
            XCTAssertTrue(medium.isEnabled)
            medium.tap()
            let done = springboard.buttons["Done"]
            if done.exists, done.isHittable { done.tap() }
        }
        XCTAssertTrue(quiet.waitForExistence(timeout: 15), springboard.debugDescription)
        XCTAssertTrue(aware.waitForExistence(timeout: 15), springboard.debugDescription)
        XCTAssertTrue(cycle.waitForExistence(timeout: 15), springboard.debugDescription)
        XCTAssertTrue(quiet.isHittable)
        XCTAssertTrue(aware.isHittable)
        XCTAssertTrue(cycle.isHittable)
        guard let tile = springboard.icons.matching(identifier: "Earshot").allElementsBoundByIndex.first(where: {
            ($0.value as? String) == "Widget" && !$0.frame.isEmpty
        }) else { XCTFail("Expected Earshot's own native widget element: \(springboard.debugDescription)"); return }
        for component in ["Left", "Right", "Case"] {
            XCTAssertTrue(tile.staticTexts[component].waitForExistence(timeout: 10), tile.debugDescription)
        }
        let widgetViewport = tile.scrollViews.firstMatch
        XCTAssertTrue(widgetViewport.exists, tile.debugDescription)
        let visibleContent = widgetViewport.frame.insetBy(dx: 8, dy: 8)
        let header = tile.staticTexts["earshot"]
        XCTAssertTrue(header.exists)
        // Hittability alone accepted the earlier clipped layout. Require actual frames
        // inside the observed native widget viewport, excluding the Home Screen caption.
        for element in [header, quiet, aware, cycle] {
            XCTAssertFalse(element.frame.isEmpty)
            XCTAssertTrue(visibleContent.contains(element.frame),
                          "Widget control must be fully visible: \(element.frame), viewport: \(visibleContent)\n\(tile.debugDescription)")
        }
        let attachment = XCTAttachment(screenshot: tile.screenshot())
        attachment.name = "Actual Earshot medium widget before Aware"
        attachment.lifetime = .keepAlways
        add(attachment)

        aware.tap()
        let foreground = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.state == .runningForeground }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [foreground], timeout: 10), .completed,
                       "The medium widget must open Earshot itself; the test does not activate the app.")
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.staticTexts["currentMode"].label.contains("Aware") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [applied], timeout: 10), .completed, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Demo device"].exists)
        reveal(app.staticTexts["currentMode"], in: app)
        capture(app, name: "Actual medium widget Aware opened Earshot and changed only demo state")
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
