// AI-assisted port of HellzYeahh/earshot (MIT). App Intents enqueue requests;
// only this foreground app path validates and executes them against its controls.
import Foundation
import WidgetKit

@MainActor extension AppStore {
    func syncPlatformIntegrations() {
        let observeWiFi = appIsActive && !saved.demo
        if lastWiFiActive != observeWiFi { lastWiFiActive = observeWiFi; wifi.setActive(observeWiFi) }
        processWiFiRules()
        let reminderRules = saved.demo ? [] : saved.rules
        if lastReminderRules != reminderRules {
            lastReminderRules = reminderRules
            notifications.syncRuleReminders(reminderRules)
        }
        let items: [EarshotWidgetBattery]
        if !batteryReadings.isEmpty {
            items = batteryReadings.map { .init(id: String($0.component), name: $0.label, percent: $0.percent, remainingMinutes: $0.remainingMinutes) }
        } else {
            items = [.init(id: "main", name: "Headphones", percent: battery, remainingMinutes: batteryMinutes)]
        }
        var snapshot = EarshotWidgetSnapshot(connected: connected, demo: saved.demo, profileName: displayDeviceName, modeName: connected ? modeName : "Disconnected", batteries: items)
        snapshot.cycleStatus = modeCycleRequestError
        if modeCycleRequestError == nil, let next = EarshotModeCycle.next(current: saved.currentMode, order: modeCycleOrder) {
            snapshot.cycleNextModeName = modeCycleModes.first { $0.id == next }?.name
        }
        let catalog = EarshotIntentCatalog(
            modes: saved.modes.filter(\.configured).map { .init(id: String($0.id), name: $0.name) },
            presets: presets.map { .init(id: $0.id, name: $0.name) },
            rules: saved.rules.map { .init(id: $0.id, name: $0.name) })
        if let previous = lastSharedSnapshot {
            snapshot.updatedAt = previous.updatedAt
            if previous == snapshot && lastIntentCatalog == catalog && Date.now.timeIntervalSince(previous.updatedAt) < 60 { return }
        }
        snapshot.updatedAt = .now
        lastSharedSnapshot = snapshot; lastIntentCatalog = catalog
        EarshotShared.save(snapshot: snapshot, catalog: catalog)
        WidgetCenter.shared.reloadTimelines(ofKind: "EarshotListeningWidget")
    }

    /// Consume each envelope once, retaining only a short-lived in-memory execution
    /// list. A failure for one headphone action must not reject a following local EQ
    /// action merely because Bluetooth is disconnected.
    func processSharedRequests() {
        guard appIsActive else { return }
        do {
            let drain = try EarshotShared.commandQueue().consumePending()
            if drain.expiredCount > 0 || drain.discardedCount > 0 {
                recordShortcutResult("Ignored \(drain.expiredCount) expired and \(drain.discardedCount) unreadable requests.")
            }
            queuedAppRequests.append(contentsOf: drain.commands)
        } catch {
            // On unsigned builds App Group provisioning may be unavailable. Report
            // this only when explicitly requested, rather than showing launch alerts
            // on every scene activation that has no possible shared queue.
            shortcutStatus = error.localizedDescription
        }
        startQueuedRequests()
    }

    func requestFromURL(_ url: URL) {
        guard url.scheme == "earshot" else { return }
        let payload: EarshotCommandPayload?
        switch url.host {
        case "mode": payload = Int(url.lastPathComponent).map { .listeningMode(index: $0) }
        case "quiet": payload = .listeningRole(.quiet)
        case "aware": payload = .listeningRole(.aware)
        case "cycle": payload = .cycleModes
        case "rule": payload = .runRule(id: url.lastPathComponent)
        case "preset": payload = .localPreset(id: url.lastPathComponent)
        default: return // A widget's home link simply opens the native app.
        }
        guard let payload else { message = "This Earshot link contains an invalid request."; return }
        do {
            try payload.validate()
            queuedAppRequests.append(EarshotCommandEnvelope(id: UUID(), createdAt: .now, expiresAt: .now.addingTimeInterval(120), payload: payload))
            startQueuedRequests()
        } catch { message = error.localizedDescription }
    }

