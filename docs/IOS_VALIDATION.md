# Validation of the AI-assisted iOS port attempt

The original application is [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot), MIT. This report describes only the **AI-assisted native iOS port attempt** in this fork. Upstream Android test results and captures are preserved separately and do not establish iOS compatibility.

## Environment

- Validation date: 19 October 2026 (Australia/Melbourne).
- Installed Xcode: **26.4.1**, build **17E202**, `/Applications/Xcode.app`.
- Simulator SDK: **iOS 26.4**; the test result reports runtime **iOS 26.4.1 (23E254a)**.
- Primary simulator: **iPhone 17 Pro**, `670AA0BD-A1DF-4768-835F-966A0D09E7B3`.
- Secondary simulator: **iPad Pro 11-inch (M5)**, `F0735D38-82C8-4F9F-B319-410374B0B2B7`, also runtime iOS 26.4.1 (23E254a).
- Deployment target: iOS 17.0; iOS 17 hardware/runtime was not available for this run.
- Project: `ios/Earshot.xcodeproj`, shared scheme **Earshot**; Swift 5 language mode, no third-party packages.

## Baseline outcomes (before the feature-gap pass)

| Check | Actual outcome | Evidence |
| --- | --- | --- |
| Native app + Widget extension build | Passed with installed Xcode | `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` |
| Combined iPhone simulator acceptance | **53 passed, 0 failed, 0 skipped** | `ios/TestResults/Acceptance.xcresult`; `xcodebuild` exited 0 and `xcresulttool get test-results summary` confirms Passed |
| Focused device-control harness follow-up | **1 passed, 0 failed, 0 skipped** | `ios/TestResults/UIDeviceControlsFinal.xcresult`; final observed-thumb slider drag plus volume/playback/restart/power cancellation assertions |
| iPad UI smoke, normal build | **2 passed, 0 failed, 0 skipped** | `ios/TestResults/iPadSmoke.xcresult`; onboarding/demo mode switching and tools/compatibility navigation |
| Earlier independent unit suite | **41 passed, 0 failed, 0 skipped** | `ios/TestResults/UnitTestsVerified.xcresult` |

Compact [Xcode summary exports](ios-test-results/README.md) are checked into the fork; full result bundles remain local.

The combined run comprises **41 unit tests** (14 DSP/audio, 6 app-state and 21 protocol/integration) and **12 XCUITest scenarios**. It includes the complete master-bypass regression, automation-row fix, fresh microphone recording, device-control confirmations, onboarding, persistence, attribution and both appearances. The focused device-control and iPad smoke runs repeat existing scenarios; they are additional device/harness evidence, not additional distinct test cases. The complete 12-scenario UI suite ran on iPhone; only the two stated smoke scenarios ran on iPad. No tests are marked as expected failures to obtain these results.

## What the checks establish

The Xcode build compiles a real native iOS app and WidgetKit extension. XCTest checks wire framing/safety, data parsers, state persistence, DSP response math, and waveform output rendered through the actual AVAudioEngine/AVAudioUnitEQ/limiter graph. XCUITest launches the actual app, operates its controls and verifies resulting UI state. Microphone and local-player tests exercise AVFoundation inside Simulator, rather than substituting prerecorded test responses.

Screenshot attachments are retained in the `.xcresult` bundles. Selected exported screenshots from the passing iPhone acceptance and iPad smoke runs are available in [docs/ios-screenshots/](ios-screenshots/README.md) after visual inspection. All original numbered images in `docs/screenshots/` are Android reference images.

## Issues found during validation

- A Swift initialization-order error introduced while validating saved preferences was caught by the test build and repaired.
- A sustained overload test found that the initial peak-only limiter graph decayed toward silence in this installed simulator. The player now uses native dynamics compression followed by peak limiting. Regression checks require audible, finite, bounded output for sustained boosted tones, plus actual amplification of a quiet signal. This is a measured simulator finding; no universal claim about Apple hardware is made.
- An asynchronous initial Bluetooth state event could clear restored demo device controls. The handler now keeps demo state, with a regression test that yields through the asynchronous callback.
- Connection rules could run before a requested custom-mode frame arrived and falsely log a sent request. Rules now wait for their configured target mode, and unavailable manual/scheduled modes cannot log success.
- Actual UI test video revealed that tapping Run now also opened the automation editor: SwiftUI List's automatic button style shared an action across sibling buttons. Separate borderless actions prevent the editor action from firing on a Run now tap.
- A strict fresh-recording UI check found the live recorder clock could show 8.8 seconds for a finalized 7.963-second AAC clip. The display now uses the finalized file's frame count/sample rate. The fresh capture/play/delete check passed after this correction.

Test automation also needed platform-specific corrections. Accessibility can report a control beneath the translucent iOS 26 tab bar as hittable, so the harness checks the visible control frame before tapping. Anchored confirmation popovers can omit a Cancel button, so cancellation taps outside the popover and asserts dismissal and unchanged state. XCTest’s standard slider adjustment intermittently triggered an interactive Back swipe; a follow-up check uses a drag from the observed slider thumb. These are harness corrections; recorded failures remain in the earlier bundles. The final rebuilt device-control log explicitly records the thumb press/drag and changed reported volume.

The first iPad attempt stalled during Simulator cold boot/launch, before an app process started. After restarting that simulator, direct app launch succeeded. A subsequent smoke attempt exposed a test-only assumption that tabs always have a `TabBar` accessibility container: iPad exposes its floating top tabs as semantic buttons. The helper now uses the compact TabBar when present and exact-label buttons otherwise. A normal-build rerun of both iPad cases passed, and its Home layout was visually inspected. Earlier diagnostics remain in `iPadSmokeLaunchStalled.xcresult` and `iPadSmokeTabHarness.xcresult`.

