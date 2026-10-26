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

## Checkpoint 9 — final feasible parity additions and 159-unit phase (19 October 2026)

Completed the final user-facing gaps identified by comparing every upstream navigation/action flow. Added configurable mode cycling in Settings, widgets, Shortcuts and iOS 18+ Control Center. Foreground execution resolves each next slot using current device reports; distinct taps stay ordered, stale/empty cycles explain repair steps, and old stored settings/snapshots still decode. Eight Shortcuts actions are now provided. Added durable once-per-release notes that defer behind onboarding/errors and remain available in About, with original-author credits.

Added device-reported Self Voice persistence, preserving level and remember flag independently; battery alert choices now include Off and 5–50% in 5% steps. The actual microphone player exposes elapsed/total progress. Experimental latency keeps the first valid report for the current connection; Reset to original uses the same range checks and separate experimental confirmation, and the baseline clears on connection changes.

Ported selected-block and deep GET discovery alongside the documented scan. Plans are local until Start, pace one query at a time, distinguish replies/refusals/timeouts, bound results and stop on cancellation/inactivity/link loss. Firmware/authentication/Print blocks, destructive addresses and known START-only functions are excluded. The 3,897-query deep plan explicitly shows a worst-case 72-minute estimate; no physical scan or firmware compatibility is claimed.

Regenerated the native project with 47 app files, 18 unit-test files, 6 UI-test files and 4 widget files. The reproducible script built the application/extension with installed Xcode and local signing, installed the actual Simulator app, granted test microphone access and completed **159 unit tests with 0 failures**. All 28 UI scenarios are now running in `FeatureGapAcceptance.xcresult`; this checkpoint does not claim their eventual outcome. No tests were skipped or marked expected failures. Global and subsystem documentation retain the original Earshot, MIT and research credits. Physical headphone/SSID/system-surface acceptance remains separate.

## Checkpoint 10 — complete iPhone app-journey verification (19 October 2026)

The complete broad script finished **184/187 passed**: all 159 units and 25 of 28 app UI journeys. Preserved three failures in its raw summary: deep-count localization/row visibility, the loaded-player hit target and Settings List scroll distance. Focused follow-ups passed **162/163**, leaving only the short Settings drag. The final native repair run then passed **161/161 with 0 failures, 0 skipped and xcodebuild exit 0** (all 159 units plus Wi-Fi and the final switcher).

The explicit latest-result manifest now verifies **159 unit tests + 29 distinct app UI journeys**, all with a passing latest result. This aggregate is not presented as one green 188-test run. Added the independent sidetone/50% threshold UI case without permission prompts; retained all original assertions and failure history. Visual review corrected faint inherited tint in the demo-profile list, and the final switcher capture/test confirms readable native colours and persistence. Exported exact Xcode summaries and unaltered native captures with source-bundle provenance and original credits.

Actual SpringBoard probing confirms installed Earshot Small/Medium widget options. It does not yet establish widget-action delivery; the next probe exercises rendering and a Cycle request. Expanded iPad acceptance remains next. Temporary system probes are excluded from app-journey counts and will not be committed as acceptance tests without an actual result.

## Checkpoint 11 — actual small-widget action and expanded iPad run (19 October 2026)

Actual SpringBoard diagnostics installed Earshot's small widget through the native icon-size menu. Its Cycle button opened Earshot and changed the simulated mode from Quiet to Aware. Replaced the temporary probe with a permanent repeatable `WidgetSystemUITests` journey that also handles an already-installed widget and explicitly asserts foreground activation without activating the app on its behalf. `WidgetSystemFinal.xcresult` passed **1/1, 0 failures, 0 skipped**, Xcode exit 0. The latest iPhone manifest now contains 159 unit, 29 app UI and one separate system UI identifier; temporary probes remain excluded.

