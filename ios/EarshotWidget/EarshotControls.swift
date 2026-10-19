// AI-assisted iOS port attempt of HellzYeahh/earshot (MIT). Original contributors retain credit.
import AppIntents
import SwiftUI
import WidgetKit

// Buttons request foreground work; a toggle would imply live device state that a
// widget cannot guarantee. iOS 17 continues to provide the ordinary Home Screen widget.
@available(iOS 18.0, *)
struct EarshotQuietControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "EarshotQuietControl") {
            ControlWidgetButton(action: QuietModeIntent()) { Label("Quiet mode", systemImage: "moon") }
        }
        .displayName("Earshot Quiet")
        .description("Open Earshot and request Quiet mode on supported connected headphones or the demo device.")
    }
}

@available(iOS 18.0, *)
struct EarshotAwareControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "EarshotAwareControl") {
            ControlWidgetButton(action: AwareModeIntent()) { Label("Aware mode", systemImage: "sun.max") }
        }
        .displayName("Earshot Aware")
        .description("Open Earshot and request Aware mode on supported connected headphones or the demo device.")
    }
}
