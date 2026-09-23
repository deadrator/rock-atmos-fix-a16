# Atmos Fix [Pong ATMOS] — Poco M5 (TWS)

> **Project Context for LLMs:**
> - **Environment:** Android 16 (Infinity-X custom ROM), KernelSU, MediaTek Helio G99 (Poco M5, codename `rock`).
> - **Core Languages:** XML (Android Audio Policy), Shell, Android properties.
> - **Primary Objective:** Route `AUDIO_OUTPUT_FLAG_DEEP_BUFFER` and `AUDIO_OUTPUT_FLAG_SPATIALIZER` output flags to Bluetooth A2DP (TWS) so Dolby Atmos / DAP (`libswdap.so`) renders multi-channel audio on earbuds instead of a forced stereo downmix.
> - **Scope:** TWS (Bluetooth) ONLY. The primary `audio_policy_configuration.xml` is deliberately NOT shipped; Speaker, Earpiece, BT SCO and `BT A2DP Speaker` paths are untouched.

---

## Current Behavior vs Expected Behavior

* **Current Behavior:** `AudioFlinger: createTrack_l() mismatch (00000008 vs 00000004)` — Atmos decodes correctly but AudioFlinger forces a 2.0 stereo downmix before the DSP, because `a2dp output` in `bluetooth_audio_policy_configuration.xml` has no flags and no profile.
* **Expected Behavior:** AudioFlinger routes the deep-buffer track (`00000008`) to the `a2dp output` mixPort, and the spatializer engine attaches on the `a2dp spatial` port for BT A2DP Out / BT A2DP Headphones.

---

## 📂 Module Structure

The zip MUST match this tree (steps.md Step 6):

```text
audio_policy_fix.zip
├── META-INF/
│   └── com/
│       └── google/
│           └── android/
│               ├── update-binary            <-- Magisk/KSU installer script
│               └── updater-script           <-- "# MAGISK" dummy
├── module.prop
├── system.prop
├── post-fs-data.sh                           <-- early boot mount verification
├── service.sh                                <-- late boot prop/mount verification
└── system/
    └── vendor/
        └── etc/
            └── bluetooth_audio_policy_configuration.xml   <-- PATCHED (3 hunks)
```

---

## 🔧 The Exact Patch (bluetooth_audio_policy_configuration.xml)

Exactly 3 hunks vs the stock `/vendor/etc/bluetooth_audio_policy_configuration.xml`:

### Hunk 1 — `a2dp output` gets deep_buffer flags + minimal profile
```xml
<mixPort name="a2dp output" role="source" flags="AUDIO_OUTPUT_FLAG_DEEP_BUFFER">
    <profile name="" format="AUDIO_FORMAT_PCM_16_BIT"
             samplingRates="44100 48000" channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>
</mixPort>
```
Stereo-only on purpose (steps.md Step 2 anti-prompt): do not add channel masks or sample rates the TWS doesn't negotiate.

### Hunk 2 — new `a2dp spatial` mixPort
```xml
<mixPort name="a2dp spatial" role="source" flags="AUDIO_OUTPUT_FLAG_SPATIALIZER">
    <profile name="" format="AUDIO_FORMAT_PCM_16_BIT"
             samplingRates="48000" channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>
</mixPort>
```

### Hunk 3 — routes (TWS-capable sinks only)
```xml
<route type="mix" sink="BT A2DP Out"
       sources="a2dp output,a2dp spatial"/>
<route type="mix" sink="BT A2DP Headphones"
       sources="a2dp output,a2dp spatial"/>
```
`BT A2DP Speaker`, `BT Hearing Aid Out` and `hearing aid output` are byte-identical to stock.

---

## ⚙️ system.prop (verbatim, steps.md Step 4)

```properties
# Android 13+ Native Spatial Audio Flags
ro.audio.spatializer_enabled=true
ro.spatializer.supported=true
ro.spatializer.pose_predictor_type=0

# Dolby Mobile Service & DAP spatializer flags
vendor.audio.dolby.ds2.enabled=true
vendor.audio.dolby.ds2.hardbypass=false
ro.vendor.audio.spatializer.enabled=true
```

---

## 🚀 Installation

1. Download the latest zip from the Releases page:
   👉 **[audio_policy_fix.zip](https://github.com/deadrator/rock-atmos-fix-a16/releases/latest/download/audio_policy_fix.zip)**
   (or build it yourself: `./build.sh`)
2. Open KernelSU / Magisk / APatch manager, flash `audio_policy_fix.zip` as a module, reboot.

> **⚠️ KernelSU / APatch requirement:** this module mounts modified configuration files directly to `/vendor/etc`. If your root solution has no built-in overlayfs mount (KernelSU Next and similar), you **MUST** install a mount metamodule (**meta-overlayfs**, **Hybrid Mount**, or **Magic Mount-rs**) first. The installer detects this and warns; without one, KernelSU silently fails to inject the file.

---

## ✅ Post-Flash Verification

**Mount status** (after reboot):
```bash
adb shell getprop audio_policy_fix.status     # MOUNTED_OK or NOT_MOUNTED
adb shell cat /data/adb/audio_policy_fix_status.log
```
`service.sh` also snapshots the live props after boot:

* Step 4 gate: `vendor.audio.dolby.ds2.hardbypass` must read `false`. If the log shows it reading back `true`, a vendor `init.rc` script wins the race and DAP is in pass-through — the module is fine; the override is the problem.
* Step 1 gate: `ro.bluetooth.a2dp_offload.supported` — check what the log recorded. If offload is enabled, the BT HAL negotiates codec/format at connect time and may override the static mixPort profile; the DAP hook then needs to attach on the software encode path (effects config keyed to the A2DP session) instead of the XML profile alone.

**Playback test with TWS connected** (steps.md Step 7):

1. Play known Atmos (EAC3-JOC) content.
2. Filter LogFox for `dap`, `hardbypass`, `EffectsConfig`, `DlbDapEndpointParamCache` during playback.
3. Confirm `commit()` applies the **headphone/BT preset**, not the speaker preset.
4. A/B the Atmos toggle on the same track and earbuds. If you can't hear a difference, that is a tuning-data problem (see Known Limits), not a build failure — don't re-flash chasing it.

---

## ⚠️ Known Limits

* **A2DP offload:** if `ro.bluetooth.a2dp_offload.supported=true`, the static XML profile alone may be overridden at connect time. Verify via the `service.sh` log before assuming the patch is insufficient.
* **DAP tuning data:** if the `hardware_dolby` fork ships a generic donor `dax_config` / endpoint parameter table with no per-device retuning, the effect attaches cleanly but renders near-flat. That is a data problem, not a module bug — diff the endpoint table against a donor device rather than re-flashing.
* **OEM hardware:** untested on anything but Poco M5 (rock) stock hardware paths.

## 🔙 Rollback

Disable the module in KernelSU/Magisk Manager and reboot — the stock `bluetooth_audio_policy_configuration.xml` is untouched on `/vendor`. If needed, restore from your Step 0 backup archive via recovery/fastboot.
