# Original work and AI-assisted iOS port

This repository is an **experimental AI-assisted attempt to port [Earshot](https://github.com/HellzYeahh/earshot) from Android to native iOS**. Brian du Preez supplied AI assistance/tokens for this fork; that does not transfer authorship of the original app or its research. The original Earshot project, design, functionality, Kotlin implementation, documentation, tests, and protocol integration are credited to **HellzYeahh and the Earshot contributors**. The iOS code adapts their work and is not an independent invention of the original app.

The original MIT licence and copyright notice remain intact in [LICENSE](LICENSE). The Android tree and inherited research remain available for provenance. An iOS simulator test is not evidence of physical headphone compatibility or complete feature parity.

The preserved upstream snapshot is Earshot **0.4.0**, commit [`d6ceffa7a028f2809840160bf8323715d24384cb`](https://github.com/HellzYeahh/earshot/commit/d6ceffa7a028f2809840160bf8323715d24384cb), authored by HellzYeahh, titled “Release 0.4.0: adapts to your Bose model”. Native iOS additions are the AI-assisted port work in this fork, rather than part of that original release.

| Work | Credit | Licence and use |
| --- | --- | --- |
| Original Earshot | [HellzYeahh and contributors](https://github.com/HellzYeahh/earshot) | MIT, copyright (c) 2026 Earshot contributors. Source app, feature design, models, protocol/DSP implementation, tests and documentation adapted for this iOS attempt. |
| bosectl | [aaronsb and contributors](https://github.com/aaronsb/bosectl) | MIT. BMAP research, device layouts, fixtures and interoperability knowledge inherited through Earshot. Preserve notices in `docs/reference/bosectl/`. |
| Quiet Rebellion | [MadEyez and contributors](https://github.com/MadEyez/quietrebellion) | MIT. Bose connection/protocol reference. Full original licence retained in `docs/reference/quietrebellion-android/LICENSE`. |
| AutoEq | [Jaakko Pasanen and contributors](https://github.com/jaakkopasanen/AutoEq) | MIT, copyright (c) 2018–2022 Jaakko Pasanen. The QC Ultra correction selected by upstream Earshot uses Rtings measurements on the B&K 5128 rig. Preserved full notice in `ios/Earshot/Audio/BuiltInPresets.swift`. |

No claim is made to Bose, QuietComfort, Skullcandy, Apple, or other product trademarks. This fork is not affiliated with or endorsed by those companies. Vendor reference material is retained as reference, not represented as iOS port authorship. Bragi protobuf definitions have not been vendored.

Contributors should preserve these credits and the MIT licence when redistributing this fork, and distinguish AI-generated or AI-assisted port work from upstream contributions.


## Upstream0.5–0.75 reconciliation

The AI-assisted iOS0.2 port pass reviews all42 commits through original Earshot0.75.0,
[`9e6c4912531ec6e159eded862d1b6ffa55094199`](https://github.com/HellzYeahh/earshot/commit/9e6c4912531ec6e159eded862d1b6ffa55094199).
The retained Android source remains the0.4.0 snapshot above. See
[the per-commit audit](docs/IOS_UPSTREAM_075_AUDIT.md) for exact sources and platform decisions.
Field colours, typography choices and Strike artwork are **original upstream Earshot work**;
the native adaptation is not credited as original AI design. This includes clearly simulated
Soundcore, Sennheiser, Sony and Method fixtures and read-only protocol research catalogues.

| Reference | Credit | Licence and actual use |
| --- | --- | --- |
| soundcorebridge | [Mervin](https://github.com/mervin008/soundcorebridge) | MIT, copyright(c)2026 Mervin. Protocol facts and GATT reconnaissance cross-check; not a validated live iOS vendor channel. Full notice under docs/reference/soundcorebridge. |
| momentum4-control | [Ariazonaa](https://github.com/Ariazonaa/momentum4-control) | MIT, copyright(c)2026 Ariazonaa. Upstream captures/behaviour and blocked-command research; full retained notice under docs/reference/momentum4-control. |
| momentumctl | [Galen Abell](https://github.com/gjabell/momentumctl) | MIT, copyright(c)2026 Galen Abell. Command/UUID research through upstream Earshot; full retained notice under docs/reference/momentumctl. |
| SonyHeadphonesClient | [mos9527, Amr Satrio and contributors](https://github.com/mos9527/SonyHeadphonesClient) | MIT, copyright(c)2026 named contributors. MDR/Tandem layouts and synthetic Sony fixture through upstream; full retained notice under docs/reference/sonyheadphonesclient. |
| Barlow and Barlow Condensed | The Barlow Project Authors | SIL Open Font License1.1, copyright2017. Unmodified upstream font binaries; complete notices bundled in Resources/Fonts and docs/reference/fonts. |
| JetBrains Mono | The JetBrains Mono Project Authors | SIL Open Font License1.1, copyright2020. Unmodified upstream font binary with its full bundled OFL notice. |

OpenSCQ30, Gadgetbridge and other GPL/AGPL or unlicensed implementations are **protocol-fact
references only**. Their implementation code is not newly copied into this MIT native port.
No manufacturer authorizes or endorses the port merely because a protocol fact is documented.
