// AI-assisted iOS port attempt of HellzYeahh/earshot (MIT). Original contributors retain credit.
// These tests exercise native/local and explicitly simulated state, never physical headphone behavior.
import XCTest

final class FeatureGapUITests: XCTestCase {
    private var app: XCUIApplication!
    private enum ScrollDirection { case towardTop, towardBottom }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    func testUserPresetLifecyclePersistsAndDeletingActiveReturnsFlat() throws {
        launchDemo()
        openProEQ()
        tap(app.buttons["editPreset"])
        XCTAssertTrue(app.navigationBars["Edit preset copy"].waitForExistence(timeout: 5))
        replaceText(app.textFields["Name"], with: "Commute curve")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit preset copy"].waitForNonExistence(timeout: 5))
        assertValue(app.buttons["presetPicker"], contains: "Commute curve")

        tap(app.buttons["editPreset"])
        XCTAssertTrue(app.navigationBars["Edit preset"].waitForExistence(timeout: 5))
        replaceText(app.textFields["Name"], with: "Edited commute curve")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit preset"].waitForNonExistence(timeout: 5))
        assertValue(app.buttons["presetPicker"], contains: "Edited commute curve")

        tap(app.buttons["managePreset"])
        app.buttons["Rename"].tap()
        let rename = app.alerts["Rename preset"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        replaceText(rename.textFields["Preset name"], with: "Morning library", dismissKeyboard: false)
        rename.buttons["Rename"].tap()
        assertValue(app.buttons["presetPicker"], contains: "Morning library")
        relaunchPreservingState()
        openProEQ()
        assertValue(app.buttons["presetPicker"], contains: "Morning library")

        requestPresetDeletion()
        dismissPopover(action: app.buttons["Delete preset"])
        assertValue(app.buttons["presetPicker"], contains: "Morning library")
        requestPresetDeletion()
        app.buttons["Delete preset"].tap()
        assertValue(app.buttons["presetPicker"], contains: "Flat")
        relaunchPreservingState()
        openProEQ()
        assertValue(app.buttons["presetPicker"], contains: "Flat")
        tap(app.buttons["presetPicker"])
        XCTAssertFalse(app.buttons["Morning library"].exists)
        // A SwiftUI picker menu is exposed as a collection view on this OS,
        // rather than the confirmation popover's dismissal region. Selecting
        // the already-active item closes that native picker without ambiguity.
        app.buttons["Flat"].tap()
        screenshot("User preset deleted and Flat persisted after relaunch")
    }

