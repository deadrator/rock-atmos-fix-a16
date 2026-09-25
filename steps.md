# On-device verification

Run these after installing v2 and rebooting. Capture output both with playback stopped and while known E-AC-3 JOC content is playing through TWS.

## 1. Confirm both overlays mounted

```bash
adb shell getprop audio_policy_fix.status
adb shell cat /data/adb/audio_policy_fix_status.log
adb shell grep -n 'ccd4cf09-a79d-46c2-9aae-06a1698d6c8f' /vendor/etc/audio_effects.xml
adb shell grep -n 'AUDIO_OUTPUT_FLAG_SPATIALIZER' /vendor/etc/bluetooth_audio_policy_configuration.xml
```

Expected: `MOUNTED_OK`, plus one match in each XML. This proves only that the files mounted.

## 2. Confirm the required binary and service exist

```bash
adb shell ls -l /vendor/lib64/soundfx/libswspatializer.so
adb shell getprop init.svc.vendor.dolby.hardware.dms-2-0
adb shell dumpsys media.codec | grep -i -A8 -B3 'c2.dolby.eac3.decoder\|eac3-joc'
```

The exact init property name can differ. If necessary:

```bash
adb shell getprop | grep -i dolby
adb shell ps -A | grep -i dolby
```

## 3. Confirm AudioFlinger loaded the spatializer effect

```bash
adb shell dumpsys media.audio_flinger > audio_flinger.txt
adb shell grep -in -A12 -B4 'ccd4cf09\|DAP_Spatializer\|Spatializer' audio_flinger.txt
```

The UUID/name must appear in the loaded effect descriptors. If it does not, inspect boot logs:

```bash
adb logcat -b all -d | grep -iE 'EffectsConfig|libswspatializer|ccd4cf09|could not load effect|audio_effects'
```

A missing dependency, SELinux denial or rejected XML must be fixed before testing sound.

## 4. Query framework spatializer state

```bash
adb shell pm list features | grep -i spatializer
adb shell dumpsys audio > audio_service.txt
adb shell grep -in -A35 -B5 spatial audio_service.txt
adb shell dumpsys media.audio_policy > audio_policy.txt
adb shell grep -in -A20 -B5 spatial audio_policy.txt
```

Look for:

- immersive level is not `NONE`/0;
- enabled is true;
- available is true with the TWS connected;
- the `spatial output` profile is opened/routable to the active A2DP device.

A feature declaration or property by itself is not enough. The framework queries the effect for supported levels, channel masks and modes.

## 5. Prove the player did not choose stereo

Use a player that exposes the selected track (Media3/ExoPlayer debug information is useful). Verify the selected MIME type is `audio/eac3-joc`, not AAC stereo or plain E-AC-3 stereo.

While it plays:

```bash
adb shell dumpsys media.audio_flinger > playing_audio_flinger.txt
adb shell grep -in -A45 -B8 'SpatializerThread\|Spatializer' playing_audio_flinger.txt
adb logcat -v threadtime | grep -iE 'eac3-joc|c2.dolby.eac3|SpatializerThread|Dlb.*Spatial|canBeSpatialized'
```

The decisive evidence is a multichannel track feeding an active spatializer thread, followed by a two-channel output. Exact dump formatting varies by Android branch. Save the full dumps rather than only screenshots of grep output.

If the track entering AudioFlinger is already `AUDIO_CHANNEL_OUT_STEREO`, Android's standard behavior is not to spatialize it. In that case the audible change can only be DAP profile processing/upmix/widening, regardless of the Atmos badge.

## 6. Controlled listening test

Use the same level-matched excerpt and compare:

1. known stereo source, spatial audio off/on;
2. known 5.1 source, spatial audio off/on;
3. verified E-AC-3 JOC source, spatial audio off/on.

A stereo source is a negative control. The standard Android spatializer should not process it. If stereo changes strongly, you are hearing DAP stereo processing or a ROM-specific stereo-spatialization mode.

Use material with stable off-centre/rear/height events. Overall width, bass and loudness are poor tests because DAP's EQ, virtualizer and leveler also alter them.

## 7. A2DP offload

```bash
adb shell getprop ro.bluetooth.a2dp_offload.supported
adb shell getprop persist.vendor.bluetooth.a2dp_offload.disable
```

Offload changes where Bluetooth encoding happens, but does not change the core requirement: the spatializer renders to stereo before the A2DP endpoint. Do not add 5.1/7.1 masks to the Bluetooth sink.

## Rollback

Disable the module and reboot. If audioserver fails to load effects, collect `logcat -b all -d` first, then disable the module from the root manager or recovery.
