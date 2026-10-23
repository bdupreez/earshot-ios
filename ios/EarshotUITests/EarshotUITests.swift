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

    func testHomeANCRepeatedDragsCommitFinalDemoLevelAndPersist() throws {
        launchDemo()
        let level = app.sliders["noiseLevel"]
        XCTAssertTrue(level.waitForExistence(timeout: 5))
        for target: CGFloat in [0.2, 0.9, 0.3, 0.8, 0.7] {
            reveal(level)
            let frame = level.frame
            let inset = min(CGFloat(18), frame.width / 4)
            let travel = frame.width - 2 * inset
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: frame.minX + inset + travel * level.normalizedSliderPosition, dy: frame.midY))
            let end = origin.withOffset(CGVector(dx: frame.minX + inset + travel * target, dy: frame.midY))
            start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            XCTAssertFalse(app.alerts.firstMatch.exists, "A native Home gesture should complete without a command error in demo.")
        }
        let finalLevel = NSPredicate(format: "label == %@", "7/10")
        XCTAssertTrue(app.staticTexts.matching(finalLevel).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        selectTab("Tools")
        selectTab("Home")
        reveal(level)
        XCTAssertTrue(app.staticTexts["7/10"].exists)
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo device"].waitForExistence(timeout: 5))
        reveal(app.sliders["noiseLevel"])
        XCTAssertTrue(app.staticTexts["7/10"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attachScreenshot("Home ANC gesture final level persists in demo — hardware queue behavior requires device testing")
    }

    func testAllHeadphoneEQBandDragsCommitAndPersistFinalDemoValues() throws {
        launchDemo()
        selectTab("Sound")
        XCTAssertTrue(app.buttons["Headphone EQ"].waitForExistence(timeout: 5))
        func dragBand(_ slider: XCUIElement, to position: CGFloat) {
            reveal(slider)
            let frame = slider.frame
            XCTAssertGreaterThan(frame.width, 50)
            let inset = min(CGFloat(18), frame.width / 4)
            let track = frame.width - 2 * inset
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: frame.minX + inset + track * slider.normalizedSliderPosition, dy: frame.midY))
            // Carry the finger beyond the native control bounds for a clamped
            // end stop, allowing for the thumb's expanded tracking appearance.
            let targetX = position == 0 ? max(2, frame.minX - 30) : position == 1 ? min(app.frame.maxX - 2, frame.maxX + 30) : frame.minX + inset + track * position
            let end = origin.withOffset(CGVector(dx: targetX, dy: frame.midY))
            print("EQ finger drag \(slider.label): frame \(frame), target fraction \(position), endpoint x\(targetX)")
            // Intermediate drags exercise repeated changes. Exact assertions use
            // physical end stops beyond the thumb's travel, without assuming that
            // an estimated pixel position maps to a precise midrange integer tick.
            start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            XCTAssertTrue(app.navigationBars["Sound"].exists, "The EQ finger drag must remain on Sound.\n\(app.debugDescription)")
        }
        let bands: [(String, CGFloat)] = [("Bass", 1), ("Mid", 0), ("Treble", 1)]
        for (name, finalPosition) in bands {
            let slider = app.sliders[name]
            XCTAssertTrue(slider.waitForExistence(timeout: 5))
            for position: CGFloat in [0.2, 0.85, finalPosition] {
                dragBand(slider, to: position)
                XCTAssertFalse(app.alerts.firstMatch.exists, "Demo \(name) gestures should not show command errors.")
            }
            XCTAssertEqual(slider.normalizedSliderPosition, finalPosition, accuracy: 0.001, "\(name) should retain its exact final committed demo limit; frame \(slider.frame), AX value \(String(describing: slider.value)).\n\(app.debugDescription)")
            XCTAssertTrue(app.staticTexts[String(format: "%+.0f dB", Double(finalPosition) * 20 - 10)].exists)
        }
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Demo device"].waitForExistence(timeout: 5))
        selectTab("Sound")
        for (name, finalPosition) in bands {
            let slider = app.sliders[name]
            reveal(slider)
            XCTAssertEqual(slider.normalizedSliderPosition, finalPosition, accuracy: 0.001, "\(name)'s exact limit must persist after relaunch.")
            XCTAssertTrue(app.staticTexts[String(format: "%+.0f dB", Double(finalPosition) * 20 - 10)].exists)
        }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attachScreenshot("Native EQ finger drags preserve exact signed limits after relaunch in demo — Bluetooth requires device testing")
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
        func playbackDiagnostics() -> String {
            let tabs = app.tabBars.firstMatch
            let tabFrame = tabs.exists ? String(describing: tabs.frame) : "No TabBar element"
            return "Play frame: \(play.frame), label: \(play.label), enabled: \(play.isEnabled), hittable: \(play.isHittable); app frame: \(app.frame); tab bar: \(tabFrame)\n\(app.debugDescription)"
        }
        XCTAssertTrue(play.waitForExistence(timeout: 5), playbackDiagnostics())
        // Loading the sample adds progress/seek controls and changes the player's height.
        // Reveal Play after that layout change so the floating tab bar cannot intercept it.
        reveal(play)
        XCTAssertTrue(play.isEnabled, playbackDiagnostics())
        XCTAssertTrue(play.isHittable, playbackDiagnostics())
        play.tap()
        let playing = NSPredicate(format: "label CONTAINS %@", "Pause")
        let playingExpectation = XCTNSPredicateExpectation(predicate: playing, object: play)
        guard XCTWaiter.wait(for: [playingExpectation], timeout: 5) == .completed else {
            attachScreenshot("Audio playback failed to start — control layout and status")
            XCTFail("Expected real playback to expose Pause. \(playbackDiagnostics())")
            return
        }
        XCTAssertTrue(play.label.contains("Pause"), playbackDiagnostics())
        attachScreenshot("Real AVAudioEngine playback running")
        reveal(play)
        play.tap()
        XCTAssertTrue(play.label.contains("Play"), playbackDiagnostics())
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Commute rule → applied in demo")).firstMatch.waitForExistence(timeout: 5))
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
        let restart = app.buttons["Change LE Audio and restart"]
        XCTAssertTrue(restart.waitForExistence(timeout: 5), app.debugDescription)
        dismissConfirmation(restart)
        XCTAssertEqual(leAudio.value as? String, prior)
        tapSwitchKnob(leAudio)
        XCTAssertTrue(restart.waitForExistence(timeout: 5))
        restart.tap()
        XCTAssertTrue(restart.waitForNonExistence(timeout: 5))
        // Popover dismissal can leave one stale switch snapshot on iPad. Wait
        // for its actual reported value rather than weakening the change check.
        let changedLEAudio = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", prior ?? "1"), object: leAudio)
        XCTAssertEqual(XCTWaiter.wait(for: [changedLEAudio], timeout: 5), .completed, app.debugDescription)
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
        let progress = app.progressIndicators["micPlaybackProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.label, "Recording playback progress")
        let advanced = NSPredicate { _, _ in
            guard let value = progress.value as? String,
                  let elapsed = Double(value.components(separatedBy: " of ").first ?? "") else { return false }
            return elapsed >= 0.7 && elapsed < duration
        }
        expectation(for: advanced, evaluatedWith: progress)
        waitForExpectations(timeout: 4)
        let reportedTime = (progress.value as? String ?? "").components(separatedBy: " of ")
        XCTAssertEqual(reportedTime.count, 2)
        let reportedTotal = Double(reportedTime.last?.replacingOccurrences(of: " seconds", with: "") ?? "") ?? 0
        XCTAssertEqual(reportedTotal, duration, accuracy: 0.15)
        attachScreenshot("Real microphone recording playback with actual elapsed and total progress")
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

    func testHeadsetCompanionCyclesLocalEQAndShowsHonestRouteBoundary() throws {
        launchDemo()
        selectTab("Tools")
        let link = button(startingWith: "Headset companion")
        reveal(link); link.tap()
        XCTAssertTrue(app.navigationBars["Headset companion"].waitForExistence(timeout: 5))
        let cycle = app.buttons["companionCycleEQ"]
        reveal(cycle); cycle.tap()
        XCTAssertTrue(app.staticTexts["companionStatus"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attachScreenshot("Field headset companion — native route picker, output EQ memory and local actions")
    }

    func testSoundcoreSleepDemoUsesDocumentedControlsWithoutLiveConnection() throws {
        app.launchArguments = ["--uitesting", "--demo-profile=soundcore.D1301"]
        app.launch()
        dismissReleaseNotesIfPresented()
        XCTAssertTrue(tabButton("Home").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Demo device"].exists)
        let listening = app.buttons["soundcoreControl.listening_mode"]
        reveal(listening); listening.tap()
        let sounds = app.buttons["Local sounds"]
        XCTAssertTrue(sounds.waitForExistence(timeout: 3), app.debugDescription)
        sounds.tap()
        let result = app.staticTexts["soundcoreSimulationResult"]
        reveal(result)
        XCTAssertTrue(result.label.contains("No physical command was sent"), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attachScreenshot("Soundcore Sleep A30 local setting round-trip — no physical command")
    }

    func testSennheiserCatalogueDemoAndResearchAreSeparateFromPhysicalControl() throws {
        app.launchArguments = ["--uitesting", "--demo-profile=sennheiser.momentum4"]
        app.launch()
        dismissReleaseNotesIfPresented()
        XCTAssertTrue(tabButton("Home").waitForExistence(timeout: 10))
        app.swipeUp()
        let slider = app.sliders["vendorControl.noiseLevel"]
        reveal(slider)
        XCTAssertTrue(slider.exists, app.debugDescription)
        slider.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attachScreenshot("Momentum 4 local fixture — native controls with original research attribution")
    }

    func testVoiceMemoFinalizesBeforeLocalPlaybackAndSurvivesNavigation() throws {
        launchDemo(); selectTab("Tools")
        let link = button(startingWith: "Headset companion")
        reveal(link); link.tap()
        let record = app.buttons["companionRecordMemo"]
        reveal(record); record.tap()
        XCTAssertTrue(app.buttons["Stop and save memo"].waitForExistence(timeout: 5), app.debugDescription)
        let elapsed = app.descendants(matching: .any).matching(identifier: "companionMemoElapsed").firstMatch
        let recorded = NSPredicate(format: "value MATCHES %@", "([2-9]|[1-9][0-9]+) seconds")
        expectation(for: recorded, evaluatedWith: elapsed)
        waitForExpectations(timeout: 8)
        selectTab("Sound")
        app.buttons["Pro EQ"].tap()
        let load = app.buttons["loadSample"]
        reveal(load); load.tap()
        let play = app.buttons["playAudio"]
        reveal(play); play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 4))
        selectTab("Tools")
        XCTAssertTrue(record.waitForExistence(timeout: 4)); reveal(record)
        XCTAssertEqual(record.label, "Record voice memo", "Starting local playback must finalize the live memo first.")
        let memo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "companionPlayMemo.")).firstMatch
        reveal(memo); XCTAssertTrue(memo.exists)
        attachScreenshot("Real Simulator voice memo finalized before local playback — physical headset input unverified")
    }

    func testBatteryCompanionExplainsSelectionAndDoesNotRequireDiscoveryToOpen() throws {
        launchDemo(); selectTab("Tools")
        let link = button(startingWith: "Battery companion")
        reveal(link); link.tap()
        XCTAssertTrue(app.navigationBars["Battery companion"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["discoverBatterySources"].exists)
        XCTAssertTrue(app.staticTexts["batteryCompanionStatus"].label.contains("Choose Discover"))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attachScreenshot("Read-only battery companion before user-initiated Bluetooth discovery")
    }

    private func dismissReleaseNotesIfPresented() {
        let done = app.buttons["dismissReleaseNotes"]
        if done.waitForExistence(timeout: 2) { done.tap() }
    }

    private func launchDemo() {
        app.launch()
        XCTAssertTrue(app.buttons["tryDemo"].waitForExistence(timeout: 10))
        reveal(app.buttons["tryDemo"])
        app.buttons["tryDemo"].tap()
        dismissReleaseNotesIfPresented()
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