    func testUnsavedPresetNameCanKeepEditingOrDiscardWithoutChangingSavedPreset() throws {
        launchDemo()
        openProEQ()
        tap(app.buttons["editPreset"])
        XCTAssertTrue(app.navigationBars["Edit preset copy"].waitForExistence(timeout: 5))
        replaceText(app.textFields["Name"], with: "Saved studio curve")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit preset copy"].waitForNonExistence(timeout: 5))
        assertValue(app.buttons["presetPicker"], contains: "Saved studio curve")

        tap(app.buttons["editPreset"])
        XCTAssertTrue(app.navigationBars["Edit preset"].waitForExistence(timeout: 5))
        replaceText(app.textFields["Name"], with: "Unsaved studio draft")
        app.navigationBars.buttons["Cancel"].tap()
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "The saved preset will stay unchanged.").exists)
        let keepEditing = app.buttons["Keep editing"]
        if keepEditing.exists, keepEditing.isHittable {
            keepEditing.tap()
        } else {
            // iOS can present this as a popover without its cancel-role row;
            // dismissing outside invokes the same keep-editing cancellation.
            dismissMenu()
        }
        XCTAssertTrue(discard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Edit preset"].exists)
        XCTAssertEqual(app.textFields["Name"].value as? String, "Unsaved studio draft")

        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(app.navigationBars["Edit preset"].waitForNonExistence(timeout: 5))
        assertValue(app.buttons["presetPicker"], contains: "Saved studio curve")
        relaunchPreservingState()
        openProEQ()
        assertValue(app.buttons["presetPicker"], contains: "Saved studio curve")
        tap(app.buttons["editPreset"])
        XCTAssertTrue(app.navigationBars["Edit preset"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Name"].value as? String, "Saved studio curve")
        screenshot("Discarded preset draft leaves the selected saved preset unchanged after relaunch")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit preset"].waitForNonExistence(timeout: 5))
    }

    func testGraphicConversionCanBeCancelledAndRestoredWithoutLosingFilters() throws {
        launchDemo()
        openProEQ()
        choosePreset("Bass boost")
        tap(app.buttons["editPreset"])
        XCTAssertTrue(app.navigationBars["Edit preset copy"].waitForExistence(timeout: 5))
        replaceText(app.textFields["Name"], with: "Reversible bass")
        let graphic = app.switches["10-band graphic layout"]
        setSwitch(graphic, on: true)
        let convert = app.buttons["Approximate with ten bands"]
        XCTAssertTrue(convert.waitForExistence(timeout: 5))
        dismissPopover(action: convert)
        XCTAssertEqual(graphic.value as? String, "0")
        XCTAssertTrue(app.navigationBars["Edit preset copy"].exists)
        setSwitch(graphic, on: true)
        XCTAssertTrue(convert.waitForExistence(timeout: 5))
        convert.tap()
        reveal(app.staticTexts["10 of 128 filters"])
        XCTAssertTrue(app.staticTexts["10 of 128 filters"].exists)
        let restore = app.buttons["Restore prior parametric filters"]
        reveal(restore, direction: .towardTop)
        restore.tap()
        reveal(graphic, direction: .towardTop)
        XCTAssertEqual(graphic.value as? String, "0")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Edit preset copy"].waitForNonExistence(timeout: 5))
        assertValue(app.buttons["presetPicker"], contains: "Reversible bass")
        tap(app.buttons["editPreset"])
        XCTAssertTrue(app.navigationBars["Edit preset"].waitForExistence(timeout: 5))
        for header in ["90 Hz · +5.0 dB", "60 Hz · +1.5 dB", "250 Hz · -1.0 dB"] {
            reveal(named(header))
            XCTAssertTrue(named(header).exists)
        }
        reveal(app.staticTexts["3 of 128 filters"])
        XCTAssertTrue(app.staticTexts["3 of 128 filters"].exists)
        tap(named("90 Hz · +5.0 dB"), direction: .towardTop)
        let type = button(startingWith: "Type")
        reveal(type)
        assertValue(type, contains: "Low shelf")
        XCTAssertTrue(app.staticTexts["0.7"].exists)
        screenshot("Restored parametric filter values survive saving")
        app.navigationBars.buttons["Cancel"].tap()
    }

    func testPastedAutoEQImportReportsDuplicatesAndKeepsActualFilters() throws {
        launchDemo()
        openProEQ()
        let text = "Preamp: -3.0 dB\nFilter 1: ON PK Fc 1000 Hz Gain 2.0 dB Q 1.00\nFilter 2: ON LSC Fc 120 Hz Gain -1.0 dB Q 0.70"
        importText(text, name: "Pasted studio")
        let imported = app.alerts["Earshot"]
        XCTAssertTrue(imported.waitForExistence(timeout: 5))
        XCTAssertTrue(imported.staticTexts["Imported 1 preset."].exists)
        imported.buttons["OK"].tap()
        assertValue(app.buttons["presetPicker"], contains: "Pasted studio")
        tap(app.buttons["editPreset"])
        XCTAssertTrue(app.navigationBars["Edit preset"].waitForExistence(timeout: 5))
        for header in ["1000 Hz · +2.0 dB", "120 Hz · -1.0 dB"] {
            reveal(named(header))
            XCTAssertTrue(named(header).exists)
        }
        reveal(app.staticTexts["2 of 128 filters"])
        XCTAssertTrue(app.staticTexts["2 of 128 filters"].exists)
        app.navigationBars.buttons["Cancel"].tap()
        importText(text, name: "Pasted studio")
        XCTAssertTrue(imported.waitForExistence(timeout: 5))
        XCTAssertTrue(imported.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Imported 0 presets.", "Skipped 1 existing duplicate.")).firstMatch.exists)
        screenshot("AutoEQ duplicate import explains the result")
        imported.buttons["OK"].tap()
        assertValue(app.buttons["presetPicker"], contains: "Pasted studio")
    }

    func testNativePlayerSeeksProgressesAndComparesOriginal() throws {
        launchDemo()
        openProEQ()
        setSwitch(app.switches["Enable Pro EQ"], on: true)
        choosePreset("Bass boost")
        tap(app.buttons["loadSample"])
        let position = app.sliders["Playback position"]
        reveal(position, direction: .towardTop)
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        dragSlider(position, from: 0, to: 0.45)
        waitUntil("Seeking must update the actual player position") { self.playbackSeconds(position) >= 4 && self.playbackSeconds(position) <= 7 }
        let sought = playbackSeconds(position)
        let play = app.buttons["playAudio"]
        tap(play)
        assertValue(play, contains: "Pause")
        waitUntil("Playing must advance beyond the sought position", timeout: 7) { self.playbackSeconds(position) >= sought + 1 }
        play.tap()
        assertValue(play, contains: "Play")
        let comparison = app.switches["compareOriginal"]
        setSwitch(comparison, on: true)
        XCTAssertTrue(text(containing: "Original audio: filters, preamp, boost and protection are bypassed.").exists)
        setSwitch(comparison, on: false)
        XCTAssertTrue(text(containing: "Listening with your current Pro EQ settings.").exists)
        tap(app.buttons["Stop audio"], direction: .towardTop)
        reveal(position, direction: .towardTop)
        waitUntil("Stopping must return the real player position to zero") { self.playbackSeconds(position) == 0 }
        screenshot("Native player seek, progress and A-B completed")
    }

    func testMultiActionRuleAppliesAwareNoiseAndLocalPreset() throws {
        launchDemo()
        openAutomations()
        app.buttons["Add automation"].tap()
        XCTAssertTrue(app.navigationBars["Listening rule"].waitForExistence(timeout: 5))
        replaceText(app.textFields["Rule name"], with: "Commute combination")
        tap(button(startingWith: "Trigger"))
        app.buttons["Manual / Shortcut"].tap()
        tap(button(startingWith: "Listening mode"))
        app.buttons["Aware"].tap()
        setSwitch(app.switches["Change noise controls"], on: true)
        let noise = app.sliders["noiseLevel"]
        reveal(noise)
        dragSlider(noise, from: noise.normalizedSliderPosition, to: 0.6)
        XCTAssertTrue(app.staticTexts["6/10"].exists)
        setSwitch(app.switches["Change local EQ"], on: true)
        tap(app.buttons["rulePresetPicker"])
        app.buttons["Bass boost"].tap()
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Listening rule"].waitForNonExistence(timeout: 5))
        let description = text(containing: "Mode: Aware · Noise: 6/10")
        reveal(description)
        XCTAssertTrue(description.label.contains("Local EQ: Bass boost"))
        tap(app.buttons["Run now"])
        XCTAssertTrue(app.staticTexts["Applied in demo"].waitForExistence(timeout: 5))
        selectTab("Home")
        reveal(app.staticTexts["currentMode"])
        XCTAssertTrue(app.staticTexts["currentMode"].label.contains("Aware"))
        reveal(app.sliders["noiseLevel"])
        XCTAssertTrue(app.staticTexts["6/10"].exists)
        openProEQ()
        assertValue(app.buttons["presetPicker"], contains: "Bass boost")
        XCTAssertEqual(app.switches["Enable Pro EQ"].value as? String, "1")
        screenshot("Demo multi-action rule applied mode, noise and local EQ")
    }

    func testWeekdayScheduleAndReminderChoicePersistAndExplainShortcuts() throws {
        launchDemo()
        openAutomations()
        app.buttons["Add automation"].tap()
        XCTAssertTrue(app.navigationBars["Listening rule"].waitForExistence(timeout: 5))
        replaceText(app.textFields["Rule name"], with: "Weekday commute")
        tap(button(startingWith: "Trigger"))
        app.buttons["Schedule (app open)"].tap()
        tap(named(startingWith: "Repeat on:"))
        setSwitch(app.switches["ruleWeekday.6"], on: false)
        setSwitch(app.switches["ruleWeekday.7"], on: false)
        setSwitch(app.switches["Remind me when Earshot is closed"], on: true)
        let reminderNote = text(containing: "Reminders are paused in demo mode")
        reveal(reminderNote)
        XCTAssertTrue(reminderNote.exists)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Listening rule"].waitForNonExistence(timeout: 5))
        relaunchPreservingState()
        openAutomations()
        tap(app.buttons["Weekday commute"])
        XCTAssertTrue(app.navigationBars["Listening rule"].waitForExistence(timeout: 5))
        assertValue(button(startingWith: "Trigger"), contains: "Schedule (app open)")
        tap(named(startingWith: "Repeat on:"))
        for day in 1...7 {
            let toggle = app.switches["ruleWeekday.\(day)"]
            reveal(toggle)
            XCTAssertEqual(toggle.value as? String, day <= 5 ? "1" : "0")
        }
        let reminder = app.switches["Remind me when Earshot is closed"]
        reveal(reminder)
        XCTAssertEqual(reminder.value as? String, "1")
        app.navigationBars.buttons["Cancel"].tap()
        tap(button(startingWith: "Use rules with Shortcuts"), direction: .towardTop)
        XCTAssertTrue(app.navigationBars["Shortcuts & controls"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Shortcuts owns those triggers").exists)
        let controls = text(containing: "On iOS 18 or later")
        reveal(controls)
        XCTAssertTrue(controls.label.contains("open Earshot"))
        screenshot("Weekday rule persistence and system Shortcuts guidance")
    }

    func testDemoDeviceRenameAndInstalledLanguagePersist() throws {
        launchDemo()
        openDeviceControls()
        replaceText(app.textFields["Name"], with: "Morning cans")
        XCTAssertEqual(app.textFields["Name"].value as? String, "Morning cans")
        tap(app.buttons["Save name"])
        XCTAssertEqual(app.textFields["Name"].value as? String, "Morning cans", "Saving must retain the requested name.")
        selectTab("Home")
        XCTAssertTrue(app.navigationBars["earshot"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Morning cans"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Demo device"].exists)
        selectTab("Settings")
        let language = button(startingWith: "Language")
        tap(language)
        app.buttons["French"].tap()
        assertValue(button(startingWith: "Language"), contains: "French", direction: .towardBottom)
        relaunchPreservingState()
        XCTAssertTrue(app.staticTexts["Morning cans"].waitForExistence(timeout: 5))
        openDeviceControls()
        assertValue(button(startingWith: "Language"), contains: "French", direction: .towardBottom)
        screenshot("Renamed demo device and installed language persisted")
    }

    func testDemoSourceConnectAndForgetRequireConfirmationAndChangeVirtualState() throws {
        launchDemo()
        openDeviceControls()
        let laptop = app.buttons["Manage Demo laptop"]
        tap(laptop)
        XCTAssertTrue(app.buttons["Connect source"].exists)
        app.buttons["Connect source"].tap()
        let connect = app.alerts["Connect source"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        connect.buttons["Cancel"].tap()
        tap(laptop)
        XCTAssertTrue(app.buttons["Connect source"].exists)
        XCTAssertFalse(app.buttons["Disconnect source"].exists)
        app.buttons["Connect source"].tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        connect.buttons["Connect source"].tap()
        tap(laptop)
        XCTAssertTrue(app.buttons["Disconnect source"].exists)
        XCTAssertTrue(app.buttons["Request active source"].exists)
        XCTAssertFalse(app.buttons["Connect source"].exists)
        app.buttons["Forget paired source"].tap()
        let forget = app.alerts["Forget paired source"]
        XCTAssertTrue(forget.waitForExistence(timeout: 5))
        forget.buttons["Cancel"].tap()
        XCTAssertTrue(laptop.exists)
        tap(laptop)
        app.buttons["Forget paired source"].tap()
        XCTAssertTrue(forget.waitForExistence(timeout: 5))
        forget.buttons["Forget paired source"].tap()
        XCTAssertTrue(laptop.waitForNonExistence(timeout: 5))
        let status = app.staticTexts["deviceRequestStatus"]
        reveal(status)
        XCTAssertTrue(status.label.contains("Forget paired source completed in demo only."))
        screenshot("Source confirmation changed only virtual paired-device state")
    }

    func testExperimentalLatencyCancelAndSimulationUpdateOnlyReportedDemoValue() throws {
        launchDemo()
        openDeviceControls()
        let reported = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Reported latency,")).firstMatch
        reveal(reported)
        let before = reported.label
        XCTAssertTrue(before.contains("210"))
        let stepper = app.steppers["latencyValue"]
        let increment = stepper.buttons["latencyValue-Increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 5), app.debugDescription)
        // The Stepper container is descriptive; its native Increment button is
        // the actionable hit target. Reveal that button rather than the label.
        reveal(increment)
        XCTAssertTrue(stepper.isEnabled)
        increment.tap()
        tap(app.buttons["reviewLatencyWrite"])
        let confirmation = app.alerts["Send an experimental latency write?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "simulate a value of 211", "No Bluetooth command is sent.")).firstMatch.exists)
        confirmation.buttons["Cancel"].tap()
        let unchanged = app.staticTexts.matching(NSPredicate(format: "label == %@", before)).firstMatch
        reveal(unchanged, direction: .towardTop)
        XCTAssertTrue(unchanged.exists)
        tap(app.buttons["reviewLatencyWrite"])
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Simulate write"].tap()
        let updated = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@", "Reported latency,", "211", "simulated device units")).firstMatch
        reveal(updated, direction: .towardTop)
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
        selectTab("Home")
        XCTAssertTrue(app.staticTexts["Demo device"].waitForExistence(timeout: 5))
        selectTab("Settings")
        XCTAssertTrue(app.navigationBars["Device controls"].waitForExistence(timeout: 5))
        reveal(updated, direction: .towardTop)
        XCTAssertTrue(updated.exists)
        screenshot("Experimental latency confirmation changed only the virtual reported value")
    }

    func testWiFiAccessIsDisabledInDemoAndNavigationDoesNotPrompt() throws {
        launchDemo()
        selectTab("Settings")
        tap(button(startingWith: "App preferences"))
        XCTAssertTrue(app.navigationBars["App preferences"].waitForExistence(timeout: 5))
        let access = app.buttons["Allow Wi-Fi access"]
        reveal(access)
        XCTAssertFalse(access.isEnabled)
        let privacy = text(containing: "Reads only the Wi-Fi name while Earshot is open")
        reveal(privacy)
        XCTAssertTrue(privacy.label.contains("Simulator cannot verify SSID access."))
        assertNoPermissionPrompt()
        app.navigationBars["App preferences"].buttons.element(boundBy: 0).tap()
        openAutomations()
        app.buttons["Add automation"].tap()
        XCTAssertTrue(app.navigationBars["Listening rule"].waitForExistence(timeout: 5))
        tap(button(startingWith: "Trigger"))
        app.buttons["Wi-Fi (app open)"].tap()
        let ruleAccess = app.buttons["Allow Wi-Fi access"]
        reveal(ruleAccess)
        XCTAssertFalse(ruleAccess.isEnabled)
        XCTAssertTrue(app.textFields["Wi-Fi name (SSID)"].exists)
        let requirement = text(containing: "signed physical iPhone")
        reveal(requirement)
        XCTAssertTrue(requirement.label.contains("paused in demo"))
        XCTAssertTrue(text(containing: "Rules can run only while Earshot is open").exists)
        assertNoPermissionPrompt()
        screenshot("Wi-Fi demo restriction and signed physical iPhone requirement")
        app.navigationBars.buttons["Cancel"].tap()
    }

    func testPrintConsoleValidatesLocallyRequiresConsentAndCannotSendInDemo() throws {
        launchDemo()
        selectTab("Tools")
        tap(button(startingWith: "Protocol lab"))
        XCTAssertTrue(app.navigationBars["Protocol lab"].waitForExistence(timeout: 5))
        tap(app.buttons["Capability scan and console"])
        XCTAssertTrue(app.navigationBars["Protocol diagnostics"].waitForExistence(timeout: 5))
        let command = app.textFields["printCommand"]
        reveal(command)
        XCTAssertEqual(command.value as? String, "output")
        tap(app.buttons["validatePrintCommand"])
        let validation = app.staticTexts["printValidation"]
        assertValue(validation, contains: "Valid Print command:", direction: .towardBottom)
        XCTAssertTrue(validation.label.contains("Nothing sent."))

        replaceText(command, with: "factory/reset")
        tap(app.buttons["validatePrintCommand"])
        assertValue(validation, contains: "Unknown Print command", direction: .towardBottom)
        XCTAssertTrue(validation.label.contains("Nothing sent."))
        replaceText(command, with: "output")
        tap(app.buttons["validatePrintCommand"])
        assertValue(validation, contains: "Valid Print command:", direction: .towardBottom)

        let consent = app.switches["enablePrintCommands"]
        reveal(consent)
        XCTAssertEqual(consent.value as? String, "0")
        let send = app.buttons["sendPrintCommand"]
        reveal(send)
        XCTAssertFalse(send.isEnabled)
        setSwitch(consent, on: true)
        let confirmation = app.alerts["Enable experimental firmware commands?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "No firmware update, authentication, factory-reset or arbitrary BMAP commands are offered.")).firstMatch.exists)
        confirmation.buttons["Cancel"].tap()
        XCTAssertEqual(consent.value as? String, "0")
        setSwitch(consent, on: true)
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Enable experimental commands"].tap()
        XCTAssertEqual(consent.value as? String, "1")
        reveal(send)
        XCTAssertFalse(send.isEnabled, "Consent and valid syntax cannot substitute for a verified physical control channel.")
        let offline = text(containing: "Demo and Simulator provide no console replies.")
        reveal(offline)
        XCTAssertTrue(offline.label.contains("Local validation sends nothing."))
        assertValue(app.staticTexts["printConsoleStatus"], contains: "No Print commands have been sent.")
        XCTAssertFalse(app.buttons["cancelPrintConsole"].exists)
        XCTAssertFalse(app.buttons["clearPrintConsole"].exists)
        screenshot("Print console validates locally and stays offline after explicit experimental consent")
    }

    private func launchDemo() {
        app.launch()
        XCTAssertTrue(app.buttons["tryDemo"].waitForExistence(timeout: 10))
        tap(app.buttons["tryDemo"])
        XCTAssertTrue(app.staticTexts["Demo device"].waitForExistence(timeout: 5))
    }

    private func relaunchPreservingState() {
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertFalse(app.buttons["tryDemo"].exists)
        XCTAssertTrue(tab("Home").waitForExistence(timeout: 5))
    }

    private func openProEQ() {
        selectTab("Sound")
        tap(app.buttons["Pro EQ"])
    }

    private func choosePreset(_ name: String) {
        tap(app.buttons["presetPicker"], direction: .towardTop)
        app.buttons[name].tap()
        assertValue(app.buttons["presetPicker"], contains: name)
    }

    private func openAutomations() {
        selectTab("Settings")
        tap(button(startingWith: "Automations"))
        XCTAssertTrue(app.navigationBars["Automations"].waitForExistence(timeout: 5))
    }

    private func openDeviceControls() {
        selectTab("Settings")
        if app.navigationBars["Device controls"].exists { return }
        tap(button(startingWith: "Device controls"))
        XCTAssertTrue(app.navigationBars["Device controls"].waitForExistence(timeout: 5))
    }

    private func importText(_ content: String, name: String) {
        tap(app.buttons["Paste AutoEQ"])
        XCTAssertTrue(app.navigationBars["Import preset"].waitForExistence(timeout: 5))
        replaceText(app.textFields["Name"], with: name)
        let editor = app.textViews["presetImportText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(content)
        app.navigationBars.buttons["Import"].tap()
        XCTAssertTrue(app.navigationBars["Import preset"].waitForNonExistence(timeout: 5))
    }

    private func requestPresetDeletion() {
        tap(app.buttons["managePreset"])
        app.buttons["Delete preset"].tap()
        XCTAssertTrue(text(containing: "Deleting an active preset returns playback to Flat.").waitForExistence(timeout: 5))
    }

    private func selectTab(_ title: String) {
        let element = tab(title)
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable, "Dismiss the modal before switching tabs.")
        element.tap()
    }

    private func tab(_ title: String) -> XCUIElement {
        let compact = app.tabBars.buttons[title]
        return compact.exists ? compact : app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func button(startingWith prefix: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch }
    private func named(_ label: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch }
    private func named(startingWith prefix: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch }
    private func text(containing fragment: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch }

    private func tap(_ element: XCUIElement, direction: ScrollDirection = .towardBottom) {
        reveal(element, direction: direction)
        element.tap()
    }

    private func reveal(_ element: XCUIElement, direction: ScrollDirection = .towardBottom) {
        var nextDirection = direction
        for _ in 0..<20 {
            let screen = app.frame
            var top = screen.minY + 20
            var bottom = screen.maxY - 20
            if let navigation = app.navigationBars.allElementsBoundByIndex.last(where: { $0.isHittable && !$0.frame.isEmpty }) { top = max(top, navigation.frame.maxY + 6) }
            let bar = app.tabBars.firstMatch
            if bar.exists, bar.isHittable {
                if bar.frame.minY > screen.midY { bottom = min(bottom, bar.frame.minY - 12) }
                else { top = max(top, bar.frame.maxY + 6) }
            }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, keyboard.isHittable { bottom = min(bottom, keyboard.frame.minY - 8) }
            var distance = min(CGFloat(180), (bottom - top) * 0.35)
            if element.exists {
                let frame = element.frame
                if element.isHittable, !frame.isEmpty, frame.minY >= top, frame.maxY <= bottom { return }
                if !frame.isEmpty, frame.minY < top {
                    nextDirection = .towardTop
                    distance = min(distance, max(36, top - frame.minY + 16))
                } else if !frame.isEmpty, frame.maxY > bottom {
                    nextDirection = .towardBottom
                    distance = min(distance, max(36, frame.maxY - bottom + 16))
                }
            }
            scrollSmallStep(nextDirection, distance: distance, top: top, bottom: bottom)
        }
        XCTFail("Expected fully visible control: \(element)")
    }

    private func scrollSmallStep(_ direction: ScrollDirection, distance: CGFloat, top: CGFloat, bottom: CGFloat) {
        XCTAssertGreaterThan(bottom - top, 60, "A modal or keyboard leaves no usable scroll area.")
        let screen = app.frame
        let travel = min(max(36, distance), (bottom - top) * 0.45)
        let middle = (top + bottom) / 2
        let startY = direction == .towardBottom ? middle + travel / 2 : middle - travel / 2
        let endY = direction == .towardBottom ? middle - travel / 2 : middle + travel / 2
        // The list/scroll-view gutter avoids sliders, EQ handles and switches.
        // A short slow drag followed by a hold prevents a full-screen inertial flick
        // from oscillating a row between the navigation bar and floating tab bar.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = screen.minX + 8
        origin.withOffset(CGVector(dx: x, dy: startY))
            .press(forDuration: 0.05,
                   thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY)),
                   withVelocity: .slow,
                   thenHoldForDuration: 0.15)
    }

    private func replaceText(_ field: XCUIElement, with value: String, dismissKeyboard: Bool = true) {
        tap(field, direction: .towardTop)
        if let text = field.value as? String, !text.isEmpty, text != field.placeholderValue {
            if app.alerts.firstMatch.exists {
                // Wait for keyboard focus before sending public Select All keys.
                // Selection-menu items outside UIAlert trigger XCTest's default
                // interruption handler, so keep this action within the text field.
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                for _ in 0..<2 {
                    field.typeKey("a", modifierFlags: .command)
                    field.typeText(XCUIKeyboardKey.delete.rawValue)
                    let current = field.value as? String ?? ""
                    if current.isEmpty || current == field.placeholderValue { break }
                }
            } else {
                // A center tap can leave the caret halfway through an existing name.
                // Use UIKit's actual selection menu rather than deleting only its prefix.
                field.press(forDuration: 1.1)
                let selectAllItem = app.menuItems["Select All"]
                let selectAllButton = app.buttons["Select All"]
                let selectAll = selectAllItem.exists ? selectAllItem : selectAllButton
                if selectAll.waitForExistence(timeout: 2), selectAll.isHittable {
                    selectAll.tap()
                    field.typeText(XCUIKeyboardKey.delete.rawValue)
                } else {
                    // A single-word field may already be fully selected and offer Cut
                    // instead of Select All. Verify the field is empty before entering a fixture.
                    let cutItem = app.menuItems["Cut"]
                    let cutButton = app.buttons["Cut"]
                    let cut = cutItem.exists ? cutItem : cutButton
                    XCTAssertTrue(cut.waitForExistence(timeout: 2), app.debugDescription)
                    XCTAssertTrue(cut.isHittable)
                    cut.tap()
                }
            }
            let cleared = field.value as? String ?? ""
            XCTAssertTrue(cleared.isEmpty || cleared == field.placeholderValue,
                          "Native selection must clear the entire previous value; UIKit may expose its placeholder when empty.")
        }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value, "Text entry must produce the exact requested fixture before saving.")
        guard dismissKeyboard else { return }
        let keyboard = app.keyboards.firstMatch
        if keyboard.buttons["Return"].exists { keyboard.buttons["Return"].tap() }
        else if keyboard.buttons["Done"].exists { keyboard.buttons["Done"].tap() }
    }

    private func setSwitch(_ element: XCUIElement, on: Bool) {
        reveal(element)
        guard (element.value as? String == "1") != on else { return }
        let frame = element.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.maxX - min(25, frame.width / 2), dy: frame.midY)).tap()
    }

    private func dragSlider(_ slider: XCUIElement, from start: CGFloat, to end: CGFloat) {
        reveal(slider)
        let frame = slider.frame
        XCTAssertGreaterThan(frame.width, 50)
        let inset = min(CGFloat(18), frame.width / 4)
        let track = frame.width - 2 * inset
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.minX + inset + track * start, dy: frame.midY))
            .press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: frame.minX + inset + track * end, dy: frame.midY)))
    }

