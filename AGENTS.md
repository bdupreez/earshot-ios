# Earshot: AI-assisted native iOS port attempt

The original Android app is [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot), MIT. Preserve original copyright/licences, attribution, reference captures and protocol research. Read `THIRD_PARTY_NOTICES.md` and keep the original project's prominent credit in the README and About screen. This fork is an experimental AI-assisted port, not an original invention of Earshot.

Native implementation is `ios/`, Swift/SwiftUI, without third-party packages. Open `ios/Earshot.xcodeproj`. Xcode 26.4.1 is installed; target iOS 17+. After adding/removing Swift files, regenerate the checked-in project with `python3 ios/scripts/generate_project.py`. Build artifacts belong under ignored `ios/build/` and test results under `ios/TestResults/`.

Push progress checkpoints regularly, with detailed commit messages and current validation/remaining-work notes in `docs/IOS_PROGRESS.md`. Push **only** to the user's fork, `git@github.com:bdupreez/earshot-ios.git` (or the equivalent HTTPS URL). Verify the push URL before each push. Never push to `HellzYeahh/earshot`, add an upstream push destination, or open an upstream pull request. Work on a `codex/` branch unless the user requests another branch.

The fork's default is `codex/native-ios-port`; `main` retains the original Android snapshot.
Check upstream using `ios/scripts/check-upstream-updates.py` or the manual Actions workflow.
`docs/upstream-baseline.json` records the last deliberately imported snapshot, not the last check.
Never advance it just because an update check ran. Review/port upstream changes separately, with
original credits, meaningful tests and fork-only pushes. Do not automatically sync upstream over iOS.

Keep personal Apple developer-account identifiers, signing identities, provisioning profiles, keys,
local Xcode user settings and private configuration out of commits. Preserve local signing edits
without staging them; never regenerate the project over those edits. Before each push, run
`python3 ios/scripts/check-push-privacy.py` against the index and inspect the exact staged paths.
Ignore rules do not protect an already-tracked project file: inspect its staged contents explicitly.

Use actual `xcodebuild test` on an installed simulator and inspect screenshots for UI changes. `ios/scripts/test-simulator.sh` runs both XCTest and XCUITest; select a local device using `EARSHOT_SIMULATOR_ID`. Never equate simulator demo tests with headphone-hardware validation. Record results and outstanding limitations in `docs/IOS_VALIDATION.md` and `docs/IOS_MIGRATION.md`.

The retained Android sources and historical docs are upstream provenance/reference; their Android-only ownership/build instructions in `CLAUDE.md` apply to that retained implementation. Do not remove the Android implementation just to make this fork appear original. iOS is the primary development target of this fork.

Do not invent platform capabilities. No global other-app EQ, arbitrary RFCOMM socket API, codec forcing, call audio interception, exact background schedules, or app-use spying. BLE L2CAP control is conditional on hardware exposing the expected service and a verified BMAP reply. Do not report a physical device as connected until protocol verification succeeds. Keep destructive firmware/auth/reset commands blocked at the write path, and never turn demo values into physical device state.
