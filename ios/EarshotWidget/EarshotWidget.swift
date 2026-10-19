// AI-assisted iOS port attempt of HellzYeahh/earshot (MIT). Original contributors retain credit.
import AppIntents
import SwiftUI
import WidgetKit

struct EarshotEntry: TimelineEntry {
    let date: Date
    var snapshot: EarshotWidgetSnapshot?
}

struct EarshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> EarshotEntry {
        .init(date: .now, snapshot: .init(connected: true, demo: true, profileName: "QC Ultra Earbuds", modeName: "Quiet", batteries: [
            .init(id: "left", name: "Left", percent: 85, remainingMinutes: 270),
            .init(id: "right", name: "Right", percent: 82, remainingMinutes: 250),
            .init(id: "case", name: "Case", percent: 68)
        ]))
    }
    func getSnapshot(in context: Context, completion: @escaping (EarshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : .init(date: .now, snapshot: EarshotShared.snapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EarshotEntry>) -> Void) {
        let now = Date.now
        let snapshot = EarshotShared.snapshot()
        var entries = [EarshotEntry(date: now, snapshot: snapshot)]
        if let staleAt = snapshot?.updatedAt.addingTimeInterval(300), staleAt > now {
            entries.append(.init(date: staleAt, snapshot: snapshot))
        }
        // A scheduled stale entry changes the label even when reloads are budget-limited.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
    }
}

struct EarshotWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: EarshotEntry
    private var snapshot: EarshotWidgetSnapshot? { entry.snapshot }
    private var batteries: [EarshotWidgetBattery] { Array((snapshot?.visibleBatteries ?? []).prefix(family == .systemSmall ? 3 : 4)) }
    private var stale: Bool { snapshot?.isStale(at: entry.date) ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("earshot", systemImage: "waveform").font(.caption.weight(.bold))
                Spacer(minLength: 3)
                if snapshot?.demo == true { Text("DEMO").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
            }
            Text(snapshot.map { $0.connected ? $0.modeName : "Disconnected" } ?? "Open Earshot")
                .font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.75)
            if family != .systemSmall, let snapshot { Text(snapshot.profileName).font(.caption2).lineLimit(1).foregroundStyle(.secondary) }
            if !batteries.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(batteries) { battery in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(battery.name).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
                            Text(battery.validPercent.map { "\($0)%" } ?? "—").font(.callout.weight(.semibold).monospacedDigit())
                            if family != .systemSmall, let remaining = battery.remainingDescription {
                                Text(remaining).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.accessibilityElement(children: .combine)
            }
            HStack(spacing: 3) {
                if let snapshot {
                    Text(stale ? "Older app snapshot" : "App snapshot")
                    Text(snapshot.updatedAt, style: .relative)
                } else { Text("No saved app snapshot") }
            }.font(.system(size: 9)).lineLimit(1)
                .foregroundStyle(stale ? Color(red: 0.50, green: 0.24, blue: 0.05) : Color(red: 0.22, green: 0.34, blue: 0.31))
            Spacer(minLength: 0)
            if family != .systemSmall {
                Text(stale ? "Open app to refresh cycle" : snapshot?.cycleNextModeName.map { "Cycle snapshot next: \($0)" } ?? "Configure Mode cycle in Earshot")
                    .font(.caption2).lineLimit(1).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if family != .systemSmall {
                    Button(intent: OpenEarshotListeningIntent(target: .quiet)) { Label("Quiet", systemImage: "moon").font(.caption2.weight(.semibold)) }
                    Spacer(minLength: 0)
                    Button(intent: OpenEarshotListeningIntent(target: .aware)) { Label("Aware", systemImage: "sun.max").font(.caption2.weight(.semibold)) }
                    Spacer(minLength: 0)
                }
                Button(intent: OpenEarshotListeningIntent(target: .cycle)) { Label("Cycle", systemImage: "arrow.triangle.2.circlepath").font(.caption2.weight(.semibold)) }
                    .accessibilityLabel("Cycle configured listening modes")
            }.buttonStyle(.plain)
        }
        .foregroundStyle(Color(red: 0.04, green: 0.18, blue: 0.16))
        .containerBackground(for: .widget) { Color(red: 0.88, green: 0.96, blue: 0.94) }
        .widgetURL(URL(string: "earshot://home"))
        .privacySensitive()
    }
}

struct EarshotWidget: Widget {
    let kind = "EarshotListeningWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EarshotProvider()) { EarshotWidgetView(entry: $0) }
            .configurationDisplayName("Your listening space")
            .description("Last app snapshot, headphone and earbud battery, and foreground listening-mode requests. Values may be stale.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main struct EarshotWidgets: WidgetBundle {
    var body: some Widget {
        EarshotWidget()
        if #available(iOS 18.0, *) {
            EarshotQuietControl()
            EarshotAwareControl()
            EarshotCycleControl()
        }
    }
}
