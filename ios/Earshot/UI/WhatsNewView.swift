// Original Earshot and release-note feature: HellzYeahh and contributors (MIT).
import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    var showsDoneButton = false

    var body: some View {
        Page {
            Panel(title: "Earshot for iOS", subtitle: "What’s new in \(ReleaseNotes.version)") {
                Text("An experimental, AI-assisted native iOS port of the original Earshot by HellzYeahh and contributors. The original app, ideas, Kotlin code, protocol research and documentation remain their work.")
                    .accessibilityIdentifier("releaseNotesCredits")
                Link("Original Earshot — HellzYeahh & contributors", destination: URL(string: "https://github.com/HellzYeahh/earshot")!)
            }
            Panel(title: "Listen with local EQ") {
                Text("Play your own audio files with native EQ, automatic or manual preamp, loudness protection, progress and seeking. Compare the original sound with A/B bypass.")
                Text("Create, edit, copy and share presets; import Android JSON and AutoEq text. Graphic conversion keeps the original filters available to restore while editing.")
            }
            Panel(title: "Headphone controls and useful tools") {
                Text("Listening modes, hardware EQ and supported device settings use the capabilities and reports returned by the headphones. A quick switcher keeps physical discovery separate from clearly labelled demo profiles.")
                Text("Combine listening actions in rules, use Shortcuts and widgets, trigger rules on a foreground Wi-Fi join, or record and play a microphone check. Schedules run while Earshot is open; optional tap-to-run reminders do not promise exact background execution.")
            }
            Panel(title: "Platform limits and credits") {
                Text("Local EQ changes audio played inside Earshot. iOS does not permit global EQ of other apps or arbitrary Bluetooth RFCOMM control. Physical iPhone/headphone compatibility still needs hardware verification; demo values are simulated.")
                Text("The port preserves upstream MIT notices and credits AutoEq by Jaakko Pasanen and contributors, bosectl by aaronsb and contributors, and Quiet Rebellion by MadEyez. Find their links and full attribution in About & credits.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("What’s new")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("dismissReleaseNotes")
                }
            }
        }
        .onDisappear {
            // The automatic sheet records its dismissal in RootView. A manually opened screen
            // also counts as seen, without making About's entry disappear.
            if !showsDoneButton { ReleaseNotesStore().markSeen() }
        }
    }
}
