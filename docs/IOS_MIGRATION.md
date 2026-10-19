# Earshot iOS migration audit

**This is an AI-assisted attempt to port [the original Earshot Android app by HellzYeahh and Earshot contributors](https://github.com/HellzYeahh/earshot) to native iOS.** The original app, feature design, protocol research, captured hardware evidence and Kotlin implementations belong to those upstream contributors. This fork does not claim to have invented their work. The upstream MIT licence, reference licences and acknowledgements remain applicable. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

Audit date: 19 October 2026. The iOS application uses Swift, SwiftUI, Core Bluetooth and AVFoundation. It is a port in progress. A working simulator experience is evidence about the iOS application, not proof that real headphones work or that Android feature parity has been reached.

## Evidence and scope

The Android audit covered `README.md`, `CLAUDE.md`, the core repository contracts, every navigation destination, `AndroidManifest.xml`, the Bose and Crusher protocol notes, the BLE PSM reader, the phone testing checklist and historical QA status. The Android implementation has capabilities that ordinary iOS apps cannot reproduce. Some Android features themselves remain experimental or unverified on hardware; those caveats must survive the port.

The retained Android directories are reference material for this migration. Old Android QA records describe upstream Android builds. They do not establish iOS compatibility.

## Platform challenges

### Bluetooth transport

Bose's Android implementation primarily opens an arbitrary Bluetooth Classic RFCOMM channel and probes BMAP. Core Bluetooth's Classic support is **GATT over BR/EDR**; it does not expose Android's arbitrary RFCOMM channel sockets. This distinction follows Apple's description of its Classic support. [Apple, What's New in Core Bluetooth](https://developer.apple.com/videos/play/wwdc2019/901/).

The public iOS route available to this port is the Bose BLE connection-oriented channel. The Android source discovers service `0000FEBE-0000-1000-8000-00805F9B34FB`, reads PSM characteristic `089CA084-6721-4419-9003-5E14D5AB587D`, validates a dynamic PSM in `0x80...0xFF`, then sends BMAP over an L2CAP stream. Core Bluetooth supplies `openL2CAPChannel(_:)` and input/output streams for this purpose. Whether a given model/firmware publishes that channel to iOS is a **physical-device question**. [Apple, openL2CAPChannel](https://developer.apple.com/documentation/corebluetooth/cbperipheral/openl2capchannel(_:)), [Apple, CBL2CAPChannel](https://developer.apple.com/documentation/corebluetooth/cbl2capchannel).

A Classic-only BMAP device cannot be made compatible merely by renaming a UUID or tunnelling arbitrary RFCOMM through a GATT characteristic. External Accessory is a separate MFi path that requires accessory-manufacturer cooperation and an authorized protocol; the presence of Bluetooth audio pairing alone does not grant it. The fork does not have that authorization. [Apple, External Accessory](https://developer.apple.com/documentation/externalaccessory).

Skullcandy Crusher 1080 is a separate Bragi BOS-RPC stack over Classic RFCOMM, with PPP framing and optional authenticated key exchange. A Bose BMAP implementation cannot control it. Its iOS control transport and secure-session port are outstanding; demo support must remain labelled simulated.

### Audio and calls

An iOS AVAudioEngine can equalize audio that this application plays. It cannot attach Android DynamicsProcessing effects to Spotify, YouTube, other applications or the system mix. Therefore the local Pro EQ preview and local-file player are useful native replacements, but they do not provide the original cross-app Pro EQ or volume boost. AVAudioUnitEQ is an audio-processing node in the application's graph. [Apple, AVAudioUnitEQ](https://developer.apple.com/documentation/avfaudio/avaudiouniteq), [Apple, AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession).

The hardware's own three-band EQ is different: a successful BMAP write changes the headphone firmware and can affect audio from other sources. That control remains possible over a working BLE BMAP connection.

The local player stops its hardware engine and releases its own playback session when idle, and resets the native timeline after completion for replay. It respects the microphone tool’s shared-session ownership. UI and engine share the actual applied preamp calculation, including extra headroom when protection is off. The local audio graph uses Apple's Dynamics Processor compressor before the Peak Limiter. The compressor controls sustained overload; the limiter catches remaining peaks. Native offline-render tests check both a bounded peak and audible output, because a silent output would otherwise satisfy a peak-only assertion. This validates the app's own DSP graph, not a headset's acoustic output or a safe listening level.

The system chooses the Bluetooth audio codec. There is no public iOS counterpart to the Android Shizuku shell service used here to select AAC/SBC, inspect negotiated HFP codecs or change absolute-volume settings. Route type and application session sample rate must not be presented as proof of a negotiated wireless codec. Only a user may directly set the system output volume; `AVAudioSession.outputVolume` is read-only. Automatic volume boosting for another application's call is consequently unavailable. [Apple, outputVolume](https://developer.apple.com/documentation/avfaudio/avaudiosession/outputvolume).

The microphone check uses the real iOS recorder/player and reports the actual input route. Requesting Bluetooth HFP input may switch a headset from high-quality A2DP playback to its call-audio route. A recording made through the simulator's Mac microphone does not validate the headset microphone or its call quality.

### Background behavior and automations

An Android connected-device foreground service and persistent notification have no direct always-running iOS equivalent. Core Bluetooth background handling can respond to relevant connection/peripheral events, subject to system suspension and restoration rules. It is not an unrestricted scheduler. iOS 26's Core Bluetooth Live Activity behavior is a possible future extension, not a feature this port should claim without implementing it. [Apple, Core Bluetooth background processing](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html), [Apple, Core Bluetooth](https://developer.apple.com/documentation/corebluetooth).

Exact clock-time device commands cannot be guaranteed by BGTaskScheduler: Apple states that `earliestBeginDate` is a lower bound, not a guaranteed launch time. The current schedule implementation runs while Earshot is open. [Apple, earliestBeginDate](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate).

Ordinary apps cannot monitor arbitrary other apps becoming foreground as Android Usage Access does. User-created Shortcuts personal automations are an appropriate iOS integration path. Optional foreground Wi-Fi rules use the Access Wi-Fi Information entitlement and precise While Using location authorization, requested only by the explicit Allow Wi-Fi access action. They observe SSID changes while Earshot is open and pause when inactive or in demo. No GPS updates, Always location, or background Wi-Fi watcher is used. Simulator cannot validate real SSID access; signed-iPhone authorization and entitlement checks remain required. [Apple, App Intents](https://developer.apple.com/documentation/appintents), [Apple, current Wi-Fi network](https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent(completionhandler:)).

Widgets and Control Center actions are feasible on iOS through WidgetKit and App Intents. They require their own extension, shared state and real command execution. They are implementation work rather than an inherent platform prohibition. [Apple, interactive widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [Apple, controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system).

## Feature parity matrix

Status meanings: **Native** is implemented for local iOS behavior; **Partial** has a working subset; **Hardware pending** has a public transport/code path but lacks physical validation; **Blocked** requires a capability unavailable to this ordinary iOS app; **Outstanding** is feasible work not delivered. Demo behavior is always simulated.

| Android capability | iOS status | What this means in this fork |
|---|---|---|
| Native onboarding, tab navigation, light/dark UI | Native | SwiftUI interface and explicit simulator/demo entry. |
| Home quick switcher and release notes | Native | Tap the device name for local demo profiles or the existing real discovery/connection flow. Once-per-release notes defer behind onboarding/errors and remain available in About. iOS does not expose an arbitrary system paired-device list. |
| No account, local settings/presets | Native | Stored on device; no Bose sign-in or analytics SDK. |
| Virtual Bose model selection | Partial | Swift model profiles drive a simulated UI; this is not the Android virtual peripheral protocol test harness. |
| BLE discovery and BMAP over LE L2CAP | Hardware pending | Real Core Bluetooth scan, PSM lookup and streams need iPhone/headphones validation. |
| Bluetooth Classic RFCOMM channel probing | Blocked | No arbitrary RFCOMM socket API for this iOS application; no supported MFi integration. |
| Automatic reconnect and background state restoration | Hardware pending | Opt-in remembered peripheral, finite backoff, cancellation/manual-stop, Core Bluetooth restoration and fresh BMAP verification are implemented. Physical reconnect/background delivery remains unverified. |
| Battery and firmware | Hardware pending | Parse/report received device information; sample demo battery is explicitly simulated. |
| Bud/case battery and remaining minutes | Hardware pending | Per-component reports and device-estimated minutes are parsed; unknown sentinels remain unknown. Home/widget display and demo values exist; actual device reports need validation. |
| Model/product identification and capability adaptation | Partial | Upstream product/name catalogue, known absences, older mode-dump fallback and reported built-in counts are ported; device responses override defaults. Physical model/firmware combinations remain unverified. |
| Listening-mode selection | Hardware pending | BMAP command path and demo switching; audible behavior requires hardware. |
| ANC, noise level, Wind Block, spatial modes | Hardware pending | Live settings, direct-noise and editable custom-slot fallback paths. Direct CNC preserves toggle permission and step quantization; compact Wind Block comparison follows upstream echo behavior without changing wire bytes. Physical effects still require acceptance tests. |
| Custom mode editing/favourites/reset | Hardware pending | Demo editing/persistence plus writes gated by device-reported capabilities and complete slot layouts; physical validation remains outstanding. |
| Hardware three-band EQ | Hardware pending | Uses BMAP values; do not infer audible results from simulator sliders. |
| Graphic/parametric EQ, presets and AutoEq import | Partial | Native create/edit/copy/rename/delete, filter reorder/removal, reversible graphic conversion, JSON/AutoEq import/export, bounded deduplicated imports and recovery backups. Seeking/progress/A-B and automatic/manual preamp operate on local playback; cross-app effects remain unavailable. |
| Systemwide/per-app Pro EQ, external-app profiles | Blocked | The app cannot intercept other apps' audio sessions. |
| Volume boost and limiter | Partial | Local audio graph with a compressor followed by a peak limiter; native render checks cover sustained overload and audible output. No system or call boost. |
| Playback transport/headset volume | Hardware pending | Device-control panel uses reported volume ranges and playback action masks; writes wait for device reports. Simulator controls are explicitly simulated. |
| Live headset push notifications | Hardware pending | Requires successful BMAP subscription and handling real responses; simulator changes prove UI behavior only. |
| LE Audio toggle | Hardware pending | Device-control toggle requires restart confirmation. The headphone setting is distinct from iPhone transport support. Opt-in reconnect is implemented; restart/reconnect needs physical testing. |
| Codec readout/switching and absolute-volume toggle | Blocked | Shizuku/private Android Bluetooth APIs have no public iOS replacement. |
| Latency readout/experimental write | Partial | Reported signed-16-bit range/value plus a separately confirmed experimental write, only when the device reports support and a valid range. Units and audible effect remain unknown, as upstream warns. The first valid report is retained for this session; Reset to original uses the same experimental confirmation and range/report checks. A SET echo is followed by a fresh GET; a valid report is required for completion. Physical testing is still required. |
| Call-volume boost, negotiated call codec | Blocked | Cannot change another app's call gain or inspect its private Bluetooth negotiation. |
| Real microphone record/meter/play/delete | Native | AVAudioRecorder/AVAudioPlayer, explicit permission, actual route, local cache, interruptions stop capture, and actual elapsed/total playback progress. |
| Sidetone | Hardware pending | Device-reported level and remember-after-restart flag are independently controlled without overwriting the other value; audible effect and persistence need hardware verification. |
| Auto-pause, auto-answer, multipoint, prompts, touch, standby | Partial | Capability-gated read/write controls; installed voice-prompt languages can be selected while preserving prompt enablement. Physical effects require validation. |
| Paired-source list and information | Hardware pending | Reads the headphone-reported list and device names; this is separate from iOS system audio pairing. |
| Headphone source routing, pairing mode and rename | Hardware pending | Safe upstream commands, independent capability evidence, local-source warnings, confirmations and report-driven completion/timeout are implemented. System audio route selection remains a separate iOS picker. |
| Power off and shortcut-button mapping | Hardware pending | Power confirmation and shortcut choices gated by reported device support. Physical effect remains unverified. |
| Read-only device/LE/profile reports | Hardware pending | Microphone mute flag (meaning unconfirmed), firmware-only operation banner, received button events, headphone LE preference/availability and paired Classic/LE profile bits are parsed and shown separately from iPhone transport/codec. Actual reports need physical validation. |
| Safe raw read/lab report | Partial | Manual GETs plus documented, selected-block and deep 0–63 GET discovery with response/refusal/timeouts, cancellation and bounded redacted reports. Deep discovery excludes firmware/auth/Print blocks, destructive addresses and known START-only functions; 3,897 eligible queries can take up to 72 minutes. Plan selection is local and sending requires a verified foreground link. The separate experimental Print console accepts only upstream’s bind/unbind/verbosity/output verbs after explicit consent; local validation sends nothing. It bounds collection/transcript, times out, and redacts generic logs. Firmware arguments/effects remain unverified. No arbitrary BMAP write console, firmware/auth scans or destructive scan operations. |
| Destructive firmware/auth/factory writes | Guarded | Remain disallowed; never advertise firmware updates in this port. |
| On-connect/manual automation | Partial | Native stored multi-action rules preflight every action, wait for matching live reports between mode/noise writes, expose cancellation/failures and allow local-only rules offline. |
| Automation action combinations | Partial | Mode, noise and local EQ preset/off actions are implemented in canonical order. Preset deletion leaves an actionable broken reference; invalid combinations fail before any action is sent. |
| Day/time background schedule | Partial | ISO weekdays, DST-safe occurrence latching and foreground execution; optional system reminders open the app after a user tap. Exact suspended command execution remains unavailable. |
| Wi-Fi/other-app foreground triggers | Partial/blocked | Optional foreground SSID join rules with explicit precise While Using authorization, once-per-join latching and deferred capability preflight. Eight foreground Shortcuts actions support user-created Shortcuts personal automations. Signed physical SSID access is unverified; unrestricted other-app/background watchers remain unavailable. |
| Low-battery notification | Hardware pending | Native permission/helper integrated with actual battery/charging reports and threshold recovery; Off or 5–50% in 5% steps. No alerts from demo data; physical delivery remains unverified. |
| Widget and Quick Settings replacement | Partial | WidgetKit shows timestamped battery/per-bud/minutes snapshots with stale-state indication. Eight Shortcuts actions and iOS 18+ Quiet/Aware/Cycle ControlWidget request buttons use a bounded atomic expiring App Group queue and foreground capability validation. Actual small-widget Cycle opened the app and applied the next demo mode in Simulator. Medium widgets, Control Center, Siri and signed-device delivery remain pending. |
| Configurable one-tap mode cycle | Partial | User-selected configured slots persist in slot order; automatic uses favorites, then presets/available modes. Widget, Control Center and Shortcut requests resolve the next slot against current foreground device reports, with stale/empty choices explained. System-surface delivery needs acceptance. |
| Skullcandy Crusher bass/security | Outstanding/blocked | Simulated model only; Bragi secure transport is not ported and Classic transport is unavailable. |
| Credits/licences | Native | Original Earshot provenance, AI-assisted migration disclosure and upstream/reference acknowledgements. |

The table is deliberately stricter than a screenshot checklist. A button existing in a demo does not establish a hardware feature, and an unavailable API must not be replaced with a pretend success message.

## Permissions and capabilities

| Capability | Required iOS declaration/authorization | When to ask |
|---|---|---|
| Bluetooth discovery and BLE commands | `NSBluetoothAlwaysUsageDescription`; system Core Bluetooth authorization | When the user chooses real headphones. Demo entry should not require it. |
| Bluetooth event handling in background | `UIBackgroundModes` → `bluetooth-central` | Build capability; does not grant unlimited execution or exact timers. |
| Local audio continuing when backgrounded | `UIBackgroundModes` → `audio`; appropriate AVAudioSession category | Only while the app is playing or recording actual audio; never use silent playback to keep automation alive. |
| Microphone check | `NSMicrophoneUsageDescription`; `AVAudioApplication.requestRecordPermission()` | Only when Record is tapped. Denial should explain how to enable it in Settings. |
| Battery alert | `UNUserNotificationCenter.requestAuthorization` with alert/sound | When the user enables notifications; not needed for normal controls. |
| File import/export | User-selected document picker/share sheet | User action grants scoped access; no broad filesystem permission. |
| Widget shared state | Matching App Group entitlement for app/widget | Signing capability; requires a valid development team for device distribution. |
| Wi-Fi trigger | Access Wi-Fi Information entitlement and `NSLocationWhenInUseUsageDescription`, precise While Using authorization | Only the explicit Allow Wi-Fi access action. Demo navigation does not request access. No location updates or Always authorization. |
| Other-app usage/call controls | No applicable public permission | Do not request unrelated permissions as a workaround. |

For recording, a cached `earshot-mic-check.m4a` stays in the application's cache until deleted, replaced, cleared by the OS or the app is removed. It is protected with complete file protection where supported. The app stops on an audio interruption and does not start microphone capture merely because a screen is displayed. Playback is this app's own audio. System microphone privacy indicators and the active recording UI remain visible while recording.

## Simulator verification and hardware acceptance

The project is built with the installed `/Applications/Xcode.app` toolchain (Xcode 26.4.1, build 17E202), rather than a substitute mobile runtime. Completed Simulator XCTest and XCUITest results are recorded in the [iOS validation report](IOS_VALIDATION.md). The [simulator test script](../ios/scripts/test-simulator.sh) reproduces the run. The simulator can verify Swift compilation, navigation, state updates, persistence, parsers, local DSP and UI accessibility. It cannot establish a working RF link to these headphones, audible ANC/EQ changes, multipoint behavior, headset microphone routing, codec negotiation, or locked-device Bluetooth reliability. Apple's current Bluetooth accessory sample explicitly requires a physical device. [Apple, setting up a Bluetooth accessory](https://developer.apple.com/documentation/accessorysetupkit/setting-up-and-authorizing-a-bluetooth-accessory).

The simulator UI tests exposed a real SwiftUI List bug: the automation row's edit and Run now buttons shared the automatic row interaction, so Run now could also reopen the editor. The row now uses an independent button style, and tests assert that the editor is dismissed and the requested mode appears on Home. LabeledContent is queried by its actual combined accessibility label. The test harness scrolls controls fully clear of the floating tab bar before interacting; accessibility can otherwise report an obscured control as hittable. Anchored confirmation popovers are cancelled by tapping outside when the system omits a Cancel row, with assertions that cancellation preserves the setting.

Microphone permission is pre-granted to the app in the test Simulator for the recording acceptance flow; the recorded file, automatic stop, playback and deletion use the real AVFoundation implementation. Final duration is read from the completed audio file, avoiding a longer wall-clock display when the Simulator delays a recorder callback. Simulator microphone permission does not validate headset routing or physical iPhone permission behavior.

Physical-device acceptance remains required:

1. Install a signed build on an iPhone using Xcode. Record iPhone model/iOS version, headphone model, firmware and whether the official vendor app was closed. Test Bluetooth denied/off/on and fresh permission states.
2. Pair audio in iOS Settings. Discover the device in Earshot. Log advertised services, the PSM bytes, L2CAP open/error, liveness reply, product ID and capabilities. Do not treat audio pairing as a control connection.
3. Read battery, per-bud/case state, firmware, current mode and EQ. Compare with the vendor application, used separately. Unknown values must stay unknown rather than demo defaults.
4. Select Quiet/Aware/custom modes, change ANC level and wind/spatial controls, and listen for each change. Confirm that a STATUS/RESULT matches the requested value. Exercise firmware refusals and legacy/no-block-31 models before advertising those models as supported.
5. Change hardware EQ and sidetone, then reconnect and re-read. Verify supported switches individually. For custom slots, physically validate each reported complete status/write layout and the resulting saved mode before claiming support; the UI enables writes only when it receives a complete supported layout.
6. Subscribe to pushes; change modes/volume on headset controls and connect charging power. Confirm timely UI updates without aggressive polling. Test dropped streams, busy vendor app, radio loss and reconnect.
7. If offering the LE Audio switch, obtain the in-app restart confirmation, observe interruption/reconnect and verify the resulting state. Treat latency writes as experimental: record the reported range/units, obtain the in-app confirmation, verify the fresh report, and establish a repeatable audible result before claiming useful latency control.
8. Record with the phone mic and the headset mic separately. Confirm reported input routes, meter movement, 8-second auto-stop, playback, delete, microphone denial, incoming-call interruption and route removal. Compare device behavior to simulator behavior without equating them.
9. Play a user-imported local audio file through the native EQ. Verify the graph affects only that audio, presets survive relaunch, invalid imports explain errors and disabling restores flat playback. Listen at a conservative user-chosen output volume.
10. Verify manual/on-connect rules, foreground schedules and no duplicate fire within one schedule occurrence. For Wi-Fi rules, test precise/approximate/denied authorization, foreground join/leave, same-SSID resume, late Bluetooth readiness, and a signed entitlement on an iPhone; do not infer SSID behavior from Simulator. Test widget/Shortcut commands with the app open, suspended and after termination, displaying actionable failure when disconnected.
11. Request notifications, simulate an actual low-battery threshold crossing, verify one alert, and verify charging/recovery resets the latch. Demo mode must never emit fake low-battery system alerts.
12. Lock the iPhone, switch apps, reboot, force-quit and relaunch. Document what reconnects automatically and what requires reopening Earshot. Run VoiceOver and large Dynamic Type checks on actual hardware before release.

Only update a matrix entry to verified after saving its device details and evidence. The Android captures retained in `docs/reference/` are valuable parser fixtures, not iOS hardware certification.