    func startQueuedRequests() {
        guard appIsActive, appRequestTask == nil, !queuedAppRequests.isEmpty else { return }
        appRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.appIsActive, !self.queuedAppRequests.isEmpty, !Task.isCancelled {
                let request = self.queuedAppRequests.removeFirst()
                guard request.expiresAt > .now else { self.recordShortcutResult("Request expired before it could run."); continue }
                do {
                    try request.payload.validate()
                    while self.activeRuleID != nil {
                        guard self.appIsActive, request.expiresAt > .now else { throw RuleExecutionError.failed("The request expired or Earshot left the foreground.") }
                        try await Task.sleep(for: .milliseconds(80))
                    }
                    let result = try await self.executeSharedPayload(request.payload)
                    self.recordShortcutResult(result)
                } catch is CancellationError { break }
                catch {
                    self.recordShortcutResult("Failed: \(error.localizedDescription)")
                    self.message = error.localizedDescription
                }
            }
            self.appRequestTask = nil
            self.syncPlatformIntegrations()
        }
    }

    func resolveListeningRole(_ role: EarshotListeningRole) -> Int? {
        saved.modes.first { $0.configured && $0.builtIn && $0.name.caseInsensitiveCompare(role.rawValue) == .orderedSame }?.id
    }

    /// Real devices use this connection's received slot reports, never a stale widget snapshot.
    var modeCycleModes: [ListeningMode] {
        saved.modes.filter { $0.configured && (0...254).contains($0.id) && (saved.demo || reportedModeIDs.contains($0.id)) }
            .sorted { $0.id < $1.id }
    }

    var modeCycleOrder: [Int] {
        guard !modeCycleModes.isEmpty else { return [] }
        return EarshotModeCycle.order(preferred: saved.modeCycleModes, modes: modeCycleModes.map { .init(id: $0.id, configured: $0.configured, favorite: $0.favorite) })
    }

    var modeCycleUnavailableIDs: [Int] {
        let available = Set(modeCycleModes.map(\.id))
        return EarshotModeCycle.canonical(saved.modeCycleModes).filter { !available.contains($0) }
    }

    var modeCycleRequestError: String? {
        guard connected else { return "Connect headphones or start demo mode, then refresh the available modes." }
        guard !profile.unsupported else { return "Mode cycling is unavailable for this headphone profile." }
        guard saved.demo || supports(31, 3) else { return "Refresh device reports before cycling; mode selection has not been reported as available." }
        guard !modeCycleModes.isEmpty else { return "No configured modes have been reported for this connection. Refresh device reports or create a mode first." }
        if !saved.modeCycleModes.isEmpty, !saved.modeCycleModes.contains(where: { selected in modeCycleModes.contains { $0.id == selected } }) {
            return "Your saved cycle has no modes available on these headphones. Choose current modes or use the automatic cycle in Settings → Mode cycle."
        }
        guard !modeCycleOrder.isEmpty else { return "The cycle is empty. Configure a mode cycle in Settings." }
        return nil
    }

    @discardableResult
    func updateModeCycleModes(_ indices: [Int]) -> Bool {
        let selected = EarshotModeCycle.canonical(indices)
        guard indices.allSatisfy({ (0...254).contains($0) }), selected.allSatisfy({ id in modeCycleModes.contains { $0.id == id } }) else {
            message = "Choose only configured modes currently available on these headphones."
            return false
        }
        saved.modeCycleModes = selected
        syncPlatformIntegrations()
        return true
    }

    func requestModeCycle() {
        guard let url = URL(string: "earshot://cycle") else { return }
        requestFromURL(url)
    }

    func executeSharedPayload(_ payload: EarshotCommandPayload) async throws -> String {
        guard appIsActive else { throw RuleExecutionError.failed("Open Earshot to execute this request.") }
        switch payload {
        case .localPreset(let id):
            guard presets.contains(where: { $0.id == id }) else { throw RuleExecutionError.failed("That local EQ preset was removed. Update the Shortcut.") }
            saved.proEnabled = true; choosePreset(id)
            return "Local EQ preset applied to Earshot playback."
        case .hardwareEQ(let bass, let mid, let treble):
            let values = [bass, mid, treble].map { $0.rounded() }
            if let error = hardwareEQRequestError(values) { throw RuleExecutionError.failed(error) }
            let failureVersion = commandFailureVersion
            for (index, value) in values.enumerated() where saved.eq[index] != value { setEQ(index, value: value) }
            if !saved.demo { try await waitForRuleReport(failureVersion: failureVersion) { self.saved.eq == values } }
            return saved.demo ? "Headphone EQ applied in demo only." : "Headphone EQ confirmed by device reports."
        default:
            let rule: AutomationRule
            switch payload {
            case .listeningMode(let index): rule = AutomationRule(name: "Shortcut mode", trigger: "Manual", actions: [.mode(index)])
            case .cycleModes:
                if let error = modeCycleRequestError { throw RuleExecutionError.failed(error) }
                guard let index = EarshotModeCycle.next(current: saved.currentMode, order: modeCycleOrder) else {
                    throw RuleExecutionError.failed("No configured cycle mode is available. Update Mode cycle in Settings.")
                }
                rule = AutomationRule(name: "Cycle modes", trigger: "Manual", actions: [.mode(index)])
            case .listeningRole(let role):
                guard let index = resolveListeningRole(role) else { throw RuleExecutionError.failed("The current headphones have not reported a \(role.rawValue.capitalized) mode. Open Earshot to refresh the available modes.") }
                rule = AutomationRule(name: "Shortcut \(role.rawValue)", trigger: "Manual", actions: [.mode(index)])
            case .noiseLevel(let level):
                var noise = saved.noise; noise.level = level.rounded()
                rule = AutomationRule(name: "Shortcut noise", trigger: "Manual", actions: [.noise(noise)])
            case .runRule(let id):
                guard let found = saved.rules.first(where: { $0.id == id }) else { throw RuleExecutionError.failed("That listening rule was removed. Update the Shortcut.") }
                rule = found
            default: throw EarshotIntegrationError.invalidCommand
            }
            let transient = !saved.rules.contains(where: { $0.id == rule.id })
            defer { if transient { ruleStatuses.removeValue(forKey: rule.id) } }
            guard runRule(rule, source: .shortcut) else { throw RuleExecutionError.failed(message ?? "The listening rule could not start.") }
            while activeRuleID == rule.id { try await Task.sleep(for: .milliseconds(80)) }
            let outcome = ruleStatuses[rule.id] ?? "No execution result was recorded."
            guard outcome == "Applied in demo" || outcome == "Local audio settings applied" || outcome == "Confirmed by headphone reports" else { throw RuleExecutionError.failed(outcome) }
            return "\(rule.name): \(outcome)."
        }
    }

    private func recordShortcutResult(_ text: String) {
        shortcutStatus = text
        shortcutLog.insert("\(Date.now.formatted(date: .omitted, time: .shortened)) · \(text)", at: 0)
        if shortcutLog.count > 50 { shortcutLog.removeLast(shortcutLog.count - 50) }
    }
}
