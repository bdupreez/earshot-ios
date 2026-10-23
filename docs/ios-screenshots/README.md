# Native iOS simulator captures

These images show the **AI-assisted iOS port attempt** of [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot). Original app, feature design, protocol research and DSP remain credited to upstream and its cited projects; preserve [all notices](../../THIRD_PARTY_NOTICES.md).

Images are unaltered exports from actual installed-Xcode XCUITest runs. Demo batteries, modes and device settings are simulated. Captures from an individually passing case do not imply the containing broad run passed every case, and no capture proves physical headphone compatibility. [Validation](../IOS_VALIDATION.md) records exact outcomes. Original Android reference images remain separately in `docs/screenshots/`.

| Capture | Verified view | Source bundle/case |
| --- | --- | --- |
| [Field light](upstream075-field-light.png), [System light](upstream075-system-light.png) | Independent persisted visual-style and Light/Dark choices, credited native Field typography | `Upstream075-iPhone-AppUI.xcresult` / `testFieldAndSystemColoursPersistWithoutChangingLightAppearance` (Passed; whole run 36/38) |
| [Neutral Home](upstream075-neutral-home.png) | No assumed Bose identity or telemetry without verified control | `Upstream075-iPhone-Repairs.xcresult` / `testRealConnectionExplainsSimulatorHardwareLimit` (Passed; whole run 281/281) |
| [Saved output management](upstream075-output-preferences.png) | App-only nickname with actual system route visibly separate, selective confirmed preference removal | Same / `testAppOnlyOutputNicknamePersistsAndSavedPreferencesForgetIsConfirmed` (Passed) |
| [Accessibility XXXL](upstream075-accessibility-xxxl.png) | Full listening-mode menu control above the floating tab bar; actual subsequent menu selection | Same / `testSoundcoreControlsRemainLabelledAndUsableAtAccessibilityTextSize` (Passed) |
| [Current Control Center](upstream075-control-center.png), [small widget](upstream075-widget-small.png), [medium widget](upstream075-widget-medium.png) | Actual native system elements before verified system-driven app activation and demo mode application; medium header/actions and three batteries fit the viewport | `Upstream075-iPhone-SystemAndValues.xcresult` / corresponding three permanent system cases (Passed; whole run 6/6) |
| [ANC after repeated drags](slider-anc.png) | Exact simulated 7/10 survives navigation and relaunch, with no alert | `SliderBackpressureUI.xcresult` / `testHomeANCRepeatedDragsCommitFinalDemoLevelAndPersist` (Passed; whole run 7/8) |
| [Hardware EQ controls](slider-headphone-eq.png) | All three native sliders retain exact signed end stops after repeated finger drags and relaunch | `SliderEQClampedFinal.xcresult` / `testAllHeadphoneEQBandDragsCommitAndPersistFinalDemoValues` (Passed; 1/1) |
| [Home, light](home-light.png), [Home, dark](home-dark.png) | Device-name quick switcher, explicit Demo, native appearances | `FeatureGapAcceptance.xcresult` / `testLightAndDarkAppearance` (Passed) |
| [Pro EQ](pro-eq.png) | Response graph and local-player scope | Same bundle / `testSoundAndAutomationScreens` (Passed) |
| [Original credits](credits.png) | HellzYeahh/contributors, AI-assisted disclosure, research links and release notes | Same / `testCreditsAcknowledgeUpstreamAndAIAssistance` (Passed) |
| [Mode cycle](mode-cycle.png) | Custom/Aware selection, current mode and wrapped sequence | Same / `testCustomConfiguredModeCycleWrapsAndPersistsInDemo` (Passed) |
| [Local player](local-player.png) | Seek, duration, stop, applied preamp and A/B | Same / `testNativePlayerSeeksProgressesAndComparesOriginal` (Passed) |
| [Restored preset](preset-editor.png) | Exact prior parametric filters after conversion/save | Same / `testGraphicConversionCanBeCancelledAndRestoredWithoutLosingFilters` (Passed) |
| [Latency reset](latency-reset.png) | Returned to first reported simulated session value; reset disabled when unchanged | Same / `testExperimentalLatencyCancelAndSimulationUpdateOnlyReportedDemoValue` (Passed) |
| [Print console](print-console.png) | Local validation and consent; Send disabled without a verified live link | Same / `testPrintConsoleValidatesLocallyRequiresConsentAndCannotSendInDemo` (Passed) |
| [Release notes](release-notes.png) | Original credits and native feature notes | Same / `testFreshInstallKeepsOnboardingClearAndNotesCanReopenAfterRelaunch` (Passed) |
| [Quick switcher](quick-switcher.png) | Final primary/secondary text colours and retained simulated earbud selection | `NativeUIRepairsFinal.xcresult` / `testHomeQuickSwitcherSelectsAndPersistsSimulatedEarbuds` (Passed) |
| [Wi-Fi rule](wifi-rule.png) | Demo access disabled and explicit physical-iPhone authorization boundary | Same / `testWiFiAccessIsDisabledInDemoAndNavigationDoesNotPrompt` (Passed) |
| [Deep GET plan](deep-scan.png) | Local planned queries/exclusions/estimate; offline Start disabled | `FeatureGapFinalFollowups.xcresult` / `testSelectedAndDeepScanPlansAreLocalAndCannotSendInDemo` (Passed) |
| [Self Voice](self-voice.png), [50% alert](battery-alert.png) | Level/remember flag independence and threshold persistence | Same / `testSelfVoicePersistencePreservesLevelAndFiftyPercentThresholdSurvivesRelaunch` (Passed) |
| [Control Center cycle](control-center-cycle.png), [applied mode](control-center-applied-mode.png) | Actual installed system control and resulting selected Aware in demo | `SystemMediumLayoutFinal.xcresult` / `testControlCenterCycleOpensAppAndAppliesDemoMode` (Passed) |
| [Small widget](widget-small.png), [applied mode](widget-applied-mode.png) | Final native tile and actual Cycle delivery into the app | `WidgetSmallLayoutFinal.xcresult` / `testSmallWidgetCycleOpensAppAndAppliesDemoMode` (Passed) |
| [Medium widget](widget-medium.png), [applied mode](widget-medium-applied-mode.png) | Unclipped final header/actions, three earbud batteries/minutes and actual Aware delivery | `SystemMediumLayoutFinal.xcresult` / `testWidgetMediumAwareOpensAppAndAppliesDemoMode` (Passed) |
| [Custom mode](custom-mode.png) | Saved mode after relaunch | Baseline `Acceptance.xcresult` / `testCustomModeEditsSurviveRelaunch` (Passed) |
| [Microphone](microphone.png) | Real recording/playback/delete flow, clip deleted | Baseline `Acceptance.xcresult` / `testRealMicrophoneRecordingPlaybackAndDeletion` (Passed) |
| [Device controls](device-controls.png) | Simulated reports and confirmed LE setting | Baseline `Acceptance.xcresult` / `testDeviceControlsVolumePlaybackAndRestartConfirmation` (Passed) |
| [Connection](connection.png) | Actual session route facts and conditional control transport | Baseline `Acceptance.xcresult` / `testToolsAndCompatibilityNavigation` (Passed) |
| [iPad Home](ipad-home.png) | Final native top tabs, quick switcher and demo layout | `iPadFeatureAcceptance.xcresult` / `testWelcomeAndDemoModeSwitching` (Passed) |
| [iPad microphone progress](ipad-mic-playback-progress.png) | Fresh real Simulator recording playing with measured elapsed/total progress | Same / `testRealMicrophoneRecordingPlaybackAndDeletion` (Passed) |
| [iPad release notes](ipad-release-notes.png) | Native feature notes, original HellzYeahh/contributor credit and AI-assisted disclosure | Same / `testFreshInstallKeepsOnboardingClearAndNotesCanReopenAfterRelaunch` (Passed) |
| [iPad deep GET plan](ipad-deep-scan.png) | Exact 3,897-query plan and offline safety gates | `iPadNativeRepairsFinal.xcresult` / `testSelectedAndDeepScanPlansAreLocalAndCannotSendInDemo` (Passed) |
| [iPad rule-applied preset](ipad-rule-applied-preset.png) | Local Bass boost selected by the multi-action rule | Same / `testMultiActionRuleAppliesAwareNoiseAndLocalPreset` (Passed) |
| [iPad Shortcuts guidance](ipad-shortcuts-guidance.png) | Foreground/system trigger boundaries, following verified weekday/reminder persistence | Same / `testWeekdayScheduleAndReminderChoicePersistAndExplainShortcuts` (Passed) |

