# Validation of the AI-assisted iOS port attempt

The original application is [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot), MIT. This report describes only the **AI-assisted native iOS port attempt** in this fork. Upstream Android test results and captures are preserved separately and do not establish iOS compatibility.

## Upstream 0.75 native 0.2 pass — 23 October 2026

Full source review covers 42 commits and 311 changed files through 9e6c491, with per-commit
[implementation/platform decisions](IOS_UPSTREAM_075_AUDIT.md). Installed Xcode remains 26.4.1
(17E202), iPhone 17 Pro Simulator 670AA0BD…E7B3, actual runtime 26.4.1 (23E254a). Native 0.2/build 2
uses ad hoc signing (`CODE_SIGN_IDENTITY=-`, empty DEVELOPMENT_TEAM) for actual App Group tests.
Local personal signing settings are retained separately and excluded from the generated commit.

| Actual local result bundle | Observed outcome |
| --- | --- |
| Upstream075-iPhone-Unit | 237 total, 235 passed, 2 failed: directory-URL comparison in a new test, and Sleep ANC-prompt mutation classification. [Preserved summary](ios-test-results/upstream075-initial-units.json). |
| Upstream075-iPhone-NewFeatures | 263 total, 260 passed, 3 failed. All 258 units passed; release notes obscured vendor UI and the memo test waited for an exact elapsed tick. [Preserved summary](ios-test-results/upstream075-first-feature-attempt.json). |
| Upstream075-iPhone-NewFeatures2 | 263 total, 262 passed, 1 failed. All 258 units and four new UI journeys passed; the Sennheiser container overrode child identifiers. [Preserved summary](ios-test-results/upstream075-iphone-new-features.json). |
| Upstream075-iPhone-VendorFinal | 1/1 passed, zero failures/skips; real native slider interaction after containing the vendor accessibility group. [Summary](ios-test-results/upstream075-vendor-ui-final.json). |

An intermediate test build failed on a private test-fixture flag and was repaired. Installed-Xcode
builds then passed. Independent source reviews found and corrected both low-code Soundcore setting
commands 1075/1077, missing reverse memo→player ownership and late BAS disconnect callbacks before
recording acceptance. Tests exercise the production frame guards, parsers, route policy and battery
read lifecycle; synthetic captures are explicitly simulated and never sent as live commands.
The actual recording UI captures foreground audio and verifies that starting local playback saves
and stops the memo. Microphone permission is pre-granted in Simulator; first-install device consent
and actual headset-input quality are separate acceptance work.

The final **Upstream075-iPhone-Checkpoint.xcresult passed 263/263**, zero failures/skips,
Xcode exit 0: all 258 unit/integration tests plus five actual UI journeys in one run.
[Actual summary](ios-test-results/upstream075-iphone-checkpoint.json). Exported screenshots
were inspected after correcting visible setting labels, independent child identifiers and
filled-button contrast. The memo screenshot shows a newly saved 15-second AAC clip after
local playback started; no physical headset input is inferred.

### Follow-up: complete app UI, route identity and preference management

