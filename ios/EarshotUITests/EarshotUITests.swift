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
        let before = reported.label + String(describing: reported.value)
        app.sliders["Headphone volume"].adjust(toNormalizedSliderPosition: 0.9)
        XCTAssertNotEqual(reported.label + String(describing: reported.value), before)
        app.buttons["Play"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Playing · simulated")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Paused · simulated")).firstMatch.waitForExistence(timeout: 5))
        let leAudio = app.switches["LE Audio"]
        reveal(leAudio)
        let prior = leAudio.value as? String
        print("LE Audio switch frame: \(leAudio.frame)")
        attachScreenshot("Device controls before requesting LE Audio")
        tapSwitchKnob(leAudio)
        XCTAssertTrue(app.buttons["Change LE Audio and restart"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertEqual(leAudio.value as? String, prior)
        tapSwitchKnob(leAudio)
        app.buttons["Change LE Audio and restart"].tap()
        XCTAssertNotEqual(leAudio.value as? String, prior)
        let power = app.buttons["Power off headphones"]
        reveal(power)
        power.tap()
        XCTAssertTrue(app.buttons["Power off"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Power off"].waitForNonExistence(timeout: 5))
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
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        if let value = field.value as? String, !value.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        field.typeText(text)
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "Expected a reachable control: \(element)")
    }

    private func button(startingWith title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func selectTab(_ title: String) {
        let item = app.tabBars.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(item.isHittable, "Dismiss the presented screen before switching tabs.")
        item.tap()
        if title == "Home" { XCTAssertTrue(app.navigationBars["earshot"].waitForExistence(timeout: 5), app.debugDescription) }
    }

    private func tapSwitchKnob(_ toggle: XCUIElement) {
        let frame = toggle.frame
        XCTAssertFalse(frame.isEmpty)
        // SwiftUI may expose the label and toggle as one wide switch element. Its control
        // is at the trailing edge; tap the knob rather than the row's empty center.
        let point = CGVector(dx: frame.maxX - min(25, frame.width / 2), dy: frame.midY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
