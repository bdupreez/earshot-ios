# Native iOS simulator captures

These images show the **AI-assisted iOS port attempt** of [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot). Original app, feature design, protocol research and DSP remain credited to upstream and its cited projects; preserve [all notices](../../THIRD_PARTY_NOTICES.md).

Images are unaltered exports from actual installed-Xcode XCUITest runs. Demo batteries, modes and device settings are simulated. Captures from an individually passing case do not imply the containing broad run passed every case, and no capture proves physical headphone compatibility. [Validation](../IOS_VALIDATION.md) records exact outcomes. Original Android reference images remain separately in `docs/screenshots/`.

| Capture | Verified view | Source bundle/case |
| --- | --- | --- |
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
| [Widget-applied mode](widget-applied-mode.png) | Actual small-widget Cycle opened the app and applied Aware in demo | `WidgetSystemFinal.xcresult` / `testSmallWidgetCycleOpensAppAndAppliesDemoMode` (Passed) |
| [Custom mode](custom-mode.png) | Saved mode after relaunch | Baseline `Acceptance.xcresult` / `testCustomModeEditsSurviveRelaunch` (Passed) |
| [Microphone](microphone.png) | Real recording/playback/delete flow, clip deleted | Baseline `Acceptance.xcresult` / `testRealMicrophoneRecordingPlaybackAndDeletion` (Passed) |
| [Device controls](device-controls.png) | Simulated reports and confirmed LE setting | Baseline `Acceptance.xcresult` / `testDeviceControlsVolumePlaybackAndRestartConfirmation` (Passed) |
| [Connection](connection.png) | Actual session route facts and conditional control transport | Baseline `Acceptance.xcresult` / `testToolsAndCompatibilityNavigation` (Passed) |
| [iPad Home](ipad-home.png) | Native top tabs and demo layout | Baseline `iPadSmoke.xcresult` / `testWelcomeAndDemoModeSwitching` (Passed) |

All use installed Xcode 26.4.1 and runtime iOS 26.4.1. `FeatureGapAcceptance` finished 184/187, `FeatureGapFinalFollowups` 162/163 and `NativeUIRepairsFinal` 161/161. Earlier failures remain in their raw summaries; the final [per-case manifest](../ios-test-results/current-iphone-coverage.json) resolves them explicitly. The historical baseline bundles passed 53/53 and 2/2 respectively. The permanent actual small-widget action passed 1/1 separately. Its full SpringBoard capture stays in the local result bundle; the public capture shows only Earshot’s resulting app state. Expanded iPad evidence follows separately.
