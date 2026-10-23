#!/usr/bin/env bash
# Patches the Android project that `flutter create` generates:
#  - adds the permissions the app needs
#  - sets a sane minSdk
# Signing is handled separately in CI by using a fixed debug keystore
# (signing/debug.keystore) so every build shares one signature — that lets
# Android install updates over previous builds and lets in-app auto-update work.
# Safe to run repeatedly (idempotent).
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"

# --- Permissions -----------------------------------------------------------
PERMS='    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>'

if ! grep -q "BLUETOOTH_SCAN" "$MANIFEST"; then
  # Insert permissions right after the opening <manifest ...> tag.
  awk -v perms="$PERMS" '
    /<manifest/ && !done { print; print perms; done=1; next }
    { print }
  ' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
  echo "Permissions injected."
else
  echo "Permissions already present."
fi

# --- minSdk (BLE needs >= 21) ----------------------------------------------
for f in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$f" ] || continue
  sed -i -E 's/minSdk(Version)?\s*=?\s*(flutter\.minSdkVersion|[0-9]+)/minSdk = 21/' "$f" || true
done

echo "Android patch complete."
