# iOS Bluetooth transport and verification limits

This is part of an **AI-assisted iOS port attempt of [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot)**. The original Android protocol and connection research provide its foundation. Preserve the original MIT licence and [full credits](../../../THIRD_PARTY_NOTICES.md).

The Swift implementation uses Apple's public Core Bluetooth API. It scans for Bose advertisements,
discovers the PSM characteristic `089CA084-6721-4419-9003-5E14D5AB587D` (normally in service `FEBE`),
reads a dynamic LE PSM in `0x80...0xFF`, opens an LE connection-oriented L2CAP channel, and sends
the same BMAP wire packets as the Android app. These identifiers and parsing rules come from
`app/src/main/kotlin/dev/earshot/bt/BmapPsmReader.kt` and
`docs/bmap-from-bose-app-13.3.4.md`, not a verified iPhone capture.

The input/output streams preserve partial writes and fragmented/concatenated frames. Commands are
spaced 80 ms apart. A connection is published as usable only after a device-side STATUS/ERROR/RESULT
response to GET `[0.1]`. Opening GATT or L2CAP alone never marks it connected. Every outgoing packet
passes the write guard: firmware/authentication writes and destructive reset/wipe commands are blocked.

Following a user report of queue-full alerts on a connected QC Ultra 2, all Bluetooth-backed sliders
(ANC, bass/mid/treble and reported headset volume) keep a local thumb value during a drag and commit
the final value on release, restoring upstream's original end-of-drag noise behavior. Device reports
remain authoritative after release; reports during a gesture do not move its thumb. Context changes,
disablement, navigation and inactivity cancel an unfinished gesture. Accessibility/keyboard value
changes can commit without touch callbacks. Local audio/DSP sliders do not send Bluetooth commands.

The output pump runs in common run-loop modes so touch tracking cannot pause its paced retries.
Only wholly unsent, contiguous absolute ANC writes (`[31.10]` or `[1.5]`) to the same device/port
can replace an older unsent value, retaining one associated `[31.3]` read. Partially transmitted
frames, EQ-band commands, discrete actions, diagnostic traffic and unrelated commands are ordering
barriers. The 256-frame bound and 80 ms spacing remain. Compact `[31.6]` mode records trigger at most
one automatic detail read per slot until explicit refresh/reconnect; a repeated compact reply must
not cause a request/reply loop. Complete editable mode records remain authoritative.

Controls use parsed capability and status reports rather than assuming that every Bose model accepts
the same functions. The upstream product catalogue and model-name matching supply fallback labels
and known-absent functions; valid device reports take precedence. Refresh skips functions explicitly
refused by the device. A queued write is not proof that a setting changed: pending operations wait for
the relevant device report or show an error/timeout.

Noise control can use the current-settings command, an editable mode, or the upstream CNC `[1.5]`
path when supported. Direct CNC requires a valid reported step range, converts the UI's 0–10 scale
to that range, preserves a non-toggleable enable flag and compares the reply with the quantized
target. Optional read-only reports include microphone mute, operation mode, button events,
LE Audio support/preference, connection availability and paired-source profiles. Unknown values
remain hidden. These reports do not establish iOS microphone permission, the negotiated audio
codec or an iPhone's active LE Audio transport.

Protocol diagnostics offers foreground GET-only discovery using documented addresses, selected
blocks/functions or the upstream 0...63 deep grid. Firmware/authentication/Print blocks,
destructive addresses and known START-only functions are excluded. Deep discovery contains 3,897
queries and can take up to 72 minutes when every response times out. Selection sends nothing;
a verified control link is required. Queries run one at a time with a one-second response deadline
and 100 ms pacing; cancellation, inactivity or link loss stops further requests. GET echoes do not
count as replies. Results and response text are bounded. Ordinary transport logs and scan results
redact known paired-source, name, serial, MAC, aggregate-settings and Print fields. This is targeted
redaction rather than a guarantee about unknown discovery payloads.

