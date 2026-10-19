# Progress log — AI-assisted iOS port attempt

The original Android app is **[Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot)**, MIT. This fork's native iOS work is an AI-assisted port attempt, not a claim of original authorship. Preserve [all credits and notices](../THIRD_PARTY_NOTICES.md).

## Checkpoint 1 — native app and first simulator validation (19 October 2026)

Implemented a SwiftUI iOS application with Home, Sound, Modes, Tools and Settings tabs, persistent demo profiles and settings, light/dark appearance, native local audio playback, graphic/parametric EQ, the seven upstream presets, AutoEq/JSON import/export, microphone recording/playback/deletion, diagnostics, rule editing, foreground schedules, WidgetKit overview and Quiet/Aware App Intents.

Ported BMAP packet framing, parsers, commands and safety guards. Added public Core Bluetooth discovery, Bose BLE PSM discovery, L2CAP streams, and protocol liveness verification. Live settings, battery, modes, favourites, custom-mode layouts, volume, playback, LE Audio, paired-source reads and shortcut controls are conditional on actual device reports. No physical headphone compatibility claim is made.

Built the app and Widget extension with the installed Xcode 26.4.1. The first completed simulator unit suite passed **40 tests**. Actual waveform tests caught an overloaded peak-limiter graph decaying toward silence; adding native dynamics compression before the peak limiter corrected the measured simulator behavior. A subsequent regression for fully bypassing Pro EQ is added and awaits the next completed unit run.

UI work has already exercised attribution, custom-mode persistence, earbuds profiles, light/dark display, local playback and microphone recording/playback/deletion in the real simulator. The final complete UI suite is still being repaired/rerun. Initial test issues included combined accessibility labels and microphone permission handling. Review of an actual test video also revealed a SwiftUI List row triggering both the automation editor and Run now buttons; separate borderless button actions fix that product bug and need confirmation in the next run.

Updated README, About/onboarding, changelog, contributor guidance, notices and historical document banners to identify the original project and this AI-assisted attempt. The original MIT licence, Android implementation, captures and third-party reference licences remain intact. [Migration details](IOS_MIGRATION.md) distinguish native, partial, hardware-pending, blocked and outstanding features.

Next: complete the iPhone UI suite, run iPad smoke checks, rerun all unit tests on final sources, export/inspect screenshots, and record authoritative result bundles in [IOS_VALIDATION.md](IOS_VALIDATION.md).

## Checkpoint 2 — final native unit validation (19 October 2026)

The full final simulator unit run passed **41 tests, 0 failures, 0 skipped**, including 14 DSP/audio, 6 app-state and 21 protocol/integration tests. Verified the result directly with Xcode's `xcresulttool`; authoritative bundle: `ios/TestResults/UnitTestsVerified.xcresult`.

The Pro EQ master switch now bypasses compression and peak limiting as well as filters, preamp and boost. Native waveform tests confirm original source level for both quiet and loud input when disabled, and verify meaningful boost with bounded audible output when enabled.

The focused microphone UI flow passed actual local recording, playback and deletion. Hardened it to delete any prior cached clip first, require a newly captured approximately eight-second recording, and assert playback/deletion state. Simulator microphone authorization was pre-granted to isolate the recorder from the native XCTest interruption-monitor stall. The complete final iPhone UI suite and iPad smoke checks remain pending at this checkpoint.

