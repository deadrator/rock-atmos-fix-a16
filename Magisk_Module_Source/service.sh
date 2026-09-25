#!/system/bin/sh
##########################################################################################
# Atmos Audio Policy & Spatializer Fix (TWS) - late-boot verification
#
# Runs in the late_start service stage. It rechecks both mounted XML files and
# records the live Dolby/spatializer and A2DP-offload properties for diagnosis.
#
# Read results after boot with:
#   adb shell getprop audio_policy_fix.status
#   adb shell cat /data/adb/audio_policy_fix_status.log
##########################################################################################

LOG=/data/adb/audio_policy_fix_status.log
CHECK_FILE=/vendor/etc/bluetooth_audio_policy_configuration.xml
EFFECTS_FILE=/vendor/etc/audio_effects.xml
ROUTE_MARKER="AUDIO_OUTPUT_FLAG_SPATIALIZER"
EFFECT_MARKER="ccd4cf09-a79d-46c2-9aae-06a1698d6c8f"

mkdir -p /data/adb 2>/dev/null

# Wait for boot to complete (bounded at ~10 min) so vendor init scripts
# have had their chance to set/override props before we snapshot them.
COUNT=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$COUNT" -lt 300 ]; do
  sleep 2
  COUNT=$((COUNT + 1))
done

# Give audioserver / vendor audio HAL props a few more seconds to settle.
sleep 5

# Late mount check - this is the authoritative reading.
if [ -f "$CHECK_FILE" ] && grep -q "$ROUTE_MARKER" "$CHECK_FILE" 2>/dev/null \
   && [ -f "$EFFECTS_FILE" ] && grep -q "$EFFECT_MARKER" "$EFFECTS_FILE" 2>/dev/null; then
  STATUS="MOUNTED_OK"
else
  STATUS="NOT_MOUNTED"
fi

resetprop -n audio_policy_fix.status "$STATUS" 2>/dev/null || setprop audio_policy_fix.status "$STATUS" 2>/dev/null

HARDBYPASS=$(getprop vendor.audio.dolby.ds2.hardbypass)
DS2ENABLED=$(getprop vendor.audio.dolby.ds2.enabled)
SYS_SPAT=$(getprop ro.audio.spatializer_enabled)
A2DP_OFFLOAD=$(getprop ro.bluetooth.a2dp_offload.supported)
A2DP_OFFLOAD_DIS=$(getprop persist.vendor.bluetooth.a2dp_offload.disable)

{
  echo "[$(date)] audio_policy_fix (TWS) late-boot check: $STATUS"
  echo "  Dolby/spatializer props:"
  echo "    vendor.audio.dolby.ds2.hardbypass = ${HARDBYPASS:-<unset>}"
  echo "    vendor.audio.dolby.ds2.enabled    = ${DS2ENABLED:-<unset>}"
  echo "    ro.audio.spatializer_enabled      = ${SYS_SPAT:-<unset>}"
  echo "  A2DP offload state:"
  echo "    ro.bluetooth.a2dp_offload.supported          = ${A2DP_OFFLOAD:-<unset>}"
  echo "    persist.vendor.bluetooth.a2dp_offload.disable = ${A2DP_OFFLOAD_DIS:-<unset>}"
  if [ "$HARDBYPASS" = "true" ]; then
    echo "  !! WARNING: vendor.audio.dolby.ds2.hardbypass reads back true"
    echo "  !! despite system.prop setting it to false - a vendor init script"
    echo "  !! wins the race. Dolby processing may be bypassed."
  fi
  if [ "$STATUS" = "NOT_MOUNTED" ]; then
    echo "  !! WARNING: patched BT XML not mounted on /vendor/etc."
    echo "  !! Check for a mount metamodule (KernelSU/APatch) or module"
    echo "  !! conflicts (Magisk)."
  fi
} >> "$LOG" 2>/dev/null

if [ "$HARDBYPASS" = "true" ]; then
  log -t AUDIO_POLICY_FIX "WARNING: hardbypass overridden to true by vendor init" 2>/dev/null
fi
log -t AUDIO_POLICY_FIX "late mount check: $STATUS" 2>/dev/null

exit 0
