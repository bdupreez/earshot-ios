// Original configurable mode cycle: HellzYeahh/earshot (MIT). Native demo state only.
import XCTest

final class ModeCycleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    func testCustomConfiguredModeCycleWrapsAndPersistsInDemo() {
        app.launch()
        let demo = app.buttons["tryDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        reveal(demo); demo.tap()
        if app.buttons["dismissReleaseNotes"].waitForExistence(timeout: 2) { app.buttons["dismissReleaseNotes"].tap() }
        selectTab("Modes")
        let edit = app.buttons["editMode.4"]
        reveal(edit); edit.tap()
        let name = app.textFields["modeName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: "Cycle office")
        app.buttons["saveMode"].tap()
        XCTAssertTrue(app.navigationBars["Custom mode"].waitForNonExistence(timeout: 5))
        openCycle()
        let aware = app.switches["cycleMode.1"], custom = app.switches["cycleMode.4"]
        setSwitch(aware, on: true)
        setSwitch(custom, on: true)
        XCTAssertEqual(aware.value as? String, "1")
        XCTAssertEqual(custom.value as? String, "1")
        let order = app.staticTexts["modeCycleOrder"]
        reveal(order)
        XCTAssertTrue(order.label.contains("Aware → Cycle office → Aware"))
        cycleAndExpect("Aware")
        cycleAndExpect("Cycle office")
        app.terminate()
        app.launchArguments = []
        app.launch()
        openCycle()
        XCTAssertEqual(app.switches["cycleMode.1"].value as? String, "1")
        XCTAssertEqual(app.switches["cycleMode.4"].value as? String, "1")
        cycleAndExpect("Aware")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Configured custom mode cycle persisted and wrapped in demo"; shot.lifetime = .keepAlways; add(shot)
    }

    private func cycleAndExpect(_ mode: String) {
        let cycle = app.buttons["cycleModesNow"]
        reveal(cycle); XCTAssertTrue(cycle.isEnabled); cycle.tap()
        let result = app.staticTexts["cycleResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let current = app.descendants(matching: .any).matching(identifier: "cycleCurrentMode").firstMatch
        let changed = expectation(for: NSPredicate(format: "value == %@ OR label CONTAINS %@", mode, mode), evaluatedWith: current)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    private func openCycle() {
        selectTab("Settings")
        let open = app.buttons["openModeCycle"]
        reveal(open); open.tap()
        XCTAssertTrue(app.navigationBars["Mode cycle"].waitForExistence(timeout: 5))
    }

    private func selectTab(_ name: String) {
        let bar = app.tabBars.buttons[name]
        let target = bar.exists ? bar : app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5)); target.tap()
    }

    private func replaceText(_ field: XCUIElement, with text: String) {
        reveal(field); field.tap(); field.press(forDuration: 1.1)
        let item = app.menuItems["Select All"], button = app.buttons["Select All"]
        let selectAll = item.exists ? item : button
        if selectAll.waitForExistence(timeout: 2), selectAll.isHittable {
            selectAll.tap(); field.typeText(XCUIKeyboardKey.delete.rawValue)
        } else {
            let cutItem = app.menuItems["Cut"], cutButton = app.buttons["Cut"]
            let cut = cutItem.exists ? cutItem : cutButton
            XCTAssertTrue(cut.waitForExistence(timeout: 2)); cut.tap()
        }
        let cleared = field.value as? String ?? ""
        XCTAssertTrue(cleared.isEmpty || cleared == field.placeholderValue)
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
        if app.keyboards.buttons["Return"].exists { app.keyboards.buttons["Return"].tap() }
        else if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
    }

    private func setSwitch(_ element: XCUIElement, on: Bool) {
        reveal(element)
        guard (element.value as? String == "1") != on else { return }
        let frame = element.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.maxX - min(25, frame.width / 2), dy: frame.midY)).tap()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<20 {
            let frame = app.frame
            let navBottom = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map { $0.frame.maxY }.max() ?? frame.minY + 20
            let bar = app.tabBars.firstMatch
            let fallbackTab = app.buttons.matching(NSPredicate(format: "label == %@", "Home")).firstMatch
            var bottom = frame.maxY - 30, top = navBottom + 8
            if bar.exists, bar.isHittable {
                if bar.frame.minY > frame.midY { bottom = min(bottom, bar.frame.minY - 8) }
                else { top = max(top, bar.frame.maxY + 8) }
            } else if fallbackTab.exists, fallbackTab.isHittable, fallbackTab.frame.minY > frame.midY { bottom = min(bottom, fallbackTab.frame.minY - 16) }
            if app.keyboards.firstMatch.exists { bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 8) }
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            let scrollDown = !element.exists || element.frame.midY >= bottom
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let middle = (top + bottom) / 2, travel = min(140, (bottom - top) * 0.4)
            let start = middle + (scrollDown ? travel / 2 : -travel / 2)
            let end = middle - (scrollDown ? travel / 2 : -travel / 2)
            origin.withOffset(CGVector(dx: frame.minX + 8, dy: start)).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: frame.minX + 8, dy: end)), withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTFail("Could not reveal \(element)")
    }
}
