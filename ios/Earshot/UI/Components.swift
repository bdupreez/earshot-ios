import SwiftUI

extension Color {
    static let earshot = Color(red: 0.12, green: 0.61, blue: 0.52)
    static let ink = Color(red: 0.08, green: 0.15, blue: 0.17)
}

struct Panel<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title { Text(title).font(.headline) }
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }.padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}

struct InfoNote: View {
    let text: String
    var icon = "info.circle"
    var body: some View {
        Label(text, systemImage: icon).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.earshot.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ToolLink<Destination: View>: View {
    let title: String
    let detail: String
    let icon: String
    @ViewBuilder var destination: Destination
    var body: some View {
        NavigationLink { destination } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title2).foregroundStyle(Color.earshot).frame(width: 42, height: 48)
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline).foregroundStyle(.primary); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }.padding(18).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain)
    }
}

struct HeadphoneArtwork: View {
    var earbuds = false
    var body: some View {
        ZStack {
            Circle().fill(Color.earshot.opacity(0.07)).frame(width: 200, height: 200)
            Circle().stroke(Color.earshot.opacity(0.1), lineWidth: 1).frame(width: 238, height: 238)
            if earbuds { Image(systemName: "earbuds").font(.system(size: 125)).foregroundStyle(.white, Color.ink) }
            else {
                RoundedRectangle(cornerRadius: 72).trim(from: 0.45, to: 1).stroke(Color.black.opacity(0.15), style: StrokeStyle(lineWidth: 20, lineCap: .round)).frame(width: 136, height: 154).offset(y: 3)
                RoundedRectangle(cornerRadius: 72).trim(from: 0.45, to: 1).stroke(Color(red: 0.25, green: 0.30, blue: 0.31), style: StrokeStyle(lineWidth: 15, lineCap: .round)).frame(width: 136, height: 154)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    RoundedRectangle(cornerRadius: 17).fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.2)))
                        .frame(width: 42, height: 88).rotationEffect(.degrees(side * -8)).offset(x: side * 65, y: 48)
                    Capsule().fill(Color(white: 0.1)).frame(width: 17, height: 74).rotationEffect(.degrees(side * -8)).offset(x: side * 44, y: 50)
                }
            }
        }.frame(height: 230).accessibilityHidden(true)
    }
}

/// Restores the local dragLevel/onValueChangeFinished behavior in HellzYeahh and
/// contributors' original Android NoiseControls (MIT), missed by this AI-assisted port.
/// A device report remains authoritative; a drag never writes the reported state.
struct SliderValueDraft {
    private(set) var value: Double?
    private(set) var isEditing = false
    private var cancelled = false
    private var lastCommittedValue: Double?

    mutating func begin(reportedValue: Double, canEdit: Bool) {
        isEditing = true
        cancelled = !canEdit
        value = canEdit ? reportedValue : nil
        lastCommittedValue = nil
    }

    mutating func update(_ candidate: Double, reportedValue: Double, range: ClosedRange<Double>, canEdit: Bool) -> Double? {
        guard canEdit else { cancel(); return nil }
        guard candidate.isFinite else { return nil }
        let rounded = min(range.upperBound, max(range.lowerBound, candidate.rounded()))
        if isEditing {
            if !cancelled { value = rounded }
            return nil
        }
        // VoiceOver and keyboard adjustments may have no touch-editing callbacks.
        return request(rounded, reportedValue: reportedValue)
    }

    mutating func finish(reportedValue: Double, canEdit: Bool) -> Double? {
        defer { isEditing = false; value = nil; cancelled = false }
        guard isEditing, !cancelled, canEdit, let value else { return nil }
        return request(value, reportedValue: reportedValue)
    }

    mutating func cancel() {
        // Keep the cancelled gesture marked until its end callback: late value
        // callbacks must not become immediate accessibility-style commits.
        if isEditing { cancelled = true }
        value = nil
        lastCommittedValue = nil
    }

    mutating func reportChanged() { lastCommittedValue = nil }
    mutating func reset() { self = Self() }

    private mutating func request(_ value: Double, reportedValue: Double) -> Double? {
        guard value != reportedValue, value != lastCommittedValue else { return nil }
        lastCommittedValue = value
        return value
    }
}

struct NoiseLevelDraft {
    private var scalar = SliderValueDraft()
    var level: Double? { scalar.value }
    var isEditing: Bool { scalar.isEditing }
    mutating func begin(reportedLevel: Double, canEdit: Bool) { scalar.begin(reportedValue: reportedLevel, canEdit: canEdit) }
    mutating func update(_ value: Double, latest: NoiseState, canEdit: Bool) -> NoiseState? {
        guard let level = scalar.update(value, reportedValue: latest.level, range: 0...10, canEdit: canEdit) else { return nil }
        var requested = latest; requested.level = level; return requested
    }
    mutating func finish(latest: NoiseState, canEdit: Bool) -> NoiseState? {
        guard let level = scalar.finish(reportedValue: latest.level, canEdit: canEdit) else { return nil }
        var requested = latest; requested.level = level; return requested
    }
    mutating func cancel() { scalar.cancel() }
    mutating func reportChanged() { scalar.reportChanged() }
    mutating func reset() { scalar.reset() }
}

