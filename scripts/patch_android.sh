#!/usr/bin/env bash
# Injects the permissions and SDK settings the app needs into the Android
# project that `flutter create` generates. Safe to run repeatedly (idempotent).
set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"
GRADLE_KTS="android/app/build.gradle.kts"
GRADLE="android/app/build.gradle"

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

# --- minSdk (BLE needs >= 21; flutter_blue_plus/permission_handler happy) ---
for f in "$GRADLE_KTS" "$GRADLE"; do
  [ -f "$f" ] || continue
  sed -i -E 's/minSdk(Version)?\s*=?\s*(flutter\.minSdkVersion|[0-9]+)/minSdk = 21/' "$f" || true
done

echo "Android patch complete."