Preserved unaltered native captures and exact failed/passing summary exports, plus a per-identifier manifest that makes the multi-run result explicit. The widget README credits the original Earshot/AI-assisted attempt, explains app-process `OpenIntent` execution with primary Apple references, bounded queue history and signed-device limits. No medium-widget, Widget Gallery search, Control Center, Siri or physical-headphone acceptance is inferred from the small-widget result.

Installed the final app on iPad Pro 11-inch (M5), granted test microphone access and started all 159 units plus 12 representative UI journeys. The **159-unit phase passed without failures**. The first iPad UI case found duplicate semantic Tools buttons in its floating top tabs; the selector was narrowed to the exact-label first match and is awaiting its focused rerun. The remaining iPad cases continue. Source app/widget builds and simulator operations remain serialized; pushes remain exclusive to the fork.

## Checkpoint 12 — diagnostic correctness and actual Control Center delivery (19 October 2026)

A further parity review found that diagnostic GET refusals could disable a supported normal feature or interfere with pending writes. Added explicit scan/mutation isolation and diagnostic-origin frame metadata, with correlation starting only after full transmission. Cancellation/completion discard unsent diagnostic traffic and preserve partial-frame wire integrity; valid status pushes and genuine unrelated write errors still reach the app. Same-address changes wait through an eight-second settling window or reconnect; arbitrarily later replies remain ambiguous in BMAP. Independent read-only review found no defect in these boundaries. The installed-Xcode Simulator **complete unit run passed 166/166, 0 failures/skips**, including seven new regressions (`DiagnosticIsolationUnitsFinal.xcresult`).

Actual Control Center diagnostics inspected Add Controls, its gallery and all three Earshot entries, then installed the mode-cycle control. Replaced the temporary probe with a permanent foreground-delivery assertion: **1/1 passed**, Xcode exit 0 (`ControlCenterSystemFinal.xcresult`). The system control opened Earshot and changed simulated Quiet to Aware without test-driven activation. The unlocked desktop also allowed visual gallery review. Temporary probes are excluded and removed from source. Original credits, AI-assisted disclosure and physical/signing limits remain explicit.

Expanded iPad integration completed **168/171**: all 159 then-current units and nine of 12 UI journeys passed. The three failures were a duplicate floating Tools selector and gestures outside the centered rule Form (actual x127…707 versus old x8). The helper now uses foreground scroll bounds; focused reruns are underway, together with primary-device regressions and actual medium-widget execution. Updated iPad Home, real microphone playback progress and credited release-note screenshots come from passing cases. The latest-result iPhone manifest currently records 166 unit, 29 app UI and two system UI cases; it remains an aggregate of named bundles, not one combined green run.

## Checkpoint 13 — final iPad repairs and unclipped system widgets (19 October 2026)

The focused iPhone run passed **6/6, 0 failures/skips**: exact deep-scan plan/offline gates, multi-action rule application, weekday/reminder persistence, permission-free demo Wi-Fi navigation, and actual small/medium widget actions (`NativePlatformUIFinal.xcresult`). Its exported medium image nevertheless revealed clipped header/buttons. Replaced the medium-only stacked body with native horizontal mode/profile and battery columns plus a compact footer. Small rendering and all snapshot/demo/staleness/minutes/action semantics are preserved; readable native percentage fonts remain.

Rebuilt with installed Xcode and passed **2/2 system UI cases** in `SystemMediumLayoutFinal.xcresult`: actual Control Center Cycle and medium-widget Aware, both with system-driven foreground activation and correct demo state. The medium case selects simulated QC Earbuds II, verifies Left/Right/Case and requires header/action frames completely inside the actual native widget viewport. Visual inspection confirmed the corrected layout. The final small-widget resize/render/Cycle regression then passed **1/1** in `WidgetSmallLayoutFinal.xcresult`. Both xcodebuild commands exited 0. Native element captures avoid unrelated Home Screen apps; earlier clipped evidence remains in the local bundle.

