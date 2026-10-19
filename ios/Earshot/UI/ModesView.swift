import SwiftUI

struct ModesView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: ListeningMode?
    var body: some View {
        Page {
            Text("A setting for every setting.").font(.title2.weight(.bold))
            Text("Switch listening modes or make a space of your own.").foregroundStyle(.secondary)
            if store.saved.modes.isEmpty { InfoNote(text: "Connect compatible headphones or use demo mode to see listening modes.") }
            ForEach(store.saved.modes) { mode in
                Panel {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(mode.builtIn ? "BUILT-IN" : "CUSTOM · SLOT \(mode.id)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            Text(mode.configured ? mode.name : "Create a mode").font(.title3.weight(.semibold))
                            if mode.configured { Text(mode.id == store.saved.currentMode ? "Currently listening" : "Cancellation \(Int(mode.noise.level))/10").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if mode.configured {
                            Button { store.toggleFavorite(mode.id) } label: { Image(systemName: mode.favorite ? "star.fill" : "star").foregroundStyle(Color.earshot) }.disabled(!store.canEditFavorites).accessibilityLabel("Favorite \(mode.name)")
                            Button("Use") { store.selectMode(mode.id) }.buttonStyle(.bordered).disabled(store.saved.currentMode == mode.id)
                        }
                        if !mode.builtIn { Button { editing = mode } label: { Image(systemName: "square.and.pencil") }.accessibilityIdentifier("editMode.\(mode.id)").accessibilityLabel("Edit \(mode.name)").disabled(!store.canEditMode(mode.id)) }
                    }
                }
            }
            if !store.saved.demo { InfoNote(text: "Custom mode editing is enabled only for slots reported editable with a complete firmware layout. Physical-device verification is still required.") }
        }.navigationTitle("Modes")
            .sheet(item: $editing) { ModeEditor(mode: $0) }
    }
}

struct ModeEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var mode: ListeningMode
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Mode name", text: $mode.name).accessibilityIdentifier("modeName"); Text("\(mode.name.utf8.count)/31 UTF-8 bytes").font(.caption).foregroundStyle(.secondary) }
                Section("Listening preferences") { NoiseControls(noise: $mode.noise, profile: store.profile) }
                if mode.configured { Section { Button("Reset custom mode", role: .destructive) { store.resetMode(mode.id); dismiss() } } }
            }.navigationTitle("Custom mode").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { store.saveMode(mode); dismiss() }.disabled(mode.name.trimmingCharacters(in: .whitespaces).isEmpty || mode.name.utf8.count > 31).accessibilityIdentifier("saveMode") } }
        }
    }
}
