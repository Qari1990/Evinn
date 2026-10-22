# EVINN — companion app (phase 1)

A modern cross-platform app for EV bikes. Two data sources in one app:

- **Traccar API** (cloud) — live location/map, speed, ignition, odometer, trips, and the
  tracker's battery %. Works anywhere.
- **BMS over Bluetooth** (JBD/Daly protocol) — pack voltage/current, true SOC, per-cell
  voltages, temperatures, charge/discharge MOSFET state, cycles. Works near the bike.

Built with **Flutter** (one codebase → Android + iPhone). Designed to be **white-labelled**:
all brand-specific values live in `lib/app_config.dart`.

## Status

Phase 1, buildable source. Confirmed against WAQAR's bike:
- Tracker: gps103/TK103 on `webapp.elfaelectric.com`; `fuel1` = battery %.
- BMS: JBD/JiaBaiDa (Daly-branded), BLE service **FFF0**, notify **FFF1**, write **FFF2**,
  23S LiFePO4. Read frames `DDA50300FFFD77` (pack info) and `DDA50400FFFC77` (cells).

## Project layout

```
lib/
  app_config.dart          # white-label config (name, server, colours, BMS type)
  models/traccar.dart      # Traccar device/position models (+ field helpers)
  models/bms.dart          # parsed battery snapshot
  services/traccar_api.dart# REST client (Basic auth)
  services/jbd_protocol.dart# JBD frame build + parse (pack info, cells)
  services/bms_service.dart# BLE scan/connect (flutter_blue_plus) + streaming
  state/app_state.dart     # auth, selected bike, live polling
  ui/                      # login, dashboard, battery, trips, settings
```

## Build the APK

### Option A — automatic (recommended): GitHub Actions
Push this project to a GitHub repo. The workflow in `.github/workflows/android-build.yml`
builds an installable debug APK on every push and uploads it as a build artifact
(Actions → latest run → `evinn-debug-apk`). Download and install it on an Android phone
(allow "install from unknown sources").

### Option B — local machine (needs Flutter installed)
```bash
flutter create --platforms=android --project-name evinn --org com.evinn .
./scripts/patch_android.sh      # adds BLE/location permissions
flutter pub get
flutter build apk --debug       # -> build/app/outputs/flutter-apk/app-debug.apk
```
For iPhone: `flutter build ios` (needs macOS + an Apple Developer account for a device/TestFlight).

## Notes / next steps
- Credentials are stored in plain SharedPreferences for phase 1 — move to
  `flutter_secure_storage` before public release.
- Live updates use REST polling (every ~12s). A later version can use the Traccar
  WebSocket (`/api/socket`) for instant push and add theft/geofence push notifications.
- The BMS parser uses the standard JBD layout; validate parsed values against the Daly app
  on first run and tweak scaling if any field differs.
