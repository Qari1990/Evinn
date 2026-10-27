import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bms.dart';

/// One completed charging session, worked out from the BMS readings we saw
/// while the phone was connected to the battery during a charge.
class ChargeSession {
  final DateTime start;
  final DateTime end;
  final int? socFrom; // %
  final int? socTo; // %
  final double energyWh; // energy put in, integrated from power
  final double avgPowerW;

  ChargeSession({
    required this.start,
    required this.end,
    required this.socFrom,
    required this.socTo,
    required this.energyWh,
    required this.avgPowerW,
  });

  Duration get duration => end.difference(start);
  double get units => energyWh / 1000.0; // 1 unit = 1 kWh

  Map<String, dynamic> toJson() => {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'socFrom': socFrom,
        'socTo': socTo,
        'energyWh': energyWh,
        'avgPowerW': avgPowerW,
      };

  factory ChargeSession.fromJson(Map<String, dynamic> j) => ChargeSession(
        start: DateTime.tryParse('${j['start']}') ?? DateTime.now(),
        end: DateTime.tryParse('${j['end']}') ?? DateTime.now(),
        socFrom: (j['socFrom'] as num?)?.toInt(),
        socTo: (j['socTo'] as num?)?.toInt(),
        energyWh: (j['energyWh'] as num?)?.toDouble() ?? 0,
        avgPowerW: (j['avgPowerW'] as num?)?.toDouble() ?? 0,
      );
}

/// Persists the recent charging sessions in SharedPreferences.
class ChargeLog {
  static const _key = 'charge_sessions';
  static const _max = 40;

  static Future<List<ChargeSession>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_key);
      if (s == null) return [];
      final list = (jsonDecode(s) as List).cast<Map<String, dynamic>>();
      final out = list.map(ChargeSession.fromJson).toList();
      out.sort((a, b) => b.start.compareTo(a.start)); // newest first
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(ChargeSession session) async {
    try {
      final p = await SharedPreferences.getInstance();
      final existing = await load();
      final all = [session, ...existing];
      while (all.length > _max) {
        all.removeLast();
      }
      await p.setString(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}

/// Watches live BMS snapshots and records a [ChargeSession] each time a charge
/// starts and ends. Charging is detected from a positive pack current (the BMS
/// reports current as + when charging) or the charger-connected flag. Energy is
/// integrated from instantaneous power over the time between readings.
class ChargeTracker {
  static const double _chargeAmps = 0.8; // above this current = charging
  static const int _minSeconds = 120; // ignore blips shorter than this

  bool _charging = false;
  DateTime? _start;
  DateTime? _lastTs;
  int? _socStart;
  int? _socLast;
  double _energyWh = 0;
  double _powerSum = 0;
  int _powerN = 0;

  void record(BmsData d) {
    final current = d.current ?? 0;
    final charging = current > _chargeAmps || d.chargerConnected == true;
    final now = d.updated;

    if (charging) {
      if (!_charging) {
        _begin(now, d);
      } else {
        _accumulate(now, d);
      }
      _lastTs = now;
      _socLast = d.soc ?? _socLast;
    } else if (_charging) {
      _finish();
    }
  }

  /// Finalise any in-progress session (e.g. on disconnect).
  void flush() {
    if (_charging) _finish();
  }

  void _begin(DateTime now, BmsData d) {
    _charging = true;
    _start = now;
    _lastTs = now;
    _socStart = d.soc;
    _socLast = d.soc;
    _energyWh = 0;
    _powerSum = 0;
    _powerN = 0;
  }

  void _accumulate(DateTime now, BmsData d) {
    final p = d.power; // W (+ while charging)
    if (p != null && p > 0) {
      final dtH = now.difference(_lastTs ?? now).inMilliseconds / 3600000.0;
      if (dtH > 0 && dtH < 0.5) _energyWh += p * dtH; // ignore huge gaps
      _powerSum += p;
      _powerN++;
    }
  }

  void _finish() {
    final start = _start;
    final end = _lastTs;
    _charging = false;
    if (start == null || end == null) return;
    if (end.difference(start).inSeconds < _minSeconds) return;
    final avg = _powerN > 0 ? _powerSum / _powerN : 0.0;
    // Only log if something actually happened.
    final gained = (_socStart != null && _socLast != null) ? (_socLast! - _socStart!) : 0;
    if (_energyWh <= 0 && gained <= 0) return;
    ChargeLog.add(ChargeSession(
      start: start,
      end: end,
      socFrom: _socStart,
      socTo: _socLast,
      energyWh: _energyWh,
      avgPowerW: avg,
    ));
  }
}
