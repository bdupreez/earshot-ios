// AI-assisted port of upstream Earshot's RuleRunner and AutomationRepository (MIT).
// Hardware actions use the real report-driven controls; local EQ stays in Earshot.
import Foundation

@MainActor extension AppStore {
    @discardableResult
    func upsertRule(_ rule: AutomationRule) -> Bool {
        if let error = rule.configurationError { message = error; return false }
        var proposed = saved.rules.filter { $0.id != rule.id }
        proposed.append(rule)
        guard NotificationManager.scheduleRequests(for: proposed).count <= NotificationManager.maximumScheduleRequests else {
            message = "There are too many schedule reminders. Choose fewer days or disable another reminder."
            return false
        }
        var copy = rule
        copy.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = saved.rules.firstIndex(where: { $0.id == rule.id }) {
            let old = saved.rules[i]
            if old.effectiveActions != copy.effectiveActions || old.trigger != copy.trigger ||
                old.hour != copy.hour || old.minute != copy.minute || old.effectiveWeekdays != copy.effectiveWeekdays {
                copy.lastFiredDay = nil
            }
            saved.rules[i] = copy
        } else if saved.rules.count < 100 { saved.rules.append(copy) }
        else { message = "You can save up to 100 listening rules."; return false }
        return true
    }

    func describeRule(_ rule: AutomationRule) -> String {
        rule.effectiveActions.map { action in
            switch action {
            case .mode(let index): return "Mode: " + (saved.modes.first { $0.id == index }?.name ?? "#\(index)")
            case .noise(let noise): return "Noise: \(Int(noise.level))/10 · \(noise.enabled ? "ANC on" : "ANC off")"
            case .preset(let id): return "Local EQ: " + (id.flatMap { value in presets.first { $0.id == value }?.name } ?? "Off")
            }
        }.joined(separator: " · ")
    }

    func ruleAvailabilityError(_ rule: AutomationRule) -> String? {
        if let error = rule.configurationError { return error }
        if rule.effectiveActions.contains(where: \.needsHeadphones), !connected { return "Connect headphones or start demo mode first." }
        let targetMode = rule.effectiveActions.compactMap { action -> Int? in if case .mode(let index) = action { return index }; return nil }.first
        for action in rule.effectiveActions {
            switch action {
            case .mode(let index):
                guard saved.modes.contains(where: { $0.id == index && $0.configured }), saved.demo || supports(31, 3), !profile.unsupported else { return "This rule’s listening mode is not available on the current headphones." }
            case .noise(let noise):
                let writes = NoiseWriteCapabilities(globalWrite: saved.demo || supports(31, 10) || supports(1, 5), editableModeIDs: Set(saved.modes.filter { canEditMode($0.id) }.map(\.id)), currentMode: saved.currentMode)
                guard !profile.unsupported, writes.canWrite(afterSelecting: targetMode) else { return "These headphones have not reported an available noise-control write path." }
                if noise.wind && !profile.wind { return "Wind Block is not supported by the current headphones." }
                if noise.spatial != 0 && !profile.spatial { return "Spatial audio is not supported by the current headphones." }
            case .preset(let id):
                if let id, !presets.contains(where: { $0.id == id }) { return "This rule refers to a removed EQ preset. Edit the rule and choose another preset." }
            }
        }
        return nil
    }

