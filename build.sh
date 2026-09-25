#!/usr/bin/env bash
##########################################################################################
# Build audio_policy_fix.zip from Magisk_Module_Source/
# Mirrors reference/poco-m5-incall-audio-fix/.github/workflows/build.yml:
#   cd Magisk_Module_Source && zip -r9 ../<name>.zip *
#
# Module structure (what the zip MUST contain):
#   META-INF/com/google/android/{update-binary,updater-script}
#   module.prop
#   system.prop
#   system/vendor/etc/bluetooth_audio_policy_configuration.xml
#   system/vendor/etc/permissions/android.hardware.audio.spatializer.xml
#
# Packaging backends, in order of preference:
#   1. `zip`        - best (exec bits + forward slashes preserved)
#   2. `python`     - equivalent (zipfile module writes forward-slash names and
#                     we set the exec bit on scripts explicitly)
#   3. powershell   - LAST RESORT ONLY: Compress-Archive stores backslash
#                     separators that Magisk/KernelSU cannot extract. Avoid.
##########################################################################################
set -euo pipefail

MODULE_NAME="audio_policy_fix"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$ROOT_DIR/Magisk_Module_Source"
OUT_ZIP="$ROOT_DIR/${MODULE_NAME}.zip"
PYTHON_BIN="python"

cd "$SRC_DIR"

# Sanity gate: required files present and all XML well-formed.
for f in META-INF/com/google/android/update-binary \
         META-INF/com/google/android/updater-script \
         module.prop system.prop post-fs-data.sh service.sh \
         system/vendor/etc/bluetooth_audio_policy_configuration.xml \
         system/vendor/etc/permissions/android.hardware.audio.spatializer.xml; do
  [ -f "$f" ] || { echo "ERROR: missing required module file: $f" >&2; exit 1; }
done
if command -v xmllint >/dev/null 2>&1; then
  for xml in system/vendor/etc/bluetooth_audio_policy_configuration.xml \
             system/vendor/etc/permissions/android.hardware.audio.spatializer.xml; do
    xmllint --noout "$xml" || { echo "ERROR: $xml is not well-formed" >&2; exit 1; }
  done
fi

rm -f "$OUT_ZIP"

package_with_python() {
  "$PYTHON_BIN" - "$SRC_DIR" "$OUT_ZIP" <<'PYEOF'
import os, sys, stat, zipfile

src, out = sys.argv[1], sys.argv[2]
EXEC_FILES = {"META-INF/com/google/android/update-binary", "post-fs-data.sh", "service.sh"}

# Deterministic order, directories first (mirrors `zip -r` layout).
paths = []
for root, dirs, files in os.walk(src):
    dirs.sort()
    for d in dirs:
        rel = os.path.relpath(os.path.join(root, d), src).replace(os.sep, "/")
        paths.append(rel + "/")
    for f in sorted(files):
        paths.append(os.path.relpath(os.path.join(root, f), src).replace(os.sep, "/"))

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for rel in paths:
        disk = os.path.join(src, rel.replace("/", os.sep))
        if rel.endswith("/"):
            info = zipfile.ZipInfo(rel)
            info.external_attr = (0o755 << 16) | 0x10  # drwxr-xr-x
            zf.writestr(info, b"")
            continue
        info = zipfile.ZipInfo(rel, date_time=(2026, 1, 1, 0, 0, 0))
        mode = 0o755 if rel in EXEC_FILES else 0o644
        info.external_attr = (mode << 16)
        with open(disk, "rb") as fh:
            zf.writestr(info, fh.read())
print("Built (python zipfile):", out)
PYEOF
}

if command -v zip >/dev/null 2>&1; then
  zip -r9 "$OUT_ZIP" .
  echo "Built (zip): $OUT_ZIP"
elif command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python || command -v python3)"
  package_with_python
elif command -v powershell.exe >/dev/null 2>&1; then
  echo "WARNING: only powershell.exe available - its zip uses backslash" >&2
  echo "separators and is NOT safe to flash. Install zip or python." >&2
  WIN_SRC="$(cygpath -w "$SRC_DIR")"
  WIN_OUT="$(cygpath -w "$OUT_ZIP")"
  powershell.exe -NoProfile -Command "Compress-Archive -Path '$WIN_SRC\\*' -DestinationPath '$WIN_OUT' -Force"
  echo "Built (Compress-Archive, UNUSABLE): $OUT_ZIP"
  exit 2
else
  echo "ERROR: no packaging backend available (need zip, python, or powershell)" >&2
  exit 1
fi

echo
echo "Contents:"
if command -v unzip >/dev/null 2>&1; then
  unzip -l "$OUT_ZIP"
else
  "$PYTHON_BIN" -c "import zipfile,sys; [print(f'  {i.filename} {i.file_size}') for i in zipfile.ZipFile(sys.argv[1]).infolist()]" "$OUT_ZIP"
fi
