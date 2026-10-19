# Native iOS simulator captures

These images show the **AI-assisted iOS port attempt** of [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot). The original app, feature design, protocol research and DSP implementation remain credited to upstream and its cited projects; see [all notices](../../THIRD_PARTY_NOTICES.md).

Captures are exported from actual XCUITest runs with the installed Xcode/iOS Simulator, or taken directly with `simctl`. Demo batteries, modes and device settings are simulated. A screenshot does not establish physical headphone compatibility. [IOS_VALIDATION.md](../IOS_VALIDATION.md) records outcomes and evidence paths; [IOS_MIGRATION.md](../IOS_MIGRATION.md) lists remaining limits.

The historical Android reference screenshots remain in the separate `docs/screenshots/` directory.

| Capture | What it shows |
| --- | --- |
| [Home, light](home-light.png), [Home, dark](home-dark.png) | Native device card, explicit Demo label, modes and system appearance. |
| [iPad Home](ipad-home.png) | iPad Pro 11-inch (M5) layout with native top tabs and demo controls. |
| [Pro EQ](pro-eq.png) | Native controls/response graph and the local-player scope disclosure. |
| [Custom mode](custom-mode.png) | A mode persisted after terminating and relaunching the app. |
| [Original credits](credits.png) | Original Earshot attribution, AI-assisted attempt disclosure and research credits. |
| [Microphone](microphone.png) | Real simulator recording/playback/deletion flow completed; local clip deleted. |
| [Device controls](device-controls.png) | Simulated device reports, LE Audio restart confirmation and independent power-off cancellation. |
| [Connection](connection.png) | Actual simulator audio-route facts and conditional headphone transport. |

The iPhone captures above are exported from the passing **53-test** `Acceptance.xcresult` run. The iPad capture comes from the passing **2-scenario** `iPadSmoke.xcresult` run. Both used the installed Xcode 26.4.1 and runtime iOS 26.4.1.