| Actual local result bundle | Observed outcome |
| --- | --- |
| `Upstream075-iPhone-AppUI` | **36 passed, 2 failed, 0 skipped** across all 38 then-current app UI cases. Large-text scrolling overshot the target; the preset rename helper tried to scroll the native alert's small internal viewport. [Summary](ios-test-results/upstream075-iphone-app-ui-initial.json). |
| `Upstream075-iPhone-Final` | **282 passed, 2 failed, 0 skipped**: all **278 units** and four UI cases passed, including the repaired full preset lifecycle, Field/System persistence, neutral Home and vendor settings. Nickname assertion used the standalone value rather than its combined labelled row; full flicks still oscillated the large-text control. [Summary](ios-test-results/upstream075-iphone-final-attempt.json). |
| `Upstream075-iPhone-Repairs` | **281/281 passed**, Xcode exit 0, no skips/expected failures: all **278 units**, nickname save/relaunch/cancel/confirmed-forget, neutral disconnected Home and actual Soundcore menu selection at Accessibility XXXL. [Summary](ios-test-results/upstream075-iphone-repairs.json). |
| `Upstream075-iPhone-SystemAndValues` | **6/6 passed**, Xcode exit 0, zero failures/skips: actual Control Center Cycle, small-widget Cycle and medium-widget Aware, plus Sennheiser/Soundcore selected accessibility values and the Accessibility XXXL interaction. [Summary](ios-test-results/upstream075-iphone-system-and-values.json). |
| `Upstream075-iPad-Final` | **288 passed, 2 failed, 0 skipped**: all **278 units** and 10 of 12 representative app UI cases passed. First-upgrade notes covered the tab after EQ relaunch; expanded disclosure header bounds covered the Forget child. [Summary](ios-test-results/upstream075-ipad-initial.json). |
| `Upstream075-iPad-Repairs` | **281/281 passed**, Xcode exit 0, zero failures/skips: all **278 units**, exact three-band EQ/relaunch, nickname cancel/confirmed-forget and real memo finalization on the repaired native disclosure layout. [Summary](ios-test-results/upstream075-ipad-repairs.json). |
| `Upstream075-iPhone-OutputFinal` | **2/2 passed**, Xcode exit 0, zero failures/skips: nickname save/relaunch/cancel/confirmed-forget and real memo finalization repeated on iPhone with the final disclosure layout. [Summary](ios-test-results/upstream075-iphone-output-final.json). |

The final test helper directly edits the native alert field and requires its dismissal; exact
rename/relaunch/delete-to-Flat assertions remain. Short gutter drags near the target prevent
inertial scroll oscillation. The saved nickname row has a single accessible label/value and a
fresh test nickname permits retries without erasing unrelated preferences. No expected-failure
or skip was added. The actual failure hierarchy confirms the nickname had saved correctly.

Twenty additional unit regressions cover explicit create/copy/editor/import memory (7), bounded
nickname migration/persistence and selective offline forgetting (8), and Home audio-route/control
identity separation (5). Home may show an actual external route or app-only nickname without
granting controls or inheriting Bose telemetry. A connected BMAP device and a different selected
audio output retain separate identities; demo never adopts a physical route. Simulator tests do
not establish real headset route delivery.

Exported [Field](ios-screenshots/upstream075-field-light.png),
[System colours](ios-screenshots/upstream075-system-light.png),
[neutral Home](ios-screenshots/upstream075-neutral-home.png),
[saved preferences](ios-screenshots/upstream075-output-preferences.png) and
[Accessibility XXXL](ios-screenshots/upstream075-accessibility-xxxl.png) PNGs were visually
inspected. The large-text listening-mode control is fully above the floating tab bar and was
actually operated. These are native Simulator captures, with demo settings explicitly simulated.
Selected menu values are explicit accessibility values, verified before/after actual Soundcore
selection and for the Sennheiser fixture. This is accessibility-tree evidence, not a full manual
VoiceOver spoken-navigation audit.

Actual [Control Center](ios-screenshots/upstream075-control-center.png),
[small widget](ios-screenshots/upstream075-widget-small.png) and
[medium widget](ios-screenshots/upstream075-widget-medium.png) element PNGs were inspected.
The system itself opened Earshot and applied the requested demo mode; the tests never activated
it on the system's behalf. Medium-widget header/actions remain within its native viewport and
Left/Right/Case labels are present. Stamped snapshots are not live hardware telemetry.
The [current iPhone manifest](ios-test-results/current-iphone-coverage.json) records **278 unit,
39 app UI and three system UI** identifiers, all latest Passed across named runs, not one combined run.

