# Earshot for iOS — an AI-assisted port attempt

This is an **experimental, AI-assisted attempt to port the original [Earshot Android app](https://github.com/HellzYeahh/earshot) to native iOS**. The original app was created by **HellzYeahh and the Earshot contributors**. Their feature design, implementation, DSP, protocol research, tests, and documentation provide the foundation for this work. Full credit belongs to those authors; this fork does not claim to have invented Earshot.

Brian du Preez is using AI assistance/tokens to help explore an iOS port in [bdupreez/earshot-ios](https://github.com/bdupreez/earshot-ios). AI-generated code is experimental and needs review and real-device testing. This is not an official release of upstream Earshot, Bose, or Skullcandy.

The original [MIT licence](LICENSE), copyright notice, Android source tree, and research are preserved. Read [all credits and third-party notices](THIRD_PARTY_NOTICES.md). The original Android README is preserved in [docs/ANDROID_UPSTREAM_README.md](docs/ANDROID_UPSTREAM_README.md).

## Default branch and upstream updates

This fork's default branch is **`codex/native-ios-port`**, containing the native iOS work.
Its retained **`main`** branch is the original Android 0.4.0 reference. This fork's branch settings
do not change [HellzYeahh/earshot](https://github.com/HellzYeahh/earshot).

To check for upstream changes, open [Actions → Check upstream updates](https://github.com/bdupreez/earshot-ios/actions/workflows/check-upstream-updates.yml),
choose **Run workflow**, and read the run's Summary. Or run locally:

```sh
python3 ios/scripts/check-upstream-updates.py --output ios/TestResults/upstream-update-check.md
```

The check compares the credited imported snapshot with upstream's current default-branch tip.
It reads public metadata and writes a report; it does not merge code, advance the imported baseline,
change remotes, or push upstream. There is no automatic schedule. See [the update workflow](docs/UPSTREAM_UPDATES.md)
for report limits and the deliberate porting process.

## Native iOS app

The primary development target of this fork is `ios/`: native **Swift + SwiftUI**, Core Bluetooth, AVFoundation, WidgetKit, App Intents, XCTest and XCUITest. No cross-platform wrapper, account, analytics SDK, or third-party Swift package is required.

Implemented areas include:

- Five native tabs: Home, Sound, Modes, Tools, and Settings, with light/dark appearance and iPhone/iPad layouts.
- Persistent, explicitly labelled demo profiles for the Bose models represented by upstream and the experimental Crusher interface. Demo data never establishes a physical Bluetooth connection.
- Real Bluetooth GATT discovery and Bose BLE L2CAP control transport, with a verified BMAP reply required before reporting connected. Battery, per-part earbud battery, noise control, modes, favourites, custom-mode layouts, device settings, and diagnostics use upstream BMAP knowledge. The fork owner reports a QC Ultra 2 connection; controlled hardware acceptance and the slider-fix retest remain pending.
- Native 3-band headphone EQ controls and a local-player Pro EQ: graphic/parametric filters, seven upstream presets including the AutoEq QC Ultra correction, response graph, headroom, preamp, limiter, and capped boost. JSON and AutoEq import/export, safe custom-preset editing/rename/delete, bounded deduplicated imports, recovery exports, seek/progress, and A/B bypass are supported.
- Actual local audio playback through AVAudioEngine and a real microphone record/play/delete check using AVAudioRecorder. The microphone route is shown rather than assumed.
- Persistent multi-action mode/noise/local-EQ rules, optional foreground Wi-Fi join triggers with explicit permission, weekday schedules while the app is open, optional tap-to-run notification reminders, low-battery notifications, eight Shortcuts actions, configurable mode cycling, rich battery/staleness widgets and iOS 18+ Quiet/Aware/Cycle Control Center buttons. Signed-device delivery remains unverified.
- Home device-name quick switching, once-per-release notes, and original-project attribution in onboarding, About, diagnostics, and documentation.
- Read-only documented/selected/deep protocol discovery, a separately consented experimental Print console, reported latency with session-original reset, and device-reported sidetone persistence. All physical effects remain unverified.

This is **not complete Android feature parity**. [The migration matrix](docs/IOS_MIGRATION.md) records implemented, conditional, missing, and platform-restricted features. In particular, iOS does not offer a direct public replacement for Android's arbitrary RFCOMM sockets, Shizuku codec controls, global other-app EQ, call-volume boosting, or unrestricted app/background automation. Compatible BLE control services must be tested on physical headphones. Crusher's documented Bragi link uses Classic RFCOMM; this fork has no supported iOS control transport for it.

**Apple Music and EQ:** Pro EQ's parametric filters, preamp and limiter process only Earshot's
local, unprotected audio files. For other apps' playback on supported Bose headphones, use
**Sound → Headphone EQ**, which controls the hardware's three bands. Apple Music also offers
its own [EQ settings](https://support.apple.com/en-ie/guide/iphone/iph5643d2c85/ios).
Adding a streaming-service player does not supply a public systemwide effects hook.

**Slider device-feedback repair:** ANC, hardware EQ and headset volume keep a local drag value
and send the final setting on release. Paced output continues during touch tracking, eligible
unsent ANC values coalesce without crossing commands, and compact mode replies cannot repeatedly
request themselves. This restores noise-slider behavior already present in upstream Earshot.
The [validation report](docs/IOS_VALIDATION.md) separates Simulator regressions from device retesting.

## Actual iOS simulator captures

These are native simulator captures of this AI-assisted port. Demo device values are simulated; they do not establish physical headphone compatibility. [More captures and provenance](docs/ios-screenshots/README.md).

<p align="center">
  <img src="docs/ios-screenshots/home-light.png" width="30%" alt="Native SwiftUI Home in light mode, explicitly marked Demo">
  <img src="docs/ios-screenshots/pro-eq.png" width="30%" alt="Native Pro EQ with explicit iOS local-player limitation">
  <img src="docs/ios-screenshots/credits.png" width="30%" alt="About credits the original Earshot and identifies this AI-assisted port attempt">
</p>

## Build with Xcode

1. Open `ios/Earshot.xcodeproj` in Xcode.
2. Select the shared **Earshot** scheme and an installed iPhone or iPad simulator.
3. Run. Choose **Try demo mode** to explore without physical headphones.

Development used the installed **Xcode 26.4.1 (17E202)** and **iOS 26.4.1** Simulator runtime (iOS 26.4 SDK). Deployment target is iOS 17.0+. No dependency manager is needed. A compilation-only simulator build can run without signing (App Group integration tests require the local ad hoc signing used by the test script):

```sh
xcodebuild -project ios/Earshot.xcodeproj -scheme Earshot \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO build
```

For a physical iPhone, select your development team for both the app and Widget extension, use unique bundle identifiers if necessary, and provision the shared App Group `group.dev.earshot.ios` consistently with `EarshotShared` and the widget provider. Bluetooth/microphone and optional Wi-Fi location-permission descriptions are included. Enable Access Wi-Fi Information on the app to validate foreground SSID rules. Headphone BLE transport, App Group provisioning, background behaviour, and real Bluetooth mic routing require hardware acceptance testing.

Keep personal team selections, provisioning profiles, signing keys and Xcode user settings local.
Do not stage personal signing edits in the tracked project file. Ignore rules cover local signing
files and user state, and `python3 ios/scripts/check-push-privacy.py` checks the Git index before
a push without displaying credential values. This is a targeted guard, not a universal secret scanner.

The checked-in project is ready to open. If Swift files are added or removed, regenerate it with:

```sh
python3 ios/scripts/generate_project.py
```

## Simulator tests

The test targets run actual XCTest and XCUITest in the installed simulator; they do not merely inspect source. Tests cover BMAP frames and safety guards, parser/capability handling, DSP and real offline audio rendering, local player lifecycle, persistent model/rule state, onboarding, navigation, custom-mode persistence, presets/player UI, microphone recording/playback/deletion, attribution, and light/dark screenshots.

```sh
xcrun simctl list devices available
EARSHOT_SIMULATOR_ID=YOUR_SIMULATOR_UDID ios/scripts/test-simulator.sh
```

**Baseline acceptance (before the feature-gap pass):** 53 tests passed (41 unit + 12 UI), with zero failures or skips on the installed iPhone 17 Pro simulator. See the validation report below for secondary-device checks and remaining limits.

**Current feature-pass verification:** all **189 native unit tests passed together**. Across the explicitly documented runs, **31 app UI journeys and three actual system journeys** have passing latest results. The focused slider/rule/player/credits checks cover eight UI identifiers across the initial run and final EQ repair. Small-widget Cycle, medium-widget Aware and Control Center Cycle retain their prior passing results. [Exact outcomes and per-case coverage](docs/IOS_VALIDATION.md) preserve earlier failures and make clear this is not one combined green run.

On iPad, all **189 units** passed and all three focused slider journeys have passing latest results after the documented confirmation-wait repair. The aggregate covers **15 representative iPad app UI journeys** across named runs; the complete iPhone UI suite was not run on iPad.

Results and screenshot attachments are stored in ignored `ios/TestResults/*.xcresult` bundles. Open a result bundle in Xcode to inspect individual assertions, logs, and screenshots. See [the validation report](docs/IOS_VALIDATION.md) for actual outcomes, environment, and limitations. Simulator tests cannot validate a physical Bose Bluetooth connection, sound through headphones, hearing safety, or vendor firmware behaviour.

## Repository map and provenance

| Path | Purpose |
| --- | --- |
| `ios/Earshot/` | AI-assisted native Swift port: app, UI, models, Bluetooth/protocol, audio, platform tools |
| `ios/EarshotWidget/` | Native WidgetKit extension |
| `ios/EarshotTests/`, `ios/EarshotUITests/` | Native simulator tests |
| `app/`, `protocol/`, `dsp/`, Gradle files | Preserved original Android implementation by upstream contributors; reference for the port |
| `docs/IOS_MIGRATION.md` | iOS parity matrix, challenges, Apple API evidence, hardware acceptance plan |
| `docs/IOS_VALIDATION.md` | Recorded iOS build/test results and simulator screenshots |
| Other `docs/*.md`, `docs/screenshots/` | Historical upstream Android notes and screenshots, labelled as such |
| `docs/reference/` | Preserved third-party protocol/reference research, captures and licences; not original iOS work |

## Credits and licence

- **[Original Earshot — HellzYeahh and contributors](https://github.com/HellzYeahh/earshot)**: the Android app and foundation of this port (MIT).
- **[bosectl — aaronsb and contributors](https://github.com/aaronsb/bosectl)** and **[Quiet Rebellion — MadEyez and contributors](https://github.com/MadEyez/quietrebellion)**: Bose protocol and connection research (MIT), as credited by upstream.
- **[AutoEq — Jaakko Pasanen and contributors](https://github.com/jaakkopasanen/AutoEq)**: headphone correction data (MIT); the QC Ultra curve selected by upstream uses Rtings/B&K 5128 measurements.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSE](LICENSE). Preserve those notices when redistributing. Bose, QuietComfort, Skullcandy, Apple, and other product names remain their owners' trademarks. No affiliation or endorsement is implied.
