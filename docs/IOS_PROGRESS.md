# Progress log — AI-assisted iOS port attempt

The original Android app is **[Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot)**, MIT. This fork's native iOS work is an AI-assisted port attempt, not a claim of original authorship. Preserve [all credits and notices](../THIRD_PARTY_NOTICES.md).

## Checkpoint 1 — native app and first simulator validation (19 October 2026)

Implemented a SwiftUI iOS application with Home, Sound, Modes, Tools and Settings tabs, persistent demo profiles and settings, light/dark appearance, native local audio playback, graphic/parametric EQ, the seven upstream presets, AutoEq/JSON import/export, microphone recording/playback/deletion, diagnostics, rule editing, foreground schedules, WidgetKit overview and Quiet/Aware App Intents.

Ported BMAP packet framing, parsers, commands and safety guards. Added public Core Bluetooth discovery, Bose BLE PSM discovery, L2CAP streams, and protocol liveness verification. Live settings, battery, modes, favourites, custom-mode layouts, volume, playback, LE Audio, paired-source reads and shortcut controls are conditional on actual device reports. No physical headphone compatibility claim is made.

Built the app and Widget extension with the installed Xcode 26.4.1. The first completed simulator unit suite passed **40 tests**. Actual waveform tests caught an overloaded peak-limiter graph decaying toward silence; adding native dynamics compression before the peak limiter corrected the measured simulator behavior. A subsequent regression for fully bypassing Pro EQ is added and awaits the next completed unit run.

UI work has already exercised attribution, custom-mode persistence, earbuds profiles, light/dark display, local playback and microphone recording/playback/deletion in the real simulator. The final complete UI suite is still being repaired/rerun. Initial test issues included combined accessibility labels and microphone permission handling. Review of an actual test video also revealed a SwiftUI List row triggering both the automation editor and Run now buttons; separate borderless button actions fix that product bug and need confirmation in the next run.

Updated README, About/onboarding, changelog, contributor guidance, notices and historical document banners to identify the original project and this AI-assisted attempt. The original MIT licence, Android implementation, captures and third-party reference licences remain intact. [Migration details](IOS_MIGRATION.md) distinguish native, partial, hardware-pending, blocked and outstanding features.

Next: complete the iPhone UI suite, run iPad smoke checks, rerun all unit tests on final sources, export/inspect screenshots, and record authoritative result bundles in [IOS_VALIDATION.md](IOS_VALIDATION.md).

## Push policy

The user requested regular progress pushes with detailed commit messages. Pushes are restricted to **[bdupreez/earshot-ios](https://github.com/bdupreez/earshot-ios)**. The original `HellzYeahh/earshot` repository must never receive a push or upstream pull request from this work. Each checkpoint should state what changed, what actually passed, what failed or remains unverified, and what happens next.