All **38 offline Python tests passed** locally: 23 GET-only checker regressions and 15 synthetic
project/privacy tests. The actual fork-hosted Ubuntu [workflow 39892166974](https://github.com/bdupreez/earshot-ios/actions/runs/39892166974)
at `5ad2e373943555c9f2c203a858d3d9fac78795b8` passed: **36 passed, two macOS parser tests skipped**
(`Ran 38`, `OK (skipped=2)`), the reviewed-boundary comparison returned **identical**, and report
publication succeeded. Both skipped parser tests passed locally on macOS. [Actual run metadata](ios-test-results/upstream075-hosted-checker.json).
Existing local project,
target and configuration dictionaries were compared before/after membership reconciliation and
are unchanged. Generated resource IDs are now relative and reproducible across checkout paths;
personal signing/account keys are not committed configuration or test fixtures. The actual guard
also flagged an ambiguous empty-team spelling in historical Markdown; it now uses an explicitly
quoted empty assignment, and the full indexed-file check passes. Older evidence below remains historical.
No physical headphone acceptance is inferred from this work.

The actual **iPad Pro 11-inch (M5), iOS 26.4.1 (23E254a)** pass reran all 278 units and 12
representative app journeys. All 12 have passing latest results across the two stated iPad runs;
the containing 290-test attempt remains Failed. The repair uses a separate 44-point native
expansion button with sibling Forget actions, rather than the expanded DisclosureGroup button
whose actual AX bounds covered its child action. Confirmation still operates on the captured
output ID; cancellation and exact preference removal remain asserted. Slider relaunch tests
dismiss real upgrade notes before tab interaction; notes are neither disabled nor suppressed.

Inspected unaltered iPad captures show [Field light](ios-screenshots/upstream075-ipad-field-light.png),
[Accessibility XXXL](ios-screenshots/upstream075-ipad-accessibility-xxxl.png),
[exact demo EQ endpoints](ios-screenshots/upstream075-ipad-eq.png),
[independent saved-output actions](ios-screenshots/upstream075-ipad-output-preferences.png) and
[a finalized real Simulator memo](ios-screenshots/upstream075-ipad-memo.png). No audio recording
files are committed. The [iPad manifest](ios-test-results/current-ipad-coverage.json) records
**278 units + 24 representative app UI identifiers**, all latest Passed: 12 app journeys rerun in
this 0.75 pass plus 12 retaining earlier named evidence. It is not the full 39-case iPhone app UI
suite, a single combined run, or a claim that all 24 were rerun on this source revision.

The final companion layout also passed both affected journeys again on iPhone. The updated
[phone preference capture](ios-screenshots/upstream075-output-preferences.png) comes from that
final 2/2 run. Native implementation/testing for the pinned range is complete at this scope;
physical acceptance and explicitly unavailable platform features remain separate.

The separate reviewed-upstream boundary is now 0.75.0/9e6c491, preserving the retained Android
0.4.0/d6ceffa provenance. The actual [GET-only live check](UPSTREAM_075_CHECK.md) resolved the
same upstream tip on 23 October: **identical, zero ahead/behind**. The hosted Ubuntu workflow
also passed the expanded Python discovery, actual reviewed comparison and summary publication,
as recorded above. This read-only workflow does not import or merge upstream source.

## Environment

Repository maintenance on **23 October 2026** made the iOS branch the fork default and added a
manual upstream checker. All **18 Python regressions** passed; the actual public API comparison
reported **42 commits ahead, zero behind** at upstream `9e6c4912531ec6e159eded862d1b6ffa55094199`.
See [upstream checks](UPSTREAM_UPDATES.md) and [checkpoint 15](IOS_PROGRESS.md).
The actual fork-hosted [workflow run](https://github.com/bdupreez/earshot-ios/actions/runs/39867056544)
also passed all 18 tests, the live comparison and summary publication at `12ecb2d`.
The comparison hit GitHub's 300-file reporting limit, flagged as possibly incomplete.
These tooling checks do not rerun or extend the native Simulator acceptance recorded below.

- Validation date: 19 October 2026 (Australia/Melbourne).
- Installed Xcode: **26.4.1**, build **17E202**, `/Applications/Xcode.app`.
- Simulator SDK: **iOS 26.4**; the test result reports runtime **iOS 26.4.1 (23E254a)**.
- Primary simulator: **iPhone 17 Pro**, `670AA0BD-A1DF-4768-835F-966A0D09E7B3`.
- Secondary simulator: **iPad Pro 11-inch (M5)**, `F0735D38-82C8-4F9F-B319-410374B0B2B7`, also runtime iOS 26.4.1 (23E254a).
- Deployment target: iOS 17.0; iOS 17 hardware/runtime was not available for this run.
- Project: `ios/Earshot.xcodeproj`, shared scheme **Earshot**; Swift 5 language mode, no third-party packages.

## Historical 19 October iPhone feature-pass evidence

### Slider backpressure repair from device feedback

The fork owner supplied a physical-iPhone screenshot showing a QC Ultra 2 connection and a
queue-full alert while dragging ANC, then reported the same issue across sliders. This establishes
a user-reported defect, not comprehensive model/firmware acceptance. Source inspection found
continuous ANC/EQ writes, a default-mode retry timer that could pause during touch tracking, and
a compact-mode reply path that could repeatedly request another detail record. The exact packet
sequence on the user's phone was not captured.

ANC, bass/mid/treble and headset volume now keep gesture drafts, commit the final value on release,
ignore incoming thumb changes during a drag, and cancel unfinished gestures when their context
changes. No device state is fabricated to acknowledge a write. This restores the original Android
`NoiseControls.kt` end-of-drag behavior by HellzYeahh and contributors. Local Pro EQ sliders remain
continuous and never enqueue headphone commands.

The installed-Xcode build passed after correcting a test-only `CFRunLoopMode` SDK type mismatch
found by the initial test build. `SliderBackpressureUnits.xcresult` passed **189/189, 0 failed,
0 skipped, 0 expected failures**, xcodebuild exit 0. This includes 23 new regressions: 11 gesture
state tests, eight production-queue/stream/run-loop tests, and four actual receive/follow-up mode
tests. A thousand queued ANC changes stay bounded to the latest unsent setting plus one mode read;
the real Foundation memory stream checks pacing, partial-frame byte integrity and completion;
the actual production timer drains while a custom non-default common run-loop mode is active.
Diagnostic cancellation and discrete-command/route barriers remain asserted.

Evidence applies to the repair working tree following `e76e9ef`, with existing local Xcode signing
edits preserved. Simulator commands override `DEVELOPMENT_TEAM=""` and use ad hoc signing without
changing those project settings. The project was not regenerated. The original device screenshots
are not republished. The Bluetooth/ANC/EQ audible effects and queue behavior on the physical Bose
still require the owner's retest; BMAP's lack of transaction identifiers remains a reply-correlation
limitation, including multiple outstanding changes at the same address.

Raw summary: [slider unit result](ios-test-results/slider-backpressure-units.json).

The focused iPhone UI run finished **7 passed, 1 failed, 0 skipped** (xcodebuild exit 65).
The new EQ case's fractional target did not reliably land on its intended discrete step. A slower
coordinate attempt, native fractional adjustment and inside-bounds end-stop attempt each failed
**0/1** without widening assertions. The final case carries real finger drags beyond the native
control bounds to clamp at Bass +10 / Mid −10 / Treble +10 dB, requiring exact normalized limits,
signed labels, no alert, continued Sound navigation and persistence after relaunch.
`SliderEQClampedFinal.xcresult` passed **1/1, 0 failures/skips**, xcodebuild exit 0. All eight
selected UI identifiers therefore have a passing latest result across these two runs; this is
not one combined green eight-case run. The other seven cases cover ANC's exact 7/10 across repeated
drags/navigation/relaunch, headset volume, mode editing, Pro EQ scope, attribution, a multi-action
rule and actual local-player seek/A-B. Midrange EQ +6/−4/+4 targets remain exact unit assertions.

Preserved raw summaries: [initial UI](ios-test-results/slider-backpressure-ui-initial.json),
[slow coordinates](ios-test-results/slider-eq-coordinate-attempt.json),
[native adjustment](ios-test-results/slider-eq-native-adjustment-attempt.json),
[inside endpoint](ios-test-results/slider-eq-inside-endpoint-attempt.json),
[final clamped drags](ios-test-results/slider-eq-clamped-final.json).
The [ANC](ios-screenshots/slider-anc.png) and [three-band EQ](ios-screenshots/slider-headphone-eq.png)
captures were exported unaltered and visually inspected. Both use simulated device state.

The iPad follow-up, `iPadSliderBackpressureFinal.xcresult`, finished **191 passed, 1 failed,
0 skipped**, Xcode exit 65: all 189 units plus ANC and EQ passed. The volume/playback portions
passed, but the later LE Audio assertion read its old switch snapshot before confirmation dismissal
settled. The test now selects the exact confirmation action, waits for dismissal and requires the
changed switch value with a five-second bound. `iPadVolumeConfirmationFinal.xcresult` passed
**1/1, 0 failures/skips**, Xcode exit 0. No app behavior or value assertion was relaxed. These
results establish all three selected slider journeys on iPad across the two named runs.
Raw summaries: [iPad integration](ios-test-results/ipad-slider-backpressure-initial.json),
[confirmation repair](ios-test-results/ipad-volume-confirmation-final.json). The same final harness
also passed **1/1** on iPhone, Xcode exit 0 (`iPhoneVolumeConfirmationFinal.xcresult`;
[raw summary](ios-test-results/iphone-volume-confirmation-final.json)).

Personal Apple developer edits in the tracked project were excluded from staging; existing local project
edits were preserved byte-for-byte. Ignore rules cover signing material and user state, and the
indexed-file privacy guard was checked with clean data and synthetic team/profile/key findings.
The read-only commit audit found no personal signing settings or detected credential material in
the 35 existing branch commits/896 commit-backed file versions. The guard checks the final index
again before the explicit named-branch push; unrelated local app snapshot refs are not published.

**At the 19 October checkpoint, 189 unit tests, 31 distinct app UI journeys and three system UI journeys had a passing latest result**, verified from Apple's per-case exports across the runs below. This is an aggregate of explicitly identified runs, **not a single combined green run**. [Current per-case coverage](ios-test-results/current-iphone-coverage.json) records the authoritative bundle for every identifier; earlier failures are retained rather than hidden.

| Run | Exact Xcode outcome | What it establishes |
| --- | --- | --- |
| `SliderBackpressureUnits.xcresult` | **189 passed, 0 failed, 0 skipped**, xcodebuild exit 0 | Then-current native unit suite, including 23 new slider draft, queue/pacing, and compact-mode follow-up regressions. |
| `SliderBackpressureUI.xcresult` | **7 passed, 1 failed, 0 skipped** | Seven focused UI regressions passed; fractional EQ gesture target failed and is retained above. |
| `SliderEQClampedFinal.xcresult` | **1 passed, 0 failed, 0 skipped**, xcodebuild exit 0 | Repeated real drags across all three EQ bands, exact signed end stops and relaunch persistence. |
| `DiagnosticIsolationUnitsFinal.xcresult` | **166 passed, 0 failed, 0 skipped**, xcodebuild exit 0 | Then-current native unit suite, including seven diagnostic isolation/partial-frame/late-reply regressions. |
| `NativePlatformUIFinal.xcresult` | **6 passed, 0 failed, 0 skipped**, xcodebuild exit 0 | Four focused app regressions and both widget actions; later visual review found medium clipping, repaired and verified below. |
| `SystemMediumLayoutFinal.xcresult` | **2 passed, 0 failed, 0 skipped**, xcodebuild exit 0 | Rebuilt extension: actual Control Center Cycle plus medium-widget Aware, three-part earbud battery labels and fully contained header/action geometry. |
| `WidgetSmallLayoutFinal.xcresult` | **1 passed, 0 failed, 0 skipped**, xcodebuild exit 0 | Final small-widget rendering and real Cycle delivery, including resizing from the installed medium tile. |
| `FeatureGapAcceptance.xcresult` | **184 passed, 3 failed, 0 skipped** (159 unit + 28 UI attempted) | All unit tests and 25 UI journeys passed, including all new functional flows except the three stated harness interactions. |
| `FeatureGapFinalFollowups.xcresult` | **162 passed, 1 failed, 0 skipped** | All 159 units, exact/localized deep-plan counts, real sample playback/pause and the new sidetone/50% threshold persistence UI passed. The Settings navigation gesture still needed repair. |
| `NativeUIRepairsFinal.xcresult` | **161 passed, 0 failed, 0 skipped**, xcodebuild exit 0 | All 159 units, Wi-Fi demo/no-prompt boundaries, and final quick-switcher colours/selection/persistence passed. |

The failed broad-run cases were a localized deep-plan count checked without revealing/waiting for its row, the Play control tapped before settling/revealing the taller loaded player, and a Settings List gesture too short to move App preferences clear of the floating tab bar. The final Settings case uses the 140-point native drag already proven by the independent settings journey. Exact counts, playback state, permission checks and persisted values remain asserted. No expected failures or skips were added.

Visual review used the actual exported PNGs. It found faint demo-profile captions inheriting Button tint; native plain rows with explicit primary/secondary text colours corrected them, and the final switcher UI rerun passed. The Shortcuts help now includes Cycle. [Native captures and precise provenance](ios-screenshots/README.md) distinguish captures from passing cases from whole-run results.

**Actual system surfaces:** small-widget Cycle, medium-widget Aware and Control Center Cycle each opened Earshot and applied the requested demo mode. Every test explicitly waits for system-driven foreground activation without activating the app on its behalf. Widget size menus and the Control Center gallery were actually operated; the three Control Center entries were visually inspected in the unlocked installed Simulator. Final captures show Earshot’s own native tile/control and resulting app state, without unrelated Home Screen apps. These are three separate system journeys, outside the 31 in-app journeys. Temporary probes were removed and are excluded from coverage.

The initial medium action passed but its exported image exposed clipped header/buttons. The corrected medium layout uses horizontal mode/profile and battery columns. The final test selects QC Earbuds II, requires Left/Right/Case labels, and asserts the header and all three button frames lie inside the actual native widget viewport; visual inspection confirmed readable, unclipped content. The final small rendering/action also passed separately after resizing from medium. Home Screen Widget Gallery search, Siri and signed-iPhone delivery remain unverified.

## Diagnostic isolation and secondary-device follow-up

The diagnostic-isolation unit run passed **166/166, 0 failures, 0 skipped**, Xcode exit 0 (`DiagnosticIsolationUnitsFinal.xcresult`). A parity review found that a scan GET refusal could enter ordinary capability/write failure handling. The corrected transport labels diagnostic frames, begins its eight-second late-reply isolation only after full transmission, refuses overlapping mutations, preserves genuine unrelated errors and valid status pushes, and discards unsent diagnostic traffic on cancellation/completion. A partial frame finishes without corrupting the stream. Seven regressions cover these boundaries; arbitrarily later BMAP replies remain ambiguous because the protocol has no transaction ID. No physical scanner behavior is inferred.

`iPadFeatureAcceptance.xcresult` finished **168 passed, 3 failed, 0 skipped**: 159 units and nine of 12 UI journeys passed. Actual AX located the foreground rule Form at x127…707, while the failing test dragged at x8 outside its centered sheet. The helper now derives the actual foreground scroll viewport and clips navigation/keyboard occlusion. Exact assertions remain. The focused iPhone run passed all four app cases plus both system-widget actions. The final iPad repair run, `iPadNativeRepairsFinal.xcresult`, then passed **169/169, 0 failures, 0 skipped**, Xcode exit 0: all 166 final units and the three previously failing UI cases. That historical iPad aggregate reached **189 units + 15 representative app UI journeys**, all latest Passed after the slider follow-up below; the [current manifest](ios-test-results/current-ipad-coverage.json) tracks subsequent validation above; this is an aggregate, not a single 204-test green run or the complete iPhone UI suite. Microphone playback progress and native release-note credit captures come from individually passing iPad cases.

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
- Small/medium widget and Control Center flows are verified on Simulator only. They do not establish signed-iPhone App Group provisioning, Home Screen Widget Gallery search, Siri recognition or real-world Shortcuts delivery.
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

The next native implementation was built and tested with the same installed Xcode 26.4.1 / iPhone 17 Pro / iOS 26.4.1 environment. `ios/TestResults/FeaturePass1Units.xcresult` reports **96 passed, 0 failed, 0 skipped**, and `xcodebuild` exited 0. This runs all eight unit-test classes, including new preset/player lifecycle, multi-action/schedule/migration, Bluetooth/reconnect/scanner, shared command queue and native notification-plan checks. The application and widget/control extension compile together. Compact export: [feature-pass1-units.json](ios-test-results/feature-pass1-units.json).

The baseline 12 UI scenarios have not yet been rerun on these expanded sources at this checkpoint. New feature UI cases are under development. Hardware, SSID entitlement access, signed widgets/Control Center/Shortcuts, background restoration and actual notification delivery remain unverified; unit queue/planner tests do not establish those platform outcomes.


## Feature-gap pass — Wi-Fi, controls and actual shared container

`ios/TestResults/FeaturePass2SignedUnits.xcresult` reports **105 passed, 0 failed, 0 skipped** with locally ad hoc signed Simulator app/extension binaries (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`). This includes actual installed-app access to its declared App Group container and a queue write/reopen/drain in an isolated child directory. It does not prove cross-process widget delivery or signed-device provisioning. Export: [feature-pass2-signed-units.json](ios-test-results/feature-pass2-signed-units.json).

The first attempt (`FeaturePass2Units.xcresult`) passed 104/105: the real App Group container was unavailable under `CODE_SIGNING_ALLOWED=NO`. The test was retained, and local ad hoc signing made the entitlement available; no production fallback or test skip was introduced. The simulator test script now uses ad hoc signing and needs no Apple development account. A bare unsigned build remains useful for compilation but cannot establish App Group behavior.

Added unit coverage includes Wi-Fi join/SSID matching, initialization without permission/query side effects, signed 16-bit experimental latency validation, demo state changes and the `OpenIntent` widget/control contract. Optional SSID observation and experimental device writes still require physical acceptance. The compact Wind Block report helper and expanded UI flows are subsequent changes awaiting their next test run.


## Feature-gap pass — integrated review fixes

`ios/TestResults/FeatureGapUnitsFinal.xcresult` reports **125 passed, 0 failed, 0 skipped** on the same iPhone 17 Pro / iOS 26.4.1 simulator, with local ad hoc signing and xcodebuild exit 0. Export: [feature-gap-units-final.json](ios-test-results/feature-gap-units-final.json). All 13 unit classes ran, including actual native finish/replay and hardware-idle checks, waveform/preamp consistency, dirty-draft preservation, direct noise step/toggle semantics, read-only status/profile layouts, recovery export after clean relaunch, product identity precedence and Wi-Fi opt-out protection.

The expanded 22-scenario XCUITest suite is running at this checkpoint. No UI acceptance claim is inferred from the unit result. Public-API code is implemented, but physical Bluetooth/SSID/signed system-surface validation is still pending.


## Expanded UI diagnostic history

The first complete expanded UI run, `FeatureGapUIInitial.xcresult`, finished with **17 passed, 5 failed, 0 skipped** (all 12 baseline cases passed). New flows confirmed multi-action rules, source confirmations, actual player seek/progress/A-B/stop, weekday/reminder persistence and permission-free demo Wi-Fi navigation. Five harness failures required repair before acceptance: a center tap left a text-field suffix, full-screen scrolls oscillated past controls or virtualized rows, and top-anchored confirmation popovers covered the background navigation title used to cancel them.

The exported accessibility hierarchy showed actual saved names `Morning cans· 2nd Gen` and `Morning librarycurve`, confirming that blind prefix deletion did not replace the full input. The repaired harness uses native text selection and verifies the exact fixture. It normalizes UIKit’s placeholder value for an empty field, uses bounded drags and cancels through the observed native popover dismissal region. `FeatureGapFocused.xcresult` contains 135 passing unit tests and an intentionally interrupted UI diagnostic attempt after that placeholder behavior was identified. These diagnostic bundles are not final acceptance evidence; no failed tests have been skipped or marked expected failures.

The simulator script now builds for testing with local signing, installs the app and explicitly grants Simulator microphone access before test execution. This makes the real recorder flow reproducible; first-install consent and physical headset routing remain separate acceptance items.


## Final UI interaction follow-ups

`FeatureGapUIRepaired.xcresult` completed with **10 passed, 2 failed, 0 skipped** across the 12 new feature scenarios. It verified device rename/language, source confirmations, exact restored filters, multi-action rules, native player progress/seek/A-B/stop, AutoEq deduplication, dirty-draft preservation, weekday/reminder persistence, Wi-Fi permission boundaries and the offline experimental-console gate. Remaining failures were native stepper child identification and XCTest cancelling a rename alert when a text-selection menu item lay outside the alert.

`FeatureGapLastRepairs.xcresult` completed its full **136-unit-test phase with 0 failures**; its two focused UI cases still failed on harness selectors. The additional unit regression checks upstream legacy custom-slot counts and absent earbud Wind Block. `FeatureGapLastInteractions.xcresult` then passed the latency journey (including cancel and retained simulated report) but exposed keyboard-focus timing during preset entry. The final helper retains exact input assertions, waits for alert keyboard focus, uses native selection in ordinary forms and public keyboard Select All within alerts. A picker menu is closed by selecting its current item rather than assuming every native menu has a popover dismissal region.

These are preserved diagnostic results, not combined acceptance. No test is skipped, marked as an expected failure or changed to accept the wrong saved name/value. A final complete script run follows after the Home quick-switcher addition.


`PresetLifecycleFinal.xcresult` subsequently completed the entire preset UI lifecycle with **1 passed, 0 failed, 0 skipped**, and xcodebuild exit 0. It verifies exact names, save/edit/rename persistence, delete cancellation, confirmed deletion, and Flat fallback after relaunch. This focused result covers the repaired helper; full combined acceptance remains separate.


## Historical checkpoint — integrated UI phase

The reproducible `ios/scripts/test-simulator.sh` completed a native `build-for-testing` and its entire **159-unit-test phase with 0 failures** on iPhone 17 Pro / iOS 26.4.1. New coverage includes mode cycling and queue ordering, release-note version migration, sidetone persistence, session-original latency, and selected/deep GET diagnostics with real asynchronous cancellation/timeouts. At that checkpoint the subsequent **28 UI scenarios were still running** in `FeatureGapAcceptance.xcresult`. Its completed outcome and subsequent repairs are recorded at the top of this report.

At that earlier checkpoint, desktop computer use was blocked by the locked Mac. Subsequent public XCUITest system interactions and the unlocked Control Center gallery review established the specific Simulator outcomes recorded above. Siri/Shortcuts and signed physical-device delivery remain unverified.


## Final system UI reproduction

After a normal build, run the permanent system journeys with a fresh result path:

```sh
xcodebuild -project ios/Earshot.xcodeproj -scheme Earshot \
  -destination 'platform=iOS Simulator,id=670AA0BD-A1DF-4768-835F-966A0D09E7B3' \
  -derivedDataPath ios/build -resultBundlePath ios/TestResults/System-NEW.xcresult \
  -only-testing:EarshotUITests/WidgetSystemUITests \
  -only-testing:EarshotUITests/ControlCenterSystemUITests \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

The tests change only Earshot’s own Simulator widget/control configuration. XCTest can wait approximately 60 seconds for SpringBoard widget-size menu animations on this runtime before continuing; the recorded final size changes still completed successfully. No private quiescence APIs, skips or expected failures are used. The final iPad scope is all `EarshotTests` plus `DeepScanUITests` and the multi-action-rule/weekday-schedule methods in `FeatureGapUITests`; the exact case identifiers and bundles are recorded in its manifest.