    /// Accept a whole rule only after every action validates. For real headphones,
    /// wait for the matching report before advancing from mode selection to noise
    /// writes; otherwise a custom-mode fallback could overwrite the previous slot.
    @discardableResult
    func runRule(_ rule: AutomationRule, source: RuleRunSource = .manual) -> Bool {
        if let error = ruleAvailabilityError(rule) {
            if source == .manual || source == .shortcut { message = error }
            return false
        }
        let needsHardware = rule.effectiveActions.contains(where: \.needsHeadphones) && !saved.demo
        if needsHardware, activeRuleID != nil {
            if source == .manual || source == .shortcut { message = "A headphone rule is already running. Wait for its device reports or cancel it first." }
            return false
        }
        if !needsHardware {
            for action in rule.effectiveActions { applyImmediateRuleAction(action) }
            ruleStatuses[rule.id] = saved.demo ? "Applied in demo" : "Local audio settings applied"
            appendAutomationLog("\(rule.name) → \(saved.demo ? "applied in demo" : "local audio settings applied")")
            return true
        }
        activeRuleID = rule.id
        ruleStatuses[rule.id] = "Waiting for headphone reports"
        let deviceID = bluetooth.connectedDeviceID
        automationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for action in rule.effectiveActions {
                    try Task.checkCancellation()
                    guard self.bluetooth.isConnected, self.bluetooth.connectedDeviceID == deviceID, !self.saved.demo else { throw RuleExecutionError.failed("The headphone control link changed.") }
                    let failureVersion = self.commandFailureVersion
                    switch action {
                    case .mode(let index):
                        self.ruleStatuses[rule.id] = "Requesting listening mode"
                        if self.saved.currentMode != index {
                            self.selectMode(index)
                            try await self.waitForRuleReport(failureVersion: failureVersion) { self.saved.currentMode == index }
                        }
                    case .noise(let noise):
                        guard self.canControlNoise else { throw RuleExecutionError.failed("Noise control is unavailable for the selected mode.") }
                        self.ruleStatuses[rule.id] = "Requesting noise settings"
                        if !Self.noiseReport(self.saved.noise, matches: noise) {
                            self.changeNoise(noise)
                            try await self.waitForRuleReport(failureVersion: failureVersion) { Self.noiseReport(self.saved.noise, matches: noise) }
                        }
                    case .preset:
                        self.applyImmediateRuleAction(action)
                    }
                }
                self.ruleStatuses[rule.id] = "Confirmed by headphone reports"
                self.appendAutomationLog("\(rule.name) → confirmed by headphone reports")
            } catch is CancellationError {
                // Explicit cancellation records its own state; do not overwrite it
                // with a late success/failure from this suspended task.
            } catch {
                if self.activeRuleID == rule.id {
                    self.ruleStatuses[rule.id] = "Failed: \(error.localizedDescription)"
                    self.appendAutomationLog("\(rule.name) → failed: \(error.localizedDescription)")
                    if source == .manual || source == .shortcut { self.message = error.localizedDescription }
                }
            }
            if self.activeRuleID == rule.id {
                self.activeRuleID = nil; self.automationTask = nil
                self.processConnectionRules()
            }
        }
        return true
    }

    func cancelRuleExecution(reason: String = "Cancelled") {
        guard let id = activeRuleID else { return }
        automationTask?.cancel(); automationTask = nil; activeRuleID = nil
        ruleStatuses[id] = reason
        appendAutomationLog("Rule → \(reason)")
    }

    func checkSchedules(now: Date = .now, calendar: Calendar = .current) {
        for rule in saved.rules {
            guard let occurrence = rule.scheduleOccurrence(at: now, calendar: calendar),
                  !rule.alreadyAttempted(occurrence, date: now, calendar: calendar),
                  ruleAvailabilityError(rule) == nil else { continue }
            if runRule(rule, source: .schedule), let i = saved.rules.firstIndex(where: { $0.id == rule.id }) {
                // A failed/disconnected preflight never consumes the occurrence.
                // Once accepted, an attempt is latched even if the device refuses it,
                // avoiding a stream of repeated writes throughout the same minute.
                saved.rules[i].lastFiredDay = occurrence
            }
        }
    }

    static func noiseReport(_ actual: NoiseState, matches requested: NoiseState) -> Bool {
        abs(actual.level - requested.level) < 0.6 && actual.enabled == requested.enabled &&
        actual.wind == requested.wind && actual.spatial == requested.spatial
    }

    private func applyImmediateRuleAction(_ action: AutomationAction) {
        switch action {
        case .mode(let index): selectMode(index)
        case .noise(let noise): changeNoise(noise)
        case .preset(let id):
            if let id { saved.proEnabled = true; choosePreset(id) }
            else { saved.proEnabled = false; applyAudio() }
        }
    }

    func waitForRuleReport(failureVersion: Int, matches: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while true {
            try Task.checkCancellation()
            guard bluetooth.isConnected, !saved.demo else { throw RuleExecutionError.failed("The headphone control link disconnected.") }
            guard commandFailureVersion == failureVersion else { throw RuleExecutionError.failed(message ?? "The headphones refused the request.") }
            if matches() { return }
            guard ContinuousClock.now < deadline else { throw RuleExecutionError.failed("The headphones did not confirm the requested value within eight seconds.") }
            try await Task.sleep(for: .milliseconds(80))
        }
    }

    private func appendAutomationLog(_ text: String) {
        automationLog.insert("\(Date.now.formatted(date: .omitted, time: .shortened)) · \(text)", at: 0)
        if automationLog.count > 100 { automationLog.removeLast(automationLog.count - 100) }
    }
}
