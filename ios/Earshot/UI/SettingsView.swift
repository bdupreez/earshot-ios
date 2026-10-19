import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        List {
            Section("On your headphones") {
                Picker("Self Voice", selection: Binding(get: { store.saved.sidetone }, set: { store.updateSidetone($0) })) { Text("Off").tag(0); Text("Low").tag(3); Text("Medium").tag(2); Text("High").tag(1) }.disabled(!store.connected || !store.supports(1, 11) || store.sidetonePersist == nil)
                if let persist = store.sidetonePersist {
                    Toggle("Remember Self Voice setting", isOn: Binding(get: { persist }, set: { store.updateSidetonePersistence($0) }))
                        .disabled(!store.connected || !store.supports(1, 11)).accessibilityIdentifier("sidetonePersistence")
                }
                settingToggle("Auto play / pause", key: "autoPause", value: store.saved.autoPause, function: 24)
                settingToggle("Auto-answer calls", key: "autoAnswer", value: store.saved.autoAnswer, function: 27)
                settingToggle("Multipoint", key: "multipoint", value: store.saved.multipoint, function: 10)
                settingToggle("Voice prompts", key: "voicePrompts", value: store.saved.voicePrompts, function: 3)
                settingToggle("Touch controls", key: "touchControls", value: store.saved.touchControls, function: 34)
                Picker("Auto-off", selection: Binding(get: { store.saved.autoOff }, set: { store.updateAutoOff($0) })) { ForEach([5,20,40,60,180,1440,0], id: \.self) { Text($0 == 0 ? "Never" : $0 == 1440 ? "24 hours" : "\($0) minutes").tag($0) } }.disabled(!store.connected || !store.supports(1, 4))
            }.disabled(store.profile.unsupported)
            Section("Make it yours") {
                NavigationLink { AutomationsView() } label: { Label("Automations", systemImage: "bolt") }
                NavigationLink { PreferencesView() } label: { Label("App preferences", systemImage: "slider.horizontal.3") }
                NavigationLink { ModeCycleView() } label: { Label("Mode cycle", systemImage: "arrow.triangle.2.circlepath") }.accessibilityIdentifier("openModeCycle")
            }
            Section("Device") {
                NavigationLink { DeviceControlsView() } label: { Label("Device controls", systemImage: "headphones") }
                LabeledContent("Profile", value: store.profile.name)
                LabeledContent("Firmware", value: store.firmware)
                if store.saved.demo { Text("All device values are simulated.").font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                NavigationLink { AboutView() } label: { Label("About & credits", systemImage: "heart") }
                NavigationLink { CompatibilityView() } label: { Label("iOS compatibility", systemImage: "checkmark.shield") }
            }
        }.navigationTitle("Settings")
    }
    private func settingToggle(_ title: String, key: String, value: Bool, function: UInt8) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { store.setSetting(key, value: $0, function: function) })).disabled(!store.connected || !store.supports(1, Int(function)))
    }
}

struct PreferencesView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        Form {
            Section("Appearance") { Picker("Appearance", selection: $store.saved.theme) { Text("System").tag("System"); Text("Light").tag("Light"); Text("Dark").tag("Dark") }.accessibilityIdentifier("appearancePicker") }
            Section {
                Toggle("Demo mode", isOn: Binding(get: { store.saved.demo }, set: { store.setDemo($0) })).accessibilityIdentifier("demoToggle")
                if store.saved.demo { Picker("Demo headphone", selection: Binding(get: { store.saved.profileID }, set: { store.selectProfile($0) })) { ForEach(DeviceProfile.all) { Text($0.name).tag($0.id) } } }
            } header: { Text("Explore") } footer: { Text("Demo mode uses local virtual state. It never controls physical headphones.") }
            Section("Optional Wi-Fi automation") {
                Text(store.wifi.status).font(.caption).foregroundStyle(.secondary)
                if let ssid = store.wifi.ssid { LabeledContent("Current network", value: ssid).privacySensitive() }
                Button("Allow Wi-Fi access") { store.wifi.requestAccess() }.disabled(store.saved.demo)
                if store.wifi.isEnabled { Button("Turn off Wi-Fi observation") { store.wifi.disable() } }
                Text("Reads only the Wi-Fi name while Earshot is open, after explicit opt-in and precise When In Use authorization. No GPS updates, background location or network-name uploads. Simulator cannot verify SSID access.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Low battery alerts") {
                Picker("Alert at", selection: $store.saved.batteryAlert) { Text("Off").tag(0); ForEach(Array(stride(from: 5, through: 50, by: 5)), id: \.self) { value in Text("\(value)%").tag(value) } }
                Button("Allow notifications") { Task { await store.notifications.requestPermission(); store.notifications.syncRuleReminders(store.saved.demo ? [] : store.saved.rules); store.objectWillChange.send() } }
                if let url = store.stateRecoveryURL { ShareLink("Export recovered settings", item: url) }
                Text(store.notifications.status).font(.caption).foregroundStyle(.secondary)
            }
            Section { Text("Your preferences and presets are stored locally. Imported audio is copied into app storage; microphone checks use the cache. No account, cloud service, or analytics SDK.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("App preferences").navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    var body: some View {
        Page {
            Panel(title: "Earshot for iOS", subtitle: "An AI-assisted port attempt · 0.1.0") {
                Text("This fork uses AI assistance to explore a native iOS port of the original Android Earshot app. The original app, ideas, Kotlin implementation, protocol research, and existing documentation belong to their respective authors. This port does not claim that work as its own.")
                Link("Original Earshot — HellzYeahh & contributors", destination: URL(string: "https://github.com/HellzYeahh/earshot")!)
                Link("AI-assisted iOS fork — bdupreez/earshot-ios", destination: URL(string: "https://github.com/bdupreez/earshot-ios")!)
                NavigationLink("What’s new") { WhatsNewView() }.accessibilityIdentifier("openReleaseNotes")
            }
            Panel(title: "Standing on their work") {
                Link("bosectl — aaronsb (MIT)", destination: URL(string: "https://github.com/aaronsb/bosectl")!)
                Link("Quiet Rebellion — MadEyez (MIT)", destination: URL(string: "https://github.com/MadEyez/quietrebellion")!)
                Link("AutoEq — Jaakko Pasanen (MIT)", destination: URL(string: "https://github.com/jaakkopasanen/AutoEq")!)
                Text("QC Ultra correction uses AutoEq’s Rtings measurement on the B&K 5128 rig, as selected and documented by upstream Earshot. All original notices and licences remain in the repository.").font(.footnote).foregroundStyle(.secondary)
            }
            Panel(title: "Licence & privacy") {
                Text("MIT License · Copyright (c) 2026 Earshot contributors. Permission is granted to use, copy, modify, distribute, sublicense, and sell this software subject to preserving the copyright and permission notices. Software is provided ‘AS IS’, without warranty.").font(.footnote)
                Text("No accounts or analytics. Settings, audio imports, and microphone recordings stay on your device. Bluetooth communicates with nearby headphones. Opening a credit link uses your browser.").font(.footnote)
                Text("Not affiliated with Bose or Skullcandy. Product names and trademarks belong to their owners. Firmware updates remain with the vendor app.").font(.caption).foregroundStyle(.secondary)
                if let path = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"), let license = try? String(contentsOf: path, encoding: .utf8) { Text(license).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary) }
            }
        }.navigationTitle("About & credits").navigationBarTitleDisplayMode(.inline)
    }
}
