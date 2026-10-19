// AI-assisted native iOS port of Earshot by HellzYeahh and contributors (MIT).
// The once-per-release policy follows upstream ui/whatsnew/WhatsNew.kt.
import Combine
import Foundation

enum ReleaseNotes {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    static let lastSeenVersionKey = "earshot.ios.releaseNotes.lastSeenVersion"

    enum Decision: Equatable { case show, markSeen, nothing }

    /// An existing installation without a notes key should still learn about this release.
    /// On a fresh installation, onboarding introduces the app instead.
    static func decide(lastSeen: String?, freshInstall: Bool, version: String) -> Decision {
        if lastSeen == version { return .nothing }
        if lastSeen == nil && freshInstall { return .markSeen }
        return .show
    }
}

@MainActor
final class ReleaseNotesStore: ObservableObject {
    @Published var isPresented = false
    let version: String
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, version: String = ReleaseNotes.version) {
        self.defaults = defaults
        self.version = version
    }

    /// No launch arguments or synthetic release overrides are used in the app's presentation path.
    func check(onboardingPresented: Bool, canPresent: Bool) {
        let lastSeen = defaults.string(forKey: ReleaseNotes.lastSeenVersionKey)
        switch ReleaseNotes.decide(lastSeen: lastSeen, freshInstall: onboardingPresented, version: version) {
        case .markSeen: markSeen()
        case .show:
            if !onboardingPresented && canPresent && !isPresented { isPresented = true }
        case .nothing: break
        }
    }

    func markSeen() {
        // Keep this independent from SavedAppState: a new release must never reset preferences.
        defaults.set(version, forKey: ReleaseNotes.lastSeenVersionKey)
    }

    func presentationDismissed() {
        isPresented = false
        markSeen()
    }
}
