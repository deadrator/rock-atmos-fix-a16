#!/system/bin/sh
##########################################################################################
# Atmos Audio Policy & Spatializer Fix (TWS) - late-boot verification
#
# Runs in the late_start service stage. Two jobs:
#   1. Re-run the mount check (post-fs-data may run before a metamodule mounts
#      this module) and update audio_policy_fix.status accordingly.
#   2. Capture the LIVE values of the Dolby/spatializer and A2DP-offload props
#      after boot settles - automating steps.md Step 4's anti-prompt ("did some
#      vendor init script override vendor.audio.dolby.ds2.hardbypass after our
#      system.prop applied?") and recording Step 1's offload state for diagnosis.
#
# Read results after boot with:
#   adb shell getprop audio_policy_fix.status
#   adb shell cat /data/adb/audio_policy_fix_status.log
##########################################################################################

LOG=/data/adb/audio_policy_fix_status.log
CHECK_FILE=/vendor/etc/bluetooth_audio_policy_configuration.xml
MARKER="a2dp spatial"

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
if [ -f "$CHECK_FILE" ] && grep -q "$MARKER" "$CHECK_FILE" 2>/dev/null; then
  STATUS="MOUNTED_OK"
else
  STATUS="NOT_MOUNTED"
fi

resetprop -n audio_policy_fix.status "$STATUS" 2>/dev/null || setprop audio_policy_fix.status "$STATUS" 2>/dev/null

HARDBYPASS=$(getprop vendor.audio.dolby.ds2.hardbypass)
DS2ENABLED=$(getprop vendor.audio.dolby.ds2.enabled)
VENDOR_SPAT=$(getprop ro.vendor.audio.spatializer.enabled)
SYS_SPAT=$(getprop ro.audio.spatializer_enabled)
SPAT_SUPP=$(getprop ro.spatializer.supported)
A2DP_OFFLOAD=$(getprop ro.bluetooth.a2dp_offload.supported)
A2DP_OFFLOAD_DIS=$(getprop persist.vendor.bluetooth.a2dp_offload.disable)

{
  echo "[$(date)] audio_policy_fix (TWS) late-boot check: $STATUS"
  echo "  Dolby/spatializer props (steps.md Step 4 anti-prompt):"
  echo "    vendor.audio.dolby.ds2.hardbypass   = ${HARDBYPASS:-<unset>}"
  echo "    vendor.audio.dolby.ds2.enabled      = ${DS2ENABLED:-<unset>}"
  echo "    ro.vendor.audio.spatializer.enabled = ${VENDOR_SPAT:-<unset>}"
  echo "    ro.audio.spatializer_enabled        = ${SYS_SPAT:-<unset>}"
  echo "    ro.spatializer.supported            = ${SPAT_SUPP:-<unset>}"
  echo "  A2DP offload state (steps.md Step 1):"
  echo "    ro.bluetooth.a2dp_offload.supported          = ${A2DP_OFFLOAD:-<unset>}"
  echo "    persist.vendor.bluetooth.a2dp_offload.disable = ${A2DP_OFFLOAD_DIS:-<unset>}"
  if [ "$HARDBYPASS" = "true" ]; then
    echo "  !! WARNING: vendor.audio.dolby.ds2.hardbypass reads back true"
    echo "  !! despite system.prop setting it to false - a vendor init script"
    echo "  !! wins the race. DAP is running in pass-through (steps.md Step 4)."
  fi
  if [ "$STATUS" = "NOT_MOUNTED" ]; then
    echo "  !! WARNING: patched BT XML not mounted on /vendor/etc."
    echo "  !! Check for a mount metamodule (KernelSU/APatch) or module"
    echo "  !! conflicts (Magisk)."
  fi
} >> "$LOG" 2>/dev/null

if [ "$HARDBYPASS" = "true" ]; then
  log -t AUDIO_POLICY_FIX "WARNING: hardbypass overridden to true by vendor init (Step 4 anti-prompt)" 2>/dev/null
fi
log -t AUDIO_POLICY_FIX "late mount check: $STATUS" 2>/dev/null

exit 0
