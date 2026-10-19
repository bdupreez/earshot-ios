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

The Android app's confirmed hardware connection was a classic RFCOMM socket. There is no equivalent
arbitrary RFCOMM socket in the iOS Core Bluetooth API. Core Bluetooth's Classic support means GATT
over BR/EDR; it does not make an Android RFCOMM channel accessible. External Accessory is a different
path requiring an accessory and protocol supported by the manufacturer under MFi. No private APIs,
made-up protocol identifier or unsupported GATT byte transport are used here. If a device does not
publish the documented PSM characteristic, the app explains that it has no supported control path.

The simulator exercises the actual SwiftUI app and deterministic protocol models. Real Bluetooth
headphone compatibility, secure-channel requirements, background connection recovery and device
firmware quirks require an actual iPhone and headphones. This implementation has not been verified
against physical headphones on an iPhone. Discovery in Simulator gives an explicit hardware message.

Official Apple references checked for this port:

- [Opening an L2CAP channel](https://developer.apple.com/documentation/corebluetooth/cbperipheral/openl2capchannel(_:))
- [CBL2CAPChannel input/output streams](https://developer.apple.com/documentation/corebluetooth/cbl2capchannel)
- [Core Bluetooth Classic uses GATT, WWDC19 (10:18)](https://developer.apple.com/videos/play/wwdc2019/901/)
- [External Accessory and MFi](https://developer.apple.com/library/archive/qa/qa1657/_index.html)

Protocol attribution: the original Earshot contributors' Kotlin protocol catalogue, aaronsb and contributors' MIT-licensed
[bosectl](https://github.com/aaronsb/bosectl), and the MIT-licensed
[Quiet Rebellion](https://github.com/MadEyez/quietrebellion). Their repository notices remain in
`docs/reference/`.