All use installed Xcode 26.4.1 and runtime iOS 26.4.1. `FeatureGapAcceptance` finished 184/187, `FeatureGapFinalFollowups` 162/163 and `NativeUIRepairsFinal` 161/161. The final focused iPhone app/system run passed 6/6; its initial medium-widget capture exposed visual clipping despite passing delivery. The corrected extension passed 2/2 Control Center/medium-widget journeys with native viewport assertions, then 1/1 small-widget regression. Only the corrected medium capture is published here; the earlier clipped image remains in its local bundle.

Earlier failures remain in raw summaries. The historical 19 October iPhone aggregate covered 189 unit, 31 app UI and three system UI identifiers; the [current manifest](../ios-test-results/current-iphone-coverage.json) includes the newer 23 October results above. The slider pass preserves its initial 7/8 result and three failed exact-target attempts; the final physical end-stop/relaunch case passed 1/1. The expanded iPad run finished 168/171, then its repair run passed 169/169. The historical iPad aggregate recorded 189 unit and 15 representative app UI latest results (the [current manifest](../ios-test-results/current-ipad-coverage.json) tracks later runs), not a complete iPad UI-suite run or one combined 204-case result. The latest slider integration finished 191/192; its confirmation-wait repair passed 1/1. Historical baseline bundles passed 53/53 and 2/2. Raw full SpringBoard captures remain local; public widget images are native captures of Earshot’s own element.


Upstream0.75 native0.2 checkpoint (23October2026), actual iPhone17Pro/iOS26.4.1 XCUITest
attachments inspected after label/contrast repairs: [battery](upstream075-battery.png),
[headset companion](upstream075-companion.png), [Sennheiser virtual controls](upstream075-sennheiser.png),
[Soundcore synthetic readback/Lab](upstream075-soundcore.png), [saved voice memo](upstream075-memo.png).
The263-test checkpoint passed in one run; these images do not show physical accessory acceptance.
All original Earshot design/protocol/artwork credit remains HellzYeahh and contributors, MIT.
