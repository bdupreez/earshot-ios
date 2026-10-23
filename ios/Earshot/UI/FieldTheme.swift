// Field palette and typography: HellzYeahh and Earshot contributors (MIT).
// Native iOS adaptation; bundled Barlow and JetBrains Mono retain their SIL OFL notices.
import SwiftUI

struct EarshotPalette {
    let background: Color
    let card: Color
    let text: Color
    let muted: Color
    let accent: Color
    let filledText: Color
    let hairline: Color
    let dots: Color
    let isField: Bool

    static func make(style: EarshotVisualStyle, dark: Bool) -> Self {
        if style == .system {
            return .init(background: Color(uiColor: .systemGroupedBackground), card: Color(uiColor: .secondarySystemGroupedBackground), text: .primary, muted: .secondary, accent: .blue, filledText: .white, hairline: Color(uiColor: .separator), dots: .clear, isField: false)
        }
        if dark {
            return .init(background: hex(0x0F130E), card: hex(0x171D15), text: hex(0xE4E9D6), muted: hex(0x9AA58A), accent: hex(0xFF7A2E), filledText: hex(0x1C2316), hairline: hex(0x2E382A), dots: hex(0xE4E9D6).opacity(0.08), isField: true)
        }
        return .init(background: hex(0xD8DCCD), card: hex(0xECEFE3), text: hex(0x1C2316), muted: hex(0x4F5A44), accent: hex(0x3F4D2B), filledText: .white, hairline: hex(0xA6AE97), dots: hex(0x1C2316).opacity(0.14), isField: true)
    }
    static func hex(_ value: UInt32) -> Color { Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255) }
    var heading: Font { isField ? .custom("BarlowCondensed-SemiBold", size: 22, relativeTo: .headline) : .headline }
    var label: Font { isField ? .custom("JetBrainsMono-Regular", size: 12, relativeTo: .caption) : .caption.monospaced() }
}

private struct EarshotPaletteKey: EnvironmentKey { static let defaultValue = EarshotPalette.make(style: .system, dark: false) }
extension EnvironmentValues {
    var earshotPalette: EarshotPalette {
        get { self[EarshotPaletteKey.self] }
        set { self[EarshotPaletteKey.self] = newValue }
    }
}

private struct EarshotVisualStyleModifier: ViewModifier {
    let style: EarshotVisualStyle
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let palette = EarshotPalette.make(style: style, dark: colorScheme == .dark)
        content.environment(\.earshotPalette, palette)
            .tint(palette.accent).accentColor(palette.accent)
            .foregroundStyle(palette.text)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .toolbarBackground(palette.background, for: .navigationBar, .tabBar)
    }
}
extension View {
    func earshotVisualStyle(_ style: EarshotVisualStyle) -> some View { modifier(EarshotVisualStyleModifier(style: style)) }
}

struct EarshotFieldBackground: View {
    @Environment(\.earshotPalette) private var palette
    var body: some View {
        palette.background.overlay {
            if palette.isField {
                Canvas { context, size in
                    var dots = Path()
                    for x in stride(from: 8.0, through: size.width, by: 20) {
                        for y in stride(from: 8.0, through: size.height, by: 20) { dots.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5)) }
                    }
                    context.fill(dots, with: .color(palette.dots))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}


private struct EarshotProminentButtonModifier: ViewModifier {
    @Environment(\.earshotPalette) private var palette
    func body(content: Content) -> some View {
        // Preserve the native button style, with readable text on Field's lamps.
        content.buttonStyle(.borderedProminent).foregroundStyle(palette.filledText)
    }
}
extension View {
    func earshotProminentButton() -> some View { modifier(EarshotProminentButtonModifier()) }
}
