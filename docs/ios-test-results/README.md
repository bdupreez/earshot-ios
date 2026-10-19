# Exported Xcode simulator summaries

These are compact summaries exported with Apple's `xcresulttool get test-results summary` from actual simulator runs of this **AI-assisted iOS port attempt**. The original project is [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot); see [all credits](../../THIRD_PARTY_NOTICES.md).

- [Feature-gap first unit checkpoint](feature-pass1-units.json): 96 passed, 0 failed, 0 skipped on expanded source; UI acceptance still pending at that checkpoint.
- [iPad smoke](ipad-smoke.json): 2 passed, 0 failed, 0 skipped; onboarding/mode switching and tools/compatibility navigation on iPad Pro 11-inch (M5).
- [Final iPhone device-control follow-up](iphone-device-controls.json): 1 passed, 0 failed, 0 skipped after rebuilding the final test helper.
- [iPhone acceptance](iphone-acceptance.json): 53 passed, 0 failed, 0 skipped; 41 unit tests and 12 UI scenarios.

JSON formatting is expanded for readability; the reported counts, device and runtime metadata are retained. Full `.xcresult` bundles, including individual logs, assertions, video and screenshot attachments, remain locally under ignored `ios/TestResults/`. These summaries do not replace those bundles or establish physical headphone compatibility. See [validation and limits](../IOS_VALIDATION.md) and [selected simulator screenshots](../ios-screenshots/README.md).
