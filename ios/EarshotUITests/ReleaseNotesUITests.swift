// Tests the actual native app's first-install and manual notes flow, not headphone hardware.
import XCTest

final class ReleaseNotesUITests: XCTestCase {
    func testFreshInstallKeepsOnboardingClearAndNotesCanReopenAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let demo = app.buttons["tryDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["What’s new"].exists)
        reveal(demo, in: app)
        demo.tap()
        XCTAssertTrue(app.navigationBars["earshot"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["What’s new"].exists)
        openNotes(in: app)
        XCTAssertTrue(app.staticTexts["releaseNotesCredits"].label.contains("HellzYeahh"))
        XCTAssertTrue(app.staticTexts["releaseNotesCredits"].label.contains("AI-assisted"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Native release notes preserve original Earshot attribution"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars["What’s new"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["About & credits"].waitForExistence(timeout: 5))
        reveal(app.buttons["openReleaseNotes"], in: app)
        app.buttons["openReleaseNotes"].tap()
        XCTAssertTrue(app.navigationBars["What’s new"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.navigationBars["earshot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo device"].exists)
        XCTAssertFalse(app.navigationBars["What’s new"].exists)
        openNotes(in: app)
    }

    private func openNotes(in app: XCUIApplication) {
        let compact = app.tabBars.buttons["Settings"]
        let settings = compact.exists ? compact : app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let about = app.buttons["About & credits"]
        reveal(about, in: app)
        about.tap()
        XCTAssertTrue(app.navigationBars["About & credits"].waitForExistence(timeout: 5))
        let notes = app.buttons["openReleaseNotes"]
        reveal(notes, in: app)
        notes.tap()
        XCTAssertTrue(app.navigationBars["What’s new"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            let screen = app.frame
            let navigation = app.navigationBars.allElementsBoundByIndex.last { $0.isHittable && !$0.frame.isEmpty }
            let top = max(screen.minY + 24, (navigation?.frame.maxY ?? screen.minY) + 8)
            let tabs = app.tabBars.firstMatch
            let bottom = tabs.exists && tabs.frame.minY > screen.midY ? tabs.frame.minY - 12 : screen.maxY - 32
            let frame = element.exists ? element.frame : .zero
            if element.exists, element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
            let distance = frame.isEmpty ? CGFloat(150) : min(CGFloat(150), max(36, frame.maxY - bottom + 12))
            let middle = (top + bottom) / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: 8, dy: middle + distance / 2))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 8, dy: middle - distance / 2)),
                       withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTFail("Expected the release-notes control fully clear of the native tab bar: \(element)")
    }
}
