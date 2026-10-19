// AI-assisted iOS port attempt of HellzYeahh/earshot (MIT). Original contributors retain credit.
// Actions request foreground app work; enqueueing never claims that a headset accepted a write.
import AppIntents
import Foundation

struct EarshotModeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Listening mode"
    static var defaultQuery = EarshotModeQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct EarshotModeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [EarshotModeEntity] {
        let items = EarshotShared.catalog().modes
        return identifiers.compactMap { id in items.first { $0.id == id }.map { .init(id: $0.id, name: $0.name) } }
    }
    func suggestedEntities() async throws -> [EarshotModeEntity] { EarshotShared.catalog().modes.map { .init(id: $0.id, name: $0.name) } }
}
struct EarshotPresetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Local EQ preset"
    static var defaultQuery = EarshotPresetQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct EarshotPresetQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [EarshotPresetEntity] {
        let items = EarshotShared.catalog().presets
        return identifiers.compactMap { id in items.first { $0.id == id }.map { .init(id: $0.id, name: $0.name) } }
    }
    func suggestedEntities() async throws -> [EarshotPresetEntity] { EarshotShared.catalog().presets.map { .init(id: $0.id, name: $0.name) } }
}
struct EarshotRuleEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Listening rule"
    static var defaultQuery = EarshotRuleQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct EarshotRuleQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [EarshotRuleEntity] {
        let items = EarshotShared.catalog().rules
        return identifiers.compactMap { id in items.first { $0.id == id }.map { .init(id: $0.id, name: $0.name) } }
    }
    func suggestedEntities() async throws -> [EarshotRuleEntity] { EarshotShared.catalog().rules.map { .init(id: $0.id, name: $0.name) } }
}

struct QuietModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Use Quiet mode in Earshot"
    static var description = IntentDescription("Open Earshot and request the device’s Quiet mode. The app checks whether the current model supports it.")
    static var openAppWhenRun = true
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    func perform() async throws -> some IntentResult { try EarshotShared.request(.listeningRole(.quiet)); return .result() }
}
struct AwareModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Use Aware mode in Earshot"
    static var description = IntentDescription("Open Earshot and request the device’s Aware mode. The app checks whether the current model supports it.")
    static var openAppWhenRun = true
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    func perform() async throws -> some IntentResult { try EarshotShared.request(.listeningRole(.aware)); return .result() }
}
struct SetListeningModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set listening mode in Earshot"
    static var description = IntentDescription("Open Earshot and request a configured listening mode. Open the app first to refresh the device’s available choices.")
    static var openAppWhenRun = true
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Listening mode") var mode: EarshotModeEntity
    static var parameterSummary: some ParameterSummary { Summary("Request \(\.$mode)") }
    init() {}
    init(mode: EarshotModeEntity) { self.mode = mode }
    func perform() async throws -> some IntentResult {
        guard let index = Int(mode.id) else { throw EarshotIntegrationError.invalidCommand }
        try EarshotShared.request(.listeningMode(index: index))
        return .result()
    }
}
struct SetNoiseLevelIntent: AppIntent {
    static var title: LocalizedStringResource = "Set cancellation level in Earshot"
    static var description = IntentDescription("Open Earshot and request a cancellation level from 0 (Aware) to 10 (Quiet). Device support is required.")
    static var openAppWhenRun = true
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Cancellation level", inclusiveRange: (0, 10)) var level: Double
    static var parameterSummary: some ParameterSummary { Summary("Request cancellation level \(\.$level)") }
    func perform() async throws -> some IntentResult { try EarshotShared.request(.noiseLevel(level)); return .result() }
}
struct SetHardwareEQIntent: AppIntent {
    static var title: LocalizedStringResource = "Set headphone EQ in Earshot"
    static var description = IntentDescription("Open Earshot and request the headphone’s three-band EQ in decibels. Each band must be between −10 and +10; the app checks device support.")
    static var openAppWhenRun = true
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Bass dB", default: 0, inclusiveRange: (-10, 10)) var bass: Double
    @Parameter(title: "Mid dB", default: 0, inclusiveRange: (-10, 10)) var mid: Double
    @Parameter(title: "Treble dB", default: 0, inclusiveRange: (-10, 10)) var treble: Double
    static var parameterSummary: some ParameterSummary { Summary("Request EQ: bass \(\.$bass), mid \(\.$mid), treble \(\.$treble)") }
    func perform() async throws -> some IntentResult { try EarshotShared.request(.hardwareEQ(bass: bass, mid: mid, treble: treble)); return .result() }
}
struct ApplyLocalPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply local EQ preset in Earshot"
    static var description = IntentDescription("Open Earshot and apply a saved preset to audio played inside Earshot. This does not change other apps’ audio and does not start playback.")
    static var openAppWhenRun = true
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Local EQ preset") var preset: EarshotPresetEntity
    static var parameterSummary: some ParameterSummary { Summary("Apply \(\.$preset) to Earshot playback") }
    func perform() async throws -> some IntentResult { try EarshotShared.request(.localPreset(id: preset.id)); return .result() }
}
struct RunListeningRuleIntent: AppIntent {
    static var title: LocalizedStringResource = "Run listening rule in Earshot"
    static var description = IntentDescription("Open Earshot and run a saved rule’s supported actions. Use this action in user-created Shortcuts personal automations for app, Wi-Fi, time or other system triggers. Earshot opens to execute; background execution is not promised.")
    static var openAppWhenRun = true
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .foreground }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Listening rule") var rule: EarshotRuleEntity
    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$rule)") }
    func perform() async throws -> some IntentResult { try EarshotShared.request(.runRule(id: rule.id)); return .result() }
}

struct EarshotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: QuietModeIntent(), phrases: ["Use Quiet mode in \(.applicationName)"], shortTitle: "Quiet mode", systemImageName: "moon")
        AppShortcut(intent: AwareModeIntent(), phrases: ["Use Aware mode in \(.applicationName)"], shortTitle: "Aware mode", systemImageName: "sun.max")
        AppShortcut(intent: SetListeningModeIntent(), phrases: ["Set listening mode in \(.applicationName)"], shortTitle: "Listening mode", systemImageName: "waveform")
        AppShortcut(intent: SetNoiseLevelIntent(), phrases: ["Set cancellation level in \(.applicationName)"], shortTitle: "Cancellation level", systemImageName: "speaker.wave.2")
        AppShortcut(intent: SetHardwareEQIntent(), phrases: ["Set headphone EQ in \(.applicationName)"], shortTitle: "Headphone EQ", systemImageName: "slider.horizontal.3")
        AppShortcut(intent: ApplyLocalPresetIntent(), phrases: ["Apply local EQ preset in \(.applicationName)"], shortTitle: "Local EQ preset", systemImageName: "line.3.horizontal.decrease")
        AppShortcut(intent: RunListeningRuleIntent(), phrases: ["Run listening rule in \(.applicationName)"], shortTitle: "Run listening rule", systemImageName: "bolt")
    }
}
