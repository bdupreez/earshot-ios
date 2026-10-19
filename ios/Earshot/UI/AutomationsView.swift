// AI-assisted native port of HellzYeahh/earshot's automation editor (MIT).
import SwiftUI

struct AutomationsView: View {
    @EnvironmentObject var store: AppStore
    @State private var editing: AutomationRule?
    var body: some View {
        List {
            Section {
                Text("Combine mode, noise and Earshot local EQ actions. Connection rules use a verified control link; schedules execute while Earshot is open. Optional notifications remind you to open the app when it is closed.")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Use rules with Shortcuts") { ShortcutsHelpView() }
            }
            Section("Rules") {
                if store.saved.rules.isEmpty { ContentUnavailableView("A little less tapping", systemImage: "bolt", description: Text("Add a listening rule with one or more actions.")) }
                ForEach(store.saved.rules) { rule in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(rule.name) { editing = rule }
                            Spacer()
                            Toggle("Enable \(rule.name)", isOn: Binding(get: { rule.enabled }, set: { var copy = rule; copy.enabled = $0; store.upsertRule(copy) })).labelsHidden()
                        }
                        Text(rule.scheduleDescription).font(.caption).foregroundStyle(.secondary)
                        Text(store.describeRule(rule)).font(.caption)
                        if let status = store.ruleStatuses[rule.id] { Text(status).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("ruleStatus.\(rule.id)") }
                        if store.activeRuleID == rule.id { Button("Cancel rule", role: .cancel) { store.cancelRuleExecution() } }
                        else { Button("Run now") { store.runRule(rule) }.font(.subheadline) }
                    }
                    // Automatic List buttons otherwise share their row's edit action.
                    .buttonStyle(.borderless)
                }.onDelete { offsets in
                    if let id = store.activeRuleID, offsets.contains(where: { store.saved.rules[$0].id == id }) { store.cancelRuleExecution() }
                    store.saved.rules.remove(atOffsets: offsets)
                }
            }
            if !store.notifications.scheduleStatus.isEmpty {
                Section("Reminders") { Text(store.notifications.scheduleStatus).font(.caption).foregroundStyle(.secondary) }
            }
            if !store.automationLog.isEmpty {
                Section("Recent activity") { ForEach(Array(store.automationLog.prefix(20).enumerated()), id: \.offset) { _, text in Text(text).font(.caption) } }
            }
        }.navigationTitle("Automations").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { editing = AutomationRule(name: "My listening rule") } label: { Image(systemName: "plus") }.accessibilityLabel("Add automation") }
            .sheet(item: $editing) { RuleEditor(rule: $0) }
    }
}

