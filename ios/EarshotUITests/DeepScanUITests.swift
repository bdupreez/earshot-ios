// AI-assisted native port of HellzYeahh/earshot (MIT). Original contributors retain credit.
import XCTest

final class DeepScanUITests: XCTestCase {
    func testSelectedAndDeepScanPlansAreLocalAndCannotSendInDemo() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let demo = app.buttons["tryDemo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        reveal(demo, in: app)
        demo.tap()
        XCTAssertTrue(app.staticTexts["Demo device"].waitForExistence(timeout: 5))
        let tools = app.tabBars.buttons["Tools"]
        (tools.exists ? tools : app.buttons.matching(NSPredicate(format: "label == %@", "Tools")).firstMatch).tap()
        let lab = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Protocol lab")).firstMatch
        reveal(lab, in: app)
        lab.tap()
        let diagnostics = app.buttons["Capability scan and console"]
        reveal(diagnostics, in: app)
        diagnostics.tap()
        XCTAssertTrue(app.navigationBars["Protocol diagnostics"].waitForExistence(timeout: 5))
        app.buttons["scanPlan"].tap()
        app.buttons["Selected blocks"].tap()
        assertPlannedCount(121, in: app)
        let blocks = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Function blocks")).firstMatch
        blocks.tap()
        let audioModes = app.switches["scanBlock.31"]
        reveal(audioModes, in: app)
        let frame = audioModes.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.maxX - 25, dy: frame.midY)).tap()
        XCTAssertEqual(audioModes.value as? String, "0")
        assertPlannedCount(82, in: app)
        reveal(app.buttons["scanPlan"], in: app, towardTop: true)
        app.buttons["scanPlan"].tap()
        app.buttons["Deep GET discovery"].tap()
        assertPlannedCount(3897, in: app)
        let exclusions = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Choosing a plan sends nothing.")).firstMatch
        reveal(exclusions, in: app)
        XCTAssertTrue(exclusions.label.contains("Firmware, authentication and Print"))
        let estimate = app.staticTexts["scanEstimate"]
        reveal(estimate, in: app)
        XCTAssertTrue(estimate.label.contains("72 minutes"))
        XCTAssertTrue(estimate.label.contains("backgrounding or disconnecting cancels"))
        let start = app.buttons["startReadOnlyScan"]
        reveal(start, in: app)
        XCTAssertFalse(start.isEnabled)
        let progress = app.staticTexts["scanProgress"]
        reveal(progress, in: app)
        XCTAssertEqual(progress.label, "0 / 0 queries completed")
        XCTAssertEqual(app.staticTexts["scanStatus"].label, "No scan has started.")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Deep GET scan planning stays local and offline in demo"
        capture.lifetime = .keepAlways
        add(capture)
    }

    private func assertPlannedCount(_ count: Int, in app: XCUIApplication) {
        reveal(app.staticTexts["scanPlannedCount"], in: app)
        // SwiftUI can localize integer interpolation with a grouping separator.
        // Both labels represent the same exact count, rather than a substring match.
        let expected = Set(["\(count) planned GET queries", "\(count.formatted(.number)) planned GET queries"])
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let row = app.staticTexts["scanPlannedCount"]
            return row.exists && expected.contains(row.label)
        }, object: nil)
        let result = XCTWaiter.wait(for: [matches], timeout: 5)
        XCTAssertEqual(result, .completed,
                       "Expected exactly \(count) planned GET queries; actual row: \(app.staticTexts["scanPlannedCount"].debugDescription)\n\(app.debugDescription)")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, towardTop: Bool = false) {
        var up = !towardTop
        for _ in 0..<24 {
            let screen = app.frame
            let navigation = app.navigationBars.allElementsBoundByIndex.first { $0.isHittable && !$0.frame.isEmpty }
            let top = max(screen.minY + 24, (navigation?.frame.maxY ?? screen.minY) + 8)
            var bottom = screen.maxY - 32
            let bar = app.tabBars.firstMatch
            if bar.exists, bar.isHittable, bar.frame.minY > screen.midY { bottom = min(bottom, bar.frame.minY - 12) }
            var distance = min(CGFloat(180), (bottom - top) * 0.35)
            if element.exists, !element.frame.isEmpty {
                let frame = element.frame
                if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
                if frame.minY < top { up = false; distance = min(distance, max(36, top - frame.minY + 12)) }
                else if frame.maxY > bottom { up = true; distance = min(distance, max(36, frame.maxY - bottom + 12)) }
            }
            let middle = (top + bottom) / 2
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: 8, dy: middle + (up ? distance / 2 : -distance / 2)))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: 8, dy: middle + (up ? -distance / 2 : distance / 2))),
                       withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTFail("Expected a fully visible local scan-plan control: \(element)")
    }
}