Checkpoint 1 was pushed as [`2ee06d1`](https://github.com/bdupreez/earshot-ios/commit/2ee06d1) exclusively to the user's fork on `codex/native-ios-port`. No original/upstream repository changes or upstream PR were made.

## Checkpoint 3 — UI acceptance fixes (19 October 2026)

The complete iPhone UI run passed **10 of 12 flows**. It confirmed the automation List action fix, attribution, mode persistence, profile batteries, appearance, local playback, discovery limitations, sound/automation navigation and tools navigation. It exposed a recorder-duration discrepancy: the UI could show 8.8 seconds while the actual finalized AAC file contained 7.963 seconds. The recorder now reads duration from the finalized file. A fresh focused recording/playback/deletion test then passed with the approximately eight-second assertion retained.

The remaining device-control flow has passed reported-volume changes and simulated playback. Its LE Audio confirmation test is still under investigation; no final acceptance claim is made at this checkpoint. Dialogs now have separate control anchors, including iPad popover placement, and the tests also check independent power-off cancellation. Next is confirming the exact switch hit target/dialog behavior, then a single combined final unit/UI run and iPad smoke checks.

Checkpoint 2 was pushed as [`b4aa918`](https://github.com/bdupreez/earshot-ios/commit/b4aa918), again only to the user's fork. The final screenshots and authoritative acceptance summary will follow once the remaining flow is verified.

## Checkpoint 4 — complete iPhone simulator acceptance (19 October 2026)

The installed Xcode completed the combined native acceptance run with **53 passed, 0 failed, 0 skipped**: 41 unit tests and all 12 UI scenarios. Both the `xcodebuild` exit status and the `xcresulttool` summary confirm success. The authoritative bundle is `ios/TestResults/Acceptance.xcresult`, recorded on iPhone 17 Pro, runtime iOS 26.4.1 (23E254a). No expected failures were used.

The remaining device-control failures were traced through actual test videos to test gestures: a switch under the translucent tab bar could be reported as hittable, anchored popovers omitted a Cancel row, and XCTest's standard slider adjustment intermittently initiated a Back swipe. The harness now exposes the entire control, verifies cancellation without changing state, and drags the observed slider thumb. A normal-build focused rerun of the final helper passed in `UIDeviceControlsFinal.xcresult`; its activity log confirms the actual 0.1-second thumb press/drag and changed reported volume. An earlier focused run predated the final helper edit and is not evidence for that edit. Product source was unchanged between the combined acceptance and that focused follow-up.

Exported native screenshots from the passing acceptance bundle cover light/dark Home, local Pro EQ, original-author credits, custom-mode persistence, microphone flow, connection facts and device controls. They are retained in `docs/ios-screenshots/`, visually inspected, and clearly identify demo device values as simulated. The README includes these native captures.

The secondary **iPad Pro 11-inch (M5)** normal-build smoke run passed **2 tests, 0 failures, 0 skipped** on iOS 26.4.1. It covers onboarding/demo mode switching and tools/compatibility navigation; it is not a complete iPad UI-suite run. A first cold-start attempt stalled before app launch, and the next attempt exposed the test harness’s iPhone-only TabBar lookup. The final helper uses iPad’s actual semantic tab buttons, and the final result is `iPadSmoke.xcresult`. Earlier diagnostic bundles are preserved. The final iPad Home screenshot was visually inspected. A final repeat of the existing iPhone onboarding case also passed (`UIHomeFinal.xcresult`), leaving the app on Home for handoff.

Checkpoint 3 was pushed as [`ef728fc`](https://github.com/bdupreez/earshot-ios/commit/ef728fc), exclusively to the user's fork. The final documentation commit records the completed acceptance and secondary-device outcomes. Physical iPhone/headphone compatibility, signed Widget/Shortcuts execution, and the explicit missing/platform-restricted features in the migration matrix remain unverified or outstanding; passing Simulator tests does not complete that work.

## Checkpoint 5 — remaining public-iOS features, first integrated unit run (19 October 2026)

Continued at the user's request. Implemented safe preset lifecycle (edit/copy/rename/delete), filter editing/reorder, reversible graphic conversion, bounded deduplicated import and recovery backups, manual/automatic preamp, playback progress/seek and A/B bypass. Added explicit saved-state migration so new fields do not erase old preferences or mode-only rules; malformed individual records preserve unrelated data and recovery bytes.

Rules now combine mode, noise and local EQ in a deterministic order, preflight the complete combination and wait for real headphone reports before dependent live actions. Added ISO weekdays, DST-safe occurrence latching, cancellation/status, offline local-only rules, optional system schedule reminders and foreground Run rule actions. A review caught and fixed the case where an editable current slot incorrectly authorized a noise write after switching to a non-editable destination slot.

Added opt-in remembered-device reconnect/restoration with fresh protocol verification; capability-gated rename, pairing, source management and installed voice languages; device-estimated battery minutes; upstream model/older-mode quirks; and a cancellable read-only protocol scanner. Added richer battery/staleness widgets, seven App Intents, iOS18+ Control Center buttons and a bounded atomic expiring command queue. No physical headphone, background, signed-widget, notification delivery or Siri compatibility claim is made.

Installed Xcode 26.4.1 built the app/widget and executed **96 native simulator unit tests: 96 passed, 0 failed, 0 skipped**. Verified `FeaturePass1Units.xcresult` with `xcresulttool`. This is new unit evidence; the earlier 53-test UI/unit acceptance belongs to the prior checkpoint. Expanded UI scenarios are being added, while optional foreground Wi-Fi triggers and guarded experimental latency writes are the remaining feasible implementation work in this pass. All destructive firmware/auth/factory operations remain blocked.

## Checkpoint 6 — foreground Wi-Fi, experimental latency and platform integration (19 October 2026)

Implemented optional foreground SSID rules using public APIs, explicit precise While Using authorization and Access Wi-Fi Information capability. Initialization/navigation never prompts. Observation pauses when inactive or in demo, remembers real joins across foreground pauses and treats an unavailable SSID as unknown. Physical signed-device access remains unverified. Added a range-gated signed 16-bit latency write with separate experimental confirmation and fresh-report completion; upstream’s unknown units/effect caveat remains visible.

Corrected Widget/Control Center buttons to use Apple’s `OpenIntent` contract, keeping both app and widget target membership. The actual App Group boundary test failed on an unsigned Simulator app; rerunning with local ad hoc signing passed all **105 unit tests, 0 failures, 0 skipped** (`FeaturePass2SignedUnits.xcresult`). The reproducible test script now preserves simulator entitlements with local signing; no Apple account is needed. The earlier failure remains documented and the real integration test is retained.

Expanded UI tests now cover presets/import/player, multi-action rules, weekday reminder persistence, rename/languages/sources, latency confirmation and Wi-Fi permission boundaries. A further code review fixed silent idle audio hardware, replay timeline reset, truthful applied-preamp display, unsaved preset dismissal, recovery-link persistence, direct CNC quantization/toggle flags, fresh current-mode reads and normal-connect routing support. Added read-only device operation/mic/button/LE/profile reports with their upstream uncertainty preserved. Foreground transitions now stop Wi-Fi immediately, cached SSIDs cannot run after opt-out, and reminder synchronization retries after returning from Settings. The complete integrated unit regression subsequently passed **125 tests, 0 failed, 0 skipped** (`FeatureGapUnitsFinal.xcresult`), including the review fixes. All 22 UI scenarios are now running; final UI acceptance is still pending at this checkpoint. Destructive writes remain blocked, credits/licences are preserved, and only the fork is a push destination.

## Checkpoint 7 — experimental console and expanded UI verification (19 October 2026)

Closed the remaining user-visible Android Lab feature: an experimental Print console with only upstream’s bind/unbind/verbosity/output verbs, exact packet layouts, local validation, explicit consent and a verified live link requirement. It bounds replies/transcript/deadlines, stops collection on inactivity/disconnect and redacts generic logs. Firmware arguments/effects remain unverified, as in upstream. No automatic logging setup or arbitrary BMAP writes are added.

A further protocol review distinguished informational START requests from mutations, so a refused LE-preference/mode-dump query cannot fail an unrelated listening rule. Explicit diagnostic rechecks now have fresh-report/error/timeout handling. The integrated unit phase passed **135 tests, 0 failures** in the focused run, including nine new console cases and the informational-refusal regression.

The first expanded UI run completed 17/22 with five failures in new harness interactions; all 12 baseline flows passed. Recorded AX evidence confirmed text suffixes from incomplete selection, scroll overshoot and popovers covering the cancellation point. The helpers now preserve exact input assertions, handle native placeholders, use bounded scrolling and the actual popover dismissal region. All 12 new feature cases (24 UI cases total) are rerunning before a complete final acceptance run. See [validation](IOS_VALIDATION.md) for diagnostic bundle names and limits.

## Checkpoint 8 — final interaction repairs and Home quick switcher (19 October 2026)

The integrated unit phase now passes **136 tests without failures**, including corrected legacy demo slot counts and absent earbud Wind Block. Focused Simulator runs verified experimental latency cancel/simulation/report retention, then the full user-preset lifecycle: create, edit, exact rename, relaunch, delete cancellation, confirmed deletion and persistent Flat fallback. `PresetLifecycleFinal.xcresult` reports **1 passed, 0 failed, 0 skipped**, with xcodebuild exit 0. The native keyboard and picker-menu harness repairs retain exact value assertions; earlier diagnostic bundles remain available.

Ported the original Home quick switcher as a native device-name button. Demo profiles are explicitly simulated and switching never scans. Real mode opens the existing discovery/connection UI; no unavailable iOS paired-device list is invented. Added a dedicated UI regression for cancellation, profile selection and relaunch persistence; this new case awaits execution. Refreshed the audio and Bluetooth subsystem documentation, preserving original-project and research credits.

The final parity review also found upstream's configurable mode cycle and once-per-release What's new screen. Both are feasible and are being implemented before the complete combined acceptance run. Widget Gallery/Control Center manual UI checks are temporarily unavailable because the Mac is locked; automated Xcode Simulator tests continue. Nothing has been pushed to the original repository.

## Push policy

The user requested regular progress pushes with detailed commit messages. Pushes are restricted to **[bdupreez/earshot-ios](https://github.com/bdupreez/earshot-ios)**. The original `HellzYeahh/earshot` repository must never receive a push or upstream pull request from this work. Each checkpoint should state what changed, what actually passed, what failed or remains unverified, and what happens next.
