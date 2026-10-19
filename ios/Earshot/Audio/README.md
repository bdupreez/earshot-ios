# Native audio

This is part of an **AI-assisted iOS port attempt of [Earshot by HellzYeahh and contributors](https://github.com/HellzYeahh/earshot)**. The original Kotlin DSP, presets, correction selection and feature design are credited to upstream Earshot and its cited research projects. Preserve [all notices](../../../THIRD_PARTY_NOTICES.md) and the original MIT licence.

`LocalAudioEngine` plays user-selected audio files through an actual `AVAudioEngine` graph:

`AVAudioPlayerNode → AVAudioUnitEQ cascade → Apple dynamics processor → Apple peak limiter → main mixer → current system output`

Imports copy the selected file into the app's cache while the security-scoped file-provider URL is accessible. Playback pauses when an output disconnects or an audio interruption starts. A hardware audio configuration change resets the track for an explicit restart. Cached audio is disposable and is not restored after relaunch.

The seven built-in presets preserve the original Kotlin frequencies, gains, Q values, order, preamp recommendations and correction source. JSON field names and filter enum strings remain compatible with Android exports. AutoEQ text accepts peak, low-shelf, high-shelf, disabled filters, comments and older shelf aliases. Imports accept up to 128 bands per preset and 1,000 presets per JSON collection. Numbers are validated, gain and Q are clamped to the Android model's limits, and imported preamp is limited to −30…0 dB.

`Biquad` and `EQResponse` faithfully port the RBJ Audio EQ Cookbook calculations used by the Android UI. Apple EQ uses octave bandwidth rather than Q, so `NativeAudioConfiguration` converts Q and selects resonant shelf filters. Apple's filter implementation can differ from the cookbook response, particularly toward Nyquist and at resonant shelves. The displayed response is a model rather than a measured output curve.

Loudness protection combines Apple's native dynamics processor (−3 dB threshold, 0.1 dB headroom, 0.1 ms attack, 60 ms release) with Apple's peak limiter (1 ms attack, 60 ms release). The dynamics stage handles sustained overload; the final peak limiter catches transients. A peak limiter alone produced a decay toward silence with a sustained overdriven test tone on the installed simulator. Boost is capped at 12 dB with protection, or 3 dB without it. With protection disabled, playback additionally compensates combined filter boost and reserves 1 dB of headroom. This differs deliberately from allowing a full-scale source to hard-clip.

Turning off the master Pro EQ switch bypasses all filters, preamp, boost and protection units, restoring the source's original level.

iOS does not let this app process other apps' output, phone calls, or protected streaming tracks. Headphone hardware EQ is a separate control path. File playback does not require microphone permission. The generated listening sample is a quiet, 12-second test source rather than imported commercial audio.

`DSPTests` verifies the original model, math, presets and interchange formats. It also renders actual waveforms through `AVAudioEngine` offline to check attenuation and peak limiting, and exercises native playback, pause and stop on a simulator. `AppStoreTests` covers isolated persistence, profile capabilities, mode validation and automation state. Simulator execution verifies the native software path; it does not measure headphones, Bluetooth latency, perceived loudness, or hardware fidelity.
