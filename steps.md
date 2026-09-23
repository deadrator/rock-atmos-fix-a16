# Dolby Atmos for TWS Only — Poco M5 (Helio G99 / Infinity-X / KernelSU)

**Goal:** Real Atmos/DAP rendering over Bluetooth TWS only. Speaker and
Earpiece (mono) are left completely untouched — no channel mask edits,
no route changes on those sinks.

Each step has an **⚠️ Anti-prompt** — a check to run *before* you move on.
If the anti-prompt fails, stop and fix that step; don't proceed and hope
the next step compensates for it. That's how a "no errors, still doesn't
work" flash happens.

---

## Step 0 — Baseline capture (do this before touching anything)

Pull and archive, untouched:
- `/vendor/etc/audio_policy_configuration.xml`
- `/vendor/etc/bluetooth_audio_policy_configuration.xml`
- `getprop` full dump
- A working LogFox log of normal BT playback (SBC/AAC, no Atmos content)

> **⚠️ Anti-prompt:** Do you have a way back to stock if this bricks BT
> audio entirely? Confirm you can restore these two files from KernelSU's
> module manager (disable module) or via the archived copies, without
> needing a full flash. If not, sort that out first — this is the one
> step you can't skip.

---

## Step 1 — Determine whether A2DP offload is active

```
getprop | grep -i a2dp_offload
getprop ro.bluetooth.a2dp_offload.supported
```

If offload is `true`, the Bluetooth Audio HAL negotiates codec/format at
**runtime per-connection**, not from the static XML profile. That changes
where your fix has to live.

> **⚠️ Anti-prompt:** If offload is enabled and you only patch
> `bluetooth_audio_policy_configuration.xml`'s `a2dp output` mixPort, you
> can get a clean flash with zero boot errors and *still* hear no
> difference — because the HAL overrides your static profile at connect
> time. If offload is on, the DAP hook needs to attach on the software
> encode path (audio effects config keyed to the A2DP session), not rely
> on the mixPort profile alone. Don't skip this check and assume the XML
> edit is sufficient.

---

## Step 2 — Scope the mixPort edit to avoid collateral damage

`a2dp output` in your current file has no `<profile>` block at all — it's
shared by `BT A2DP Out`, `BT A2DP Headphones`, and `BT A2DP Speaker`.
Anything you add here applies to *every* Bluetooth output device, not
just your TWS.

Add only:
```xml
<mixPort name="a2dp output" role="source" flags="AUDIO_OUTPUT_FLAG_DEEP_BUFFER">
    <profile name="" format="AUDIO_FORMAT_PCM_16_BIT"
             samplingRates="44100 48000" channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>
</mixPort>
```
Match the sample rate/format your TWS actually negotiates — check Step 0's
baseline log for the real values instead of guessing.

> **⚠️ Anti-prompt:** Did you add channel masks or sample rates beyond
> what your TWS actually uses "to be safe"? Don't. A profile the HAL
> can't satisfy for a real connection is a common cause of audioserver or
> bluetooth mediaserver crash-looping on *every* BT device, not just your
> earbuds — and a restart loop can look identical to a bootloop from the
> user's seat.

---

## Step 3 — Add the spatializer mixPort, BT-side only

```xml
<mixPort name="a2dp spatial" role="source" flags="AUDIO_OUTPUT_FLAG_SPATIALIZER">
    <profile name="" format="AUDIO_FORMAT_PCM_16_BIT"
             samplingRates="48000" channelMasks="AUDIO_CHANNEL_OUT_STEREO"/>
</mixPort>
```
Wire it only into `BT A2DP Out` / `BT A2DP Headphones` routes — leave
`BT A2DP Speaker`, `BT SCO`, `Speaker`, and `Earpiece` routes exactly as
they are.

> **⚠️ Anti-prompt:** Open the patched file and confirm `Speaker`,
> `Earpiece`, `BT SCO`, and `BT A2DP Speaker` routes are byte-for-byte
> identical to the original. If a find-and-replace touched more than the
> two BT-headphone routes, revert and redo it by hand.

---

## Step 4 — system.prop, and confirm nothing overrides it later

```properties
ro.audio.spatializer_enabled=true
ro.spatializer.supported=true
ro.spatializer.pose_predictor_type=0
vendor.audio.dolby.ds2.enabled=true
vendor.audio.dolby.ds2.hardbypass=false
ro.vendor.audio.spatializer.enabled=true
```

> **⚠️ Anti-prompt:** After first boot with the module active, run
> `getprop vendor.audio.dolby.ds2.hardbypass` again. If it reads back
> `true` despite your system.prop, something in vendor `init.rc` sets it
> later in the boot sequence and wins the race — your module built and
> flashed clean, but DAP is running in pass-through. This is the single
> most common reason people get "Atmos toggle shows, sounds like stereo."
> Don't treat a clean flash as confirmation this step worked.

---

## Step 5 — Check the DAP endpoint coefficient table, not just that it exists

Find whatever `dolby_dap_config` / `dax_config` / endpoint params file the
`hardware_dolby` fork you're using ships for the headphone/BT endpoint.

> **⚠️ Anti-prompt:** Diff it against the donor device's version if you
> can find one. If it's identical to a Xiaomi/Sony/Nothing donor's table
> with no per-device retuning, the effect will attach without error
> (you'll see it in LogFox) but render close to flat/neutral — a
> "sounds like stereo" result that no amount of re-flashing the module
> will fix, because the module isn't broken, the tuning data is generic.
> This is a data problem, not a build problem — don't debug it as one.

---

## Step 6 — Package and flash

```text
audio_policy_fix.zip
├── META-INF/com/google/android/{update-binary,updater-script}
├── module.prop
├── system.prop
└── system/vendor/etc/
    ├── audio_policy_configuration.xml
    └── bluetooth_audio_policy_configuration.xml
```

> **⚠️ Anti-prompt:** Before flashing, `xmllint --noout` both XML files.
> A single unclosed tag or bad attribute won't throw an install error —
> it causes AudioPolicyManager to silently reject the whole file at boot
> and fall back to a minimal default config, which can look like *nothing
> you changed took effect anywhere*, not just on the BT path.

---

## Step 7 — Verify with your TWS, not the toggle

1. Connect TWS, play known Atmos (EAC3-JOC) content.
2. Filter LogFox for `dap`, `hardbypass`, `EffectsConfig`, and
   `DlbDapEndpointParamCache` during playback.
3. Confirm `commit()` shows the **headphone/BT preset**, not the speaker
   preset, being applied.
4. A/B: same track, same TWS, Atmos toggle forced off vs on. If you can't
   tell them apart, that's Step 5's problem, not a build failure —
   don't re-flash chasing it.

---

## Rollback

Disable the module in KernelSU Manager and reboot. If BT audio is broken
badly enough to need it, boot to recovery/fastboot and restore the two
XML files from your Step 0 backup.