/// Bluetooth absolute settings commit at gesture completion; local audio controls
/// deliberately keep their continuous bindings for responsive DSP and preview.
struct CommittedBluetoothSlider: View {
    let title: String
    let reportedValue: Double
    let range: ClosedRange<Double>
    let contextID: String
    var valueFormat: String? = nil
    let onCommit: (Double) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var phase
    @State private var draft = SliderValueDraft()
    private var canEdit: Bool { isEnabled && phase == .active }
    private var displayedValue: Double { draft.value ?? reportedValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let valueFormat {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(String(format: valueFormat, displayedValue)).monospacedDigit().foregroundStyle(Color.earshot)
                }
            }
            Slider(value: Binding(get: { displayedValue }, set: { value in
                if let requested = draft.update(value, reportedValue: reportedValue, range: range, canEdit: canEdit) { onCommit(requested) }
            }), in: range, step: 1, onEditingChanged: { editing in
                if editing { draft.begin(reportedValue: reportedValue, canEdit: canEdit) }
                else if let requested = draft.finish(reportedValue: reportedValue, canEdit: canEdit) { onCommit(requested) }
            }).accessibilityLabel(title)
        }
        .onAppear { draft.reset() }
        .onDisappear { draft.cancel() }
        .onChange(of: canEdit) { _, canEdit in if !canEdit { draft.cancel() } }
        .onChange(of: contextID) { _, _ in draft.cancel() }
        .onChange(of: range) { _, _ in draft.cancel() }
        .onChange(of: reportedValue) { _, _ in draft.reportChanged() }
        .onChange(of: phase) { _, phase in if phase == .active { draft.reset() } else { draft.cancel() } }
    }
}

struct NoiseControls: View {
    @Binding var noise: NoiseState
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var phase
    @State private var levelDraft = NoiseLevelDraft()
    var profile: DeviceProfile
    var ancToggle = true
    private var ancOn: Bool { noise.enabled || !ancToggle }
    private var canEditLevel: Bool { isEnabled && phase == .active && profile.noise && ancOn && !noise.wind }
    private var displayedLevel: Double { levelDraft.level ?? noise.level }
    var body: some View {
        VStack(spacing: 18) {
            if profile.noise {
                if ancToggle { Toggle("Noise cancellation", isOn: $noise.enabled) }
                VStack(spacing: 8) {
                    HStack { Text("Cancellation level").font(.subheadline); Spacer(); Text("\(Int(displayedLevel))/10").monospacedDigit().foregroundStyle(Color.earshot) }
                    Slider(value: Binding(get: { displayedLevel }, set: { value in
                        if let requested = levelDraft.update(value, latest: noise, canEdit: canEditLevel) { noise = requested }
                    }), in: 0...10, step: 1, onEditingChanged: { editing in
                        if editing { levelDraft.begin(reportedLevel: noise.level, canEdit: canEditLevel) }
                        else if let requested = levelDraft.finish(latest: noise, canEdit: canEditLevel) { noise = requested }
                    }).accessibilityIdentifier("noiseLevel")
                    HStack { Text("Aware"); Spacer(); Text("Quiet") }.font(.caption).foregroundStyle(.secondary)
                }.disabled(!ancOn || noise.wind)
                if noise.wind {
                    Text("Cancellation level has no effect while Wind Block is on.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !ancOn {
                    Text("Cancellation level has no effect while noise cancellation is off.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if profile.wind { Toggle("Wind Block", isOn: $noise.wind) }
            if profile.spatial {
                VStack(alignment: .leading, spacing: 10) { Text("Immersive Audio").font(.subheadline); Picker("Immersive Audio", selection: $noise.spatial) { Text("Off").tag(0); Text("Still").tag(1); Text("Motion").tag(2) }.pickerStyle(.segmented) }
            }
        }
        .onAppear { levelDraft.reset() }
        .onDisappear { levelDraft.cancel() }
        .onChange(of: canEditLevel) { _, canEdit in if !canEdit { levelDraft.cancel() } }
        .onChange(of: profile) { _, _ in levelDraft.cancel() }
        .onChange(of: phase) { _, phase in if phase == .active { levelDraft.reset() } else { levelDraft.cancel() } }
        .onChange(of: noise.level) { _, _ in levelDraft.reportChanged() }
    }
}
