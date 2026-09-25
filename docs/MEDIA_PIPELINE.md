# What the public files show about the Atmos media pipeline

This note separates facts visible in AOSP/Pong files from assumptions that require an on-device trace. Dolby's decoder and renderer are proprietary binaries, so the exact JOC object hand-off cannot be proven from this repository alone.

## Short answer

TWS earbuds receive **two channels**. That is expected. Headphone spatial audio is a binaural render: a multichannel or object-based scene is converted on the phone into left/right PCM, then encoded as the negotiated A2DP codec. “Stereo at the Bluetooth sink” does not distinguish Atmos from an ordinary stereo-width effect.

The useful distinction is at the **input of the renderer**:

- stereo PCM in -> stereo processing/upmix/widening;
- 5.1/7.1/7.1.4 PCM (or a Dolby scene reconstructed by the proprietary stack) in -> binaural rendering to stereo.

## Components in Pong hardware_dolby

The public `Pong-Development/hardware_dolby` tree contains four distinct layers:

1. **Codec2 decoder**
   - `c2.dolby.eac3.decoder`
   - advertises AC-3, E-AC-3 and E-AC-3 JOC;
   - advertises up to 16 channels for `audio/eac3-joc`.
2. **Dolby service**
   - `vendor.dolby.hardware.dms@2.0-service` connects the proprietary components and parameter storage.
3. **DAP output effect**
   - `libswdap.so`, implementation UUID `9d4921da-8225-4f29-aefa-39537a04bcaa`;
   - configured as a `music` post-process in this device's `audio_effects.xml`;
   - exposes profile controls such as headphone virtualizer, stereo widening, EQ, dialogue and bass.
4. **Framework spatializer effect**
   - `libswspatializer.so`, UUID `ccd4cf09-a79d-46c2-9aae-06a1698d6c8f`;
   - its exported descriptor identifies it as `DAP_Spatializer`;
   - this is the effect Android's `SpatializerThread` needs for multichannel-to-stereo rendering.

`libswdap.so` and `libswspatializer.so` are not interchangeable. Merely registering DAP as a global music effect gives profile/EQ/virtualizer processing, but does not register an Android 13 spatializer.

## Expected path

```text
E-AC-3 JOC file/stream
        |
        v
c2.dolby.eac3.decoder
        |  decoded wide PCM / proprietary Dolby coordination
        v
AudioTrack requesting a multichannel mask
        |
        v
AudioPolicyManager decides canBeSpatialized == true
        |
        v
AudioFlinger SpatializerThread
        |
        v
libswspatializer.so (DAP_Spatializer)
        |  binaural stereo, 48 kHz
        v
Bluetooth Audio HAL -> A2DP codec encoder -> TWS L/R
```

AOSP explicitly defines the spatializer as accepting a multichannel mix and rendering stereo to the Audio HAL. Therefore, adding multichannel channel masks to the A2DP device profile would be wrong: ordinary classic-A2DP headphones are a stereo transport endpoint, not a discrete 5.1/7.1 speaker endpoint.

## What was wrong in v1 of this module

The first version added `AUDIO_OUTPUT_FLAG_SPATIALIZER` to a Bluetooth mix port, but its effects configuration registered only `libswdap.so`. It did **not** register Pong's `libswspatializer.so`. A route flag cannot synthesize a spatializer implementation.

It also changed the ordinary `a2dp output` into a `DEEP_BUFFER` profile. Public AOSP/Pong device integrations keep normal A2DP unchanged and add a separate spatial output. `DEEP_BUFFER` is a power/latency policy flag, not a way to preserve Atmos channels.

That configuration could plausibly sound like only DAP's headphone virtualizer or stereo-width control, especially if the player had already selected/decoded a stereo rendition.

## What v2 changes

- registers `libswspatializer.so` and its real implementation UUID;
- provides a dedicated 48 kHz stereo `AUDIO_OUTPUT_FLAG_SPATIALIZER` mix port in the Bluetooth HAL module;
- keeps the ordinary A2DP output unmodified;
- declares `android.hardware.audio.spatializer`;
- uses the property values present in Pong's current `dolby.mk` (`ro.audio.spatializer_enabled=true`, DS2 false, hard-bypass false).

The output profile remains stereo because stereo is the **result** of binaural rendering.

## Limits of what can be claimed

The public configuration proves that a Dolby Codec2 decoder, DAP effect and dedicated spatializer binary exist. It does not reveal the internals of the closed binaries. In particular, public files alone cannot prove whether every app preserves JOC objects all the way to the renderer or whether a given playback path exposes a reconstructed channel bed.

The player matters. It must select the `audio/eac3-joc` rendition and create a multichannel AudioTrack. If it requests stereo, Android's default spatializer behavior does not spatialize it; only DAP's stereo processing remains.

## References

- AOSP spatial audio architecture: https://source.android.com/docs/core/audio/spatial
- AOSP implementation requirements: https://source.android.com/docs/core/audio/implement-spatial-audio
- Pong hardware_dolby: https://github.com/Pong-Development/hardware_dolby
- Public MTK device integration registering `libswspatializer` and a separate BT spatial output: https://github.com/samakshkambxj/device_nothing_Galaxian/commit/902cdede1dd542ef7b5d5b7384af7a29b64ba009 and https://github.com/samakshkambxj/device_nothing_Galaxian/commit/47cacfab32c6ca731ca98ad2c76ce1197271fe00
