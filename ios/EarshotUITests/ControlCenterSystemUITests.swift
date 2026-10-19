// AI-assisted iOS port of HellzYeahh/earshot (MIT); original contributors retain credit.
// Actual Simulator Control Center -> foreground App Intent -> demo state delivery.
// This establishes no physical headphones, Siri or signed-iPhone provisioning.
import XCTest

final class ControlCenterSystemUITests: XCTestCase {
    func testControlCenterCycleOpensAppAndAppliesDemoMode() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let demo = app.buttons["tryDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        for _ in 0..<12 {
            if demo.isHittable, demo.frame.maxY < app.frame.maxY - 24 { break }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: 8, dy: app.frame.height * 0.75))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 8, dy: app.frame.height * 0.48)),
                       withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        demo.tap()
        XCTAssertTrue(app.navigationBars["earshot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo device"].exists)
        XCTAssertTrue(app.staticTexts["currentMode"].label.contains("Quiet"))

        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let frame = springboard.frame
        XCTAssertFalse(frame.isEmpty)
        let origin = springboard.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.width * 0.98, dy: max(2, frame.height * 0.01)))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: frame.width * 0.98, dy: frame.height * 0.60)),
                   withVelocity: .slow, thenHoldForDuration: 0.15)

        // These identifiers and gallery actions were inspected in actual system AX
        // before this test was authored. Reuse our own installed control on repeats.
        let folder = springboard.otherElements["cc-root-folder-view"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5), springboard.debugDescription)
        let cycle = springboard.icons["Earshot mode cycle"].firstMatch
        if !cycle.waitForExistence(timeout: 3) {
            let edit = springboard.buttons["Add Controls"]
            if edit.exists { edit.tap() }
            let add = springboard.buttons["Add a Control"]
            XCTAssertTrue(add.waitForExistence(timeout: 5), springboard.debugDescription)
            add.tap()
            let galleryCycle = springboard.icons["Earshot mode cycle"]
            XCTAssertTrue(galleryCycle.waitForExistence(timeout: 5), springboard.debugDescription)
            XCTAssertTrue(galleryCycle.isHittable)
            galleryCycle.tap()
        }
        XCTAssertTrue(cycle.waitForExistence(timeout: 5), springboard.debugDescription)
        if springboard.buttons["Add a Control"].exists {
            // The inspected one-control page has an empty centre; tapping it leaves
            // editing without touching its top-left control or delete affordance.
            folder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let finishedEditing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !springboard.buttons["Add a Control"].exists && !cycle.buttons["DeleteButton"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finishedEditing], timeout: 5), .completed, springboard.debugDescription)
        XCTAssertTrue(cycle.isHittable)
        let tile = XCTAttachment(screenshot: cycle.screenshot())
        tile.name = "Actual Earshot Control Center mode-cycle control"
        tile.lifetime = .keepAlways; add(tile)
        cycle.tap()

        let foreground = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.state == .runningForeground }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [foreground], timeout: 10), .completed,
                       "Control Center must open Earshot itself; the test does not activate the app.")
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.staticTexts["currentMode"].label.contains("Aware")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [applied], timeout: 10), .completed, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Demo device"].exists)
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "Actual Control Center Cycle opened Earshot and applied Aware in demo"
        result.lifetime = .keepAlways; add(result)
    }
}
