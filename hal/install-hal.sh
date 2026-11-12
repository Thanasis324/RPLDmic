#!/bin/bash
# Install the RPLDmic Core Audio plug-in. The kext itself goes into OpenCore (Kernel > Add) with boot-arg -rpldmic.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
DRIVER_SRC=""
if [ -d "$DIR/build/RPLDmic.driver" ]; then
  DRIVER_SRC="$DIR/build/RPLDmic.driver"
elif [ -d "$DIR/RPLDmic.driver" ]; then
  DRIVER_SRC="$DIR/RPLDmic.driver"
else
  echo "ERROR: RPLDmic.driver not found in $DIR/build or $DIR"
  exit 1
fi

WANT_VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DRIVER_SRC/Contents/Info.plist" 2>/dev/null || echo '?')"
WANT_IF=1
IOR="$(ioreg -r -c RPLDmic -d 1 -w0 2>/dev/null || ioreg -r -c TGLDmic -d 1 -w0 2>/dev/null)"
prop() { printf '%s\n' "$IOR" | sed -n "s/.*\"$1\" = \"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" | head -1; }
if [ -z "$IOR" ]; then
  echo "WARNING: RPLDmic kext is not loaded in IORegistry. Ensure RPLDmic.kext is added to OpenCore and system rebooted."
else
  KVER="$(prop RPLDmicVersion)"; [ -z "$KVER" ] && KVER="$(prop TGLDmicVersion)"
  KIF="$(prop RPLDmicInterface)"; [ -z "$KIF" ] && KIF="$(prop TGLDmicInterface)"
  KPH="$(prop RPLDmicPhase)"; [ -z "$KPH" ] && KPH="$(prop TGLDmicPhase)"
  if [ -z "$KVER" ]; then
    echo "WARNING: loaded kext does not report version."
  elif [ "$KIF" != "$WANT_IF" ]; then
    echo "ERROR: loaded kext $KVER uses interface $KIF, plug-in $WANT_VER needs $WANT_IF. Update kext first."; exit 1
  else
    echo "OK: RPLDmic kext $KVER loaded, interface $KIF."
  fi
  [ -n "$KPH" ] && [ "$KPH" != 4 ] && echo "NOTE: kext running in phase $KPH (service mode active on demand)."
fi

echo "Staging RPLDmic.driver to /Library/Audio/Plug-Ins/HAL/..."
sudo rm -rf /Library/Audio/Plug-Ins/HAL/RPLDmic.driver
sudo cp -R "$DRIVER_SRC" /Library/Audio/Plug-Ins/HAL/
sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/RPLDmic.driver
sudo chmod -R 755 /Library/Audio/Plug-Ins/HAL/RPLDmic.driver
sudo xattr -dr com.apple.quarantine /Library/Audio/Plug-Ins/HAL/RPLDmic.driver 2>/dev/null || true

echo "Restarting coreaudiod..."
sudo killall coreaudiod 2>/dev/null || sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
echo "Installed successfully. Check 'Built-in Microphone' (Input Source: Internal Microphone) in System Settings > Sound > Input."
