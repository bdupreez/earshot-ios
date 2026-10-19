// AI-assisted iOS port attempt of HellzYeahh/earshot (MIT). Original contributors retain credit.
// This checks the local simulated quick switcher, not physical headphone interoperability.
import XCTest

final class QuickSwitcherUITests: XCTestCase {
    func testHomeQuickSwitcherSelectsAndPersistsSimulatedEarbuds() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let demo = app.buttons["tryDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        reveal(demo, in: app)
        demo.tap()
        XCTAssertTrue(app.staticTexts["Demo device"].waitForExistence(timeout: 5))
        let switcher = app.buttons["headphoneSwitcher"]
        reveal(switcher, in: app)
        XCTAssertTrue(switcher.label.contains("QC Ultra Headphones"))
        switcher.tap()
        XCTAssertTrue(app.navigationBars["Switch headphones"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["switchDemo.ultra2"].value as? String, "Selected")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Switch headphones"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["headphoneSwitcher"].label.contains("QC Ultra Headphones"))

        app.buttons["headphoneSwitcher"].tap()
        XCTAssertTrue(app.navigationBars["Switch headphones"].waitForExistence(timeout: 5))
        let earbuds = app.buttons["switchDemo.budsII"]
        reveal(earbuds, in: app)
        XCTAssertTrue(earbuds.label.contains("Simulated demo profile"))
        earbuds.tap()
        XCTAssertTrue(app.navigationBars["Switch headphones"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["earshot"].exists)
        XCTAssertTrue(app.buttons["headphoneSwitcher"].label.contains("QC Earbuds II"))
        XCTAssertTrue(app.staticTexts["Demo device"].exists)
        for component in ["Left", "Right", "Case"] {
            reveal(app.staticTexts[component], in: app)
            XCTAssertTrue(app.staticTexts[component].exists)
        }
        reveal(app.buttons["mode.1"], in: app)
        XCTAssertTrue(app.buttons["mode.1"].label.contains("Aware"))
        XCTAssertFalse(app.buttons["mode.2"].exists, "This demo model has two built-in modes; unconfigured custom slots are not Home buttons.")

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["headphoneSwitcher"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["headphoneSwitcher"].label.contains("QC Earbuds II"))
        reveal(app.buttons["headphoneSwitcher"], in: app)
        app.buttons["headphoneSwitcher"].tap()
        XCTAssertTrue(app.navigationBars["Switch headphones"].waitForExistence(timeout: 5))
        reveal(app.buttons["switchDemo.budsII"], in: app)
        XCTAssertEqual(app.buttons["switchDemo.budsII"].value as? String, "Selected")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Home quick switcher preserves the explicitly simulated earbuds profile"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Switch headphones"].waitForNonExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<16 {
            let screen = app.frame
            let navigation = app.navigationBars.allElementsBoundByIndex.first { $0.isHittable && !$0.frame.isEmpty }
            let top = max(screen.minY + 24, (navigation?.frame.maxY ?? screen.minY) + 8)
            var bottom = screen.maxY - 32
            let tabBar = app.tabBars.firstMatch
            if tabBar.exists, tabBar.isHittable, tabBar.frame.minY > screen.midY { bottom = min(bottom, tabBar.frame.minY - 12) }
            var towardTop = false
            var distance = min(CGFloat(170), (bottom - top) * 0.3)
            if element.exists, !element.frame.isEmpty {
                let frame = element.frame
                if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
                if frame.minY < top { towardTop = true; distance = min(distance, max(36, top - frame.minY + 12)) }
                else if frame.maxY > bottom { distance = min(distance, max(36, frame.maxY - bottom + 12)) }
            }
            let middle = (top + bottom) / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let startY = middle + (towardTop ? -distance / 2 : distance / 2)
            let endY = middle + (towardTop ? distance / 2 : -distance / 2)
            origin.withOffset(CGVector(dx: 8, dy: startY))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: 8, dy: endY)),
                       withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTFail("Expected a fully visible quick-switcher control: \(element)")
    }
}
