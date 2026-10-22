import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// WHITE-LABEL CONFIG
///
/// Everything brand-specific lives here. To ship the app for another EV
/// manufacturer, change these values (and the app icon / applicationId) — no
/// other code changes are needed. Later this can be loaded from a remote JSON
/// so brands are configured without rebuilding.
/// ---------------------------------------------------------------------------
class AppConfig {
  /// Shown as the app title and on the login screen.
  static const String appName = 'EVINN';

  /// A short tagline on the login screen.
  static const String tagline = 'Your bike, live.';

  /// Default Traccar server for this brand. Users can still override it at login.
  static const String defaultServer = 'https://webapp.elfaelectric.com';

  /// Lock the server (hide the field) for a single-tenant brand build.
  static const bool lockServer = false;

  /// Brand colour. The whole theme derives from this.
  static const Color seedColor = Color(0xFF2B74E6);

  /// Which BMS protocol this brand's bikes use. Only 'jbd' is implemented in
  /// phase 1; others (daly-uart, etc.) plug in later.
  static const String bmsProtocol = 'jbd';

  /// Expected pack geometry (used for sane display defaults; the BMS reports
  /// the real counts). WAQAR's bike: 23S LiFePO4.
  static const int cellCount = 23;
  static const double cellNominalV = 3.2; // LiFePO4

  /// How often to poll the Traccar server for live position (seconds).
  static const int livePollSeconds = 12;

  /// GitHub repo that publishes release builds, used for in-app auto-update.
  /// Release tags are "build-<number>"; the APK is attached as a release asset.
  static const String githubOwner = 'Qari1990';
  static const String githubRepo = 'Evinn';
}
