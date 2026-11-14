import 'package:shared_preferences/shared_preferences.dart';
import '../app_config.dart';

/// Estimates remaining range ("km left") and learns the bike's real energy use
/// (Wh per km) over time.
///
/// How it learns: whenever we have both the battery's remaining energy (from the
/// BMS) and the tracker odometer at the same moment, we keep a baseline. On a
/// later sample, if energy has dropped and the odometer has advanced (and we're
/// not charging), Wh/km for that stretch = energy used ÷ distance ridden. We
/// blend that into the stored figure with a slow exponential average, so one odd
/// reading can't swing it. Until it has learned anything, it uses
/// [AppConfig.defaultWhPerKm].
class RangeEstimator {
  static const _kWhPerKm = 're_wh_per_km';
  static const _kBaseWh = 're_base_wh';
  static const _kBaseKm = 're_base_km';
  static const _kFullAh = 're_full_ah';

  static double? _whPerKmCache;

  /// Learned (or default) Wh/km. Cached after the first read.
  static Future<double> whPerKm() async {
    if (_whPerKmCache != null) return _whPerKmCache!;
    try {
      final p = await SharedPreferences.getInstance();
      _whPerKmCache = p.getDouble(_kWhPerKm) ?? AppConfig.defaultWhPerKm;
    } catch (_) {
      _whPerKmCache = AppConfig.defaultWhPerKm;
    }
    return _whPerKmCache!;
  }

  /// Synchronous best-known Wh/km for building UI without awaiting (falls back
  /// to the default until [whPerKm] has been awaited once).
  static double get whPerKmSync => _whPerKmCache ?? AppConfig.defaultWhPerKm;

  /// Best-known full-pack capacity in Ah (learned from a near-full BMS reading,
  /// else the configured estimate).
  static double get fullAhSync => _fullAhCache ?? AppConfig.fullCapacityAh;
  static double? _fullAhCache;

  static Future<void> preload() async {
    await whPerKm();
    try {
      final p = await SharedPreferences.getInstance();
      _fullAhCache = p.getDouble(_kFullAh);
    } catch (_) {}
  }

  /// Feed a paired reading (battery energy + odometer) so the estimate can learn.
  static Future<void> record({
    double? remainingWh,
    double? inferredFullAh,
    double? odometerKm,
    bool charging = false,
  }) async {
    try {
      final p = await SharedPreferences.getInstance();

      // Track the best full-capacity estimate (largest inferred value seen).
      if (inferredFullAh != null && inferredFullAh > 1) {
        final prev = p.getDouble(_kFullAh) ?? 0;
        if (inferredFullAh > prev) {
          await p.setDouble(_kFullAh, inferredFullAh);
          _fullAhCache = inferredFullAh;
        } else {
          _fullAhCache = prev;
        }
      }

      if (remainingWh == null || odometerKm == null) return;

      final baseWh = p.getDouble(_kBaseWh);
      final baseKm = p.getDouble(_kBaseKm);

      // Charging, or no baseline, or odometer went backwards (reset): rebase.
      if (charging || baseWh == null || baseKm == null || odometerKm < baseKm) {
        await p.setDouble(_kBaseWh, remainingWh);
        await p.setDouble(_kBaseKm, odometerKm);
        return;
      }

      final dKm = odometerKm - baseKm;
      final dWh = baseWh - remainingWh; // positive while discharging
      // Only learn from a meaningful stretch with real energy drawn.
      if (dKm >= 1.0 && dWh >= 40.0) {
        final sample = dWh / dKm;
        if (sample > 5 && sample < 120) {
          final current = p.getDouble(_kWhPerKm) ?? AppConfig.defaultWhPerKm;
          final blended = current * 0.8 + sample * 0.2; // slow EMA
          await p.setDouble(_kWhPerKm, blended);
          _whPerKmCache = blended;
        }
        // Rebase for the next stretch.
        await p.setDouble(_kBaseWh, remainingWh);
        await p.setDouble(_kBaseKm, odometerKm);
      }
    } catch (_) {}
  }

  /// Coulomb-based state of charge (%) from the BMS residual capacity
  /// (remainingAh ÷ full Ah). This is far steadier than the pack's voltage-based
  /// %, which recovers upward at rest (the "parked at 80%, 90% next morning"
  /// effect) and sags under load — so we prefer this for the headline number.
  static double? socFromAh(double? remainingAh) {
    if (remainingAh == null) return null;
    final full = fullAhSync;
    if (full <= 0) return null;
    return (remainingAh / full * 100).clamp(0, 100).toDouble();
  }

  /// Real range shrinks faster than the percentage suggests once the pack is
  /// low: voltage sags under load and the last stretch of charge is barely
  /// usable, so a bike shown at "40%" runs noticeably less than 40% of its full
  /// range. Below 50% we taper the estimate (1.0 at 50% → 0.75 at 10% and
  /// below) so "km left" stays honest exactly when it matters.
  static double _lowSocFactor(double? socPct) {
    if (socPct == null || socPct >= 50) return 1.0;
    if (socPct <= 10) return 0.75;
    return 0.75 + (socPct - 10) / (50 - 10) * (1.0 - 0.75);
  }

  /// Estimated km left (Normal riding). Prefers true battery energy from the
  /// BMS; otherwise estimates from the tracker battery percentage and the pack's
  /// nominal size. [socPct] (the best-known state of charge) lets the estimate
  /// taper conservatively when the pack is low.
  static double? rangeKm({double? remainingWh, double? trackerPercent, double? socPct}) {
    final whKm = whPerKmSync;
    if (whKm <= 0) return null;
    final wh = remainingWh ??
        (trackerPercent == null
            ? null
            : fullAhSync * AppConfig.packNominalV * (trackerPercent / 100.0));
    if (wh == null) return null;
    final full = fullAhSync * AppConfig.packNominalV;
    final eff = socPct ??
        trackerPercent ??
        (full > 0 ? wh / full * 100 : null);
    return wh / whKm * _lowSocFactor(eff);
  }

  /// Relative energy use of each riding mode vs Normal. Eco draws less per km
  /// (more range); Sport draws more (less range). Mirrors the 3 modes the Elfa
  /// app shows.
  static const Map<String, double> modeFactors = {
    'Eco': 0.82,
    'Normal': 1.0,
    'Sport': 1.25,
  };

  /// Estimated range for each riding mode, or null if range can't be computed.
  static Map<String, double>? rangeModes({double? remainingWh, double? trackerPercent, double? socPct}) {
    final base = rangeKm(remainingWh: remainingWh, trackerPercent: trackerPercent, socPct: socPct);
    if (base == null) return null;
    return {for (final e in modeFactors.entries) e.key: base / e.value};
  }

  /// For diagnostics / settings display.
  static Future<Map<String, dynamic>> debugState() async {
    final p = await SharedPreferences.getInstance();
    return {
      'whPerKm': p.getDouble(_kWhPerKm),
      'baseWh': p.getDouble(_kBaseWh),
      'baseKm': p.getDouble(_kBaseKm),
      'fullAh': p.getDouble(_kFullAh),
    };
  }
}
