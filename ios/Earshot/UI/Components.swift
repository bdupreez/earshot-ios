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

struct NoiseControls: View {
    @Binding var noise: NoiseState
    var profile: DeviceProfile
    var body: some View {
        VStack(spacing: 18) {
            if profile.noise {
                Toggle("Noise cancellation", isOn: $noise.enabled)
                VStack(spacing: 8) {
                    HStack { Text("Cancellation level").font(.subheadline); Spacer(); Text("\(Int(noise.level))/10").monospacedDigit().foregroundStyle(Color.earshot) }
                    Slider(value: $noise.level, in: 0...10, step: 1).accessibilityIdentifier("noiseLevel")
                    HStack { Text("Aware"); Spacer(); Text("Quiet") }.font(.caption).foregroundStyle(.secondary)
                }.disabled(!noise.enabled)
            }
            if profile.wind { Toggle("Wind Block", isOn: $noise.wind) }
            if profile.spatial {
                VStack(alignment: .leading, spacing: 10) { Text("Immersive Audio").font(.subheadline); Picker("Immersive Audio", selection: $noise.spatial) { Text("Off").tag(0); Text("Still").tag(1); Text("Motion").tag(2) }.pickerStyle(.segmented) }
            }
        }
    }
}
