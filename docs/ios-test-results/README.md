# Exported Xcode simulator summaries

These are compact summaries exported with Apple's `xcresulttool get test-results summary` from actual simulator runs of this **AI-assisted iOS port attempt**. The original project is [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot); see [all credits](../../THIRD_PARTY_NOTICES.md).

- [Current iPhone per-case coverage](current-iphone-coverage.json): derived latest results for 159 unit + 29 app UI identifiers and one separate system-widget journey, all Passed across the explicitly listed bundles. This manifest is explicitly **not a single-run total**; it excludes temporary system probes.
- [Actual small-widget acceptance](widget-system-final.json): 1 passed, 0 failed, 0 skipped; WidgetKit Cycle opened Earshot and applied Aware in demo, without test-driven app activation.

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
