import XCTest
@testable import Earshot

final class ReleaseNotesTests: XCTestCase {
    func testFreshInstallSilentlyRecordsCurrentVersionWhileExistingInstallShowsNotes() {
        XCTAssertEqual(ReleaseNotes.decide(lastSeen: nil, freshInstall: true, version: "0.1.0"), .markSeen)
        XCTAssertEqual(ReleaseNotes.decide(lastSeen: nil, freshInstall: false, version: "0.1.0"), .show)
        XCTAssertEqual(ReleaseNotes.decide(lastSeen: "0.1.0", freshInstall: true, version: "0.1.0"), .nothing)
        XCTAssertEqual(ReleaseNotes.decide(lastSeen: "0.1.0", freshInstall: false, version: "0.1.0"), .nothing)
        XCTAssertEqual(ReleaseNotes.decide(lastSeen: "0.0.9", freshInstall: false, version: "0.1.0"), .show)
    }

    @MainActor
    func testOnboardingDoesNotGetObscuredOrShowNotesImmediatelyAfterFinishing() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let notes = ReleaseNotesStore(defaults: defaults, version: "0.1.0")
        notes.check(onboardingPresented: true, canPresent: true)
        XCTAssertFalse(notes.isPresented)
        XCTAssertEqual(defaults.string(forKey: ReleaseNotes.lastSeenVersionKey), "0.1.0")
        notes.check(onboardingPresented: false, canPresent: true)
        XCTAssertFalse(notes.isPresented)
    }

    @MainActor
    func testUpdateDefersUntilOnboardingAndBlockingPresentationHaveFinished() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("0.1.0", forKey: ReleaseNotes.lastSeenVersionKey)
        let notes = ReleaseNotesStore(defaults: defaults, version: "0.2.0")
        notes.check(onboardingPresented: true, canPresent: true)
        XCTAssertFalse(notes.isPresented)
        notes.check(onboardingPresented: false, canPresent: false)
        XCTAssertFalse(notes.isPresented)
        XCTAssertEqual(defaults.string(forKey: ReleaseNotes.lastSeenVersionKey), "0.1.0")
        notes.check(onboardingPresented: false, canPresent: true)
        XCTAssertTrue(notes.isPresented)
    }

    @MainActor
    func testDismissalPersistsAcrossStoreRelaunchAndNextVersionStillShows() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ReleaseNotesStore(defaults: defaults, version: "0.1.0")
        first.check(onboardingPresented: false, canPresent: true)
        XCTAssertTrue(first.isPresented)
        first.presentationDismissed()
        XCTAssertFalse(first.isPresented)
        let relaunchedDefaults = UserDefaults(suiteName: suite)!
        let relaunched = ReleaseNotesStore(defaults: relaunchedDefaults, version: "0.1.0")
        relaunched.check(onboardingPresented: false, canPresent: true)
        XCTAssertFalse(relaunched.isPresented)
        let updated = ReleaseNotesStore(defaults: relaunchedDefaults, version: "0.2.0")
        updated.check(onboardingPresented: false, canPresent: true)
        XCTAssertTrue(updated.isPresented)
    }

    @MainActor
    func testUndismissedUpdateRemainsEligibleOnNextLaunch() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("0.1.0", forKey: ReleaseNotes.lastSeenVersionKey)
        let notes = ReleaseNotesStore(defaults: defaults, version: "0.2.0")
        notes.check(onboardingPresented: false, canPresent: true)
        XCTAssertTrue(notes.isPresented)
        XCTAssertEqual(defaults.string(forKey: ReleaseNotes.lastSeenVersionKey), "0.1.0")
        let relaunched = ReleaseNotesStore(defaults: UserDefaults(suiteName: suite)!, version: "0.2.0")
        relaunched.check(onboardingPresented: false, canPresent: true)
        XCTAssertTrue(relaunched.isPresented)
    }

    @MainActor
    func testManualViewingMarksSeenWithoutChangingPreferencesOrOnboarding() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let originalState = Data("preserved settings and presets".utf8)
        defaults.set(originalState, forKey: "earshot.ios.state")
        defaults.set(true, forKey: "earshot.welcomed")
        defaults.set("headphone-id", forKey: "earshot.bluetooth.identifier")
        let notes = ReleaseNotesStore(defaults: defaults, version: "0.1.0")
        notes.markSeen()
        notes.check(onboardingPresented: false, canPresent: true)
        XCTAssertFalse(notes.isPresented)
        XCTAssertEqual(defaults.data(forKey: "earshot.ios.state"), originalState)
        XCTAssertTrue(defaults.bool(forKey: "earshot.welcomed"))
        XCTAssertEqual(defaults.string(forKey: "earshot.bluetooth.identifier"), "headphone-id")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "ReleaseNotesTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }
}
