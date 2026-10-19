// AI-assisted iOS port attempt of HellzYeahh/earshot. Original Earshot contributors retain credit.
// Upstream: https://github.com/HellzYeahh/earshot — MIT; see THIRD_PARTY_NOTICES.md.
import XCTest

final class EarshotUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    func testWelcomeAndDemoModeSwitching() throws {
        app.launch()
        XCTAssertTrue(app.buttons["tryDemo"].waitForExistence(timeout: 10))
        reveal(app.buttons["tryDemo"])
        app.buttons["tryDemo"].tap()
        XCTAssertTrue(app.staticTexts["Demo device"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["noiseLevel"].exists)
        let aware = app.buttons["mode.1"]
        XCTAssertTrue(aware.exists)
        reveal(aware)
        aware.tap()
        XCTAssertTrue(app.staticTexts["currentMode"].label.contains("Aware"))
        app.buttons["mode.0"].tap()
        XCTAssertTrue(app.staticTexts["currentMode"].label.contains("Quiet"))
        attachScreenshot("Home — demo with Quiet selected")
    }

    func testRealConnectionExplainsSimulatorHardwareLimit() throws {
        app.launch()
        let connect = app.buttons["connectHeadphones"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        reveal(connect)
        connect.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Bluetooth hardware needs a physical iPhone")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Demo device"].exists)
        selectTab("Tools")
        button(startingWith: "Connection").tap()
        XCTAssertTrue(app.buttons["scanHeadphones"].exists)
        attachScreenshot("Real discovery gives an honest Simulator hardware limitation")
    }

    func testEarbudDemoShowsSeparateBatteryReadings() throws {
        launchDemo()
        selectTab("Settings")
        let preferences = button(startingWith: "App preferences")
        reveal(preferences)
        preferences.tap()
        button(startingWith: "Demo headphone").tap()
        app.buttons["QC Ultra Earbuds · 2nd Gen"].tap()
        selectTab("Home")
        XCTAssertTrue(app.staticTexts["Left"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Right"].exists)
        XCTAssertTrue(app.staticTexts["Case"].exists)
        XCTAssertTrue(app.staticTexts["QC Ultra Earbuds · 2nd Gen"].exists)
        attachScreenshot("Earbud profile with simulated left, right and case battery")
    }

    func testCustomModeEditsSurviveRelaunch() throws {
        launchDemo()
        selectTab("Modes")
        let edit = app.buttons["editMode.4"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        reveal(edit)
        edit.tap()
        let name = app.textFields["modeName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(in: name, with: "Morning commute")
        app.buttons["saveMode"].tap()
        XCTAssertTrue(app.staticTexts["Morning commute"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertFalse(app.buttons["tryDemo"].exists)
        selectTab("Modes")
        XCTAssertTrue(app.staticTexts["Morning commute"].waitForExistence(timeout: 5))
        attachScreenshot("Custom listening mode persisted after relaunch")
    }

    func testToolsAndCompatibilityNavigation() throws {
        launchDemo()
        selectTab("Tools")
        button(startingWith: "Connection").tap()
        XCTAssertTrue(app.navigationBars["Connection"].waitForExistence(timeout: 5))
        attachScreenshot("Connection route information")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        button(startingWith: "Microphone check").tap()
        XCTAssertTrue(app.navigationBars["Microphone check"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["recordMic"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        button(startingWith: "Protocol lab").tap()
        XCTAssertTrue(app.navigationBars["Protocol lab"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        button(startingWith: "iOS compatibility").tap()
        XCTAssertTrue(app.navigationBars["iOS compatibility"].waitForExistence(timeout: 5))
        attachScreenshot("Honest iOS compatibility limits")
    }

    func testCreditsAcknowledgeUpstreamAndAIAssistance() throws {
        launchDemo()
        selectTab("Settings")
        let about = button(startingWith: "About & credits")
        reveal(about)
        about.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "AI-assisted")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Original Earshot — HellzYeahh & contributors")).firstMatch.exists)
        attachScreenshot("Original Earshot and AI-assisted port attribution")
    }

    func testSoundAndAutomationScreens() throws {
        launchDemo()
        selectTab("Sound")
        XCTAssertTrue(app.buttons["Headphone EQ"].waitForExistence(timeout: 5))
        app.buttons["Pro EQ"].tap()
        attachScreenshot("Native Pro EQ")
        selectTab("Settings")
        let automations = button(startingWith: "Automations")
        reveal(automations)
        automations.tap()
        XCTAssertTrue(app.navigationBars["Automations"].waitForExistence(timeout: 5))
        attachScreenshot("Automations")
    }

    func testNativeAudioSampleLoadsPlaysAndPauses() throws {
        launchDemo()
        selectTab("Sound")
        app.buttons["Pro EQ"].tap()
        let enabled = app.switches["Enable Pro EQ"]
        XCTAssertTrue(enabled.exists)
        enabled.tap()
        XCTAssertEqual(enabled.value as? String, "1")
        app.buttons["presetPicker"].tap()
        app.buttons["Bass boost"].tap()
        let load = app.buttons["loadSample"]
        reveal(load)
        load.tap()
        let play = app.buttons["playAudio"]
        XCTAssertTrue(play.isEnabled)
        play.tap()
        let playing = NSPredicate(format: "label CONTAINS %@", "Pause")
        expectation(for: playing, evaluatedWith: play)
        waitForExpectations(timeout: 5)
        attachScreenshot("Real AVAudioEngine playback running")
        play.tap()
        XCTAssertTrue(play.label.contains("Play"))
    }

    func testAutomationRunsChosenMode() throws {
        launchDemo()
        selectTab("Settings")
        let automations = button(startingWith: "Automations")
        reveal(automations)
        automations.tap()
        app.buttons["Add automation"].tap()
        let name = app.textFields["Rule name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(in: name, with: "Commute rule")
        button(startingWith: "Listening mode").tap()
        app.buttons["Aware"].tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Listening rule"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Commute rule"].waitForExistence(timeout: 5))
        app.buttons["Run now"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Commute rule → mode request sent")).firstMatch.waitForExistence(timeout: 5))
        selectTab("Home")
        reveal(app.staticTexts["currentMode"])
        XCTAssertTrue(app.staticTexts["currentMode"].label.contains("Aware"))
    }

    func testDeviceControlsVolumePlaybackAndRestartConfirmation() throws {
        launchDemo()
        selectTab("Settings")
        let controls = button(startingWith: "Device controls")
        reveal(controls)
        controls.tap()
        XCTAssertTrue(app.navigationBars["Device controls"].waitForExistence(timeout: 5))
        let reported = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Reported volume,")).firstMatch
        XCTAssertTrue(reported.exists)
        let before = reported.label
        let volume = app.sliders["Headphone volume"]
        reveal(volume)
        dragSliderThumb(volume, to: 0.9)
        XCTAssertTrue(app.navigationBars["Device controls"].exists, app.debugDescription)
        // A new device report replaces this SwiftUI row; wait for the new value
        // instead of requesting a second snapshot while the old row disappears.
        let changedVolume = app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label != %@", "Reported volume,", before
        )).firstMatch
        XCTAssertTrue(changedVolume.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Play"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Playing · simulated")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Paused · simulated")).firstMatch.waitForExistence(timeout: 5))
        let leAudio = app.switches["LE Audio"]
        reveal(leAudio)
        let prior = leAudio.value as? String
        attachScreenshot("Device controls before requesting LE Audio")
        tapSwitchKnob(leAudio)
        let restart = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "restart")).firstMatch
        XCTAssertTrue(restart.waitForExistence(timeout: 5), app.debugDescription)
        dismissConfirmation(restart)
        XCTAssertEqual(leAudio.value as? String, prior)
        tapSwitchKnob(leAudio)
        XCTAssertTrue(restart.waitForExistence(timeout: 5))
        restart.tap()
        XCTAssertNotEqual(leAudio.value as? String, prior)
        let power = app.buttons["Power off headphones"]
        reveal(power)
        power.tap()
        XCTAssertTrue(app.buttons["Power off"].waitForExistence(timeout: 5))
        dismissConfirmation(app.buttons["Power off"])
        attachScreenshot("Simulated device controls and confirmed LE Audio setting")
    }

    func testRealMicrophoneRecordingPlaybackAndDeletion() throws {
        launchDemo()
        selectTab("Tools")
        button(startingWith: "Microphone check").tap()
        let record = app.buttons["recordMic"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        if app.buttons["Delete"].isEnabled { app.buttons["Delete"].tap() }
        XCTAssertFalse(app.buttons["Play recording"].isEnabled)
        record.tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if permission.waitForExistence(timeout: 3) {
            permission.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        let playback = app.buttons["Play recording"]
        let ready = NSPredicate(format: "exists == true AND enabled == true")
        expectation(for: ready, evaluatedWith: playback)
        waitForExpectations(timeout: 15)
        let seconds = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " seconds")).firstMatch.label
        let duration = Double(seconds.split(separator: " ").first.map(String.init) ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(duration, 7.5)
        XCTAssertLessThanOrEqual(duration, 8.5)
        playback.tap()
        XCTAssertTrue(app.buttons["Stop playback"].waitForExistence(timeout: 5))
        app.buttons["Stop playback"].tap()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.buttons["Play recording"].isEnabled)
        XCTAssertTrue(app.staticTexts["Recording deleted from this device."].exists)
        attachScreenshot("Real microphone check completed and local clip deleted")
    }

    func testLightAndDarkAppearance() throws {
        launchDemo()
        selectTab("Settings")
        let preferences = button(startingWith: "App preferences")
        reveal(preferences)
        preferences.tap()
        let appearance = app.buttons["appearancePicker"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.tap()
        app.buttons["Light"].tap()
        XCTAssertTrue((appearance.label + String(describing: appearance.value)).contains("Light"))
        selectTab("Home")
        attachScreenshot("Home — light appearance")
        selectTab("Settings")
        appearance.tap()
        app.buttons["Dark"].tap()
        XCTAssertTrue((appearance.label + String(describing: appearance.value)).contains("Dark"))
        selectTab("Home")
        XCTAssertTrue(app.staticTexts["Demo device"].waitForExistence(timeout: 5))
        attachScreenshot("Home — dark appearance")
    }

    private func launchDemo() {
        app.launch()
        XCTAssertTrue(app.buttons["tryDemo"].waitForExistence(timeout: 10))
        reveal(app.buttons["tryDemo"])
        app.buttons["tryDemo"].tap()
        XCTAssertTrue(tabButton("Home").waitForExistence(timeout: 5))
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        if let value = field.value as? String, !value.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            let screen = app.frame
            var top = screen.minY + 20
            var bottom = screen.maxY - 20
            let navigation = app.navigationBars.firstMatch
            if navigation.exists, navigation.isHittable { top = max(top, navigation.frame.maxY + 8) }
            let bar = app.tabBars.firstMatch
            if bar.exists, bar.isHittable {
                if bar.frame.minY > screen.midY { bottom = min(bottom, bar.frame.minY - 12) }
                else { top = max(top, bar.frame.maxY + 8) }
            }
            if element.exists {
                let frame = element.frame
                if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
                if !frame.isEmpty, frame.minY < top { app.swipeDown(); continue }
            }
            // A translucent floating tab bar can leave an obscured row "hittable" in AX.
            // Ensure the entire control is clear of that overlay before interacting.
            app.swipeUp()
        }
        XCTFail("Expected a fully visible control: \(element)")
    }

    private func button(startingWith title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func selectTab(_ title: String) {
        let item = tabButton(title)
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(item.isHittable, "Dismiss the presented screen before switching tabs.")
        item.tap()
        if title == "Home" { XCTAssertTrue(app.navigationBars["earshot"].waitForExistence(timeout: 5), app.debugDescription) }
    }

    private func tabButton(_ title: String) -> XCUIElement {
        let compact = app.tabBars.buttons[title]
        if compact.exists { return compact }
        // iPad's floating top tabs expose semantic Buttons without a TabBar container.
        return app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func tapSwitchKnob(_ toggle: XCUIElement) {
        let frame = toggle.frame
        XCTAssertFalse(frame.isEmpty)
        // SwiftUI may expose the label and toggle as one wide switch element. Its control
        // is at the trailing edge; tap the knob rather than the row's empty center.
        let point = CGVector(dx: frame.maxX - min(25, frame.width / 2), dy: frame.midY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
    }

    private func dragSliderThumb(_ slider: XCUIElement, to position: CGFloat) {
        let frame = slider.frame
        XCTAssertGreaterThan(frame.width, 50)
        let normalized = slider.normalizedSliderPosition
        print("Slider drag frame: \(frame), current fraction: \(normalized)")
        // XCTest's adjust operation invoked interactive Back in a captured run.
        // Drag the visible thumb along its observed track instead.
        let inset = min(CGFloat(18), frame.width / 4)
        let track = frame.width - 2 * inset
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.minX + inset + track * normalized, dy: frame.midY))
        let finish = origin.withOffset(CGVector(dx: frame.minX + inset + track * position, dy: frame.midY))
        start.press(forDuration: 0.1, thenDragTo: finish)
    }

    private func dismissConfirmation(_ action: XCUIElement) {
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.tap()
        } else {
            // iOS 26 presents anchored confirmation popovers without a Cancel row.
            // Tapping the observed navigation title outside the popover cancels it.
            let navigation = app.navigationBars.firstMatch.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: navigation.midX, dy: navigation.midY)).tap()
        }
        XCTAssertTrue(action.waitForNonExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