The final iPad run passed **169/169, 0 failures/skips**, Xcode exit 0 (`iPadNativeRepairsFinal.xcresult`): all 166 units and all three previously failing UI journeys. Added exact iPad summaries and a latest-result manifest covering **166 units + 12 representative app UI journeys**, all Passed across the identified integration/repair runs. This does not claim the full iPhone UI suite ran on iPad or a single combined 178-case green result. The iPhone manifest now records **166 units + 29 app UI + three system UI** latest Passed results, also explicitly an aggregate.

Updated current validation, migration matrix, changelog, widget architecture, reproduction instructions, screenshots and provenance. Original HellzYeahh/Earshot contributor credits, third-party research notices and AI-assisted port disclosure remain prominent. Clarified that the documented Crusher Classic RFCOMM link is blocked without a supported iOS transport; no physical headset, signed-device SSID/provisioning, Siri, exact background execution or full Android parity is claimed. Checkpoint 12 was pushed as [`525050d`](https://github.com/bdupreez/earshot-ios/commit/525050d) only to the fork. This final checkpoint follows the same fork-only push policy.

## Checkpoint 14 — device-reported slider backpressure and private signing (19 October 2026)

The fork owner reported a queue-full alert on a physically connected QC Ultra 2 when dragging
ANC, then similar slider problems elsewhere. Restored the original Android noise control's
local-draft/end-of-drag behavior (HellzYeahh and contributors, MIT) and applied guarded release
commits to bass, mid, treble and headset volume. Device reports stay authoritative, active thumbs
ignore report changes, and context changes cancel unfinished gestures. Local Pro EQ and player
sliders remain continuous. These source repairs are an AI-assisted port correction, not a claim
to have invented upstream Earshot's design.

The paced L2CAP output timer now runs in common run-loop modes during touch tracking. A bounded
production queue coalesces only a wholly unsent suffix of same-address/device/port absolute ANC
settings and its associated current-mode read. Partial frames, diagnostics, discrete commands and
EQ bands keep their wire order; the 256-frame bound and 80 ms spacing remain. Compact mode reports
can request one detail record per slot until refresh/reconnect, preventing identical compact
replies from causing an automatic GET loop. The exact traffic causing the user's alert was not
captured; physical audible/queue acceptance remains theirs to retest.

Installed Xcode built the actual app, extension and test targets. All **189 native units passed**,
including 23 new regressions for gesture drafts, real queue/stream/run-loop behavior and actual
mode receive/follow-up handling. The focused iPhone UI run passed **7/8**; the new EQ case exposed
unreliable exact-step targeting in coordinate and native fractional adjustments. Subsequent
attempts are preserved in raw summaries. The final case uses real repeated finger drags to
unambiguous clamped limits and exact signed-value/relaunch assertions; arbitrary midrange signed
values remain required by the pure gesture regressions. The final EQ case passed **1/1**, Xcode
exit 0; all eight selected iPhone UI identifiers now have a passing latest result across the
initial and final runs. This is not one green eight-case run. Current iPhone coverage aggregates
**189 units + 31 app UI + three system UI** latest Passed results; native captures were visually inspected.

The iPad slider integration passed **191/192**: all 189 units plus ANC and EQ. Volume/playback
passed within its third UI journey, followed by a stale LE Audio switch assertion during popover
dismissal. Exact action selection and a bounded dismissal/value wait repaired the harness; the
focused iPad rerun passed **1/1**, Xcode exit 0. The current iPad aggregate is **189 units + 15
representative app UI** latest Passed results, including the three slider cases. Failed summaries
remain exported; this is not a single combined 204-test run. The final confirmation harness
also passed **1/1** on iPhone (`iPhoneVolumeConfirmationFinal.xcresult`), Xcode exit 0.

Preserved the owner's local Xcode project/signing edits byte-for-byte and excluded that file
from the commit. Added ignore rules and an indexed-file privacy guard for signing/account/key
material; synthetic clean/failing checks verify that it blocks findings without printing values.
Read-only audit of the 35 existing branch commits and 896 commit-backed file versions found no
personal signing-team settings, private keys or common credential patterns. Local Codex snapshot
refs are outside the named branch and are not pushed. A targeted pattern audit is not a guarantee
about arbitrary opaque secrets. Only the explicit fork branch may receive this progress push.

Clarified Apple Music: supported Bose hardware three-band EQ can affect other apps' music;
Earshot's parametric Pro EQ/limiter/preamp require its own unprotected local playback. Updated
README, migration/acceptance plan, Bluetooth/audio documentation and changelog with original
credits and the physical-device retest boundary intact.

## Checkpoint 15 — iOS default branch and manual upstream checks (23 October 2026)

Made `codex/native-ios-port` the default branch of **bdupreez/earshot-ios** and verified GitHub's
setting and local `origin/HEAD`. The fork's Android `main` remains at imported upstream 0.4.0
commit `d6ceffa7a028f2809840160bf8323715d24384cb`; HellzYeahh/earshot's default remains `main`.
No original-repository settings/branches were changed, and no upstream push destination was added.

Added a standard-library, GET-only upstream checker and manual fork-gated GitHub Actions workflow.
The imported baseline is explicit and read-only. Each check discovers upstream's default branch,
resolves one immutable tip, reports ancestry/commits/changed areas and flags API truncation. It
never synchronizes code, advances the baseline, runs upstream code or creates an automatic schedule.
Remote text is bounded/escaped, requests and redirects are restricted, and optional authentication
stays in request headers. The workflow uses a temporary read-only GitHub token, pinned official
checkout and no persisted credentials or personal developer secrets.

All **18 Python regressions passed**, including identical/ahead/behind/diverged histories,
pagination/limits, renamed files, API errors, credential-safe output and remote markup injection.
An independent read-only source review found no blocking issue. A real public API check resolved
upstream `main` to `9e6c4912531ec6e159eded862d1b6ffa55094199`: **42 commits ahead, zero behind**
the imported baseline. All 42 commits were listed; the API returned its **300-file limit**, which
the report flags as possibly incomplete. The local report is ignored under `ios/TestResults/`. Upstream changes
are reported for later review, not silently imported into this native port. Actual hosted workflow
verification was then completed on the fork's default branch: [run 39867056544](https://github.com/bdupreez/earshot-ios/actions/runs/39867056544)
at commit `12ecb2d59be18e762ca7b1b3289ccaf6f9b3593a` passed all 18 tests, the actual upstream
API check and summary-publication step. The workflow completed successfully with read-only
permissions and no automatically imported upstream code.

Updated README, branch/update instructions and migration guidance while preserving HellzYeahh,
Earshot contributors, MIT and research credits. Clarified that MIT permits covered-code commercial
distribution with retained notices, while App Store branding approval and App Review are separate:
Apple's current 4.1(c) requires permission for another developer's name/icon/brand, so publishing
as Earshot needs that approval or distinct branding with original credits retained.

This checkpoint changes repository tooling/documentation only. Native Swift/UI and the Xcode
project are untouched; prior Simulator results are not presented as a new native run. Personal
signing edits remain local and excluded. Index privacy checks and explicit fork-only destination
verification are required before each push.

## Checkpoint 16 — Upstream 0.75 native reconciliation (23 October 2026)

Reviewed all 42 commits from 0.4.0 d6ceffa to 0.75.0 9e6c491 using the complete Git diff
(311 files), including each merge and new reference notice. The [audit](IOS_UPSTREAM_075_AUDIT.md)
links every commit and F01–F14 to its native implementation or public-platform limitation.
Retained Android source/captures remain 0.4.0 provenance. Original Earshot, HellzYeahh and
contributors remain prominent in README, About, source and release notes. New MIT research
notices and complete OFL font notices are retained; GPL/AGPL/unlicensed code is not imported.

Native 0.2 adds per-output explicit preset/off memory, public route/volume controls, foreground
EQ-cycle/memo Intents, optional spoken feedback and protected persistent AAC voice memos.
Recorder/mic/player ownership is exclusive; starting playback finalizes a memo first. Foreground
local-only connection rules follow real external audio-route changes after remembered-EQ restore;
category/microphone changes cannot create reconnect loops or overwrite explicit choices.

Read-only BAS discovery uses explicit source selection, only 180F/2A19, bounded deadlines,
serialized cancellation and stale-callback rejection. Optional delivered Apple adverts remain
nearby/unverified and are never assigned to the active route. Neither feature marks vendor
control connected. Added 35 Soundcore models with exact bounded frames, model-aware parsers,
write guards and synthetic readback demos; 48 other catalogue entries cover Sennheiser, Sony,
Method, Apple/Beats and generic exclusions. Unsupported live RFCOMM is never replaced with a
guessed BLE writer. Unresolved layouts and undocumented operations stay read-only.

Corrected Bose touch low-bit ON semantics, independent button/event/action records and retained
same-button masks after short echoes. Unknown current actions grant no extra writes. QCE(2024)
and other brands no longer get an assumed Bose profile. Field light/dark styling, registered OFL
fonts and opaque light/dark/tinted Strike artwork retain original upstream design credit.
Screenshot review caught hidden picker labels and low-contrast filled buttons; native controls
now have explicit visible labels and readable text. The vendor container preserves child
accessibility identifiers. Local signing settings are reconciled separately from a clean generated
project; public marketing/build versions are 0.2.0/2. Personal developer data remains unstaged.

Actual Xcode 26.4.1 / iPhone 17 Pro / iOS 26.4.1 validation history is preserved in
[IOS_VALIDATION.md](IOS_VALIDATION.md): initial 237 units exposed two new defects, repaired before
two subsequent 258-unit passing runs. The first new-UI attempt had three failed interactions,
and the next had one vendor accessibility-identifier failure; all five new identifiers have
passing latest results after repairs. Source review also caught both low-code Soundcore mutations
(1075/1077), reverse audio-session ownership and the BAS disconnect/reread race.
The final **Upstream075-iPhone-Checkpoint.xcresult passed 263/263**, zero failures/skips,
Xcode exit 0: all 258 unit/integration tests plus five actual UI journeys in one run.
[Actual summary](ios-test-results/upstream075-iphone-checkpoint.json). Exported screenshots
were inspected after correcting visible setting labels, independent child identifiers and
filled-button contrast. The memo screenshot shows a newly saved 15-second AAC clip after
local playback started; no physical headset input is inferred.
All 23 Python checker tests pass, including strict reviewed-baseline handling and escaping.
The checker can compare a separately reviewed upstream commit while preserving the 0.4 Android
import metadata; that reviewed marker is deliberately not advanced during this checkpoint.

Broader existing iPhone UI/system surfaces and representative iPad/large-text layouts are the next
verification checkpoint. Physical battery delivery, vendor transports, actual headset mic routing,
Bose touch/button effects, and the owner’s slider retest remain device acceptance work. Simulator
and synthetic-frame results do not establish those effects. Pushes target only the user’s fork,
with exact staged-path inspection and the index privacy guard required before publishing.

## Checkpoint 17 — Complete app UI and output-preference follow-up (23 October 2026)

Closed the final source-audit omissions: explicit preset creation/copy/editor save and successful
JSON/AutoEQ imports now remember the selected output's actual enabled/off choice; edits to a
different preset cannot steal it. Added bounded app-only output nicknames and confirmed selective
removal of saved EQ/action/nickname preferences, including offline outputs. System names and
Bluetooth pairing remain separate. Home now presents a real generic external audio output
prominently with an explicit no-control status, keeps its system name visible, and never adopts
stale Bose telemetry or grants capabilities. Verified BMAP identity remains separate from a
different audio output; demos remain virtual. Vendor Settings no longer shows old Bose controls.

Added 20 regressions (7 preset memory, 8 nickname/management, 5 Home identity) for **278 total
units**. The broad app UI run finished **36/38**, retaining the two scrolling/alert failures.
The follow-up finished **282/284**: all 278 units, the exact complete preset lifecycle and three
other UI cases passed; nickname row lookup and AX XXXL inertial scrolling still needed repair.
The corrected **Upstream075-iPhone-Repairs passed 281/281**, zero failures/skips, Xcode exit 0:
all 278 units plus nickname save/relaunch/cancel/confirmed-forget, neutral Home, and a real
Soundcore menu interaction at Accessibility XXXL. No assertions or expected failures were relaxed.
Failed summaries remain alongside the passing evidence in [IOS_VALIDATION.md](IOS_VALIDATION.md).
Inspected unaltered Field/System, Home, saved-output and large-text PNGs are retained with provenance.

Hardened project/privacy tooling: explicit and symlink generator destinations protect signing
settings; deterministic removed/renamed sources reconcile correctly; relative resource IDs avoid
duplicate build membership; unknown custom objects and protected settings survive. The index guard
also detects binary keystores, alternate team/profile keys and quoted JSON settings without
printing their values. All 38 local Python regressions pass on synthetic projects/repos. The
actual owner's protected project/target/configuration dictionaries were independently compared
before/after reconciliation and are unchanged; the clean generated project alone may be staged.

Original HellzYeahh/Earshot contributors, MIT/OFL/reference notices and Android 0.4 provenance
remain intact. The separate reviewed baseline is not yet advanced. Actual system-widget/Control
Center and explicit picker accessibility-value follow-up then passed **6/6**, zero failures/skips,
Xcode exit 0 (`Upstream075-iPhone-SystemAndValues`): all three actual system surfaces and three
vendor/large-text UI journeys. Selected values are now exposed separately from their setting names.
Inspected native system-element captures exclude unrelated apps. Current iPhone coverage is
**278 units + 39 app UI + 3 system UI**, all latest Passed across named runs, not one combined run.
iPad and hosted-workflow results will follow.
Physical Bose touch/buttons/slider effects, BAS/Apple delivery and vendor transports remain
hardware/platform boundaries. Check privacy and the exact fork push URL before publishing.

## Checkpoint 18 — Tablet repair and completed reviewed boundary (23 October 2026)

The installed iPad Pro 11-inch (M5), iOS 26.4.1 pass finished **288/290**: all 278 units and
10 of 12 representative UI cases passed. Exact EQ gestures succeeded, but first-upgrade release
notes covered the later tab selection; expanded saved-output disclosure AX bounds also covered
the otherwise-visible Forget action. Preserve the actual failed summary rather than calling the
whole run green. The repair dismisses real notes before subsequent tab interaction and replaces
the wrapping disclosure with an independent 44-point native expansion button and sibling actions.
Captured-ID confirmation, cancellation and scoped forgetting remain unchanged.

The final **Upstream075-iPad-Repairs passed 281/281**, zero failures/skips, Xcode exit 0: all
278 units, exact three-band EQ/relaunch, nickname save/relaunch/cancel/confirmed-forget, and
real memo finalization before local playback. The two affected companion journeys then passed
**2/2 on iPhone** in `Upstream075-iPhone-OutputFinal`. All 12 iPad UI identifiers selected for
this pass have passing latest results across the stated runs. Current manifests contain **278
units + 39 app UI + 3 system UI on iPhone**, and **278 units + 24 representative app UI on iPad**.
The iPad aggregate includes 12 earlier named UI results; it is not the complete iPhone UI suite
or a single combined green run. Inspected unaltered tablet Field/AXXXL/EQ/preferences/memo PNGs
and the final phone preference capture are retained. Recordings and raw bundles remain ignored.

All 42 upstream commits now have native source/platform decisions and mapped runtime evidence
in [the final audit](IOS_UPSTREAM_075_AUDIT.md). Original HellzYeahh/contributor credits, complete
MIT/OFL notices, reference material and the historical Android0.4 tree remain intact. No further
feasible source omission was identified in this pinned range. Actual headphone touch/buttons,
ANC/EQ/slider effects, external mic/route delivery, BAS/Apple payloads and signed-device delivery
still require hardware; inaccessible Classic RFCOMM, global EQ, call interception and Android
assistant/codec/background privileges remain explicit platform boundaries.

Advanced **only the reviewed boundary** to 9e6c491/0.75.0, preserving imported d6ceffa/0.4.0.
The actual GET-only local checker resolved the same upstream tip: **identical, zero ahead/behind**;
[unaltered public report](UPSTREAM_075_CHECK.md). The checker never merges or advances metadata.
Future manual checks therefore identify changes after the completed 42-commit review. Hosted
workflow verification of all 38 Python cases and the reviewed comparison follows this fork push.
No original-repository write, upstream push destination or upstream PR is created. Local signing
settings remain preserved outside commits; inspect exact indexed paths and privacy before pushing.

## Checkpoint 19 — Hosted reviewed-boundary verification (23 October 2026)

After fork-only push `5ad2e37`, explicitly dispatched the manual checker on
`bdupreez/earshot-ios`, branch `codex/native-ios-port`. Actual [run 39892166974](https://github.com/bdupreez/earshot-ios/actions/runs/39892166974)
completed successfully at exact commit `5ad2e373943555c9f2c203a858d3d9fac78795b8`: all 38 Python
cases were discovered, 36 passed and the two macOS-only project-parser cases were skipped on
Ubuntu. Both pass in the actual local macOS 38/38 run. The live reviewed-baseline comparison
returned **identical**, and read-only report publication succeeded. Saved the actual bounded
public [run metadata](ios-test-results/upstream075-hosted-checker.json); full logs remain ignored.

The workflow stays manual, fork-restricted, `contents: read`, pinned official checkout and
`persist-credentials: false`; it uses a temporary built-in token and never imports upstream code.
This is a tooling/documentation verification, not an additional native or hardware test. All
required work for the pinned 42-commit reconciliation is complete at the documented public-iOS
scope. Physical acceptance and unavailable capabilities remain in the migration plan. Original
credits/notices and local signing edits are preserved. This final evidence-only push must again
pass exact staged-path/privacy inspection and target only the user's named fork branch.

## Checkpoint 20 — Upstream freshness recheck (26 October 2026)

Rechecked the original credited Earshot at the user's request using the GET-only updater and
an independent live Git/tag/release-API review. Upstream default `main` and annotated tag
`v0.75.0` resolve to `9e6c4912531ec6e159eded862d1b6ffa55094199`; the newest published release
is still v0.75.0. The actual comparison is **identical, zero ahead and zero behind**.
Preserved the [unaltered public report](UPSTREAM_2026_10_26_CHECK.md). No additional upstream
commits, newer tags or newer published releases were found, so no native adaptation is needed.

Fetched only the owner's fork, without tags: its iOS branch and local HEAD both matched
`1246ce8f28db27d18c18e746a3cf934c2a35d391`, with no ahead/behind commits. Keep the imported
Android 0.4.0 snapshot and separate reviewed 0.75.0 boundary unchanged. Original HellzYeahh /
Earshot contributor credits, MIT/OFL/reference notices and retained Android sources are intact.

This checkpoint changes documentation/evidence only. Native code, app version, tests and project
membership are unchanged, so no new Simulator pass is inferred or claimed; the actual 23 October
Xcode results remain the native evidence. Xcode 26.4.1 and the recorded simulator destinations
are still installed. Hardware acceptance and public-iOS limitations remain in the migration plan.
Preserve the private working project, inspect only the explicit staged documentation paths, run
the full index privacy guard and verify the fork push URL before publishing this dated checkpoint.
Never push to or change settings in HellzYeahh/earshot.

## Push policy

The user requested regular progress pushes with detailed commit messages. Pushes are restricted to **[bdupreez/earshot-ios](https://github.com/bdupreez/earshot-ios)**. The original `HellzYeahh/earshot` repository must never receive a push or upstream pull request from this work. Each checkpoint should state what changed, what actually passed, what failed or remains unverified, and what happens next.
