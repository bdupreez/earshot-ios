// AI-assisted native port of HellzYeahh/earshot TileCycle.kt and PreferencesScreen.kt (MIT).
import SwiftUI

struct ModeCycleView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section {
                Text("Choose the modes used by the Cycle modes Shortcut, widget and Control Center button. The app opens, checks the current headphones and waits for their mode report. Modes cycle in slot order, wrapping back to the first.")
                    .font(.footnote)
                if store.saved.demo { Label("Cycle actions here are simulated.", systemImage: "sparkles").font(.caption) }
                LabeledContent("Current mode", value: store.modeName).accessibilityIdentifier("cycleCurrentMode").accessibilityValue(store.modeName)
            }
            Section("Choose cycle modes") {
                ForEach(store.modeCycleModes) { mode in
                    Toggle(mode.name, isOn: Binding(get: { store.saved.modeCycleModes.contains(mode.id) }, set: { include in
                        var next = store.saved.modeCycleModes.filter { id in store.modeCycleModes.contains { $0.id == id } }
                        if include { next.append(mode.id) } else { next.removeAll { $0 == mode.id } }
                        store.updateModeCycleModes(next)
                    })).accessibilityIdentifier("cycleMode.\(mode.id)")
                }
                if store.modeCycleModes.isEmpty { Text("Connect and refresh headphones, or create a configured demo mode, to choose a cycle.").font(.footnote).foregroundStyle(.secondary) }
                Button("Use automatic cycle") { store.updateModeCycleModes([]) }
                    .disabled(store.saved.modeCycleModes.isEmpty).accessibilityIdentifier("automaticModeCycle")
                if store.saved.modeCycleModes.isEmpty {
                    Text("Automatic uses configured favorites first, then available Quiet, Aware and Immersion slots, then other configured modes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !store.modeCycleUnavailableIDs.isEmpty {
                    Text("Saved slots \(store.modeCycleUnavailableIDs.map(String.init).joined(separator: ", ")) are unavailable. They are skipped. Choose current modes or use the automatic cycle.")
                        .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("cycleUnavailable")
                }
            }
            Section("Current cycle") {
                Text(cycleDescription).accessibilityIdentifier("modeCycleOrder")
                if let error = store.modeCycleRequestError { Text(error).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("modeCycleError") }
                Button("Cycle now") { store.requestModeCycle() }
                    .disabled(store.modeCycleRequestError != nil || store.activeRuleID != nil)
                    .accessibilityIdentifier("cycleModesNow")
                if !store.shortcutStatus.isEmpty { Text(store.shortcutStatus).font(.caption).accessibilityIdentifier("cycleResult") }
            }
            Section {
                Text("The widget may show an older snapshot. A cycle request resolves the next mode from the app’s current device reports; it never trusts an old slot from a widget. Background execution is not promised.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Based on the original Earshot by HellzYeahh and contributors · AI-assisted iOS port.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mode cycle").navigationBarTitleDisplayMode(.inline)
    }

    private var cycleDescription: String {
        let names = store.modeCycleOrder.compactMap { id in store.modeCycleModes.first { $0.id == id }?.name }
        return names.isEmpty ? "No available cycle" : (names + [names[0]]).joined(separator: " → ")
    }
}
