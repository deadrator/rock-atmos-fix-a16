#!/system/bin/sh
##########################################################################################
# Atmos Audio Policy & Spatializer Fix (TWS) - boot-time mount verification
#
# Runs early in boot (post-fs-data stage, supported by Magisk and KernelSU/APatch).
# Checks whether our bluetooth_audio_policy_configuration.xml actually got mounted
# and records the result to a log file + a readable system prop, since there is no
# way to verify a successful mount at *install* time - the mount itself only happens
# during boot. service.sh re-runs this check late in boot, in case a metamodule
# mounted this module after this script already ran.
##########################################################################################

MODDIR=${0%/*}

chcon -R u:object_r:vendor_configs_file:s0 $MODDIR/system/vendor/etc 2>/dev/null
find $MODDIR/system/vendor/etc -type d -exec chmod 755 {} + 2>/dev/null
find $MODDIR/system/vendor/etc -type f -exec chmod 644 {} + 2>/dev/null

LOG=/data/adb/audio_policy_fix_status.log
CHECK_FILE=/vendor/etc/bluetooth_audio_policy_configuration.xml
ROUTE_MARKER="AUDIO_OUTPUT_FLAG_SPATIALIZER"
DB_MARKER="AUDIO_OUTPUT_FLAG_DEEP_BUFFER"

mkdir -p /data/adb 2>/dev/null

if [ -f "$CHECK_FILE" ] && grep -q "$ROUTE_MARKER" "$CHECK_FILE" 2>/dev/null \
   && grep -q "$DB_MARKER" "$CHECK_FILE" 2>/dev/null; then
  STATUS="MOUNTED_OK"
else
  STATUS="NOT_MOUNTED"
fi

{
  echo "[$(date)] audio_policy_fix (TWS) early mount check: $STATUS"
  if [ "$STATUS" = "NOT_MOUNTED" ]; then
    echo "  -> The spatial route and/or deep-buffer A2DP profile is missing."
    echo "  -> Checked: $CHECK_FILE"
    echo "  -> On KernelSU/APatch this usually means no mount metamodule"
    echo "     (meta-overlayfs / Hybrid Mount / Magic Mount-rs) is active,"
    echo "     or it failed to mount this module."
    echo "  -> On Magisk this may mean the module failed to install, is"
    echo "     disabled, or was overridden by another module."
    echo "  -> service.sh will re-check late in boot and update the status."
  fi
} >> "$LOG" 2>/dev/null

# Expose status as a queryable prop:
#   adb shell getprop audio_policy_fix.status
resetprop -n audio_policy_fix.status "$STATUS" 2>/dev/null || setprop audio_policy_fix.status "$STATUS" 2>/dev/null

log -t AUDIO_POLICY_FIX "early mount check: $STATUS" 2>/dev/null

exit 0
