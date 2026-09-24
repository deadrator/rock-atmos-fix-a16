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

## 🧨 Related Finding — `vendor.dolby.media.c2@1.0-service` SIGSEGV (NOT this module)

A separate, pre-existing crash was investigated on-device (2026-09-24). Documented here because it lives in the same Dolby stack — and to make explicit that `audio_policy_fix` is **not** involved.

### What happens

The Dolby C2 decoder HAL (`vendor.dolby.media.c2@1.0-service`) occasionally SIGSEGVs when rapidly skipping tracks in Atmos/EAC-3 content. init restarts it in under a second; playback continues; no audio drop, no data loss. Nuisance-class, self-healing.

### Crash signature (reproduced on demand)

Automated skip-storm test (15 rapid `KEYCODE_MEDIA_NEXT`, 3 s apart, Atmos album): **5 SIGSEGVs in ~50 s**, crash buffer 0 → 21 entries. Crash #5 carried the **same library, same frame, same BuildId** as the spontaneous tombstone from normal listening — one bug, two ways to reach it.

```text
signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), read fault
  #00 libstagefright_bufferpool@2.0.1.so — MessageQueueBase::~MessageQueueBase /
      MessageQueueBase::beginRead / AccessorInvalidator::addAccessor
  #01 BufferPoolClient::Impl::~Impl / ReleaseCache::~ReleaseCache
  — or —
  #00 libcodec2_soft_ddpdec.so (dap_cpdp_process)  <-- DD+ decoder on a freed input buffer
```

### Root cause (analysis)

Three-way vintage mismatch inside the `hardware_dolby` port model:

| Component | Source (per the port's `Android.bp`) |
|---|---|
| `vendor.dolby.media.c2@1.0-service` | **Sony**-sourced prebuilt blob |
| `libcodec2_soft_ddpdec.so` (DD+ decoder) | **Xiaomi** prebuilt blob |
| `libstagefright_bufferpool@2.0.1.so` (the other crasher) | **NOT in the port** — the ROM's own fresh AOSP 16 build |

Old blobs carry stale buffer-lifetime assumptions; the new platform bufferpool changed behavior under them; rapid codec create/destroy (track skipping) trips the teardown race. None of the crash frames touch audio policy, AudioFlinger effects, or DAP processing — `DlbDap2Process` counters kept incrementing straight through the crash window.

### Scope — port-class, not device-specific

Identical crash reported on crDroid Android 16 (OnePlus Open — different OEM, different SoC), where the maintainer's verdict was: *"Vendor blob issue. No visible user impact."* As of 2026-09-24 there are **zero open issues** on the port's GitHub.

### Risk assessment

**Low.** Self-healing restart, no user-visible failure beyond a tombstone. Aggravating factor only: rapid skipping on Atmos/EAC-3 streams. The related "first track needs play pressed twice after cold start" symptom is a crash-free stall in the same decode path (verified: no new tombstones, C2 service PID unchanged).

### Links / prior art

- crDroid A16 thread reporting the same crash + maintainer response: <https://xdaforums.com/t/rom-16-oneplus-open-crdroid-v12-official.4786300/page-2>
- The Dolby port used by most A16 ROMs (including this device's): <https://github.com/Pong-Development/hardware_dolby>

### Fix routes (upstream only — do not attempt locally)

1. **Port repo:** file an issue on `Pong-Development/hardware_dolby` requesting a newer blob vintage (Sony C2 service / Xiaomi ddpdec) — they control blob selection.
2. **ROM repo:** hotfix request — cherry-pick the upstream AOSP `libstagefright_bufferpool` race fixes (MessageQueue destructor paths) into the ROM's platform build.
3. **User-side mitigation:** avoid rapid skipping on Atmos/EAC-3 albums, or set the player's Atmos mode to Off when queue-hopping (AAC tracks never enter the fragile decoder).

Local patching is explicitly **not recommended**: the crashing blobs are closed-source, and the AOSP lib is ABI-entangled with the ROM's custom HIDL build.

---

## 🔙 Rollback

Disable the module in KernelSU/Magisk Manager and reboot — the stock `bluetooth_audio_policy_configuration.xml` is untouched on `/vendor`. If needed, restore from your Step 0 backup archive via recovery/fastboot.

## Special Thanks
@piyushAdy
@Asmodeus7999