BMAP has no transaction identifier. A scan therefore cannot start while a mutation/rule is awaiting
its report, and mutations are refused while scanning. Each diagnostic frame carries local origin
metadata; error replies at its address are isolated from normal capability/write failure handling
for eight seconds after actual full transmission. Queued reads remain protected under output
backpressure. Cancellation and task completion discard unsent diagnostic frames; a partially sent
frame finishes to preserve wire integrity. Valid STATUS/RESULT pushes still update the app, and
errors at unrelated addresses still fail genuine writes. After cancellation, a same-address change
must wait for that bounded settling window or a reconnect. An arbitrarily late device reply beyond
eight seconds remains ambiguous; this is a protocol limitation, not hardware compatibility evidence.

The separate experimental Print console implements only upstream `bind`, `unbind`, `verbosity`
and `output` packet shapes. Opening the page sends nothing; local validation sends nothing.
Sending requires explicit confirmation and a verified live control channel. Firmware argument
semantics remain unknown and untested on iOS hardware. Arguments are limited to 255 UTF-8 bytes
on one line, with control characters rejected. Collection ends after a 500 ms quiet gap, a
3-second no-response timeout, 5 seconds total or 64 response frames. The in-memory transcript is
bounded to 100 entries/24,000 characters, with each entry limited to 1,024 characters. Leaving the
page, backgrounding or disconnecting stops collection and clears consent. Stopping collection
does not undo a command or disable firmware logging.

Print replies are intentionally visible as readable UTF-8 or hex in that console and may contain
private device information. Its explicit Share action warns about this; the console transcript
is not automatically redacted or persisted. Idle Print traffic cannot fill the ordinary log or
update app state. Demo and Simulator supply no synthetic console replies, and the console never
reports success merely because a packet was queued.

The Android app's confirmed hardware connection was a classic RFCOMM socket. There is no equivalent
arbitrary RFCOMM socket in the iOS Core Bluetooth API. Core Bluetooth's Classic support means GATT
over BR/EDR; it does not make an Android RFCOMM channel accessible. External Accessory is a different
path requiring an accessory and protocol supported by the manufacturer under MFi. No private APIs,
made-up protocol identifier or unsupported GATT byte transport are used here. If a device does not
publish the documented PSM characteristic, the app explains that it has no supported control path.

Reconnect is explicitly opt-in and remembers only the selected peripheral. Retry delays are finite (1/2/4/8/16/30 seconds), manual disconnect/power-off cancels retries, and demo suspends them. Core Bluetooth restoration always reopens streams and verifies a fresh BMAP reply. Three actually sent unanswered requests trigger a liveness probe; idle subscribed devices are not aggressively polled. Physical/background behavior remains unverified.

The simulator exercises the actual SwiftUI app and deterministic protocol models. Real Bluetooth
headphone compatibility, secure-channel requirements, background connection recovery and device
firmware quirks require an actual iPhone and headphones. The fork owner supplied a physical-iPhone
screenshot showing QC Ultra 2 connected and a queue-full alert while dragging; this is user-reported
evidence, not a controlled hardware acceptance run. The slider/queue repair still needs their device
retest, including audible changes and reconnect behavior. Discovery in Simulator gives an explicit hardware message.

Official Apple references checked for this port:

- [Opening an L2CAP channel](https://developer.apple.com/documentation/corebluetooth/cbperipheral/openl2capchannel(_:))
- [CBL2CAPChannel input/output streams](https://developer.apple.com/documentation/corebluetooth/cbl2capchannel)
- [Core Bluetooth Classic uses GATT, WWDC19 (10:18)](https://developer.apple.com/videos/play/wwdc2019/901/)
- [External Accessory and MFi](https://developer.apple.com/library/archive/qa/qa1657/_index.html)

Protocol attribution: the original Earshot contributors' Kotlin protocol catalogue, aaronsb and contributors' MIT-licensed
[bosectl](https://github.com/aaronsb/bosectl), and the MIT-licensed
[Quiet Rebellion](https://github.com/MadEyez/quietrebellion). Their repository notices remain in
`docs/reference/`.

Sidetone writes preserve the device-reported remember-after-restart flag when changing level, and preserve level when changing that flag. Latency retains the first valid report for the current connection; resetting it uses the same separately confirmed experimental write and does not claim a measured acoustic effect. Both state paths clear on link changes.
