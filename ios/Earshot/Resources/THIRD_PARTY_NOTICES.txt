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