struct RuleEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var rule: AutomationRule
    private var mode: Int { for case .mode(let index) in rule.effectiveActions { return index }; return 0 }
    private var noise: NoiseState { for case .noise(let value) in rule.effectiveActions { return value }; return store.saved.noise }
    private var presetID: String { for case .preset(let id) in rule.effectiveActions { return id ?? "__off" }; return store.saved.presetID }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Rule name", text: $rule.name)
                    Picker("Trigger", selection: $rule.trigger) {
                        Text("On connection").tag("On connection")
                        Text("Schedule (app open)").tag("Schedule (app open)")
                        Text("Wi-Fi (app open)").tag("Wi-Fi (app open)")
                        Text("Manual / Shortcut").tag("Manual")
                    }
                }
                if rule.trigger == "Schedule (app open)" { scheduleSection }
                if rule.trigger == "Wi-Fi (app open)" {
                    Section("Wi-Fi network") {
                        TextField("Wi-Fi name (SSID)", text: Binding(get: { rule.wifiSSID ?? "" }, set: { rule.wifiSSID = $0 }))
                            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        if let name = store.wifi.ssid { Button("Use current Wi-Fi name") { rule.wifiSSID = name } }
                        Button("Allow Wi-Fi access") { store.wifi.requestAccess() }.disabled(store.saved.demo)
                        Text(store.saved.demo ? "Wi-Fi observation is paused in demo. Configure the name now; enable access on a signed physical iPhone." : store.wifi.status).font(.caption).foregroundStyle(.secondary)
                        Text("Optional: requires While Using App and Precise Location authorization to read the SSID. No GPS updates are collected. Rules can run only while Earshot is open; use a Shortcuts personal automation for system-managed triggers.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle("Change listening mode", isOn: actionEnabled("mode", default: .mode(mode)))
                    if hasAction("mode") {
                        Picker("Listening mode", selection: Binding(get: { mode }, set: { replace(.mode($0)) })) {
                            if !store.saved.modes.contains(where: { $0.id == mode && $0.configured }) { Text("Unavailable mode #\(mode)").tag(mode) }
                            ForEach(store.saved.modes.filter { $0.configured }) { Text($0.name).tag($0.id) }
                        }
                    }
                    Toggle("Change noise controls", isOn: actionEnabled("noise", default: .noise(store.saved.noise)))
                    if hasAction("noise") {
                        NoiseControls(noise: Binding(get: { noise }, set: { replace(.noise($0)) }), profile: store.connected ? store.noiseProfile(for: hasAction("mode") ? mode : nil) : DeviceProfile.all[0], ancToggle: !store.connected || store.canToggleANC(for: hasAction("mode") ? mode : nil))
                    }
                    Toggle("Change local EQ", isOn: actionEnabled("preset", default: .preset(store.saved.presetID)))
                    if hasAction("preset") {
                        Picker("Local EQ preset", selection: Binding(get: { presetID }, set: { replace(.preset($0 == "__off" ? nil : $0)) })) {
                            Text("Off / original audio").tag("__off")
                            if presetID != "__off", !store.presets.contains(where: { $0.id == presetID }) { Text("Removed preset").tag(presetID) }
                            ForEach(store.presets) { Text($0.name).tag($0.id) }
                        }.accessibilityIdentifier("rulePresetPicker")
                    }
                } header: { Text("Actions") } footer: {
                    Text("Actions run in order: mode, noise, then local EQ. Earshot waits for real headphone reports before moving to the next hardware action. Local EQ processes only audio played inside Earshot.")
                }
                if let error = rule.configurationError { Section { Text(error).font(.caption).foregroundStyle(.secondary) } }
            }.navigationTitle("Listening rule").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.upsertRule(rule) { dismiss() } }.disabled(rule.configurationError != nil) }
                }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            DatePicker("Time", selection: Binding(get: {
                Calendar.current.date(from: DateComponents(hour: rule.hour, minute: rule.minute)) ?? .now
            }, set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                rule.hour = c.hour ?? 9; rule.minute = c.minute ?? 0
            }), displayedComponents: .hourAndMinute)
            DisclosureGroup("Repeat on: \(rule.weekdayDescription)") {
                ForEach(1...7, id: \.self) { day in
                    Toggle(AutomationRule.weekdayName(day), isOn: Binding(get: { rule.effectiveWeekdays.contains(day) }, set: { value in
                        var days = rule.effectiveWeekdays
                        if value { days.insert(day) } else { days.remove(day) }
                        rule.weekdays = days
                    })).accessibilityIdentifier("ruleWeekday.\(day)")
                }
            }
            Toggle("Remind me when Earshot is closed", isOn: Binding(get: { rule.notifyAtSchedule ?? false }, set: { rule.notifyAtSchedule = $0 }))
            if rule.notifyAtSchedule == true {
                Button("Allow schedule notifications") { Task { await store.notifications.requestPermission(); store.syncPlatformIntegrations() } }
                Text("A reminder opens Earshot to run the rule after you tap it. It does not execute headphone commands in the background. Reminders are paused in demo mode and follow system notification settings.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func hasAction(_ kind: String) -> Bool { rule.effectiveActions.contains { $0.kind == kind } }
    private func actionEnabled(_ kind: String, default action: AutomationAction) -> Binding<Bool> {
        Binding(get: { hasAction(kind) }, set: { enabled in
            if enabled { replace(action) }
            else { rule.actions = rule.effectiveActions.filter { $0.kind != kind } }
        })
    }
    private func replace(_ action: AutomationAction) {
        var actions = rule.effectiveActions.filter { $0.kind != action.kind }
        actions.append(action)
        let order = ["mode", "noise", "preset"]
        rule.actions = actions.sorted { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }
        if case .mode(let index) = action { rule.modeIndex = index }
    }
}

struct ShortcutsHelpView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        List {
            Section("Personal automations") {
                Text("In Apple’s Shortcuts app, create a personal automation for a time, joining Wi-Fi, or opening an app. Add Earshot’s Run listening rule action and select a saved rule. Allow Earshot to open when the automation runs.")
                Text("Shortcuts owns those triggers, and a locked device or system confirmation may delay execution. Earshot’s separate Wi-Fi rules observe the network name only while Earshot is open and after you allow access. Earshot cannot monitor other apps.")
            }
            if !store.shortcutStatus.isEmpty { Section("Latest request") { Text(store.shortcutStatus) } }
            if !store.shortcutLog.isEmpty { Section("Request history") { ForEach(Array(store.shortcutLog.prefix(10).enumerated()), id: \.offset) { _, text in Text(text).font(.caption) } } }
            Section("Available actions") {
                Text("Quiet or Aware by the current device’s reported mode names; a specific listening mode; noise level; hardware bass/mid/treble EQ; an Earshot local-player preset; or a multi-action listening rule.")
                Text("Headphone actions require a verified connection and reported device support. Local EQ can be selected without headphones. Requests expire after two minutes and errors are shown inside Earshot.")
            }
            Section("Widgets and Control Center") {
                Text("Add the Earshot widget from the Home Screen widget gallery. On iOS 18 or later, add Earshot’s Quiet and Aware controls to Control Center. These controls open Earshot to perform the request; the widget displays the last app snapshot and its age.")
            }
        }.navigationTitle("Shortcuts & controls").navigationBarTitleDisplayMode(.inline)
    }
}