    private func dismissPopover(action: XCUIElement) {
        let popoverCancel = app.popovers.buttons["Cancel"].firstMatch
        let sheetCancel = app.sheets.buttons["Cancel"].firstMatch
        if popoverCancel.exists, popoverCancel.isHittable { popoverCancel.tap() }
        else if sheetCancel.exists, sheetCancel.isHittable { sheetCancel.tap() }
        else { dismissMenu() }
        XCTAssertTrue(action.waitForNonExistence(timeout: 5))
    }

    private func dismissMenu() {
        let region = app.otherElements["PopoverDismissRegion"]
        let popover = app.popovers.firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(popover.exists, app.debugDescription)
        guard region.exists, popover.exists else { return }
        let screen = app.frame
        let bounds = region.frame.intersection(screen).insetBy(dx: 20, dy: 32)
        let popup = popover.frame.insetBy(dx: -8, dy: -8)
        let candidates = [CGPoint(x: bounds.midX, y: bounds.maxY),
                          CGPoint(x: bounds.minX, y: bounds.midY),
                          CGPoint(x: bounds.maxX, y: bounds.midY),
                          CGPoint(x: bounds.midX, y: bounds.minY)]
        let outside = candidates.first { !popup.contains($0) }
        XCTAssertNotNil(outside, "The observed popup must leave a native dismissal region.")
        guard let outside else { return }
        // The confirmation can cover the navigation title. Its native dismissal
        // region is the observed full-screen element outside the actual popup frame.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: outside.x - screen.minX, dy: outside.y - screen.minY)).tap()
        XCTAssertTrue(popover.waitForNonExistence(timeout: 5))
    }

    private func assertValue(_ element: XCUIElement, contains value: String, direction: ScrollDirection = .towardTop) {
        reveal(element, direction: direction)
        let predicate = NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", value, value)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5), .completed, "Expected \(value) in \(element)")
    }

    private func playbackSeconds(_ slider: XCUIElement) -> Int {
        let current = String(describing: slider.value ?? "").components(separatedBy: " of ").first ?? ""
        let parts = current.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : -1
    }

    private func waitUntil(_ message: String, timeout: TimeInterval = 5, condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, message)
    }

    private func assertNoPermissionPrompt() {
        let systemAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        let appeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: systemAlert)
        appeared.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [appeared], timeout: 1.5), .completed, "Navigation must not request location or Wi-Fi authorization.")
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
