# Exported Xcode simulator summaries

These are compact summaries exported with Apple's `xcresulttool get test-results summary` from actual simulator runs of this **AI-assisted iOS port attempt**. The original project is [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot); see [all credits](../../THIRD_PARTY_NOTICES.md).

- [Upstream0.75 iPhone checkpoint](upstream075-iphone-checkpoint.json): **263/263 Passed** in one actual run (258 units/integration +5 new UI), after the documented source/UI repairs.
- Earlier attempts are retained: [237-unit initial failure](upstream075-initial-units.json), [first263-test attempt](upstream075-first-feature-attempt.json), [second263-test attempt](upstream075-iphone-new-features.json), and [focused vendor repair1/1](upstream075-vendor-ui-final.json). These failed bundles remain Failed and are not relabelled.
- [Upstream 0.75 iPhone repairs](upstream075-iphone-repairs.json): **281/281 Passed**: all 278 units plus nickname persistence/confirmed removal, neutral Home and real menu selection at Accessibility XXXL.
- [Upstream 0.75 actual system/vendor follow-up](upstream075-iphone-system-and-values.json): **6/6 Passed**: Control Center, small/medium widgets and three vendor/large-text accessibility-value checks.
- [Broad app UI attempt](upstream075-iphone-app-ui-initial.json): 36/38 Passed; [unit/focused follow-up](upstream075-iphone-final-attempt.json): 282/284 Passed, including all 278 units and repaired complete preset lifecycle. Earlier failures remain Failed; no expected failures were added.
- [Current iPhone per-case coverage](current-iphone-coverage.json): latest results for **278 unit + 39 app UI** identifiers and three separate small/medium-widget and Control Center journeys, all Passed across the explicitly listed bundles. This manifest is explicitly **not a single-run total**; it excludes temporary system probes.
- [Upstream 0.75 iPad initial](upstream075-ipad-initial.json): **288/290 Passed**, all 278 units and 10/12 representative UI journeys. [iPad repairs](upstream075-ipad-repairs.json): **281/281 Passed**, all 278 units plus EQ/relaunch, nickname management and memo finalization on the repaired layout.
- [Final iPhone output layout](upstream075-iphone-output-final.json): **2/2 Passed**, nickname persistence/confirmed removal and real memo finalization repeated after the iPad disclosure repair.
- [Actual hosted checker metadata](upstream075-hosted-checker.json): fork workflow at `5ad2e37` succeeded; logs show 38 Python cases discovered, 36 passed/two macOS parser cases skipped on Ubuntu, live reviewed comparison identical and summary publication successful. Both parser cases passed locally. This is tooling evidence, not a native/Xcode run.
- [Current iPad per-case coverage](current-ipad-coverage.json): **278 unit + 24 representative app UI** identifiers, all latest Passed across named runs. Twelve UI journeys were rerun in this 0.75 pass; twelve retain older evidence. This is neither the full iPhone UI suite nor a single combined total.
- [Final iPad repairs](ipad-native-repairs-final.json): 169 passed, 0 failed, 0 skipped; all 166 units and the three previously failing UI cases.
- [Final medium layout and Control Center](system-medium-layout-final.json): 2 passed, 0 failed, 0 skipped; actual system delivery plus medium viewport/three-part battery checks.
- [Final small layout and action](widget-small-layout-final.json): 1 passed, 0 failed, 0 skipped on the corrected extension.
- [Focused iPhone platform UI](native-platform-ui-final.json): 6 passed, 0 failed, 0 skipped; action delivery passed, but visual review subsequently caught medium clipping, repaired and verified above.
- [Final diagnostic-isolation unit suite](diagnostic-isolation-units-final.json): 166 passed, 0 failed, 0 skipped; full native units including seven new wire/correlation regressions.
- [First actual Control Center acceptance](control-center-system-final.json): 1 passed, 0 failed, 0 skipped; system-driven Cycle opens Earshot and applies Aware in demo.
- [Expanded iPad integration](ipad-feature-integration.json): 168 passed, 3 failed, 0 skipped; 159 unit + 12 UI attempted, with all three failed harness cases subsequently passed in the final repair run.
- [First actual small-widget acceptance](widget-system-final.json): 1 passed, 0 failed, 0 skipped; WidgetKit Cycle opened Earshot and applied Aware in demo, without test-driven app activation.

- [Final native UI repairs](native-ui-repairs-final.json): 161 passed, 0 failed, 0 skipped; all 159 units plus Wi-Fi and final switcher verification.
- [Feature-gap focused follow-ups](feature-gap-followups.json): 162 passed, 1 failed, 0 skipped; preserves the remaining Settings gesture failure, subsequently resolved above.
- [Feature-gap broad integration](feature-gap-integration.json): 184 passed, 3 failed, 0 skipped; 159 unit + 28 UI attempted. The failed harness interactions were subsequently rerun as documented; this raw result remains Failed.

- [Integrated feature-gap unit regression](feature-gap-units-final.json): 125 passed, 0 failed, 0 skipped, including native replay/idle, preamp, recovery and protocol review fixes.
- [Feature-gap second signed unit checkpoint](feature-pass2-signed-units.json): 105 passed, 0 failed, 0 skipped, including access to the installed simulator app’s actual App Group container.
- [Feature-gap first unit checkpoint](feature-pass1-units.json): 96 passed, 0 failed, 0 skipped on expanded source; UI acceptance still pending at that checkpoint.
- [iPad smoke](ipad-smoke.json): 2 passed, 0 failed, 0 skipped; onboarding/mode switching and tools/compatibility navigation on iPad Pro 11-inch (M5).
- [Final iPhone device-control follow-up](iphone-device-controls.json): 1 passed, 0 failed, 0 skipped after rebuilding the final test helper.
- [iPhone acceptance](iphone-acceptance.json): 53 passed, 0 failed, 0 skipped; 41 unit tests and 12 UI scenarios.

JSON formatting is expanded for readability; the reported counts, device and runtime metadata are retained. Full `.xcresult` bundles, including individual logs, assertions, video and screenshot attachments, remain locally under ignored `ios/TestResults/`. These summaries do not replace those bundles or establish physical headphone compatibility. See [validation and limits](../IOS_VALIDATION.md) and [selected simulator screenshots](../ios-screenshots/README.md).
