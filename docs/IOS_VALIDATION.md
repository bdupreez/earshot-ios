# Validation of the AI-assisted iOS port attempt

The original application is [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot), MIT. This report describes only the **AI-assisted native iOS port attempt** in this fork. Upstream Android test results and captures are preserved separately and do not establish iOS compatibility.

## Environment

- Validation date: 19 October 2026 (Australia/Melbourne).
- Installed Xcode: **26.4.1**, build **17E202**, `/Applications/Xcode.app`.
- Simulator SDK: **iOS 26.4**; the test result reports runtime **iOS 26.4.1 (23E254a)**.
- Primary simulator: **iPhone 17 Pro**, `670AA0BD-A1DF-4768-835F-966A0D09E7B3`.
- Deployment target: iOS 17.0; iOS 17 hardware/runtime was not available for this run.
- Project: `ios/Earshot.xcodeproj`, shared scheme **Earshot**; Swift 5 language mode, no third-party packages.

## Recorded outcomes

| Check | Actual outcome | Evidence |
| --- | --- | --- |
| Native app + Widget extension build | Passed with installed Xcode | `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` |
| iPhone simulator XCTest | **41 passed, 0 failed, 0 skipped** | `ios/TestResults/UnitTestsVerified.xcresult`; verified with `xcresulttool get test-results summary` |

The XCTest count comprises 14 DSP/audio tests, 6 app-state tests, and 21 protocol/integration tests. This final run includes the complete master-bypass regression and the automation-row product fix. No tests are marked as expected failures to obtain this result.

## What the checks establish

The Xcode build compiles a real native iOS app and WidgetKit extension. XCTest checks wire framing/safety, data parsers, state persistence, DSP response math, and waveform output rendered through the actual AVAudioEngine/AVAudioUnitEQ/limiter graph. XCUITest launches the actual app, operates its controls and verifies resulting UI state. Microphone and local-player tests exercise AVFoundation inside Simulator, rather than substituting prerecorded test responses.

Screenshot attachments are retained in the `.xcresult` bundles. Selected exported screenshots are available in `docs/ios-screenshots/` after visual inspection. All original numbered images in `docs/screenshots/` are Android reference images.

## Issues found during validation

- A Swift initialization-order error introduced while validating saved preferences was caught by the test build and repaired.
- A sustained overload test found that the initial peak-only limiter graph decayed toward silence in this installed simulator. The player now uses native dynamics compression followed by peak limiting. Regression checks require audible, finite, bounded output for sustained boosted tones, plus actual amplification of a quiet signal. This is a measured simulator finding; no universal claim about Apple hardware is made.
- An asynchronous initial Bluetooth state event could clear restored demo device controls. The handler now keeps demo state, with a regression test that yields through the asynchronous callback.
- Connection rules could run before a requested custom-mode frame arrived and falsely log a sent request. Rules now wait for their configured target mode, and unavailable manual/scheduled modes cannot log success.
- Actual UI test video revealed that tapping Run now also opened the automation editor: SwiftUI List's automatic button style shared an action across sibling buttons. Separate borderless actions prevent the editor action from firing on a Run now tap.

Earlier failed/diagnostic `.xcresult` bundles are retained locally alongside the final runs. The final result paths below identify the authoritative outcomes.

## Limits of this evidence

- Simulator has no physical headphone BLE transport. No Bose or Skullcandy device, firmware, L2CAP channel, push notification, custom-mode write, headphone volume, source, or shortcut command has been verified against physical hardware here.
- Simulator recording validates the simulator/host input and a local audio file, not a Bluetooth headset microphone. Numerical audio tests do not establish perceptual quality, acoustic loudness, or hearing safety.
- Widget extension compilation does not establish App Group provisioning on a signed iPhone, Widget gallery behaviour, Siri recognition, or real-world Shortcuts delivery.
- Background Bluetooth restoration, reconnect behaviour, notification delivery, screen-reader usability, VoiceOver, all Dynamic Type sizes, and every device/firmware need additional acceptance testing.
- Unsupported Android-only features and remaining implementation gaps are listed in [the migration matrix](IOS_MIGRATION.md). This port must not be advertised as complete functional parity.

## Reproduce

```sh
EARSHOT_SIMULATOR_ID=670AA0BD-A1DF-4768-835F-966A0D09E7B3 ios/scripts/test-simulator.sh
```

Build and result directories are ignored by Git. Open the generated `.xcresult` in Xcode to inspect individual assertions, native test logs, failure history, and screenshots. Follow the hardware acceptance procedure in [IOS_MIGRATION.md](IOS_MIGRATION.md) before making compatibility claims.
