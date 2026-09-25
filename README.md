# Dolby Spatializer Fix — Poco M5 / Redmi 11 Prime (rock/stone)

Android 16 Magisk/KernelSU/APatch module for the Pong Dolby stack. It registers Pong's **dedicated framework spatializer** and routes its stereo binaural output to Bluetooth A2DP.

> The TWS output is supposed to be stereo. Spatial audio for headphones renders a multichannel scene to two binaural channels on the phone. The important question is whether the renderer receives multichannel audio, not whether Bluetooth reports more than two channels.

See [How the media pipeline works](docs/MEDIA_PIPELINE.md) for the evidence and limitations.

## Why v1 sounded like a stereo-width enhancer

The old module configured a mix port with `AUDIO_OUTPUT_FLAG_SPATIALIZER`, but the ROM's effects configuration was never verified on-device. It has since been verified: the stock `/vendor/etc/audio_effects.xml` **does** register `libswspatializer.so` (UUID `ccd4cf09-a79d-46c2-9aae-06a1698d6c8f`), so v1's remaining gap was the missing `android.hardware.audio.spatializer` feature declaration, not a missing effect registration. `libswdap.so` (DAP) and `libswspatializer.so` (framework spatializer) remain separate effects in that config; DAP's stereo-width controls are a different processing path from the spatializer renderer.

Deep buffer does not preserve multichannel content, but it is not merely a latency flag either — see the v2.1 section for why it is restored.

## v2 changes

The module overlays:

```text
/vendor/etc/bluetooth_audio_policy_configuration.xml
/vendor/etc/permissions/android.hardware.audio.spatializer.xml
```

The relevant entries are:

```xml
<mixPort name="spatial output" role="source"
         flags="AUDIO_OUTPUT_FLAG_SPATIALIZER">
    <profile name="" format="AUDIO_FORMAT_PCM_16_BIT"
             samplingRates="48000" channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>
</mixPort>
```

`BT A2DP Out` and `BT A2DP Headphones` can use that output. The normal `a2dp output`, hearing-aid route and A2DP speaker route remain non-spatial.

## Important compatibility warning

This module is intended for Pong-stack builds on rock/stone. Do not flash it on an unrelated ROM. The module assumes the ROM already ships the Pong binaries and services, especially:

```text
/vendor/lib64/soundfx/libswspatializer.so
/vendor/lib64/soundfx/libswdap.so
vendor.dolby.hardware.dms@2.0-service
c2.dolby.eac3.decoder
```

It does not redistribute proprietary Dolby blobs.

## Build and install

```bash
./build.sh
```

Flash `audio_policy_fix.zip`, then reboot. KernelSU/APatch installations need a working system/vendor mount metamodule if the manager does not provide one.

### v2.1 — corrected merge of the v2 redesign

v2 (PR #1) fixed two real gaps but introduced an audible Bluetooth stutter regression and a redundant overlay. v2.1 keeps the fixes and reverts the regressions:

**Kept from v2**

- The dedicated `spatial output` mixPort (`AUDIO_OUTPUT_FLAG_SPATIALIZER`) routed to `BT A2DP Out` / `BT A2DP Headphones`.
- The `android.hardware.audio.spatializer` feature declaration (this ROM does not ship it — verified on-device).

**Reverted, and why**

- **`audio_effects.xml` overlay removed.** Its premise was false: the ROM's stock `/vendor/etc/audio_effects.xml` *already* registers `libswspatializer.so` with UUID `ccd4cf09-a79d-46c2-9aae-06a1698d6c8f` (verified in the live vendor file). A complete-file overlay that duplicates a device file that already says the same thing only adds risk of dropping vendor-specific effect chain details. The module is ROM-agnostic again.
- **`DEEP_BUFFER` restored on `a2dp output`.** Removing it was the stutter cause. Deep buffer does not preserve Atmos channels (that part of the v2 analysis was correct), but it *is* the resilience buffer: it gives the BT mix ~200 ms of scheduling headroom, which matters once the spatializer stage adds CPU load and Bluetooth is aggressively underclocked. Without it the small default A2DP buffer under-runs and every hiccup becomes an audible glitch. The spatial output port coexists with it exactly as in the AOSP reference design.
- **`system.prop` restored** to the on-device-verified set: `ds2.enabled=true` (DAP processing confirmed live via `DlbDap2Process` counters), `ro.vendor.audio.spatializer.enabled=true`, `ro.spatializer.supported=true`, `pose_predictor_type=0`. The `spatializer_transaural_enabled_default` prop was dropped (never part of this device's verified config).

**Net effect:** flash v2.1 if you had v2 installed and heard BT stutter; expect the stutter to disappear with spatial audio still available.

### Automated GitHub release

`.github/workflows/release.yml` builds, validates and publishes the same ZIP. A release can be created in either of two ways:

1. Push a version tag matching `version=` in `Magisk_Module_Source/module.prop` (for example, `v2.0`).
2. Run **Build and publish module** from GitHub Actions and enter that tag.

The workflow rejects mismatched versions or malformed archives, uploads a 30-day Actions artifact, and attaches both `audio_policy_fix.zip` and `audio_policy_fix.zip.sha256` to the GitHub release. Re-running it for an existing release replaces those two assets.

## Verify the pipeline

Use the commands in [steps.md](steps.md). A valid test requires all of these:

1. `libswspatializer.so` is registered as the spatializer effect.
2. Android reports a nonzero multichannel immersive level and the BT route is available.
3. The player selects `audio/eac3-joc` (or another multichannel rendition).
4. The decoded AudioTrack remains wider than stereo before `SpatializerThread`.
5. The spatializer thread/effect is active and outputs stereo to A2DP.

An Atmos badge, an enabled DAP toggle, `MOUNTED_OK`, or stereo Bluetooth output alone proves none of this.

## Rollback

Disable/remove the module and reboot. The original vendor files are systemlessly restored.

## Sources

- [AOSP spatial audio architecture](https://source.android.com/docs/core/audio/spatial)
- [AOSP spatial audio implementation requirements](https://source.android.com/docs/core/audio/implement-spatial-audio)
- [Pong-Development/hardware_dolby](https://github.com/Pong-Development/hardware_dolby)
- [Public Pong/MTK spatializer integration](https://github.com/samakshkambxj/device_nothing_Galaxian/commit/902cdede1dd542ef7b5d5b7384af7a29b64ba009)
- [Public Bluetooth spatial-output integration](https://github.com/samakshkambxj/device_nothing_Galaxian/commit/47cacfab32c6ca731ca98ad2c76ce1197271fe00)