Simulator microphone permission was pre-granted before acceptance to isolate real recording from an XCTest interruption-monitor stall. The microphone case deletes any existing recording, captures a fresh approximately eight-second clip, checks the finalized duration, plays it, and deletes it. This does not verify the first-install microphone permission flow.

Earlier failed/diagnostic `.xcresult` bundles, including `AcceptanceInitial.xcresult`, are retained locally alongside the final runs. The table above identifies authoritative outcomes.

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

For the recorded iPad smoke scope:

```sh
xcodebuild -project ios/Earshot.xcodeproj -scheme Earshot \
  -destination 'platform=iOS Simulator,id=F0735D38-82C8-4F9F-B319-410374B0B2B7' \
  -derivedDataPath ios/build -resultBundlePath ios/TestResults/iPadSmoke-NEW.xcresult \
  -only-testing:EarshotUITests/EarshotUITests/testWelcomeAndDemoModeSwitching \
  -only-testing:EarshotUITests/EarshotUITests/testToolsAndCompatibilityNavigation \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Choose a new result path for every run. Build and result directories are ignored by Git. Open the generated `.xcresult` in Xcode to inspect individual assertions, native test logs, failure history, and screenshots. Follow the hardware acceptance procedure in [IOS_MIGRATION.md](IOS_MIGRATION.md) before making compatibility claims.

## Feature-gap pass — first integrated checkpoint

The next native implementation was built and tested with the same installed Xcode26.4.1/iPhone17Pro/iOS26.4.1 environment. `ios/TestResults/FeaturePass1Units.xcresult` reports **96 passed, 0 failed, 0 skipped**, and `xcodebuild` exited0. This runs all eight unit-test classes, including new preset/player lifecycle, multi-action/schedule/migration, Bluetooth/reconnect/scanner, shared command queue and native notification-plan checks. The application and widget/control extension compile together. Compact export: [feature-pass1-units.json](ios-test-results/feature-pass1-units.json).

The baseline 12 UI scenarios have not yet been rerun on these expanded sources at this checkpoint. New feature UI cases are under development. Hardware, SSID entitlement access, signed widgets/Control Center/Shortcuts, background restoration and actual notification delivery remain unverified; unit queue/planner tests do not establish those platform outcomes.


## Feature-gap pass — Wi-Fi, controls and actual shared container

`ios/TestResults/FeaturePass2SignedUnits.xcresult` reports **105 passed, 0 failed, 0 skipped** with locally ad hoc signed Simulator app/extension binaries (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`). This includes actual installed-app access to its declared App Group container and a queue write/reopen/drain in an isolated child directory. It does not prove cross-process widget delivery or signed-device provisioning. Export: [feature-pass2-signed-units.json](ios-test-results/feature-pass2-signed-units.json).

The first attempt (`FeaturePass2Units.xcresult`) passed104/105: the real App Group container was unavailable under `CODE_SIGNING_ALLOWED=NO`. The test was retained, and local ad hoc signing made the entitlement available; no production fallback or test skip was introduced. The simulator test script now uses ad hoc signing and needs no Apple development account. A bare unsigned build remains useful for compilation but cannot establish App Group behavior.

Added unit coverage includes Wi-Fi join/SSID matching, initialization without permission/query side effects, signed16-bit experimental latency validation, demo state changes and the `OpenIntent` widget/control contract. Optional SSID observation and experimental device writes still require physical acceptance. The compact Wind Block report helper and expanded UI flows are subsequent changes awaiting their next test run.


## Feature-gap pass — integrated review fixes

`ios/TestResults/FeatureGapUnitsFinal.xcresult` reports **125 passed, 0 failed, 0 skipped** on the same iPhone17Pro/iOS26.4.1 simulator, with local ad hoc signing and xcodebuild exit0. Export: [feature-gap-units-final.json](ios-test-results/feature-gap-units-final.json). All13 unit classes ran, including actual native finish/replay and hardware-idle checks, waveform/preamp consistency, dirty-draft preservation, direct noise step/toggle semantics, read-only status/profile layouts, recovery export after clean relaunch, product identity precedence and Wi-Fi opt-out protection.

The expanded22-scenario XCUITest suite is running at this checkpoint. No UI acceptance claim is inferred from the unit result. Public-API code is implemented, but physical Bluetooth/SSID/signed system-surface validation is still pending.


## Expanded UI diagnostic history

The first complete expanded UI run, `FeatureGapUIInitial.xcresult`, finished with **17 passed, 5 failed, 0 skipped** (all12 baseline cases passed). New flows confirmed multi-action rules, source confirmations, actual player seek/progress/A-B/stop, weekday/reminder persistence and permission-free demo Wi-Fi navigation. Five harness failures required repair before acceptance: a center tap left a text-field suffix, full-screen scrolls oscillated past controls or virtualized rows, and top-anchored confirmation popovers covered the background navigation title used to cancel them.

The exported accessibility hierarchy showed actual saved names `Morning cans· 2nd Gen` and `Morning librarycurve`, confirming that blind prefix deletion did not replace the full input. The repaired harness uses native text selection and verifies the exact fixture. It normalizes UIKit’s placeholder value for an empty field, uses bounded drags and cancels through the observed native popover dismissal region. `FeatureGapFocused.xcresult` contains135 passing unit tests and an intentionally interrupted UI diagnostic attempt after that placeholder behavior was identified. These diagnostic bundles are not final acceptance evidence; no failed tests have been skipped or marked expected failures.

The simulator script now builds for testing with local signing, installs the app and explicitly grants Simulator microphone access before test execution. This makes the real recorder flow reproducible; first-install consent and physical headset routing remain separate acceptance items.
