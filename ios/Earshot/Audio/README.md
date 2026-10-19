# Native audio

This is part of an **AI-assisted iOS port attempt of [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot)**. The original Kotlin DSP, presets, correction selection and feature design are credited to upstream Earshot and its cited research projects. The QC Ultra correction credits [AutoEq by Jaakko Pasanen and contributors](https://github.com/jaakkopasanen/AutoEq), using Rtings measurements on the B&K 5128 rig. Preserve [all notices](../../../THIRD_PARTY_NOTICES.md), the original MIT licence and the full AutoEq notice in `BuiltInPresets.swift`.

`LocalAudioEngine` plays user-selected audio files through an actual `AVAudioEngine` graph:

`AVAudioPlayerNode → AVAudioUnitEQ cascade → Apple dynamics processor → Apple peak limiter → main mixer → current system output`

Imports copy the selected file into the app's cache while the security-scoped file-provider URL is accessible. Cached audio is disposable and is not restored after relaunch. The player exposes actual duration/progress, seek, ±15 seconds, stop and the system output picker. Output disconnection or an audio interruption pauses playback. A hardware configuration change preserves the last tracked position, rebuilds the schedule and requires an explicit press of Play.

Pause, stop and natural completion idle the audio engine and release the player's audio session when it still owns that session. Completion resets the native player timeline so a finished track can be replayed from the beginning. The microphone tools stop local playback before recording or playing a recording; a shared ownership check prevents the player from deactivating an active microphone tool's session.

The seven built-in presets preserve the original Kotlin frequencies, gains, Q values, order, preamp recommendations and correction source. JSON field names and filter enum strings remain compatible with Android exports. AutoEQ text accepts peak, low-shelf, high-shelf, disabled filters, comments and older shelf aliases. Imports accept up to 128 bands per preset and 250 presets per JSON collection, with a 2 MiB text limit; the saved user library is also capped at 250 presets. Numbers are validated, gain and Q are clamped to the Android model's limits, and stored preset preamp is limited to −30…0 dB. Excessive overlapping boost is rejected before native processing.

`Biquad` and `EQResponse` faithfully port the RBJ Audio EQ Cookbook calculations used by the Android UI. Apple EQ uses octave bandwidth rather than Q, so `NativeAudioConfiguration` converts Q and selects resonant shelf filters. Apple's filter implementation can differ from the cookbook response, particularly toward Nyquist and at resonant shelves. The displayed response is a model rather than a measured output curve.

Loudness protection combines Apple's native dynamics processor (−3 dB threshold, 0.1 dB headroom, 0.1 ms attack, 60 ms release) with Apple's peak limiter (1 ms attack, 60 ms release). The dynamics stage handles sustained overload; the final peak limiter catches transients. A peak limiter alone produced a decay toward silence with a sustained overdriven test tone on the installed simulator. Boost is capped at 12 dB with protection, or 3 dB without it. With protection disabled, playback additionally compensates combined filter boost and reserves 1 dB of modeled headroom.

Automatic preamp uses the preset recommendation and the combined response at the loaded file's sample rate. Manual preamp accepts −30…0 dB. Both pass through the same `AudioGainPlan` used by the UI and native engine, so the displayed actual preamp includes any additional attenuation required when protection is off. Native compensation can extend to −96 dB for validated complex curves. Preamp mode, manual value and protection preferences persist. Turning off the master Pro EQ switch bypasses all filters, preamp, boost and protection units, restoring the source's original level. A/B Original temporarily bypasses the same processing without changing the saved configuration.

User presets support edit, copy, rename, delete, filter removal and reordering; built-ins are protected and can be copied. Converting to ten graphic bands requires confirmation and retains the exact prior parametric filters for restoration while the editor remains open. Returning to parametric editing preserves the current filters. Unsaved edits prevent swipe dismissal, and Cancel asks whether to discard them. Imports regenerate identities, deduplicate identical curves and validate the whole operation before saving. Repairing malformed persisted records first preserves their original JSON in a shareable recovery file. Deleting an active user preset selects Flat; rules referring to it retain their reference and show an actionable missing-preset error.

iOS does not let this app process other apps' output, phone calls, or protected streaming tracks. Headphone hardware EQ is a separate control path. File playback does not require microphone permission. The generated listening sample is a quiet, 12-second test source rather than imported commercial audio.

For Spotify, Apple Music and other sources, use **Sound → Headphone EQ** to request the Bose
hardware's three-band settings on supported headphones. These settings are applied by the headphones,
independently of which app supplies music; their audible effect must be checked on the actual device.
The full Pro EQ filters, preamp, limiter and boost are available only to Earshot's local player.
An audio session's `mixWithOthers` option permits simultaneous playback; it does not give this graph
another app's samples. See Apple's [audio-engine](https://developer.apple.com/documentation/AVFAudio/audio-engine)
and [mixing-option](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers)
documentation. Bluetooth sliders commit at the end of a drag; local Pro EQ/preview sliders remain continuous.

`DSPTests` verifies the original model, math, presets and interchange formats, including actual offline `AVAudioEngine` waveforms for boost, bypass, sustained audibility and peak limiting. `PresetLifecycleTests` covers preset identity, atomic imports, persistence/recovery, exact filter restoration, dirty drafts, shared gain calculations, real seek/progress, engine idling, session ownership and replay after natural completion. `AppStoreTests` covers isolated persistence, profile capabilities, mode validation and automation state. Simulator execution verifies the native software path; it does not measure headphones, Bluetooth latency, perceived loudness, or hardware fidelity.
