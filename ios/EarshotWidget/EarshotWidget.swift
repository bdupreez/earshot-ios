// AI-assisted iOS port attempt of https://github.com/HellzYeahh/earshot (MIT).
import SwiftUI
import WidgetKit

struct EarshotEntry: TimelineEntry {
    let date: Date
    var mode: String
    var battery: Int?
    var demo: Bool
    var updated: Date?
}

struct EarshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> EarshotEntry { .init(date: .now, mode: "Quiet", battery: 82, demo: true) }
    func getSnapshot(in context: Context, completion: @escaping (EarshotEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EarshotEntry>) -> Void) { completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(900)))) }
    private func entry() -> EarshotEntry {
        let defaults = UserDefaults(suiteName: "group.dev.earshot.ios")
        return .init(date: .now, mode: defaults?.string(forKey: "widgetMode") ?? "Open Earshot", battery: defaults?.object(forKey: "widgetBattery") as? Int, demo: defaults?.bool(forKey: "widgetDemo") ?? false, updated: defaults?.object(forKey: "widgetUpdated") as? Date)
    }
}

struct EarshotWidgetView: View {
    let entry: EarshotEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("earshot", systemImage: "waveform").font(.headline); Spacer(); if let battery = entry.battery { Text("\(battery)%").font(.caption.monospacedDigit()) } }
            Text(entry.mode).font(.title2.bold())
            Text(entry.demo ? "DEMO · last app state" : "Last app state").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Link(destination: URL(string: "earshot://mode/0")!) { Label("Quiet", systemImage: "moon").font(.caption.weight(.semibold)) }
                Spacer()
                Link(destination: URL(string: "earshot://mode/1")!) { Label("Aware", systemImage: "sun.max").font(.caption.weight(.semibold)) }
            }
        }.containerBackground(for: .widget) { Color(red: 0.88, green: 0.96, blue: 0.94) }
            .widgetURL(URL(string: "earshot://home"))
    }
}

@main struct EarshotWidget: Widget {
    let kind = "EarshotListeningWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EarshotProvider()) { EarshotWidgetView(entry: $0) }
            .configurationDisplayName("Your listening space")
            .description("The last state reported by Earshot. Open the app to request a listening mode.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
